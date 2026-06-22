import Foundation

public struct ATProtoPDSClient: PDSClient {
    private let store: SQLiteStore
    private let http: HTTPClient
    private let clientID: String?

    public init(store: SQLiteStore, clientID: String? = nil, http: HTTPClient = URLSessionHTTPClient()) {
        self.store = store
        self.clientID = clientID
        self.http = http
    }

    public func writeSchedule(did: String, rkey: String, record: SkejScheduleRecord) async throws {
        let session = try await authenticatedSession(did: did)
        try await xrpc(
            session: session,
            method: "POST",
            path: "com.atproto.repo.putRecord",
            body: [
                "repo": .string(did),
                "collection": .string("at.skej.schedule"),
                "rkey": .string(rkey),
                "validate": .bool(false),
                "record": try record.jsonValue(),
            ]
        )
        try await store.writeScheduleRecord(did: did, rkey: rkey, record: record, now: Timestamp.iso8601())
    }

    public func getSchedule(did: String, rkey: String) async throws -> SkejScheduleRecord? {
        let session = try await authenticatedSession(did: did)
        let url = "\(session.token.pdsEndpoint)/xrpc/com.atproto.repo.getRecord?repo=\(urlEncode(did))&collection=at.skej.schedule&rkey=\(urlEncode(rkey))"
        let data = try await xrpcData(session: session, method: "GET", url: url, body: nil)
        let response = try JSONDecoder().decode(GetRecordResponse<SkejScheduleRecord>.self, from: data)
        try await store.writeScheduleRecord(did: did, rkey: rkey, record: response.value, now: Timestamp.iso8601())
        return response.value
    }

    public func listSchedules(did: String) async throws -> [String: SkejScheduleRecord] {
        let session = try await authenticatedSession(did: did)
        let url = "\(session.token.pdsEndpoint)/xrpc/com.atproto.repo.listRecords?repo=\(urlEncode(did))&collection=at.skej.schedule&limit=100"
        do {
            let data = try await xrpcData(session: session, method: "GET", url: url, body: nil)
            let response = try JSONDecoder().decode(ListRecordsResponse<SkejScheduleRecord>.self, from: data)
            var records: [String: SkejScheduleRecord] = [:]
            for record in response.records {
                guard let rkey = record.uri.split(separator: "/").last.map(String.init) else { continue }
                records[rkey] = record.value
                try await store.writeScheduleRecord(did: did, rkey: rkey, record: record.value, now: Timestamp.iso8601())
            }
            return records
        } catch {
            return try await store.listScheduleRecords(did: did)
        }
    }

    public func deleteSchedule(did: String, rkey: String) async throws {
        let session = try await authenticatedSession(did: did)
        try await xrpc(
            session: session,
            method: "POST",
            path: "com.atproto.repo.deleteRecord",
            body: [
                "repo": .string(did),
                "collection": .string("at.skej.schedule"),
                "rkey": .string(rkey),
            ]
        )
        try await store.deleteScheduleRecord(did: did, rkey: rkey)
    }

    public func publishThread(did: String, record: SkejScheduleRecord) async throws -> PublishedPost {
        let session = try await authenticatedSession(did: did)
        var last: PublishedPost?
        var parent: JSONValue?
        var root: JSONValue?

        for plan in record.posts {
            var post = try plan.feedPostValue(createdAt: Timestamp.iso8601())
            if let parent, let root {
                post["reply"] = .object(["root": root, "parent": parent])
            }
            let responseData = try await xrpc(
                session: session,
                method: "POST",
                path: "com.atproto.repo.createRecord",
                body: [
                    "repo": .string(did),
                    "collection": .string("app.bsky.feed.post"),
                    "record": .object(post),
                ]
            )
            let created = try JSONDecoder().decode(CreateRecordResponse.self, from: responseData)
            let ref: JSONValue = .object([
                "uri": .string(created.uri),
                "cid": .string(created.cid),
            ])
            if root == nil {
                root = ref
            }
            parent = ref
            last = PublishedPost(uri: created.uri, cid: created.cid)
        }

        guard let last else {
            throw PDSClientError.publishFailed("No posts to publish")
        }
        return last
    }

    @discardableResult
    private func xrpc(
        session: AuthenticatedATProtoSession,
        method: String,
        path: String,
        body: [String: JSONValue]
    ) async throws -> Data {
        let data = try JSONEncoder().encode(body)
        return try await xrpcData(
            session: session,
            method: method,
            url: "\(session.token.pdsEndpoint)/xrpc/\(path)",
            body: data
        )
    }

    private func xrpcData(
        session: AuthenticatedATProtoSession,
        method: String,
        url: String,
        body: Data?
    ) async throws -> Data {
        try await xrpcDataWithNonceAndRefresh(
            session: session,
            method: method,
            url: url,
            body: body,
            allowRefresh: true
        )
    }

    private func xrpcDataWithNonceAndRefresh(
        session: AuthenticatedATProtoSession,
        method: String,
        url: String,
        body: Data?,
        allowRefresh: Bool
    ) async throws -> Data {
        do {
            return try await xrpcData(session: session, method: method, url: url, body: body, dpopNonce: nil)
        } catch {
            if let nonce = dpopNonce(from: error) {
                do {
                    return try await xrpcData(session: session, method: method, url: url, body: body, dpopNonce: nonce)
                } catch {
                    if allowRefresh, isUnauthorized(error) {
                        let refreshed = try await refreshSession(session)
                        return try await xrpcDataWithNonceAndRefresh(
                            session: refreshed,
                            method: method,
                            url: url,
                            body: body,
                            allowRefresh: false
                        )
                    }
                    throw error
                }
            }
            if allowRefresh, isUnauthorized(error) {
                let refreshed = try await refreshSession(session)
                return try await xrpcDataWithNonceAndRefresh(
                    session: refreshed,
                    method: method,
                    url: url,
                    body: body,
                    allowRefresh: false
                )
            }
            throw error
        }
    }

    private func xrpcData(
        session: AuthenticatedATProtoSession,
        method: String,
        url: String,
        body: Data?,
        dpopNonce: String?
    ) async throws -> Data {
        let dpop = try session.dpopKey.proof(
            httpMethod: method,
            url: url,
            accessToken: session.token.accessToken,
            nonce: dpopNonce
        )
        let response = try await http.data(HTTPRequest(
            url: url,
            method: method,
            headers: [
                "Authorization": "DPoP \(session.token.accessToken)",
                "DPoP": dpop,
                "Content-Type": "application/json",
            ],
            body: body
        ))
        return response.body
    }

    private func authenticatedSession(did: String) async throws -> AuthenticatedATProtoSession {
        guard let record = try await store.oauthSession(did: did) else {
            throw PDSClientError.notConfigured
        }
        let token = try JSONDecoder().decode(ATProtoTokenPayload.self, from: Data(record.tokenJSON.utf8))
        let dpopKey = try DPoPKey(json: record.dpopKeyJSON)
        return AuthenticatedATProtoSession(did: did, handle: record.handle, token: token, dpopKey: dpopKey)
    }

    private func refreshSession(_ session: AuthenticatedATProtoSession) async throws -> AuthenticatedATProtoSession {
        guard let clientID else {
            throw PDSClientError.publishFailed("OAuth client ID is not configured")
        }
        guard let refreshToken = session.token.refreshToken else {
            throw PDSClientError.publishFailed("OAuth session cannot be refreshed")
        }
        let body = formEncoded([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])
        let response = try await refreshTokenRequest(
            endpoint: session.token.tokenEndpoint,
            dpopKey: session.dpopKey,
            body: body,
            nonce: nil
        )
        let refreshed = try JSONDecoder().decode(PDSRefreshTokenResponse.self, from: response.body)
        let token = ATProtoTokenPayload(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken ?? refreshToken,
            tokenType: refreshed.tokenType,
            expiresIn: refreshed.expiresIn,
            scope: refreshed.scope,
            sub: refreshed.sub,
            pdsEndpoint: session.token.pdsEndpoint,
            tokenEndpoint: session.token.tokenEndpoint
        )
        let tokenJSON = try JSONEncoder().encodeString(token)
        try await store.createOAuthSession(
            OAuthSessionRecord(
                did: session.did,
                handle: session.handle,
                tokenJSON: tokenJSON,
                dpopKeyJSON: try session.dpopKey.exportJSON()
            ),
            now: Timestamp.iso8601()
        )
        return AuthenticatedATProtoSession(
            did: session.did,
            handle: session.handle,
            token: token,
            dpopKey: session.dpopKey
        )
    }

    private func refreshTokenRequest(
        endpoint: String,
        dpopKey: DPoPKey,
        body: Data,
        nonce: String?
    ) async throws -> HTTPResponseData {
        let proof = try dpopKey.proof(httpMethod: "POST", url: endpoint, nonce: nonce)
        do {
            return try await http.data(HTTPRequest(
                url: endpoint,
                method: "POST",
                headers: [
                    "Content-Type": "application/x-www-form-urlencoded",
                    "DPoP": proof,
                ],
                body: body
            ))
        } catch {
            guard nonce == nil, let nonce = dpopNonce(from: error) else { throw error }
            return try await refreshTokenRequest(
                endpoint: endpoint,
                dpopKey: dpopKey,
                body: body,
                nonce: nonce
            )
        }
    }
}

private struct AuthenticatedATProtoSession {
    let did: String
    let handle: String?
    let token: ATProtoTokenPayload
    let dpopKey: DPoPKey
}

private struct PDSRefreshTokenResponse: Codable {
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

private func isUnauthorized(_ error: Error) -> Bool {
    guard case HTTPClientError.badStatus(401, _, _) = error else { return false }
    return true
}

private struct GetRecordResponse<Value: Codable>: Codable {
    let uri: String
    let cid: String?
    let value: Value
}

private struct ListRecordsResponse<Value: Codable>: Codable {
    let records: [GetRecordResponse<Value>]
}

private struct CreateRecordResponse: Codable {
    let uri: String
    let cid: String
}

private extension Encodable {
    func jsonValue() throws -> JSONValue {
        let data = try JSONEncoder().encode(self)
        let object = try JSONSerialization.jsonObject(with: data)
        return try makeJSONValue(from: object)
    }
}

private extension JSONEncoder {
    func encodeString<T: Encodable>(_ value: T) throws -> String {
        guard let string = String(data: try encode(value), encoding: .utf8) else {
            throw PDSClientError.publishFailed("Could not encode JSON string")
        }
        return string
    }
}

private extension PostPlan {
    func feedPostValue(createdAt: String) throws -> [String: JSONValue] {
        var post: [String: JSONValue] = [
            "$type": .string("app.bsky.feed.post"),
            "text": .string(text),
            "createdAt": .string(createdAt),
        ]
        if let facets {
            post["facets"] = try facets.jsonValue()
        }
        if let reply {
            post["reply"] = try reply.jsonValue()
        }
        if let embed {
            post["embed"] = try embed.jsonValue()
        }
        if let langs, !langs.isEmpty {
            post["langs"] = .array(langs.map { .string($0) })
        }
        if let labels, !labels.isEmpty {
            post["labels"] = .object([
                "$type": .string("com.atproto.label.defs#selfLabels"),
                "values": .array(labels.map { .object(["val": .string($0)]) }),
            ])
        }
        if let tags, !tags.isEmpty {
            post["tags"] = .array(tags.map { .string($0) })
        }
        return post
    }
}

private func makeJSONValue(from object: Any) throws -> JSONValue {
    switch object {
    case let value as String:
        return .string(value)
    case let value as Bool:
        return .bool(value)
    case let value as NSNumber:
        return .number(value.doubleValue)
    case let value as [Any]:
        return .array(try value.map(makeJSONValue(from:)))
    case let value as [String: Any]:
        var result: [String: JSONValue] = [:]
        for (key, item) in value {
            result[key] = try makeJSONValue(from: item)
        }
        return .object(result)
    case _ as NSNull:
        return .null
    default:
        throw PDSClientError.publishFailed("Could not encode JSON value")
    }
}
