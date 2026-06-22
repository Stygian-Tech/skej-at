import Foundation
import Logging
import SkejKit
import Testing

@Suite
struct WorkerTests {
    @Test func workerPublishesAndDeletesScheduleRecord() async throws {
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let pds = InMemoryPDSClient()
        let record = makeRecord(scheduledFor: "2026-01-01T10:00:00Z")
        try await pds.writeSchedule(did: "did:plc:test", rkey: "3ldue", record: record)
        try await store.upsertScheduleJob(
            ScheduledJob(
                did: "did:plc:test",
                rkey: "3ldue",
                scheduledFor: record.scheduledFor,
                status: .scheduled,
                attempts: 0,
                lastError: nil,
                publishedUri: nil,
                publishedCid: nil
            ),
            now: "2026-01-01T09:00:00Z"
        )
        let worker = ScheduleWorker(store: store, pdsClient: pds, logger: Logger(label: "test"))

        await worker.runTick(now: ISO8601DateFormatter().date(from: "2026-01-01T10:00:01Z")!)

        let job = try await store.scheduleJob(did: "did:plc:test", rkey: "3ldue")
        #expect(job?.status == .published)
        #expect(try await pds.getSchedule(did: "did:plc:test", rkey: "3ldue") == nil)
    }

    @Test func workerMarksFailuresForRecovery() async throws {
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let pds = InMemoryPDSClient()
        await pds.setShouldFailPublish(true)
        let record = makeRecord(scheduledFor: "2026-01-01T10:00:00Z")
        try await pds.writeSchedule(did: "did:plc:test", rkey: "3lfail", record: record)
        try await store.upsertScheduleJob(
            ScheduledJob(
                did: "did:plc:test",
                rkey: "3lfail",
                scheduledFor: record.scheduledFor,
                status: .scheduled,
                attempts: 0,
                lastError: nil,
                publishedUri: nil,
                publishedCid: nil
            ),
            now: "2026-01-01T09:00:00Z"
        )
        let worker = ScheduleWorker(store: store, pdsClient: pds, logger: Logger(label: "test"))

        await worker.runTick(now: ISO8601DateFormatter().date(from: "2026-01-01T10:00:01Z")!)

        let job = try await store.scheduleJob(did: "did:plc:test", rkey: "3lfail")
        let failedRecord = try await pds.getSchedule(did: "did:plc:test", rkey: "3lfail")
        #expect(job?.status == .failed)
        #expect(job?.lastError != nil)
        #expect(failedRecord?.status == .failed)
        #expect(failedRecord?.lastError != nil)
    }
}
