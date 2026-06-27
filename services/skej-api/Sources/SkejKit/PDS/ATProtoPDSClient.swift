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

    public func writeRecord<Value: Codable & Sendable>(did: String, collection: String, rkey: String, record: Value) async throws {
        let session = try await authenticatedSession(did: did)
        try await xrpc(
            session: session,
            method: "POST",
            path: "com.atproto.repo.putRecord",
            body: [
                "repo": .string(did),
                "collection": .string(collection),
                "rkey": .string(rkey),
                "validate": .bool(false),
                "record": try record.skejJSONValue(),
            ]
        )
        try await store.writeProtocolRecord(
            did: did,
            collection: collection,
            rkey: rkey,
            record: record,
            now: Timestamp.iso8601()
        )
    }

    public func getRecord<Value: Codable & Sendable>(did: String, collection: String, rkey: String, as type: Value.Type) async throws -> Value? {
        let session = try await authenticatedSession(did: did)
        let url = "\(session.token.pdsEndpoint)/xrpc/com.atproto.repo.getRecord?repo=\(urlEncode(did))&collection=\(urlEncode(collection))&rkey=\(urlEncode(rkey))"
        let data = try await xrpcData(session: session, method: "GET", url: url, body: nil)
        let response = try JSONDecoder().decode(GetRecordResponse<Value>.self, from: data)
        try await store.writeProtocolRecord(
            did: did,
            collection: collection,
            rkey: rkey,
            record: response.value,
            now: Timestamp.iso8601()
        )
        return response.value
    }

    public func listRecords<Value: Codable & Sendable>(did: String, collection: String, as type: Value.Type) async throws -> [String: Value] {
        let session = try await authenticatedSession(did: did)
        let url = "\(session.token.pdsEndpoint)/xrpc/com.atproto.repo.listRecords?repo=\(urlEncode(did))&collection=\(urlEncode(collection))&limit=100"
        do {
            let data = try await xrpcData(session: session, method: "GET", url: url, body: nil)
            let response = try JSONDecoder().decode(ListRecordsResponse<Value>.self, from: data)
            var records: [String: Value] = [:]
            for record in response.records {
                guard let rkey = record.uri.split(separator: "/").last.map(String.init) else { continue }
                records[rkey] = record.value
                try await store.writeProtocolRecord(
                    did: did,
                    collection: collection,
                    rkey: rkey,
                    record: record.value,
                    now: Timestamp.iso8601()
                )
            }
            return records
        } catch {
            return try await store.listProtocolRecords(did: did, collection: collection, as: type)
        }
    }

    public func writeSchedule(did: String, rkey: String, record: SkejScheduleRecord) async throws {
        try await writeRecord(did: did, collection: "at.skej.schedule", rkey: rkey, record: record)
    }

    public func getSchedule(did: String, rkey: String) async throws -> SkejScheduleRecord? {
        try await getRecord(did: did, collection: "at.skej.schedule", rkey: rkey, as: SkejScheduleRecord.self)
    }

    public func listSchedules(did: String) async throws -> [String: SkejScheduleRecord] {
        try await listRecords(did: did, collection: "at.skej.schedule", as: SkejScheduleRecord.self)
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
        let recordValue: JSONValue
        if let shadowRecord = record.shadowRecord {
            recordValue = shadowRecord
        } else if let plan = record.posts.first {
            recordValue = .object(try plan.feedPostValue(createdAt: Timestamp.iso8601()))
        } else {
            throw PDSClientError.publishFailed("No record payload to publish")
        }
        let responseData = try await xrpc(
            session: session,
            method: "POST",
            path: "com.atproto.repo.putRecord",
            body: [
                "repo": .string(did),
                "collection": .string(record.recordType),
                "rkey": .string(record.publishRkey),
                "validate": .bool(false),
                "record": recordValue,
            ]
        )
        let created = try JSONDecoder().decode(CreateRecordResponse.self, from: responseData)
        return PublishedPost(uri: created.uri, cid: created.cid)
    }

    public func getBrandProfile(did: String) async throws -> BrandProfile {
        if let account = try await store.managedAccount(did: did) {
            return BrandProfile(
                did: did,
                handle: account.handle,
                displayName: account.displayName,
                avatar: account.avatar
            )
        }
        return BrandProfile(did: did)
    }

    public func updateBrandProfile(did: String, profile: UpdateBrandProfileRequest) async throws -> BrandProfile {
        var record: [String: JSONValue] = [
            "$type": .string("app.bsky.actor.profile")
        ]
        if let displayName = profile.displayName {
            record["displayName"] = .string(displayName)
        }
        if let description = profile.description {
            record["description"] = .string(description)
        }
        if let avatar = profile.avatar {
            record["avatar"] = .string(avatar)
        }
        let session = try await authenticatedSession(did: did)
        try await xrpc(
            session: session,
            method: "POST",
            path: "com.atproto.repo.putRecord",
            body: [
                "repo": .string(did),
                "collection": .string("app.bsky.actor.profile"),
                "rkey": .string("self"),
                "validate": .bool(false),
                "record": .object(record),
            ]
        )
        let existing = try await store.managedAccount(did: did)
        let updated = ManagedAccount(
            did: did,
            handle: existing?.handle,
            displayName: profile.displayName ?? existing?.displayName,
            avatar: profile.avatar ?? existing?.avatar,
            pdsEndpoint: existing?.pdsEndpoint,
            status: existing?.status ?? .active,
            isDefault: existing?.isDefault ?? false
        )
        try await store.upsertManagedAccount(updated, now: Timestamp.iso8601())
        return BrandProfile(
            did: did,
            handle: updated.handle,
            displayName: updated.displayName,
            description: profile.description,
            avatar: updated.avatar
        )
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
            post["facets"] = try facets.skejJSONValue()
        }
        if let reply {
            post["reply"] = try reply.skejJSONValue()
        }
        if let embed {
            post["embed"] = try embed.skejJSONValue()
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
