import Foundation
@testable import SkejKit
import Testing

@Test func publicMentionSearchEncodesQueryAndDecodesCanonicalMetadata() async throws {
    let http = MentionSearchHTTPClient()
    let client = PublicActorMentionSearchClient(
        http: http,
        serviceURL: try #require(URL(string: "https://public.example"))
    )
    let response = try await client.search(query: "alice test", limit: 4)

    #expect(response.actors == [MentionActor(
        handle: "alice.test",
        did: "did:plc:alice",
        displayName: "Alice"
    )])
    let request = await http.lastRequest()
    #expect(request?.url.contains("q=alice%20test") == true)
    #expect(request?.url.contains("limit=4") == true)
}

private actor MentionSearchHTTPClient: HTTPClient {
    private var request: HTTPRequest?

    func data(_ request: HTTPRequest) async throws -> HTTPResponseData {
        self.request = request
        return HTTPResponseData(
            body: Data(#"{"actors":[{"handle":"alice.test","did":"did:plc:alice","displayName":"Alice"}]}"#.utf8),
            headers: [:],
            statusCode: 200
        )
    }

    func lastRequest() -> HTTPRequest? { request }
}
