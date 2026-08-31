import Foundation

public struct MentionActor: Codable, Equatable, Sendable {
    public let handle: String
    public let did: String
    public let displayName: String?
    public let avatar: String?

    public init(handle: String, did: String, displayName: String? = nil, avatar: String? = nil) {
        self.handle = handle
        self.did = did
        self.displayName = displayName
        self.avatar = avatar
    }
}

public struct SearchMentionsResponse: Codable, Equatable, Sendable {
    public let actors: [MentionActor]

    public init(actors: [MentionActor]) {
        self.actors = actors
    }
}

public protocol ActorMentionSearching: Sendable {
    func search(query: String, limit: Int) async throws -> SearchMentionsResponse
}

public struct PublicActorMentionSearchClient: ActorMentionSearching {
    private let http: any HTTPClient
    private let serviceURL: URL

    public init(
        http: any HTTPClient = URLSessionHTTPClient(),
        serviceURL: URL = URL(string: "https://public.api.bsky.app")!
    ) {
        self.http = http
        self.serviceURL = serviceURL
    }

    public func search(query: String, limit: Int) async throws -> SearchMentionsResponse {
        var components = URLComponents(
            url: serviceURL.appending(path: "xrpc/app.bsky.actor.searchActorsTypeahead"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = components?.url else {
            throw HTTPClientError.invalidURL(serviceURL.absoluteString)
        }
        let response = try await http.data(HTTPRequest(url: url.absoluteString))
        return try JSONDecoder().decode(SearchMentionsResponse.self, from: response.body)
    }
}
