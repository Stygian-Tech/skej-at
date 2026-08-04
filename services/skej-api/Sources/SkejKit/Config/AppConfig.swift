import Foundation

public enum AppEnvironment: String, Sendable {
    case local
    case test
    case dev
    case prod
}

public struct AppConfig: Sendable {
    public let port: Int
    public let environment: AppEnvironment
    public let publicOrigin: String
    public let webOrigin: String?
    public let sqlitePath: String
    public let workerEnabled: Bool
    public let workerIntervalSeconds: UInt64
    public let liveATProtoEnabled: Bool

    public init(
        port: Int,
        environment: AppEnvironment,
        publicOrigin: String,
        webOrigin: String? = nil,
        sqlitePath: String,
        workerEnabled: Bool = true,
        workerIntervalSeconds: UInt64 = 30,
        liveATProtoEnabled: Bool = false
    ) {
        self.port = port
        self.environment = environment
        self.publicOrigin = publicOrigin.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.webOrigin = webOrigin?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.sqlitePath = sqlitePath
        self.workerEnabled = workerEnabled
        self.workerIntervalSeconds = workerIntervalSeconds
        self.liveATProtoEnabled = liveATProtoEnabled
    }

    public static func load() -> AppConfig {
        load(environment: ProcessInfo.processInfo.environment, dotenv: loadDotenv())
    }

    public static func load(environment processEnvironment: [String: String], dotenv: [String: String] = [:]) -> AppConfig {
        let env = dotenv.merging(processEnvironment) { _, processValue in processValue }
        let appEnv: AppEnvironment = {
            switch (env["APP_ENV"] ?? "local").lowercased() {
            case "prod": .prod
            case "dev": .dev
            case "test": .test
            default: .local
            }
        }()
        let port = Int(env["PORT"] ?? "8080") ?? 8080
        let origin = env["SKEJ_PUBLIC_ORIGIN"] ?? env["PUBLIC_ORIGIN"] ?? "http://127.0.0.1:\(port)"
        let webOrigin = emptyToNil(env["SKEJ_WEB_ORIGIN"])
        let sqlitePath = normalizedSQLitePath(env["SKEJ_SQLITE_PATH"], environment: appEnv)
        let workerEnabled = !["0", "false", "no"].contains((env["SKEJ_WORKER_ENABLED"] ?? "true").lowercased())
        let interval = UInt64(env["SKEJ_WORKER_INTERVAL_SECONDS"] ?? "30") ?? 30
        let liveATProtoDefault = appEnv == .dev || appEnv == .prod
        let liveATProtoEnabled = !["0", "false", "no"].contains(
            (env["SKEJ_LIVE_ATPROTO_ENABLED"] ?? (liveATProtoDefault ? "true" : "false")).lowercased()
        )
        return AppConfig(
            port: port,
            environment: appEnv,
            publicOrigin: origin,
            webOrigin: webOrigin,
            sqlitePath: sqlitePath,
            workerEnabled: workerEnabled,
            workerIntervalSeconds: interval,
            liveATProtoEnabled: liveATProtoEnabled
        )
    }

    private static func loadDotenv() -> [String: String] {
        let fileManager = FileManager.default
        let currentDirectory = fileManager.currentDirectoryPath
        let candidatePaths = [
            "\(currentDirectory)/.env.local",
            "\(currentDirectory)/.env",
            "\(currentDirectory)/services/skej-api/.env.local",
            "\(currentDirectory)/services/skej-api/.env",
        ]

        var values: [String: String] = [:]
        var seen = Set<String>()
        for path in candidatePaths where !seen.contains(path) {
            seen.insert(path)
            guard fileManager.fileExists(atPath: path),
                  let contents = try? String(contentsOfFile: path, encoding: .utf8)
            else { continue }

            for line in contents.split(whereSeparator: \.isNewline) {
                guard let pair = parseDotenvLine(String(line)) else { continue }
                values[pair.key] = pair.value
            }
        }
        return values
    }

    private static func parseDotenvLine(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.starts(with: "#"),
              let equalsIndex = trimmed.firstIndex(of: "=")
        else { return nil }

        let key = trimmed[..<equalsIndex].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }

        let rawValue = trimmed[trimmed.index(after: equalsIndex)...].trimmingCharacters(in: .whitespaces)
        let value: String
        if rawValue.count >= 2,
           let first = rawValue.first,
           let last = rawValue.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'")
        {
            value = String(rawValue.dropFirst().dropLast())
        } else {
            value = String(rawValue)
        }

        return (String(key), value)
    }

    private static func normalizedSQLitePath(_ configuredPath: String?, environment: AppEnvironment) -> String {
        let hostedDefault = "/var/lib/skej-api/data/skej.sqlite"
        let localDefault = "data/skej.sqlite"
        let fallback = switch environment {
        case .dev, .prod:
            hostedDefault
        case .local, .test:
            localDefault
        }
        guard let configuredPath, !configuredPath.isEmpty else {
            return fallback
        }

        if configuredPath == ":memory:" || configuredPath.starts(with: "/") {
            return configuredPath
        }

        switch environment {
        case .dev, .prod:
            return hostedDefault
        case .local, .test:
            return configuredPath
        }
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
