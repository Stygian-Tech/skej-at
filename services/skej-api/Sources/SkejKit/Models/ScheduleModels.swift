import Foundation

public enum ScheduleStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case scheduled
    case blocked
    case publishing
    case published
    case failed
    case canceled

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = value == "cancelled" ? .canceled : (ScheduleStatus(rawValue: value) ?? .failed)
    }
}

public enum TimezonePolicy: String, Codable, Sendable {
    case absoluteUTC = "absolute_utc"
    case accountLocal = "account_local"
    case userLocal = "user_local"
}

public enum ScheduleErrorCode: String, Codable, Sendable {
    case transientNetwork = "transient_network"
    case rateLimited = "rate_limited"
    case authInvalid = "auth_invalid"
    case recordInvalid = "record_invalid"
    case parentMissing = "parent_missing"
    case parentUnavailable = "parent_unavailable"
    case unknown
}

public struct ScheduleError: Codable, Equatable, Error, Sendable {
    public let code: ScheduleErrorCode
    public let message: String
    public let classification: ScheduleErrorCode
    public let retryAfter: String?

    public init(
        code: ScheduleErrorCode,
        message: String,
        classification: ScheduleErrorCode? = nil,
        retryAfter: String? = nil
    ) {
        self.code = code
        self.message = message
        self.classification = classification ?? code
        self.retryAfter = retryAfter
    }

    public init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            self.init(code: .unknown, message: string)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let code = try container.decodeIfPresent(ScheduleErrorCode.self, forKey: .code) ?? .unknown
        let message = try container.decodeIfPresent(String.self, forKey: .message) ?? "Unknown schedule error"
        let classification = try container.decodeIfPresent(ScheduleErrorCode.self, forKey: .classification) ?? code
        let retryAfter = try container.decodeIfPresent(String.self, forKey: .retryAfter)
        self.init(code: code, message: message, classification: classification, retryAfter: retryAfter)
    }
}

public struct RetryState: Codable, Equatable, Sendable {
    public var attemptCount: Int
    public var lastAttemptAt: String?
    public var nextAttemptAt: String?
    public var maxAttempts: Int

    public init(attemptCount: Int = 0, lastAttemptAt: String? = nil, nextAttemptAt: String? = nil, maxAttempts: Int = 8) {
        self.attemptCount = attemptCount
        self.lastAttemptAt = lastAttemptAt
        self.nextAttemptAt = nextAttemptAt
        self.maxAttempts = maxAttempts
    }
}

public struct ScheduleDependency: Codable, Equatable, Sendable {
    public var dependsOnScheduleUri: String
    public var parentPublishedUri: String?

    public init(dependsOnScheduleUri: String, parentPublishedUri: String? = nil) {
        self.dependsOnScheduleUri = dependsOnScheduleUri
        self.parentPublishedUri = parentPublishedUri
    }
}

public struct PostPlan: Codable, Equatable, Sendable {
    public let text: String
    public let facets: [JSONValue]?
    public let reply: JSONValue?
    public let embed: JSONValue?
    public let langs: [String]?
    public let labels: [String]?
    public let tags: [String]?

    public init(
        text: String,
        facets: [JSONValue]? = nil,
        reply: JSONValue? = nil,
        embed: JSONValue? = nil,
        langs: [String]? = nil,
        labels: [String]? = nil,
        tags: [String]? = nil
    ) {
        self.text = text
        self.facets = facets
        self.reply = reply
        self.embed = embed
        self.langs = langs
        self.labels = labels
        self.tags = tags
    }
}

public struct SkejScheduleRecord: Codable, Equatable, Sendable {
    public let type: String
    public var scheduledAt: String
    public var title: String?
    public var teamUri: String?
    public var createdByDid: String?
    public var approvedByDid: String?
    public var approvedAt: String?
    public var timezonePolicy: TimezonePolicy
    public var userTimezone: String?
    public var createdAt: String
    public var updatedAt: String
    public var status: ScheduleStatus
    public var recordType: String
    public var shadowRecord: JSONValue?
    public var publishRkey: String
    public var publishedUri: String?
    public var publishedCid: String?
    public var retry: RetryState
    public var lastError: ScheduleError?
    public var dependency: ScheduleDependency?
    public var posts: [PostPlan]

    public var scheduledFor: String {
        get { scheduledAt }
        set { scheduledAt = newValue }
    }

    public var scheduleUri: String {
        "at://unknown/at.skej.schedule/\(publishRkey)"
    }

    public init(
        type: String = "at.skej.schedule",
        scheduledAt: String,
        title: String? = nil,
        teamUri: String? = nil,
        createdByDid: String? = nil,
        approvedByDid: String? = nil,
        approvedAt: String? = nil,
        timezonePolicy: TimezonePolicy = .userLocal,
        userTimezone: String? = nil,
        createdAt: String,
        updatedAt: String,
        status: ScheduleStatus,
        recordType: String = "app.bsky.feed.post",
        shadowRecord: JSONValue? = nil,
        publishRkey: String,
        publishedUri: String? = nil,
        publishedCid: String? = nil,
        retry: RetryState = RetryState(),
        lastError: ScheduleError? = nil,
        dependency: ScheduleDependency? = nil,
        posts: [PostPlan]
    ) {
        self.type = type
        self.scheduledAt = scheduledAt
        self.title = title
        self.teamUri = teamUri
        self.createdByDid = createdByDid
        self.approvedByDid = approvedByDid
        self.approvedAt = approvedAt
        self.timezonePolicy = timezonePolicy
        self.userTimezone = userTimezone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.recordType = recordType
        self.shadowRecord = shadowRecord
        self.publishRkey = publishRkey
        self.publishedUri = publishedUri
        self.publishedCid = publishedCid
        self.retry = retry
        self.lastError = lastError
        self.dependency = dependency
        self.posts = posts
    }

    public init(
        type: String = "at.skej.schedule",
        scheduledFor: String,
        createdAt: String,
        updatedAt: String,
        status: ScheduleStatus,
        lastError: ScheduleError? = nil,
        posts: [PostPlan]
    ) {
        self.init(
            type: type,
            scheduledAt: scheduledFor,
            createdAt: createdAt,
            updatedAt: updatedAt,
            status: status,
            publishRkey: ULID.generate(),
            lastError: lastError,
            posts: posts
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(String.self, forKey: .type)
        self.scheduledAt = try container.decodeIfPresent(String.self, forKey: .scheduledAt)
            ?? container.decode(String.self, forKey: .scheduledFor)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.teamUri = try container.decodeIfPresent(String.self, forKey: .teamUri)
        self.createdByDid = try container.decodeIfPresent(String.self, forKey: .createdByDid)
        self.approvedByDid = try container.decodeIfPresent(String.self, forKey: .approvedByDid)
        self.approvedAt = try container.decodeIfPresent(String.self, forKey: .approvedAt)
        self.timezonePolicy = try container.decodeIfPresent(TimezonePolicy.self, forKey: .timezonePolicy) ?? .userLocal
        self.userTimezone = try container.decodeIfPresent(String.self, forKey: .userTimezone)
        self.createdAt = try container.decode(String.self, forKey: .createdAt)
        self.updatedAt = try container.decode(String.self, forKey: .updatedAt)
        self.status = try container.decode(ScheduleStatus.self, forKey: .status)
        self.recordType = try container.decodeIfPresent(String.self, forKey: .recordType) ?? "app.bsky.feed.post"
        self.shadowRecord = try container.decodeIfPresent(JSONValue.self, forKey: .shadowRecord)
        self.publishRkey = try container.decodeIfPresent(String.self, forKey: .publishRkey) ?? ULID.generate()
        self.publishedUri = try container.decodeIfPresent(String.self, forKey: .publishedUri)
        self.publishedCid = try container.decodeIfPresent(String.self, forKey: .publishedCid)
        self.retry = try container.decodeIfPresent(RetryState.self, forKey: .retry) ?? RetryState()
        self.lastError = try container.decodeIfPresent(ScheduleError.self, forKey: .lastError)
        self.dependency = try container.decodeIfPresent(ScheduleDependency.self, forKey: .dependency)
        self.posts = try container.decodeIfPresent([PostPlan].self, forKey: .posts) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(scheduledAt, forKey: .scheduledAt)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(teamUri, forKey: .teamUri)
        try container.encodeIfPresent(createdByDid, forKey: .createdByDid)
        try container.encodeIfPresent(approvedByDid, forKey: .approvedByDid)
        try container.encodeIfPresent(approvedAt, forKey: .approvedAt)
        try container.encode(timezonePolicy, forKey: .timezonePolicy)
        try container.encodeIfPresent(userTimezone, forKey: .userTimezone)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(status, forKey: .status)
        try container.encode(recordType, forKey: .recordType)
        try container.encodeIfPresent(shadowRecord, forKey: .shadowRecord)
        try container.encode(publishRkey, forKey: .publishRkey)
        try container.encodeIfPresent(publishedUri, forKey: .publishedUri)
        try container.encodeIfPresent(publishedCid, forKey: .publishedCid)
        try container.encode(retry, forKey: .retry)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encodeIfPresent(dependency, forKey: .dependency)
        try container.encode(posts, forKey: .posts)
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case scheduledAt
        case title
        case teamUri
        case createdByDid
        case approvedByDid
        case approvedAt
        case scheduledFor
        case timezonePolicy
        case userTimezone
        case createdAt
        case updatedAt
        case status
        case recordType
        case shadowRecord
        case publishRkey
        case publishedUri
        case publishedCid
        case retry
        case lastError
        case dependency
        case posts
    }
}

public enum TeamStatus: String, Codable, Sendable {
    case active
    case archived
}

public enum TeamRole: String, Codable, Sendable {
    case admin
    case user
}

public enum MembershipStatus: String, Codable, Sendable {
    case active
    case disabled
}

public enum BrandCapability: String, Codable, CaseIterable, Sendable {
    case create
    case approve
    case manage
}

public enum GrantGranteeType: String, Codable, Sendable {
    case member
    case group
}

public struct SkejTeamRecord: Codable, Equatable, Sendable {
    public let type: String
    public var ownerAdminDid: String
    public var title: String
    public var status: TeamStatus
    public var createdAt: String
    public var updatedAt: String

    public init(
        type: String = "at.skej.team",
        ownerAdminDid: String,
        title: String,
        status: TeamStatus = .active,
        createdAt: String,
        updatedAt: String
    ) {
        self.type = type
        self.ownerAdminDid = ownerAdminDid
        self.title = title
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case ownerAdminDid
        case title
        case status
        case createdAt
        case updatedAt
    }
}

public struct TeamMemberRecord: Codable, Equatable, Sendable {
    public let type: String
    public var teamUri: String
    public var memberDid: String
    public var role: TeamRole
    public var status: MembershipStatus
    public var groupUris: [String]
    public var createdAt: String
    public var updatedAt: String

    public init(
        type: String = "at.skej.team.member",
        teamUri: String,
        memberDid: String,
        role: TeamRole,
        status: MembershipStatus = .active,
        groupUris: [String] = [],
        createdAt: String,
        updatedAt: String
    ) {
        self.type = type
        self.teamUri = teamUri
        self.memberDid = memberDid
        self.role = role
        self.status = status
        self.groupUris = groupUris
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case teamUri
        case memberDid
        case role
        case status
        case groupUris
        case createdAt
        case updatedAt
    }
}

public struct TeamGroupRecord: Codable, Equatable, Sendable {
    public let type: String
    public var teamUri: String
    public var name: String
    public var memberDids: [String]
    public var brandGrantUris: [String]
    public var createdAt: String
    public var updatedAt: String

    public init(
        type: String = "at.skej.team.group",
        teamUri: String,
        name: String,
        memberDids: [String] = [],
        brandGrantUris: [String] = [],
        createdAt: String,
        updatedAt: String
    ) {
        self.type = type
        self.teamUri = teamUri
        self.name = name
        self.memberDids = memberDids
        self.brandGrantUris = brandGrantUris
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case teamUri
        case name
        case memberDids
        case brandGrantUris
        case createdAt
        case updatedAt
    }
}

public struct BrandGrantRecord: Codable, Equatable, Sendable {
    public let type: String
    public var teamUri: String
    public var brandDid: String
    public var granteeType: GrantGranteeType
    public var grantee: String
    public var capabilities: [BrandCapability]
    public var createdAt: String
    public var updatedAt: String

    public init(
        type: String = "at.skej.team.brandGrant",
        teamUri: String,
        brandDid: String,
        granteeType: GrantGranteeType,
        grantee: String,
        capabilities: [BrandCapability],
        createdAt: String,
        updatedAt: String
    ) {
        self.type = type
        self.teamUri = teamUri
        self.brandDid = brandDid
        self.granteeType = granteeType
        self.grantee = grantee
        self.capabilities = capabilities
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case teamUri
        case brandDid
        case granteeType
        case grantee
        case capabilities
        case createdAt
        case updatedAt
    }
}

public struct SkejBrandRecord: Codable, Equatable, Sendable {
    public let type: String
    public var teamUri: String
    public var ownerAdminDid: String
    public var brandDid: String
    public var status: ManagedAccountStatus
    public var createdAt: String
    public var updatedAt: String

    public init(
        type: String = "at.skej.brand",
        teamUri: String,
        ownerAdminDid: String,
        brandDid: String,
        status: ManagedAccountStatus = .active,
        createdAt: String,
        updatedAt: String
    ) {
        self.type = type
        self.teamUri = teamUri
        self.ownerAdminDid = ownerAdminDid
        self.brandDid = brandDid
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case teamUri
        case ownerAdminDid
        case brandDid
        case status
        case createdAt
        case updatedAt
    }
}

public struct ManagedAccount: Codable, Equatable, Sendable {
    public var did: String
    public var handle: String?
    public var displayName: String?
    public var avatar: String?
    public var pdsEndpoint: String?
    public var status: ManagedAccountStatus
    public var isDefault: Bool
}

public enum ManagedAccountStatus: String, Codable, Sendable {
    case active
    case needsReauth = "needs_reauth"
    case disabled
}

public struct ScheduledJob: Codable, Equatable, Sendable {
    public let did: String
    public let rkey: String
    public var scheduledAt: String
    public var status: ScheduleStatus
    public var attempts: Int
    public var lastError: ScheduleError?
    public var nextAttemptAt: String?
    public var lastAttemptAt: String?
    public var publishRkey: String
    public var recordType: String
    public var publishedUri: String?
    public var publishedCid: String?
    public var dependsOnScheduleUri: String?
    public var parentPublishedUri: String?

    public var scheduledFor: String {
        get { scheduledAt }
        set { scheduledAt = newValue }
    }

    public init(
        did: String,
        rkey: String,
        scheduledAt: String,
        status: ScheduleStatus,
        attempts: Int,
        lastError: ScheduleError? = nil,
        nextAttemptAt: String? = nil,
        lastAttemptAt: String? = nil,
        publishRkey: String,
        recordType: String = "app.bsky.feed.post",
        publishedUri: String? = nil,
        publishedCid: String? = nil,
        dependsOnScheduleUri: String? = nil,
        parentPublishedUri: String? = nil
    ) {
        self.did = did
        self.rkey = rkey
        self.scheduledAt = scheduledAt
        self.status = status
        self.attempts = attempts
        self.lastError = lastError
        self.nextAttemptAt = nextAttemptAt
        self.lastAttemptAt = lastAttemptAt
        self.publishRkey = publishRkey
        self.recordType = recordType
        self.publishedUri = publishedUri
        self.publishedCid = publishedCid
        self.dependsOnScheduleUri = dependsOnScheduleUri
        self.parentPublishedUri = parentPublishedUri
    }

    public init(
        did: String,
        rkey: String,
        scheduledFor: String,
        status: ScheduleStatus,
        attempts: Int,
        lastError: ScheduleError? = nil,
        publishedUri: String? = nil,
        publishedCid: String? = nil
    ) {
        self.init(
            did: did,
            rkey: rkey,
            scheduledAt: scheduledFor,
            status: status,
            attempts: attempts,
            lastError: lastError,
            publishRkey: rkey,
            publishedUri: publishedUri,
            publishedCid: publishedCid
        )
    }
}

public struct ScheduledPostSummary: Codable, Equatable, Sendable {
    public let rkey: String
    public let did: String
    public let scheduleUri: String
    public let scheduledAt: String
    public let status: ScheduleStatus
    public let record: SkejScheduleRecord
    public let attempts: Int
    public let lastError: ScheduleError?
    public let nextAttemptAt: String?
    public let publishedUri: String?
    public let publishedCid: String?

    public var scheduledFor: String { scheduledAt }
}

public struct TeamSummary: Codable, Equatable, Sendable {
    public let rkey: String
    public let uri: String
    public var record: SkejTeamRecord
}

public struct TeamMemberSummary: Codable, Equatable, Sendable {
    public let rkey: String
    public let uri: String
    public let record: TeamMemberRecord
}

public struct TeamGroupSummary: Codable, Equatable, Sendable {
    public let rkey: String
    public let uri: String
    public let record: TeamGroupRecord
}

public struct BrandGrantSummary: Codable, Equatable, Sendable {
    public let rkey: String
    public let uri: String
    public let record: BrandGrantRecord
}

public struct BrandSummary: Codable, Equatable, Sendable {
    public let rkey: String
    public let uri: String
    public let record: SkejBrandRecord
}

public struct EffectiveBrandPermission: Codable, Equatable, Sendable {
    public let brandDid: String
    public let capabilities: [BrandCapability]
}

public struct BrandProfile: Codable, Equatable, Sendable {
    public var did: String
    public var handle: String?
    public var displayName: String?
    public var description: String?
    public var avatar: String?

    public init(did: String, handle: String? = nil, displayName: String? = nil, description: String? = nil, avatar: String? = nil) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.description = description
        self.avatar = avatar
    }
}

public struct AuditEvent: Codable, Equatable, Sendable {
    public let id: String
    public let did: String
    public let scheduleRkey: String?
    public let action: String
    public let message: String
    public let createdAt: String
}

public struct Viewer: Codable, Equatable, Sendable {
    public let did: String
    public let handle: String?
    public let displayName: String?
    public let avatar: String?
    public let defaultAccountDid: String?

    public init(
        did: String,
        handle: String? = nil,
        displayName: String? = nil,
        avatar: String? = nil,
        defaultAccountDid: String? = nil
    ) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.avatar = avatar
        self.defaultAccountDid = defaultAccountDid ?? did
    }
}

public struct CreateScheduleRequest: Codable, Sendable {
    public let record: SkejScheduleRecord

    public init(record: SkejScheduleRecord) {
        self.record = record
    }
}

public struct CreateTeamRequest: Codable, Sendable {
    public let title: String

    public init(title: String) {
        self.title = title
    }
}

public struct UpdateTeamRequest: Codable, Sendable {
    public let title: String?
    public let status: TeamStatus?

    public init(title: String? = nil, status: TeamStatus? = nil) {
        self.title = title
        self.status = status
    }
}

public struct TransferTeamOwnerRequest: Codable, Sendable {
    public let ownerAdminDid: String

    public init(ownerAdminDid: String) {
        self.ownerAdminDid = ownerAdminDid
    }
}

public struct UpsertMemberRequest: Codable, Sendable {
    public let memberDid: String
    public let role: TeamRole
    public let status: MembershipStatus?
    public let groupUris: [String]?

    public init(memberDid: String, role: TeamRole, status: MembershipStatus? = nil, groupUris: [String]? = nil) {
        self.memberDid = memberDid
        self.role = role
        self.status = status
        self.groupUris = groupUris
    }
}

public struct UpsertGroupRequest: Codable, Sendable {
    public let name: String
    public let memberDids: [String]?
    public let brandGrantUris: [String]?

    public init(name: String, memberDids: [String]? = nil, brandGrantUris: [String]? = nil) {
        self.name = name
        self.memberDids = memberDids
        self.brandGrantUris = brandGrantUris
    }
}

public struct UpsertBrandGrantRequest: Codable, Sendable {
    public let brandDid: String
    public let granteeType: GrantGranteeType
    public let grantee: String
    public let capabilities: [BrandCapability]

    public init(brandDid: String, granteeType: GrantGranteeType, grantee: String, capabilities: [BrandCapability]) {
        self.brandDid = brandDid
        self.granteeType = granteeType
        self.grantee = grantee
        self.capabilities = capabilities
    }
}

public struct UpsertBrandRequest: Codable, Sendable {
    public let brandDid: String
    public let status: ManagedAccountStatus?

    public init(brandDid: String, status: ManagedAccountStatus? = nil) {
        self.brandDid = brandDid
        self.status = status
    }
}

public struct UpdateBrandProfileRequest: Codable, Sendable {
    public let displayName: String?
    public let description: String?
    public let avatar: String?

    public init(displayName: String? = nil, description: String? = nil, avatar: String? = nil) {
        self.displayName = displayName
        self.description = description
        self.avatar = avatar
    }
}

public struct ListSchedulesResponse: Codable, Sendable {
    public let records: [ScheduledPostSummary]
}

public struct ListTeamsResponse: Codable, Sendable {
    public let teams: [TeamSummary]
}

public struct ListMembersResponse: Codable, Sendable {
    public let members: [TeamMemberSummary]
}

public struct ListGroupsResponse: Codable, Sendable {
    public let groups: [TeamGroupSummary]
}

public struct ListBrandGrantsResponse: Codable, Sendable {
    public let grants: [BrandGrantSummary]
}

public struct ListBrandsResponse: Codable, Sendable {
    public let brands: [BrandSummary]
}

public struct ListAccountsResponse: Codable, Sendable {
    public let accounts: [ManagedAccount]
}

public struct ListAuditEventsResponse: Codable, Sendable {
    public let events: [AuditEvent]
}

public struct OKResponse: Codable, Sendable {
    public let ok: Bool

    public init(ok: Bool) {
        self.ok = ok
    }
}

public struct PublishedPost: Codable, Equatable, Sendable {
    public let uri: String
    public let cid: String

    public init(uri: String, cid: String) {
        self.uri = uri
        self.cid = cid
    }
}

public enum ATURI {
    public static func record(did: String, collection: String, rkey: String) -> String {
        "at://\(did)/\(collection)/\(rkey)"
    }

    public static func schedule(did: String, rkey: String) -> String {
        record(did: did, collection: "at.skej.schedule", rkey: rkey)
    }

    public static func published(did: String, recordType: String, publishRkey: String) -> String {
        "at://\(did)/\(recordType)/\(publishRkey)"
    }
}

public enum ULID {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func generate(date: Date = Date()) -> String {
        var value = UInt64(date.timeIntervalSince1970 * 1000)
        var time = Array(repeating: Character("0"), count: 10)
        for index in stride(from: 9, through: 0, by: -1) {
            time[index] = alphabet[Int(value % 32)]
            value /= 32
        }

        var random = ""
        for _ in 0..<16 {
            random.append(alphabet[Int.random(in: 0..<alphabet.count)])
        }
        return String(time) + random
    }
}
