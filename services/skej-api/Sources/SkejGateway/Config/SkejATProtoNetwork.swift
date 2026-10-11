import Foundation

/// OAuth publicOrigin remains stable even when the API uses a different hostname.
public struct SkejATProtoNetwork: Sendable {
    public let browserOrigins: Set<String>
    public let apiOrigin: String
    public let plcOrigin: String
    public let handleResolverOrigin: String
    public let localPDSOrigins: Set<String>
    public let didWebOrigins: Set<String>
    public let isolated: Bool

    public var serviceDID: String {
        guard let url = URL(string: apiOrigin), let host = url.host else { return "" }
        return "did:web:" + host + (url.port.map { "%3A\($0)" } ?? "")
    }
    public var serviceAudience: String { serviceDID + "#skej_scheduler" }

    public init(environment: AppEnvironment, publicOrigin: String, environmentValues: [String: String] = [:]) {
        let browserDefaults: Set<String> = environment == .prod
            ? ["https://skej.at", "https://thesocialwire.app"]
            : environment == .dev ? ["https://testing.skej.at", "https://testing.thesocialwire.app"]
            : ["http://localhost:3016", "http://127.0.0.1:3016"]
        browserOrigins = browserDefaults.union(Self.origins(environmentValues["SKEJ_CORS_ORIGINS"]))
        let hosted = environment == .prod ? "https://api.skej.at" : "https://api.testing.skej.at"
        apiOrigin = Self.origin(environmentValues["SKEJ_API_ORIGIN"] ?? ((environment == .dev || environment == .prod) ? hosted : publicOrigin)) ?? ""
        let local = environment == .local
        plcOrigin = local ? (Self.origin(environmentValues["SKEJ_LOCAL_PLC_ORIGIN"] ?? "https://plc.directory") ?? "") : "https://plc.directory"
        handleResolverOrigin = local ? (Self.origin(environmentValues["SKEJ_LOCAL_HANDLE_RESOLVER_ORIGIN"] ?? "https://bsky.social") ?? "") : "https://bsky.social"
        isolated = local && plcOrigin != "https://plc.directory"
        localPDSOrigins = local ? Self.origins(environmentValues["SKEJ_LOCAL_PDS_ORIGINS"]) : []
        // Explicit DID-web issuer origins prevent untrusted DID strings from becoming
        // arbitrary server fetch targets. PLC accounts require no additional configuration.
        didWebOrigins = Self.origins(environmentValues[local ? "SKEJ_LOCAL_DID_WEB_ORIGINS" : "SKEJ_DID_WEB_ORIGINS"])
    }

    public func allowsOAuthEndpoint(_ value: String) -> Bool {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host,
              url.user == nil, url.password == nil, url.fragment == nil else { return false }
        let origin = "https://" + host + (url.port.map { ":\($0)" } ?? "")
        return !isolated || localPDSOrigins.contains(origin)
    }

    public func allowsPDS(_ value: String) -> Bool {
        guard let origin = Self.origin(value), origin == value.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else { return false }
        return !isolated || localPDSOrigins.contains(origin)
    }

    static func origin(_ value: String) -> String? {
        guard let url = URL(string: value), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { return nil }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    private static func origins(_ value: String?) -> Set<String> {
        Set((value ?? "").split(separator: ",").compactMap { origin(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) })
    }
}
