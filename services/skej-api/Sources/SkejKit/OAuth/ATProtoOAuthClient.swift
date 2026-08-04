@preconcurrency import Crypto
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol OAuthClient: Sendable {
    func start(handle: String, state: String, pkceVerifier: String, nonce: String) async throws -> OAuthStartResult
    func complete(state: OAuthStateRecord, code: String) async throws -> OAuthCompletion
}

public struct OAuthStartResult: Sendable, Equatable {
    public let redirectURL: String
    public let authServer: String
    public let tokenEndpoint: String
    public let pdsEndpoint: String
    public let dpopKeyJSON: String

    public init(
        redirectURL: String,
        authServer: String,
        tokenEndpoint: String,
        pdsEndpoint: String,
        dpopKeyJSON: String
    ) {
        self.redirectURL = redirectURL
        self.authServer = authServer
        self.tokenEndpoint = tokenEndpoint
        self.pdsEndpoint = pdsEndpoint
        self.dpopKeyJSON = dpopKeyJSON
    }
}

public struct OAuthCompletion: Sendable, Equatable {
    public let viewer: Viewer
    public let session: OAuthSessionRecord

    public init(viewer: Viewer, session: OAuthSessionRecord) {
        self.viewer = viewer
        self.session = session
    }
}

public struct LocalOAuthClient: OAuthClient {
    public init() {}

    public func start(handle: String, state: String, pkceVerifier: String, nonce: String) async throws -> OAuthStartResult {
        OAuthStartResult(
            redirectURL: "/oauth/callback?state=\(state)&code=local-dev",
            authServer: "local",
            tokenEndpoint: "local",
            pdsEndpoint: "local",
            dpopKeyJSON: "{}"
        )
    }

    public func complete(state: OAuthStateRecord, code: String) async throws -> OAuthCompletion {
        let handle = state.handle
        let did = localDID(for: handle)
        let tokenJSON = try JSONEncoder().encodeString(ATProtoTokenPayload(
            accessToken: "local",
            refreshToken: nil,
            tokenType: "DPoP",
            expiresIn: nil,
            scope: "atproto transition:generic",
            sub: did,
            pdsEndpoint: "local",
            tokenEndpoint: "local"
        ))
        return OAuthCompletion(
            viewer: Viewer(did: did, handle: handle, displayName: handle, avatar: nil),
            session: OAuthSessionRecord(
                did: did,
                handle: handle,
                tokenJSON: tokenJSON,
                dpopKeyJSON: state.dpopKeyJSON ?? "{}"
            )
        )
    }
}

public struct ATProtoOAuthClient: OAuthClient {
    private let config: AppConfig
    private let http: HTTPClient
    private let scope = "atproto transition:generic"

    public init(config: AppConfig, http: HTTPClient = URLSessionHTTPClient()) {
        self.config = config
        self.http = http
    }

    public func start(handle: String, state: String, pkceVerifier: String, nonce: String) async throws -> OAuthStartResult {
        let identity = try await resolveIdentity(handle)
        let resource = try await fetchProtectedResourceMetadata(pdsEndpoint: identity.pdsEndpoint)
        let authServer = resource.authorizationServers.first ?? identity.pdsEndpoint
        let authorization = try await fetchAuthorizationServerMetadata(authServer: authServer)
        let dpopKey = DPoPKey()
        let requestBody = formEncoded([
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "response_type": "code",
            "scope": scope,
            "state": state,
            "code_challenge": pkceChallenge(pkceVerifier),
            "code_challenge_method": "S256",
            "login_hint": handle,
        ])
        let response = try await postWithDPoPNonceRetry(
            url: authorization.pushedAuthorizationRequestEndpoint,
            dpopKey: dpopKey,
            body: requestBody,
            accessToken: nil
        )
        let par = try JSONDecoder().decode(PARResponse.self, from: response.body)
        let redirectURL = "\(authorization.authorizationEndpoint)?client_id=\(urlEncode(clientID))&request_uri=\(urlEncode(par.requestURI))"
        return OAuthStartResult(
            redirectURL: redirectURL,
            authServer: authServer,
            tokenEndpoint: authorization.tokenEndpoint,
            pdsEndpoint: identity.pdsEndpoint,
            dpopKeyJSON: try dpopKey.exportJSON()
        )
    }

    public func complete(state: OAuthStateRecord, code: String) async throws -> OAuthCompletion {
        guard let tokenEndpoint = state.tokenEndpoint,
              let pdsEndpoint = state.pdsEndpoint,
              let dpopKeyJSON = state.dpopKeyJSON
        else {
            throw OAuthClientError.invalidState("OAuth state is missing authorization metadata")
        }

        let dpopKey = try DPoPKey(json: dpopKeyJSON)
        let tokenResponse = try await tokenRequest(
            endpoint: tokenEndpoint,
            dpopKey: dpopKey,
            form: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirectURI,
                "client_id": clientID,
                "code_verifier": state.pkceVerifier,
            ]
        )
        guard tokenResponse.scope.split(separator: " ").contains("atproto") else {
            throw OAuthClientError.invalidToken("Token response did not grant atproto scope")
        }
        guard tokenResponse.scope.split(separator: " ").contains("transition:generic") else {
            throw OAuthClientError.invalidToken("Skej requires transition:generic to write scheduled and feed records")
        }

        let profile = try? await fetchProfile(
            did: tokenResponse.sub,
            pdsEndpoint: pdsEndpoint,
            accessToken: tokenResponse.accessToken,
            dpopKey: dpopKey
        )
        let payload = ATProtoTokenPayload(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            tokenType: tokenResponse.tokenType,
            expiresIn: tokenResponse.expiresIn,
            scope: tokenResponse.scope,
            sub: tokenResponse.sub,
            pdsEndpoint: pdsEndpoint,
            tokenEndpoint: tokenEndpoint
        )
        let tokenJSON = try JSONEncoder().encodeString(payload)
        let viewer = Viewer(
            did: tokenResponse.sub,
            handle: profile?.handle ?? state.handle,
            displayName: profile?.displayName ?? profile?.handle ?? state.handle,
            avatar: profile?.avatar
        )
        return OAuthCompletion(
            viewer: viewer,
            session: OAuthSessionRecord(
                did: tokenResponse.sub,
                handle: viewer.handle,
                tokenJSON: tokenJSON,
                dpopKeyJSON: dpopKeyJSON
            )
        )
    }

    private var clientID: String {
        "\(config.publicOrigin)/oauth/client-metadata.json"
    }

    private var redirectURI: String {
        "\(config.webOrigin ?? config.publicOrigin)/oauth/callback"
    }

    private func tokenRequest(endpoint: String, dpopKey: DPoPKey, form: [String: String]) async throws -> TokenResponse {
        let response = try await postWithDPoPNonceRetry(
            url: endpoint,
            dpopKey: dpopKey,
            body: formEncoded(form),
            accessToken: nil
        )
        return try JSONDecoder().decode(TokenResponse.self, from: response.body)
    }

    private func resolveIdentity(_ handle: String) async throws -> ResolvedIdentity {
        if handle.starts(with: "did:") {
            let didDocument = try await fetchDIDDocument(did: handle)
            return ResolvedIdentity(did: handle, pdsEndpoint: try didDocument.pdsEndpoint())
        }

        if let did = try? await resolveHandleViaWellKnown(handle) {
            let didDocument = try await fetchDIDDocument(did: did)
            return ResolvedIdentity(did: did, pdsEndpoint: try didDocument.pdsEndpoint())
        }

        let url = "https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=\(urlEncode(handle))"
        let response = try await http.data(HTTPRequest(url: url))
        let resolved = try JSONDecoder().decode(ResolveHandleResponse.self, from: response.body)
        let didDocument = try await fetchDIDDocument(did: resolved.did)
        return ResolvedIdentity(did: resolved.did, pdsEndpoint: try didDocument.pdsEndpoint())
    }

    private func resolveHandleViaWellKnown(_ handle: String) async throws -> String {
        let response = try await http.data(HTTPRequest(url: "https://\(handle)/.well-known/atproto-did"))
        guard let did = String(data: response.body, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              did.starts(with: "did:")
        else {
            throw OAuthClientError.identityResolutionFailed("Invalid handle well-known response")
        }
        return did
    }

    private func fetchDIDDocument(did: String) async throws -> DIDDocument {
        let url: String
        if did.starts(with: "did:plc:") {
            url = "https://plc.directory/\(did)"
        } else if did.starts(with: "did:web:") {
            let host = did.dropFirst("did:web:".count).replacingOccurrences(of: ":", with: "/")
            url = "https://\(host)/.well-known/did.json"
        } else {
            throw OAuthClientError.identityResolutionFailed("Unsupported DID method")
        }
        let response = try await http.data(HTTPRequest(url: url))
        return try JSONDecoder().decode(DIDDocument.self, from: response.body)
    }

    private func fetchProtectedResourceMetadata(pdsEndpoint: String) async throws -> ProtectedResourceMetadata {
        let response = try await http.data(HTTPRequest(url: "\(pdsEndpoint)/.well-known/oauth-protected-resource"))
        return try JSONDecoder().decode(ProtectedResourceMetadata.self, from: response.body)
    }

    private func fetchAuthorizationServerMetadata(authServer: String) async throws -> AuthorizationServerMetadata {
        let response = try await http.data(HTTPRequest(url: "\(authServer)/.well-known/oauth-authorization-server"))
        let metadata = try JSONDecoder().decode(AuthorizationServerMetadata.self, from: response.body)
        guard metadata.scopesSupported.contains("atproto") else {
            throw OAuthClientError.authorizationServerUnsupported("Authorization server does not advertise atproto")
        }
        return metadata
    }

    private func fetchProfile(did: String, pdsEndpoint: String, accessToken: String, dpopKey: DPoPKey) async throws -> ATProtoProfile {
        let url = "\(pdsEndpoint)/xrpc/app.bsky.actor.getProfile?actor=\(urlEncode(did))"
        let response = try await getWithDPoPNonceRetry(url: url, dpopKey: dpopKey, accessToken: accessToken)
        return try JSONDecoder().decode(ATProtoProfile.self, from: response.body)
    }

    private func postWithDPoPNonceRetry(
        url: String,
        dpopKey: DPoPKey,
        body: Data,
        accessToken: String?
    ) async throws -> HTTPResponseData {
        do {
            return try await postWithDPoP(url: url, dpopKey: dpopKey, body: body, accessToken: accessToken, nonce: nil)
        } catch {
            guard let nonce = dpopNonce(from: error) else { throw error }
            return try await postWithDPoP(url: url, dpopKey: dpopKey, body: body, accessToken: accessToken, nonce: nonce)
        }
    }

    private func postWithDPoP(
        url: String,
        dpopKey: DPoPKey,
        body: Data,
        accessToken: String?,
        nonce: String?
    ) async throws -> HTTPResponseData {
        let proof = try dpopKey.proof(httpMethod: "POST", url: url, accessToken: accessToken, nonce: nonce)
        var headers = [
            "Content-Type": "application/x-www-form-urlencoded",
            "DPoP": proof,
        ]
        if let accessToken {
            headers["Authorization"] = "DPoP \(accessToken)"
        }
        return try await http.data(HTTPRequest(url: url, method: "POST", headers: headers, body: body))
    }

    private func getWithDPoPNonceRetry(url: String, dpopKey: DPoPKey, accessToken: String) async throws -> HTTPResponseData {
        do {
            return try await getWithDPoP(url: url, dpopKey: dpopKey, accessToken: accessToken, nonce: nil)
        } catch {
            guard let nonce = dpopNonce(from: error) else { throw error }
            return try await getWithDPoP(url: url, dpopKey: dpopKey, accessToken: accessToken, nonce: nonce)
        }
    }

    private func getWithDPoP(
        url: String,
        dpopKey: DPoPKey,
        accessToken: String,
        nonce: String?
    ) async throws -> HTTPResponseData {
        let proof = try dpopKey.proof(httpMethod: "GET", url: url, accessToken: accessToken, nonce: nonce)
        return try await http.data(HTTPRequest(
            url: url,
            headers: [
                "Authorization": "DPoP \(accessToken)",
                "DPoP": proof,
            ]
        ))
    }
}

public enum OAuthClientError: Error, Equatable {
    case identityResolutionFailed(String)
    case authorizationServerUnsupported(String)
    case invalidState(String)
    case invalidToken(String)
}

public struct ATProtoTokenPayload: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let tokenType: String
    public let expiresIn: Int?
    public let scope: String
    public let sub: String
    public let pdsEndpoint: String
    public let tokenEndpoint: String
}

public struct HTTPRequest: Sendable {
    public let url: String
    public let method: String
    public let headers: [String: String]
    public let body: Data?

    public init(url: String, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponseData: Sendable {
    public let body: Data
    public let headers: [String: String]
    public let statusCode: Int
}

public protocol HTTPClient: Sendable {
    func data(_ request: HTTPRequest) async throws -> HTTPResponseData
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func data(_ request: HTTPRequest) async throws -> HTTPResponseData {
        guard let url = URL(string: request.url) else {
            throw HTTPClientError.invalidURL(request.url)
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (body, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }
        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            headers[String(describing: key).lowercased()] = String(describing: value)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HTTPClientError.badStatus(
                httpResponse.statusCode,
                String(data: body, encoding: .utf8) ?? "",
                headers
            )
        }
        return HTTPResponseData(body: body, headers: headers, statusCode: httpResponse.statusCode)
    }
}

public enum HTTPClientError: Error, Equatable {
    case invalidURL(String)
    case invalidResponse
    case badStatus(Int, String, [String: String])
}

public struct DPoPKey: @unchecked Sendable {
    private let privateKey: P256.Signing.PrivateKey

    public init() {
        self.privateKey = P256.Signing.PrivateKey()
    }

    public init(json: String) throws {
        let stored = try JSONDecoder().decode(StoredDPoPKey.self, from: Data(json.utf8))
        guard let data = Data(base64Encoded: stored.rawRepresentation) else {
            throw OAuthClientError.invalidState("Invalid stored DPoP key")
        }
        self.privateKey = try P256.Signing.PrivateKey(rawRepresentation: data)
    }

    public func exportJSON() throws -> String {
        try JSONEncoder().encodeString(StoredDPoPKey(
            kty: "EC",
            crv: "P-256",
            rawRepresentation: privateKey.rawRepresentation.base64EncodedString()
        ))
    }

    public func proof(httpMethod: String, url: String, accessToken: String? = nil, nonce: String? = nil) throws -> String {
        var payload: [String: JSONValue] = [
            "jti": .string(UUID().uuidString),
            "htm": .string(httpMethod.uppercased()),
            "htu": .string(url),
            "iat": .number(Double(Int(Date().timeIntervalSince1970))),
        ]
        if let nonce {
            payload["nonce"] = .string(nonce)
        }
        if let accessToken {
            payload["ath"] = .string(base64URLEncode(Data(SHA256.hash(data: Data(accessToken.utf8)))))
        }
        let header: [String: JSONValue] = [
            "typ": .string("dpop+jwt"),
            "alg": .string("ES256"),
            "jwk": .object(publicJWK()),
        ]
        return try signJWT(header: header, payload: payload)
    }

    private func signJWT(header: [String: JSONValue], payload: [String: JSONValue]) throws -> String {
        let encoder = JSONEncoder()
        let encodedHeader = try base64URLEncode(encoder.encode(header))
        let encodedPayload = try base64URLEncode(encoder.encode(payload))
        let signingInput = "\(encodedHeader).\(encodedPayload)"
        let signature = try privateKey.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(base64URLEncode(signature.rawRepresentation))"
    }

    private func publicJWK() -> [String: JSONValue] {
        let x963 = privateKey.publicKey.x963Representation
        let x = x963.dropFirst().prefix(32)
        let y = x963.dropFirst(33).prefix(32)
        return [
            "kty": .string("EC"),
            "crv": .string("P-256"),
            "x": .string(base64URLEncode(Data(x))),
            "y": .string(base64URLEncode(Data(y))),
        ]
    }
}

private struct StoredDPoPKey: Codable {
    let kty: String
    let crv: String
    let rawRepresentation: String
}

private struct ResolvedIdentity {
    let did: String
    let pdsEndpoint: String
}

private struct ResolveHandleResponse: Codable {
    let did: String
}

private struct DIDDocument: Codable {
    let service: [DIDService]

    func pdsEndpoint() throws -> String {
        guard let service = service.first(where: { $0.id == "#atproto_pds" || $0.type == "AtprotoPersonalDataServer" }) else {
            throw OAuthClientError.identityResolutionFailed("DID document does not declare an atproto PDS")
        }
        return service.serviceEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private struct DIDService: Codable {
    let id: String
    let type: String
    let serviceEndpoint: String
}

private struct ProtectedResourceMetadata: Codable {
    let authorizationServers: [String]

    enum CodingKeys: String, CodingKey {
        case authorizationServers = "authorization_servers"
    }
}

private struct AuthorizationServerMetadata: Codable {
    let authorizationEndpoint: String
    let tokenEndpoint: String
    let pushedAuthorizationRequestEndpoint: String
    let scopesSupported: [String]

    enum CodingKeys: String, CodingKey {
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case pushedAuthorizationRequestEndpoint = "pushed_authorization_request_endpoint"
        case scopesSupported = "scopes_supported"
    }
}

private struct PARResponse: Codable {
    let requestURI: String

    enum CodingKeys: String, CodingKey {
        case requestURI = "request_uri"
    }
}

private struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let expiresIn: Int?
    let scope: String
    let sub: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
        case sub
    }
}

private struct ATProtoProfile: Codable {
    let did: String
    let handle: String?
    let displayName: String?
    let avatar: String?
}

public func pkceChallenge(_ verifier: String) -> String {
    base64URLEncode(Data(SHA256.hash(data: Data(verifier.utf8))))
}

public func formEncoded(_ fields: [String: String]) -> Data {
    fields
        .map { "\(urlEncode($0.key))=\(urlEncode($0.value))" }
        .joined(separator: "&")
        .data(using: .utf8) ?? Data()
}

public func urlEncode(_ value: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: ":/?#[]@!$&'()*+,;=")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

public func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private extension JSONEncoder {
    func encodeString<T: Encodable>(_ value: T) throws -> String {
        guard let string = String(data: try encode(value), encoding: .utf8) else {
            throw OAuthClientError.invalidState("Could not encode JSON string")
        }
        return string
    }
}

func dpopNonce(from error: Error) -> String? {
    guard case HTTPClientError.badStatus(_, _, let headers) = error,
          let nonce = headers["dpop-nonce"],
          !nonce.isEmpty
    else { return nil }
    return nonce
}

func localDID(for handle: String) -> String {
    let digest = SHA256.hash(data: Data(handle.lowercased().utf8))
    let suffix = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    return "did:plc:\(suffix)"
}
