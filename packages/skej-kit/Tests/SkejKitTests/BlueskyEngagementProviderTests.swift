import Foundation
import Testing
@testable import SkejKit

@Suite("Bluesky engagement provider")
struct BlueskyEngagementProviderTests {
    @Test("discovers authored posts while excluding repost feed entries")
    func discoversAuthoredPostsOnly() async throws {
        let actor = "did:plc:author"
        let http = EngagementHTTPStub(responses: [
            .init(body: Data(
                """
                {"feed":[
                  {"post":{"uri":"at://did:plc:author/app.bsky.feed.post/one","author":{"did":"did:plc:author"},"record":{"createdAt":"2026-08-29T12:00:00Z"},"indexedAt":"2026-08-29T12:00:01Z"}},
                  {"post":{"uri":"at://did:plc:other/app.bsky.feed.post/repost","author":{"did":"did:plc:other"},"record":{"createdAt":"2026-08-29T11:00:00Z"},"indexedAt":"2026-08-29T11:00:01Z"},"reason":{"$type":"app.bsky.feed.defs#reasonRepost"}}
                ]}
                """.utf8
            ), headers: [:], statusCode: 200)
        ])
        let provider = BlueskyEngagementProvider(origin: "https://example.test", http: http)

        let posts = try await provider.discoverAuthoredPosts(
            accountDid: actor,
            since: try #require(Timestamp.date(from: "2026-08-01T00:00:00Z")),
            stopAtKnown: []
        )

        #expect(posts.map { $0.uri } == ["at://did:plc:author/app.bsky.feed.post/one"])
    }

    @Test("hydrates post views in batches of twenty-five")
    func batchesGetPosts() async throws {
        let uris = (0 ..< 26).map { "at://did:plc:author/app.bsky.feed.post/\($0)" }
        let http = EngagementHTTPStub(responses: [
            .init(body: getPostsBody(uris: Array(uris.prefix(25))), headers: [:], statusCode: 200),
            .init(body: getPostsBody(uris: [uris[25]]), headers: [:], statusCode: 200),
        ])
        let provider = BlueskyEngagementProvider(origin: "https://example.test", http: http)

        let observations = try await provider.fetchObservations(
            postURIs: uris,
            observedAt: "2026-08-30T12:00:00Z"
        )

        #expect(observations.count == 26)
        #expect(await http.requestCount == 2)
        #expect(observations.allSatisfy { $0.complete })
        #expect(observations[0].counts.total == 10)
        #expect(observations[0].counts.bookmarks == 5)
    }

    private func getPostsBody(uris: [String]) -> Data {
        let posts = uris.map {
            """
            {"uri":"\($0)","author":{"did":"did:plc:author"},"record":{"createdAt":"2026-08-29T12:00:00Z"},"indexedAt":"2026-08-29T12:00:01Z","likeCount":4,"repostCount":3,"replyCount":2,"quoteCount":1,"bookmarkCount":5}
            """
        }.joined(separator: ",")
        return Data("{\"posts\":[\(posts)]}".utf8)
    }
}

private actor EngagementHTTPStub: HTTPClient {
    private var responses: [HTTPResponseData]
    private(set) var requests: [HTTPRequest] = []

    var requestCount: Int { requests.count }

    init(responses: [HTTPResponseData]) {
        self.responses = responses
    }

    func data(_ request: HTTPRequest) async throws -> HTTPResponseData {
        requests.append(request)
        guard !responses.isEmpty else { throw HTTPClientError.invalidResponse }
        return responses.removeFirst()
    }
}
