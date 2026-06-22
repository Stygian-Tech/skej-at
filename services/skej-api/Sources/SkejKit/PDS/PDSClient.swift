import Foundation

public protocol PDSClient: Sendable {
    func writeSchedule(did: String, rkey: String, record: SkejScheduleRecord) async throws
    func getSchedule(did: String, rkey: String) async throws -> SkejScheduleRecord?
    func listSchedules(did: String) async throws -> [String: SkejScheduleRecord]
    func deleteSchedule(did: String, rkey: String) async throws
    func publishThread(did: String, record: SkejScheduleRecord) async throws -> PublishedPost
}

public struct SQLitePDSClient: PDSClient {
    private let store: SQLiteStore

    public init(store: SQLiteStore) {
        self.store = store
    }

    public func writeSchedule(did: String, rkey: String, record: SkejScheduleRecord) async throws {
        try await store.writeScheduleRecord(
            did: did,
            rkey: rkey,
            record: record,
            now: Timestamp.iso8601()
        )
    }

    public func getSchedule(did: String, rkey: String) async throws -> SkejScheduleRecord? {
        try await store.scheduleRecord(did: did, rkey: rkey)
    }

    public func listSchedules(did: String) async throws -> [String: SkejScheduleRecord] {
        try await store.listScheduleRecords(did: did)
    }

    public func deleteSchedule(did: String, rkey: String) async throws {
        try await store.deleteScheduleRecord(did: did, rkey: rkey)
    }

    public func publishThread(did: String, record: SkejScheduleRecord) async throws -> PublishedPost {
        let suffix = stableSuffix(did: did, text: record.posts.map(\.text).joined(separator: "\n"))
        return PublishedPost(
            uri: "at://\(did)/app.bsky.feed.post/\(suffix)",
            cid: "bafy\(suffix)"
        )
    }

    private func stableSuffix(did: String, text: String) -> String {
        "\(abs("\(did):\(text)".hashValue))"
    }
}

public actor InMemoryPDSClient: PDSClient {
    private var schedules: [String: [String: SkejScheduleRecord]] = [:]
    private var shouldFailPublish = false

    public init() {}

    public func setShouldFailPublish(_ value: Bool) {
        shouldFailPublish = value
    }

    public func writeSchedule(did: String, rkey: String, record: SkejScheduleRecord) async throws {
        var user = schedules[did] ?? [:]
        user[rkey] = record
        schedules[did] = user
    }

    public func getSchedule(did: String, rkey: String) async throws -> SkejScheduleRecord? {
        schedules[did]?[rkey]
    }

    public func listSchedules(did: String) async throws -> [String: SkejScheduleRecord] {
        schedules[did] ?? [:]
    }

    public func deleteSchedule(did: String, rkey: String) async throws {
        schedules[did]?[rkey] = nil
    }

    public func publishThread(did: String, record: SkejScheduleRecord) async throws -> PublishedPost {
        if shouldFailPublish {
            throw PDSClientError.publishFailed("PDS rejected scheduled record")
        }
        let suffix = record.posts.first?.text.hashValue.magnitude ?? 0
        return PublishedPost(
            uri: "at://\(did)/app.bsky.feed.post/\(suffix)",
            cid: "bafy\(suffix)"
        )
    }
}

public enum PDSClientError: Error, Equatable {
    case publishFailed(String)
    case notConfigured
}
