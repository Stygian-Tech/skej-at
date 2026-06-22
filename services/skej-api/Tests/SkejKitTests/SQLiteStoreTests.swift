import Foundation
import SkejKit
import Testing

@Suite
struct SQLiteStoreTests {
    @Test func claimDueJobsMarksPublishing() async throws {
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        try await store.upsertScheduleJob(
            ScheduledJob(
                did: "did:plc:test",
                rkey: "3ldue",
                scheduledFor: "2026-01-01T10:00:00Z",
                status: .scheduled,
                attempts: 0,
                lastError: nil,
                publishedUri: nil,
                publishedCid: nil
            ),
            now: "2026-01-01T09:00:00Z"
        )

        let claimed = try await store.claimDueJobs(now: "2026-01-01T10:00:01Z")

        #expect(claimed.map(\.rkey) == ["3ldue"])
        let updated = try await store.scheduleJob(did: "did:plc:test", rkey: "3ldue")
        #expect(updated?.status == .publishing)
        #expect(updated?.attempts == 1)
    }

    @Test func scheduleRecordsPersistInSQLite() async throws {
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let record = makeRecord(scheduledFor: "2026-01-01T12:00:00Z")

        try await store.writeScheduleRecord(
            did: "did:plc:test",
            rkey: "3lrecord",
            record: record,
            now: "2026-01-01T09:00:00Z"
        )

        let fetched = try await store.scheduleRecord(did: "did:plc:test", rkey: "3lrecord")
        #expect(fetched == record)
        let listed = try await store.listScheduleRecords(did: "did:plc:test")
        #expect(listed["3lrecord"] == record)

        try await store.deleteScheduleRecord(did: "did:plc:test", rkey: "3lrecord")
        #expect(try await store.scheduleRecord(did: "did:plc:test", rkey: "3lrecord") == nil)
    }
}
