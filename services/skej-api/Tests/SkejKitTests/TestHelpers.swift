import Foundation
import Hummingbird
import HTTPTypes
import SkejGateway
import SkejKit

func makeTestServices(
    proFeaturesEnabled: Bool = true,
    mentionSearchClient: any ActorMentionSearching = EmptyMentionSearchClient()
) async throws -> SkejServices {
    let store = try SQLiteStore(path: ":memory:")
    try await store.migrate()
    if proFeaturesEnabled {
        let now = "2026-01-01T00:00:00Z"
        for did in ["did:plc:test", "did:plc:me", "did:plc:owner", "did:plc:admin", "did:plc:user", "did:plc:alice"] {
            try await store.upsertProEntitlement(ProEntitlement(
                subject: did,
                status: .active,
                source: "test_seed",
                createdAt: now,
                updatedAt: now
            ))
            try await store.createOAuthSession(
                OAuthSessionRecord(did: did, handle: nil, tokenJSON: "{}", dpopKeyJSON: "{}"),
                now: now
            )
        }
    }
    return SkejServices(
        config: AppConfig(
            port: 8080,
            environment: .test,
            publicOrigin: "http://localhost",
            sqlitePath: ":memory:",
            workerEnabled: false,
            proFeaturesEnabled: proFeaturesEnabled,
            adminDids: ["did:plc:admin"]
        ),
        store: store,
        pdsClient: InMemoryPDSClient(),
        oauthClient: LocalOAuthClient(),
        mentionSearchClient: mentionSearchClient
    )
}

private struct EmptyMentionSearchClient: ActorMentionSearching {
    func search(query: String, limit: Int) async throws -> SearchMentionsResponse {
        SearchMentionsResponse(actors: [])
    }
}

func makeRecord(scheduledFor: String = "2026-01-01T11:00:00Z") -> SkejScheduleRecord {
    SkejScheduleRecord(
        type: "at.skej.schedule",
        scheduledFor: scheduledFor,
        createdAt: "2026-01-01T10:00:00Z",
        updatedAt: "2026-01-01T10:00:00Z",
        status: .scheduled,
        lastError: nil,
        posts: [
            PostPlan(
                text: "hello from skej",
                facets: nil,
                reply: nil,
                embed: nil,
                langs: ["en"],
                labels: nil,
                tags: ["skej"]
            ),
        ]
    )
}

func encodedBody<T: Encodable>(_ value: T) throws -> ByteBuffer {
    var buffer = ByteBuffer()
    buffer.writeBytes(try JSONEncoder().encode(value))
    return buffer
}

func didHeaders(_ did: String) -> HTTPFields {
    var fields = HTTPFields()
    fields[HTTPField.Name("X-Skej-DID")!] = did
    return fields
}
