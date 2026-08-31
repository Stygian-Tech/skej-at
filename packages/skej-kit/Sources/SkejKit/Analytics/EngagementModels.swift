import Foundation

public enum EngagementBucket: String, Codable, CaseIterable, Sendable {
    case day
    case week
}

public enum EngagementMetric: String, Codable, CaseIterable, Sendable {
    case total
    case likes
    case reposts
    case replies
    case quotes
    case bookmarks
}

public enum EngagementDataStatus: String, Codable, Sendable {
    case live
    case stale
    case partial
}

public enum EngagementPostAvailability: String, Codable, Sendable {
    case available
    case unavailable
}

public struct EngagementCounts: Codable, Equatable, Sendable {
    public var likes: Int
    public var reposts: Int
    public var replies: Int
    public var quotes: Int
    public var bookmarks: Int

    /// Bookmarks remain visible as their own metric but are intentionally not
    /// part of Skej's headline engagement total.
    public var total: Int { likes + reposts + replies + quotes }

    public init(
        likes: Int = 0,
        reposts: Int = 0,
        replies: Int = 0,
        quotes: Int = 0,
        bookmarks: Int = 0
    ) {
        self.likes = likes
        self.reposts = reposts
        self.replies = replies
        self.quotes = quotes
        self.bookmarks = bookmarks
    }

    public static let zero = EngagementCounts()

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            likes: lhs.likes + rhs.likes,
            reposts: lhs.reposts + rhs.reposts,
            replies: lhs.replies + rhs.replies,
            quotes: lhs.quotes + rhs.quotes,
            bookmarks: lhs.bookmarks + rhs.bookmarks
        )
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        Self(
            likes: lhs.likes - rhs.likes,
            reposts: lhs.reposts - rhs.reposts,
            replies: lhs.replies - rhs.replies,
            quotes: lhs.quotes - rhs.quotes,
            bookmarks: lhs.bookmarks - rhs.bookmarks
        )
    }
}

public struct EngagementPostCandidate: Equatable, Sendable {
    public let uri: String
    public let accountDid: String
    public let indexedAt: String
    public let scheduleRkey: String?

    public init(uri: String, accountDid: String, indexedAt: String, scheduleRkey: String? = nil) {
        self.uri = uri
        self.accountDid = accountDid
        self.indexedAt = indexedAt
        self.scheduleRkey = scheduleRkey
    }
}

public struct TrackedEngagementPost: Equatable, Sendable {
    public let uri: String
    public let accountDid: String
    public let indexedAt: String
    public let scheduleRkey: String?
    public let firstObservedAt: String
    public let lastCheckedAt: String?
    public let availability: EngagementPostAvailability
    public let lastError: String?

    public init(
        uri: String,
        accountDid: String,
        indexedAt: String,
        scheduleRkey: String? = nil,
        firstObservedAt: String,
        lastCheckedAt: String? = nil,
        availability: EngagementPostAvailability = .available,
        lastError: String? = nil
    ) {
        self.uri = uri
        self.accountDid = accountDid
        self.indexedAt = indexedAt
        self.scheduleRkey = scheduleRkey
        self.firstObservedAt = firstObservedAt
        self.lastCheckedAt = lastCheckedAt
        self.availability = availability
        self.lastError = lastError
    }
}

public struct EngagementObservation: Equatable, Sendable {
    public let postURI: String
    public let observedAt: String
    public let counts: EngagementCounts
    public let complete: Bool

    public init(postURI: String, observedAt: String, counts: EngagementCounts, complete: Bool) {
        self.postURI = postURI
        self.observedAt = observedAt
        self.counts = counts
        self.complete = complete
    }
}

public struct EngagementSnapshot: Equatable, Sendable {
    public let postURI: String
    public let accountDid: String
    public let observedAt: String
    public let counts: EngagementCounts
    public let complete: Bool

    public init(
        postURI: String,
        accountDid: String,
        observedAt: String,
        counts: EngagementCounts,
        complete: Bool
    ) {
        self.postURI = postURI
        self.accountDid = accountDid
        self.observedAt = observedAt
        self.counts = counts
        self.complete = complete
    }
}

public struct EngagementAccountCollectionState: Equatable, Sendable {
    public let accountDid: String
    public let lastDiscoveredAt: String?
    public let coverageStartedAt: String?
    public let lastError: String?

    public init(
        accountDid: String,
        lastDiscoveredAt: String? = nil,
        coverageStartedAt: String? = nil,
        lastError: String? = nil
    ) {
        self.accountDid = accountDid
        self.lastDiscoveredAt = lastDiscoveredAt
        self.coverageStartedAt = coverageStartedAt
        self.lastError = lastError
    }
}

public struct EngagementPoint: Codable, Equatable, Sendable {
    public let bucketStart: String
    public let likes: Int
    public let reposts: Int
    public let replies: Int
    public let quotes: Int
    public let bookmarks: Int
    public let total: Int

    public init(bucketStart: String, counts: EngagementCounts) {
        self.bucketStart = bucketStart
        self.likes = counts.likes
        self.reposts = counts.reposts
        self.replies = counts.replies
        self.quotes = counts.quotes
        self.bookmarks = counts.bookmarks
        self.total = counts.total
    }
}

public struct EngagementTotals: Codable, Equatable, Sendable {
    public let likes: Int
    public let reposts: Int
    public let replies: Int
    public let quotes: Int
    public let bookmarks: Int
    public let total: Int

    public init(_ counts: EngagementCounts) {
        self.likes = counts.likes
        self.reposts = counts.reposts
        self.replies = counts.replies
        self.quotes = counts.quotes
        self.bookmarks = counts.bookmarks
        self.total = counts.total
    }
}

public struct EngagementAccountIdentity: Codable, Equatable, Sendable {
    public let did: String
    public let handle: String?
    public let displayName: String?
    public let avatar: String?

    public init(did: String, handle: String? = nil, displayName: String? = nil, avatar: String? = nil) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.avatar = avatar
    }
}

public struct EngagementAccountSeries: Codable, Equatable, Sendable {
    public let account: EngagementAccountIdentity
    public let trackedPostCount: Int
    public let unavailablePostCount: Int
    public let lifetime: EngagementTotals
    public let period: EngagementTotals
    public let points: [EngagementPoint]

    public init(
        account: EngagementAccountIdentity,
        trackedPostCount: Int,
        unavailablePostCount: Int,
        lifetime: EngagementTotals,
        period: EngagementTotals,
        points: [EngagementPoint]
    ) {
        self.account = account
        self.trackedPostCount = trackedPostCount
        self.unavailablePostCount = unavailablePostCount
        self.lifetime = lifetime
        self.period = period
        self.points = points
    }
}

public struct GetEngagementOutput: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let coverageStartedAt: String?
    public let lastCollectedAt: String?
    public let status: EngagementDataStatus
    public let accounts: [EngagementAccountSeries]

    public init(
        generatedAt: String,
        coverageStartedAt: String?,
        lastCollectedAt: String?,
        status: EngagementDataStatus,
        accounts: [EngagementAccountSeries]
    ) {
        self.generatedAt = generatedAt
        self.coverageStartedAt = coverageStartedAt
        self.lastCollectedAt = lastCollectedAt
        self.status = status
        self.accounts = accounts
    }
}

public protocol EngagementStore: Sendable {
    func engagementCollectionState(accountDid: String) async throws -> EngagementAccountCollectionState?
    func setEngagementCollectionState(_ state: EngagementAccountCollectionState) async throws
    func knownEngagementPostURIs(accountDid: String) async throws -> Set<String>
    func upsertEngagementPosts(_ posts: [EngagementPostCandidate], observedAt: String) async throws
    func correlateEngagementPosts(accountDid: String, schedulePosts: [String: String]) async throws
    func engagementPostsDue(
        accountDids: [String],
        now: String,
        recentCutoff: String,
        recentIntervalSeconds: Int,
        oldIntervalSeconds: Int
    ) async throws -> [TrackedEngagementPost]
    func recordEngagementBatch(
        posts: [TrackedEngagementPost],
        observations: [EngagementObservation],
        checkedAt: String
    ) async throws
    func trackedEngagementPosts(accountDids: [String]) async throws -> [TrackedEngagementPost]
    func engagementSnapshots(accountDids: [String], through: String) async throws -> [EngagementSnapshot]
}
