import Foundation
@testable import SkejKit
import Testing

@Suite
struct ATProtoPDSClientTests {
    @Test func publishesThreadSequentiallyWithStableRkeysAndReplyChain() async throws {
        let http = RecordingPublishHTTPClient()
        let client = try await authenticatedClient(http: http)
        var record = makeRecord()
        let rkeys = ["3aaaaaaaaaaaa", "3aaaaaaaaaaab", "3aaaaaaaaaaac"]
        record.publishRkey = rkeys[0]
        record.posts = [
            PostPlan(text: "First", publishRkey: rkeys[0]),
            PostPlan(text: "Second", publishRkey: rkeys[1]),
            PostPlan(text: "Third", publishRkey: rkeys[2]),
        ]

        let firstAttempt = try await client.publishThread(did: "did:plc:test", record: record)
        let secondAttempt = try await client.publishThread(did: "did:plc:test", record: record)

        #expect(firstAttempt.map(\.rkey) == rkeys)
        #expect(secondAttempt.map(\.rkey) == rkeys)
        let requests = await http.publishBodies()
        #expect(requests.count == 6)
        #expect(requests.compactMap { stringValue($0, path: ["rkey"]) } == rkeys + rkeys)
        let firstURI = "at://did:plc:test/app.bsky.feed.post/\(rkeys[0])"
        let secondURI = "at://did:plc:test/app.bsky.feed.post/\(rkeys[1])"
        #expect(strongRefURI(requests[1], path: ["record", "reply", "root"]) == firstURI)
        #expect(strongRefURI(requests[1], path: ["record", "reply", "parent"]) == firstURI)
        #expect(strongRefURI(requests[2], path: ["record", "reply", "root"]) == firstURI)
        #expect(strongRefURI(requests[2], path: ["record", "reply", "parent"]) == secondURI)
    }

    @Test func publishesLabeledHypertextWithTheAuthoredTargetFacet() async throws {
        let http = RecordingPublishHTTPClient()
        let client = try await authenticatedClient(http: http)
        var record = makeRecord()
        record.publishRkey = "3hypertextlink"
        record.posts = [PostPlan(
            text: "stale",
            source: PostSource(
                format: .markdown,
                text: "[https://shown.example](https://target.example)"
            ),
            publishRkey: record.publishRkey
        )]

        _ = try await client.publishThread(did: "did:plc:test", record: record)

        let requests = await http.publishBodies()
        #expect(stringValue(requests[0], path: ["record", "text"]) == "https://shown.example")
        guard case let .array(facets)? = value(requests[0], path: ["record", "facets"]) else {
            Issue.record("Expected a labeled-link facet in the published post")
            return
        }
        #expect(facets.count == 1)
        #expect(facetFeatureString(facets[0], key: "uri") == "https://target.example")
        #expect(facetByteRange(facets[0]) == 0..<21)
    }

    @Test func preservesCodeMarkersForClientSideRendering() async throws {
        let http = RecordingPublishHTTPClient()
        let client = try await authenticatedClient(http: http)
        var record = makeRecord()
        record.publishRkey = "3clientcodefmt"
        record.posts = [PostPlan(
            text: "stale",
            source: PostSource(
                format: .markdown,
                text: "Use `mono`.\n```swift\nlet answer = 42\n```"
            ),
            publishRkey: record.publishRkey
        )]

        _ = try await client.publishThread(did: "did:plc:test", record: record)

        let requests = await http.publishBodies()
        #expect(
            stringValue(requests[0], path: ["record", "text"]) ==
                "Use `mono`.\n```swift\nlet answer = 42\n```"
        )
        #expect(value(requests[0], path: ["record", "facets"]) == nil)
    }

    @Test func appliesExternalReplyToFirstPostThenChainsThread() async throws {
        let http = RecordingPublishHTTPClient()
        let client = try await authenticatedClient(http: http)
        var record = makeRecord()
        record.publishRkey = "3bbbbbbbbbbbb"
        record.dependency = ScheduleDependency(
            dependsOnScheduleUri: "at://did:plc:test/at.skej.schedule/parent",
            relationship: .reply,
            parentPublishedUri: "at://did:plc:other/app.bsky.feed.post/parent",
            parentPublishedCid: "bafyparent"
        )
        record.posts = [
            PostPlan(text: "External reply", publishRkey: "3bbbbbbbbbbbb"),
            PostPlan(text: "Follow-up", publishRkey: "3bbbbbbbbbbbc"),
        ]

        _ = try await client.publishThread(did: "did:plc:test", record: record)

        let requests = await http.publishBodies()
        #expect(strongRefURI(requests[0], path: ["record", "reply", "root"]) == "at://did:plc:other/app.bsky.feed.post/parent")
        #expect(strongRefCID(requests[0], path: ["record", "reply", "parent"]) == "bafyparent")
        #expect(strongRefURI(requests[1], path: ["record", "reply", "root"]) == "at://did:plc:test/app.bsky.feed.post/3bbbbbbbbbbbb")
    }

    @Test func publishesQuoteAsRecordOrRecordWithMedia() async throws {
        let http = RecordingPublishHTTPClient()
        let client = try await authenticatedClient(http: http)
        let dependency = ScheduleDependency(
            dependsOnScheduleUri: "at://did:plc:test/at.skej.schedule/parent",
            relationship: .quote,
            parentPublishedUri: "at://did:plc:other/app.bsky.feed.post/parent",
            parentPublishedCid: "bafyparent"
        )
        var plain = makeRecord()
        plain.publishRkey = "3cccccccccccc"
        plain.dependency = dependency
        plain.posts = [PostPlan(text: "Quote", publishRkey: plain.publishRkey)]
        var withMedia = makeRecord()
        withMedia.publishRkey = "3dddddddddddd"
        withMedia.dependency = dependency
        withMedia.posts = [PostPlan(
            text: "Quote with media",
            publishRkey: withMedia.publishRkey,
            embed: .object([
                "$type": .string("app.bsky.embed.images"),
                "images": .array([]),
            ])
        )]

        _ = try await client.publishThread(did: "did:plc:test", record: plain)
        _ = try await client.publishThread(did: "did:plc:test", record: withMedia)

        let requests = await http.publishBodies()
        #expect(stringValue(requests[0], path: ["record", "embed", "$type"]) == "app.bsky.embed.record")
        #expect(stringValue(requests[1], path: ["record", "embed", "$type"]) == "app.bsky.embed.recordWithMedia")
        #expect(stringValue(requests[1], path: ["record", "embed", "media", "$type"]) == "app.bsky.embed.images")
        #expect(strongRefCID(requests[1], path: ["record", "embed", "record", "record"]) == "bafyparent")
    }

    @Test func primesAndCachesDPoPNonceBeforeBlobUpload() async throws {
        let did = "did:plc:test"
        let pdsEndpoint = "https://pds.example.com"
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let token = ATProtoTokenPayload(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            tokenType: "DPoP",
            expiresIn: 3_600,
            scope: "atproto",
            sub: did,
            pdsEndpoint: pdsEndpoint,
            tokenEndpoint: "https://auth.example.com/token"
        )
        let key = DPoPKey()
        try await store.createOAuthSession(
            OAuthSessionRecord(
                did: did,
                handle: "test.example.com",
                tokenJSON: String(decoding: try JSONEncoder().encode(token), as: UTF8.self),
                dpopKeyJSON: try key.exportJSON()
            ),
            now: "2026-08-05T00:00:00Z"
        )
        let http = NonceChallengeHTTPClient()
        let client = ATProtoPDSClient(store: store, http: http)

        let blob = try await client.uploadBlob(
            did: did,
            data: Data([0x89, 0x50, 0x4e, 0x47]),
            mimeType: "image/png"
        )

        #expect(blob.ref.link == "bafytest")
        #expect(blob.mimeType == "image/png")
        #expect(blob.size == 4)
        let requests = await http.requests()
        #expect(requests.count == 3)
        #expect(requests.map(\.method) == ["GET", "GET", "POST"])
        #expect(dpopNonce(in: requests[0]) == nil)
        #expect(dpopNonce(in: requests[1]) == "nonce-1")
        #expect(dpopNonce(in: requests[2]) == "nonce-2")
        #expect(requests[2].url == "\(pdsEndpoint)/xrpc/com.atproto.repo.uploadBlob")
    }

    @Test func listsCachedRecordsWhenAccountHasNoOAuthSession() async throws {
        let did = "did:plc:disconnected"
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let team = SkejTeamRecord(
            ownerAdminDid: did,
            title: "Cached Team",
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )
        try await store.writeProtocolRecord(
            did: did,
            collection: "at.skej.team",
            rkey: "team-1",
            record: team,
            now: "2026-01-01T00:00:00Z"
        )
        let client = ATProtoPDSClient(store: store, http: UnreachableHTTPClient())

        let records = try await client.listRecords(did: did, collection: "at.skej.team", as: SkejTeamRecord.self)

        #expect(records.count == 1)
        #expect(records["team-1"]?.title == "Cached Team")
    }

    @Test func listsNoSchedulesWhenAccountHasNoOAuthSession() async throws {
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let client = ATProtoPDSClient(store: store, http: UnreachableHTTPClient())

        let records = try await client.listSchedules(did: "did:plc:disconnected")

        #expect(records.isEmpty)
    }

    @Test func getsCachedRecordWhenAccountHasNoOAuthSession() async throws {
        let did = "did:plc:disconnected"
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let team = SkejTeamRecord(
            ownerAdminDid: did,
            title: "Cached Team",
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )
        try await store.writeProtocolRecord(
            did: did,
            collection: "at.skej.team",
            rkey: "team-1",
            record: team,
            now: "2026-01-01T00:00:00Z"
        )
        let client = ATProtoPDSClient(store: store, http: UnreachableHTTPClient())

        let record = try await client.getRecord(did: did, collection: "at.skej.team", rkey: "team-1", as: SkejTeamRecord.self)
        let missing = try await client.getRecord(did: did, collection: "at.skej.team", rkey: "absent", as: SkejTeamRecord.self)

        #expect(record?.title == "Cached Team")
        #expect(missing == nil)
    }

    @Test func flagsAccountForReauthWhenReadIsRejected() async throws {
        let did = "did:plc:disconnected"
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        try await store.upsertManagedAccount(
            ManagedAccount(
                did: did,
                handle: "stale.example.com",
                displayName: nil,
                avatar: nil,
                pdsEndpoint: "https://pds.example.com",
                status: .active,
                isDefault: true
            ),
            now: "2026-01-01T00:00:00Z"
        )
        let client = ATProtoPDSClient(store: store, http: UnreachableHTTPClient())

        _ = try await client.listSchedules(did: did)

        #expect(try await store.managedAccount(did: did)?.status == .needsReauth)
    }

    @Test func leavesAccountActiveWhenPDSIsMerelyUnreachable() async throws {
        let did = "did:plc:connected"
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        try await store.upsertManagedAccount(
            ManagedAccount(
                did: did,
                handle: "fine.example.com",
                displayName: nil,
                avatar: nil,
                pdsEndpoint: "https://pds.example.com",
                status: .active,
                isDefault: true
            ),
            now: "2026-01-01T00:00:00Z"
        )
        try await store.createOAuthSession(
            OAuthSessionRecord(
                did: did,
                handle: "fine.example.com",
                tokenJSON: String(decoding: try JSONEncoder().encode(ATProtoTokenPayload(
                    accessToken: "access-token",
                    refreshToken: nil,
                    tokenType: "DPoP",
                    expiresIn: 3_600,
                    scope: "atproto",
                    sub: did,
                    pdsEndpoint: "https://pds.example.com",
                    tokenEndpoint: "https://auth.example.com/token"
                )), as: UTF8.self),
                dpopKeyJSON: try DPoPKey().exportJSON()
            ),
            now: "2026-01-01T00:00:00Z"
        )
        let client = ATProtoPDSClient(store: store, http: UnreachableHTTPClient())

        _ = try await client.listSchedules(did: did)

        #expect(try await store.managedAccount(did: did)?.status == .active)
    }
}

private func authenticatedClient(http: any HTTPClient) async throws -> ATProtoPDSClient {
    let did = "did:plc:test"
    let store = try SQLiteStore(path: ":memory:")
    try await store.migrate()
    let token = ATProtoTokenPayload(
        accessToken: "access-token",
        refreshToken: nil,
        tokenType: "DPoP",
        expiresIn: 3_600,
        scope: "atproto",
        sub: did,
        pdsEndpoint: "https://pds.example.com",
        tokenEndpoint: "https://auth.example.com/token"
    )
    try await store.createOAuthSession(
        OAuthSessionRecord(
            did: did,
            handle: "test.example.com",
            tokenJSON: String(decoding: try JSONEncoder().encode(token), as: UTF8.self),
            dpopKeyJSON: try DPoPKey().exportJSON()
        ),
        now: "2026-08-05T00:00:00Z"
    )
    return ATProtoPDSClient(store: store, http: http)
}

private actor RecordingPublishHTTPClient: HTTPClient {
    private var bodies: [[String: JSONValue]] = []

    func data(_ request: HTTPRequest) async throws -> HTTPResponseData {
        guard request.url.hasSuffix("/xrpc/com.atproto.repo.putRecord"),
              let body = request.body,
              let raw = try? JSONDecoder().decode([String: JSONValue].self, from: body),
              case let .string(rkey)? = raw["rkey"],
              case let .string(repo)? = raw["repo"],
              case let .string(collection)? = raw["collection"]
        else {
            throw HTTPClientError.invalidResponse
        }
        bodies.append(raw)
        return HTTPResponseData(
            body: Data(#"{"uri":"at://\#(repo)/\#(collection)/\#(rkey)","cid":"bafy\#(rkey)"}"#.utf8),
            headers: [:],
            statusCode: 200
        )
    }

    func publishBodies() -> [[String: JSONValue]] { bodies }
}

private func value(_ object: [String: JSONValue], path: [String]) -> JSONValue? {
    path.reduce(JSONValue.object(object) as JSONValue?) { partial, key in
        guard case let .object(fields)? = partial else { return nil }
        return fields[key]
    }
}

private func stringValue(_ object: [String: JSONValue], path: [String]) -> String? {
    guard case let .string(result)? = value(object, path: path) else { return nil }
    return result
}

private func strongRefURI(_ object: [String: JSONValue], path: [String]) -> String? {
    stringValue(object, path: path + ["uri"])
}

private func strongRefCID(_ object: [String: JSONValue], path: [String]) -> String? {
    stringValue(object, path: path + ["cid"])
}

private func facetFeatureString(_ facet: JSONValue, key: String) -> String? {
    guard case let .object(object) = facet,
          case let .array(features)? = object["features"],
          case let .object(feature)? = features.first,
          case let .string(result)? = feature[key]
    else { return nil }
    return result
}

private func facetByteRange(_ facet: JSONValue) -> Range<Int>? {
    guard case let .object(object) = facet,
          case let .object(index)? = object["index"],
          case let .number(start)? = index["byteStart"],
          case let .number(end)? = index["byteEnd"]
    else { return nil }
    return Int(start)..<Int(end)
}

private struct UnreachableHTTPClient: HTTPClient {
    func data(_ request: HTTPRequest) async throws -> HTTPResponseData {
        throw HTTPClientError.badStatus(503, "unreachable", [:])
    }
}

private actor NonceChallengeHTTPClient: HTTPClient {
    private var recordedRequests: [HTTPRequest] = []

    func data(_ request: HTTPRequest) async throws -> HTTPResponseData {
        recordedRequests.append(request)
        if request.url.hasSuffix("/xrpc/com.atproto.server.getSession") {
            guard dpopNonce(in: request) != nil else {
                throw HTTPClientError.badStatus(
                    401,
                    #"{"error":"use_dpop_nonce"}"#,
                    ["dpop-nonce": "nonce-1"]
                )
            }
            return HTTPResponseData(
                body: Data("{}".utf8),
                headers: ["dpop-nonce": "nonce-2"],
                statusCode: 200
            )
        }
        return HTTPResponseData(
            body: Data(#"{"blob":{"$type":"blob","ref":{"$link":"bafytest"},"mimeType":"image/png","size":4}}"#.utf8),
            headers: [:],
            statusCode: 200
        )
    }

    func requests() -> [HTTPRequest] {
        recordedRequests
    }
}

private func dpopNonce(in request: HTTPRequest) -> String? {
    guard let proof = request.headers["DPoP"] else { return nil }
    let parts = proof.split(separator: ".")
    guard parts.count == 3 else { return nil }
    var encoded = String(parts[1])
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
    guard let data = Data(base64Encoded: encoded),
          let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return payload["nonce"] as? String
}
