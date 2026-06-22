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
    public let sqlitePath: String
    public let workerEnabled: Bool
    public let workerIntervalSeconds: UInt64
    public let liveATProtoEnabled: Bool

    public init(
        port: Int,
        environment: AppEnvironment,
        publicOrigin: String,
        sqlitePath: String,
        workerEnabled: Bool = true,
        workerIntervalSeconds: UInt64 = 30,
        liveATProtoEnabled: Bool = false
    ) {
        self.port = port
        self.environment = environment
        self.publicOrigin = publicOrigin.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.sqlitePath = sqlitePath
        self.workerEnabled = workerEnabled
        self.workerIntervalSeconds = workerIntervalSeconds
        self.liveATProtoEnabled = liveATProtoEnabled
    }

    public static func load() -> AppConfig {
        let env = ProcessInfo.processInfo.environment
        let appEnv: AppEnvironment = {
            switch (env["APP_ENV"] ?? "local").lowercased() {
            case "prod": .prod
            case "dev": .dev
            case "test": .test
            default: .local
            }
        }()
        let port = Int(env["PORT"] ?? "8080") ?? 8080
        let origin = env["PUBLIC_ORIGIN"] ?? "http://127.0.0.1:\(port)"
        let sqlitePath = env["SKEJ_SQLITE_PATH"] ?? "data/skej.sqlite"
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
            sqlitePath: sqlitePath,
            workerEnabled: workerEnabled,
            workerIntervalSeconds: interval,
            liveATProtoEnabled: liveATProtoEnabled
        )
    }
}
