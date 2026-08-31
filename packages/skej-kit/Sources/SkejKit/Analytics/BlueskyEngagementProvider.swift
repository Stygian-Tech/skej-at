import Foundation

public enum EngagementProviderError: Error, Equatable, Sendable {
    case invalidResponse
    case missingPosts([String])
}

public protocol EngagementProvider: Sendable {
    func discoverAuthoredPosts(accountDid: String, since: Date, stopAtKnown: Set<String>) async throws -> [EngagementPostCandidate]
    func fetchObservations(postURIs: [String], observedAt: String) async throws -> [EngagementObservation]
}

public struct BlueskyEngagementProvider: EngagementProvider, Sendable {
    public static let getPostsBatchLimit = 25

    private let origin: String
    private let http: any HTTPClient

    public init(
        origin: String = "https://public.api.bsky.app",
        http: any HTTPClient = URLSessionHTTPClient()
    ) {
        self.origin = origin.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.http = http
    }

    public func discoverAuthoredPosts(
        accountDid: String,
        since: Date,
        stopAtKnown: Set<String> = []
    ) async throws -> [EngagementPostCandidate] {
        var cursor: String?
        var discovered: [EngagementPostCandidate] = []
        var seen = Set<String>()

        discovery: while true {
            var url = "\(origin)/xrpc/app.bsky.feed.getAuthorFeed?actor=\(urlEncode(accountDid))&filter=posts_with_replies&limit=100"
            if let cursor, !cursor.isEmpty {
                url += "&cursor=\(urlEncode(cursor))"
            }
            let response = try await http.data(HTTPRequest(url: url))
            let page = try JSONDecoder().decode(AuthorFeedResponse.self, from: response.body)
            guard !page.feed.isEmpty else { break }

            for item in page.feed {
                let post = item.post
                let authoredAt = post.record.createdAt.flatMap(Timestamp.date(from:))
                    ?? Timestamp.date(from: post.indexedAt)
                guard let authoredAt else { continue }
                if authoredAt < since { break discovery }

                // Author feeds may contain repost reasons and hydrated posts by
                // other authors. Only the account's own records belong in its
                // analytics inventory.
                guard item.reason?.type != "app.bsky.feed.defs#reasonRepost",
                      post.author.did == accountDid
                else { continue }
                if stopAtKnown.contains(post.uri) { break discovery }
                guard seen.insert(post.uri).inserted else { continue }
                discovered.append(EngagementPostCandidate(
                    uri: post.uri,
                    accountDid: accountDid,
                    indexedAt: post.record.createdAt ?? post.indexedAt
                ))
            }

            guard let next = page.cursor, !next.isEmpty, next != cursor else { break }
            cursor = next
        }
        return discovered
    }

    public func fetchObservations(
        postURIs: [String],
        observedAt: String
    ) async throws -> [EngagementObservation] {
        var observations: [EngagementObservation] = []
        for start in stride(from: 0, to: postURIs.count, by: Self.getPostsBatchLimit) {
            let end = min(start + Self.getPostsBatchLimit, postURIs.count)
            let batch = Array(postURIs[start ..< end])
            let query = batch.map { "uris=\(urlEncode($0))" }.joined(separator: "&")
            let response = try await http.data(HTTPRequest(
                url: "\(origin)/xrpc/app.bsky.feed.getPosts?\(query)"
            ))
            let decoded = try JSONDecoder().decode(GetPostsResponse.self, from: response.body)
            let views = Dictionary(uniqueKeysWithValues: decoded.posts.map { ($0.uri, $0) })
            for uri in batch {
                guard let view = views[uri] else { continue }
                let fields = [
                    view.likeCount,
                    view.repostCount,
                    view.replyCount,
                    view.quoteCount,
                    view.bookmarkCount,
                ]
                observations.append(EngagementObservation(
                    postURI: uri,
                    observedAt: observedAt,
                    counts: EngagementCounts(
                        likes: view.likeCount ?? 0,
                        reposts: view.repostCount ?? 0,
                        replies: view.replyCount ?? 0,
                        quotes: view.quoteCount ?? 0,
                        bookmarks: view.bookmarkCount ?? 0
                    ),
                    complete: fields.allSatisfy { $0 != nil }
                ))
            }
        }
        return observations
    }
}

private struct AuthorFeedResponse: Decodable {
    let feed: [AuthorFeedItem]
    let cursor: String?
}

private struct AuthorFeedItem: Decodable {
    let post: EngagementPostView
    let reason: FeedReason?
}

private struct FeedReason: Decodable {
    let type: String?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
    }
}

private struct EngagementPostView: Decodable {
    let uri: String
    let author: PostAuthor
    let record: FeedPostRecord
    let indexedAt: String
    let bookmarkCount: Int?
    let replyCount: Int?
    let repostCount: Int?
    let likeCount: Int?
    let quoteCount: Int?
}

private struct PostAuthor: Decodable {
    let did: String
}

private struct FeedPostRecord: Decodable {
    let createdAt: String?
}

private struct GetPostsResponse: Decodable {
    let posts: [EngagementPostView]
}
