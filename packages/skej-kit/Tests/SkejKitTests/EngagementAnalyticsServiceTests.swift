import Foundation
import Testing
@testable import SkejKit

@Suite("Engagement analytics")
struct EngagementAnalyticsServiceTests {
    @Test("persists change-only snapshots and unavailable post state")
    func sqliteChangeOnlySnapshots() async throws {
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let uri = "at://did:plc:a/app.bsky.feed.post/persisted"
        try await store.upsertEngagementPosts([
            EngagementPostCandidate(uri: uri, accountDid: "did:plc:a", indexedAt: "2026-08-30T00:00:00Z"),
        ], observedAt: "2026-08-30T00:01:00Z")
        let posts = try await store.trackedEngagementPosts(accountDids: ["did:plc:a"])
        let observation = EngagementObservation(
            postURI: uri,
            observedAt: "2026-08-30T00:02:00Z",
            counts: EngagementCounts(likes: 3, bookmarks: 4),
            complete: true
        )

        try await store.recordEngagementBatch(
            posts: posts,
            observations: [observation],
            checkedAt: "2026-08-30T00:02:00Z"
        )
        try await store.recordEngagementBatch(
            posts: posts,
            observations: [EngagementObservation(
                postURI: uri,
                observedAt: "2026-08-30T00:03:00Z",
                counts: observation.counts,
                complete: true
            )],
            checkedAt: "2026-08-30T00:03:00Z"
        )
        #expect(try await store.engagementSnapshots(
            accountDids: ["did:plc:a"],
            through: "2026-08-31T00:00:00Z"
        ).count == 1)

        try await store.recordEngagementBatch(
            posts: posts,
            observations: [],
            checkedAt: "2026-08-30T00:04:00Z"
        )
        let tracked = try #require(await store.trackedEngagementPosts(accountDids: ["did:plc:a"]).first)
        #expect(tracked.availability == EngagementPostAvailability.unavailable)
        #expect(tracked.lastError == "post_unavailable")
    }

    @Test("reports signed changes and excludes bookmarks from total")
    func signedChanges() async throws {
        let store = AnalyticsStoreStub(
            posts: [TrackedEngagementPost(
                uri: "at://did:plc:a/app.bsky.feed.post/one",
                accountDid: "did:plc:a",
                indexedAt: "2026-08-01T00:00:00Z",
                firstObservedAt: "2026-08-20T00:00:00Z",
                lastCheckedAt: "2026-08-30T12:00:00Z"
            )],
            snapshots: [
                Self.snapshot(at: "2026-08-29T00:00:00Z", likes: 10, bookmarks: 20),
                Self.snapshot(at: "2026-08-30T00:00:00Z", likes: 8, bookmarks: 25),
            ],
            states: [EngagementAccountCollectionState(
                accountDid: "did:plc:a",
                lastDiscoveredAt: "2026-08-30T12:00:00Z",
                coverageStartedAt: "2026-08-20T00:00:00Z"
            )]
        )
        let service = EngagementAnalyticsService(store: store)

        let report = try await service.report(
            accounts: [ManagedAccount(did: "did:plc:a", handle: "a.test")],
            from: try #require(Timestamp.date(from: "2026-08-29T00:00:00Z")),
            to: try #require(Timestamp.date(from: "2026-08-31T00:00:00Z")),
            bucket: .day,
            timezone: "UTC",
            now: try #require(Timestamp.date(from: "2026-08-30T12:05:00Z"))
        )

        let account = try #require(report.accounts.first)
        #expect(account.period.likes == -2)
        #expect(account.period.bookmarks == 5)
        #expect(account.period.total == -2)
        #expect(account.lifetime.total == 8)
        #expect(account.lifetime.bookmarks == 25)
        #expect(report.status == EngagementDataStatus.live)
    }

    @Test("treats the first observation of an older post as a partial baseline")
    func olderPostBaseline() async throws {
        let store = AnalyticsStoreStub(
            posts: [TrackedEngagementPost(
                uri: "at://did:plc:a/app.bsky.feed.post/old",
                accountDid: "did:plc:a",
                indexedAt: "2026-01-01T00:00:00Z",
                firstObservedAt: "2026-08-29T00:00:00Z",
                lastCheckedAt: "2026-08-30T00:00:00Z"
            )],
            snapshots: [
                Self.snapshot(uri: "at://did:plc:a/app.bsky.feed.post/old", at: "2026-08-29T00:00:00Z", likes: 100),
                Self.snapshot(uri: "at://did:plc:a/app.bsky.feed.post/old", at: "2026-08-30T00:00:00Z", likes: 102),
            ]
        )
        let service = EngagementAnalyticsService(store: store)
        let report = try await service.report(
            accounts: [ManagedAccount(did: "did:plc:a")],
            from: try #require(Timestamp.date(from: "2026-08-28T00:00:00Z")),
            to: try #require(Timestamp.date(from: "2026-08-31T00:00:00Z")),
            bucket: .day,
            timezone: "UTC",
            now: try #require(Timestamp.date(from: "2026-08-30T00:01:00Z"))
        )

        #expect(report.accounts[0].period.likes == 2)
        #expect(report.status == EngagementDataStatus.partial)
    }

    private static func snapshot(
        uri: String = "at://did:plc:a/app.bsky.feed.post/one",
        at: String,
        likes: Int,
        bookmarks: Int = 0
    ) -> EngagementSnapshot {
        EngagementSnapshot(
            postURI: uri,
            accountDid: "did:plc:a",
            observedAt: at,
            counts: EngagementCounts(likes: likes, bookmarks: bookmarks),
            complete: true
        )
    }
}

private actor AnalyticsStoreStub: EngagementStore {
    var posts: [TrackedEngagementPost]
    var snapshots: [EngagementSnapshot]
    var states: [String: EngagementAccountCollectionState]

    init(
        posts: [TrackedEngagementPost] = [],
        snapshots: [EngagementSnapshot] = [],
        states: [EngagementAccountCollectionState] = []
    ) {
        self.posts = posts
        self.snapshots = snapshots
        self.states = Dictionary(uniqueKeysWithValues: states.map { ($0.accountDid, $0) })
    }

    func engagementCollectionState(accountDid: String) -> EngagementAccountCollectionState? { states[accountDid] }
    func setEngagementCollectionState(_ state: EngagementAccountCollectionState) { states[state.accountDid] = state }
    func knownEngagementPostURIs(accountDid: String) -> Set<String> { Set(posts.filter { $0.accountDid == accountDid }.map(\.uri)) }
    func upsertEngagementPosts(_ posts: [EngagementPostCandidate], observedAt: String) {}
    func correlateEngagementPosts(accountDid: String, schedulePosts: [String: String]) {}
    func engagementPostsDue(accountDids: [String], now: String, recentCutoff: String, recentIntervalSeconds: Int, oldIntervalSeconds: Int) -> [TrackedEngagementPost] { [] }
    func recordEngagementBatch(posts: [TrackedEngagementPost], observations: [EngagementObservation], checkedAt: String) {}
    func trackedEngagementPosts(accountDids: [String]) -> [TrackedEngagementPost] { posts.filter { accountDids.contains($0.accountDid) } }
    func engagementSnapshots(accountDids: [String], through: String) -> [EngagementSnapshot] { snapshots.filter { accountDids.contains($0.accountDid) && $0.observedAt <= through } }
}
