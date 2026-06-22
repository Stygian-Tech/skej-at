import Foundation

public enum ScheduleStatus: String, Codable, Sendable {
    case scheduled
    case publishing
    case published
    case failed
    case cancelled
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
    public var scheduledFor: String
    public var createdAt: String
    public var updatedAt: String
    public var status: ScheduleStatus
    public var lastError: String?
    public var posts: [PostPlan]

    public init(
        type: String,
        scheduledFor: String,
        createdAt: String,
        updatedAt: String,
        status: ScheduleStatus,
        lastError: String? = nil,
        posts: [PostPlan]
    ) {
        self.type = type
        self.scheduledFor = scheduledFor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.lastError = lastError
        self.posts = posts
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case scheduledFor
        case createdAt
        case updatedAt
        case status
        case lastError
        case posts
    }
}

public struct ScheduledJob: Codable, Equatable, Sendable {
    public let did: String
    public let rkey: String
    public let scheduledFor: String
    public var status: ScheduleStatus
    public var attempts: Int
    public var lastError: String?
    public var publishedUri: String?
    public var publishedCid: String?

    public init(
        did: String,
        rkey: String,
        scheduledFor: String,
        status: ScheduleStatus,
        attempts: Int,
        lastError: String? = nil,
        publishedUri: String? = nil,
        publishedCid: String? = nil
    ) {
        self.did = did
        self.rkey = rkey
        self.scheduledFor = scheduledFor
        self.status = status
        self.attempts = attempts
        self.lastError = lastError
        self.publishedUri = publishedUri
        self.publishedCid = publishedCid
    }
}

public struct ScheduledPostSummary: Codable, Equatable, Sendable {
    public let rkey: String
    public let did: String
    public let scheduledFor: String
    public let status: ScheduleStatus
    public let record: SkejScheduleRecord
    public let attempts: Int
    public let lastError: String?
    public let publishedUri: String?
    public let publishedCid: String?
}

public struct Viewer: Codable, Equatable, Sendable {
    public let did: String
    public let handle: String?
    public let displayName: String?

    public init(did: String, handle: String? = nil, displayName: String? = nil) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
    }
}

public struct CreateScheduleRequest: Codable, Sendable {
    public let record: SkejScheduleRecord

    public init(record: SkejScheduleRecord) {
        self.record = record
    }
}

public struct ListSchedulesResponse: Codable, Sendable {
    public let records: [ScheduledPostSummary]
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
