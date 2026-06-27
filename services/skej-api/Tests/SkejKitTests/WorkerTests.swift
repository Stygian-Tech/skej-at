import Foundation
import Logging
import SkejKit
import Testing

@Suite
struct WorkerTests {
    @Test func workerPublishesAndRetainsScheduleRecord() async throws {
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
        let publishedRecord = try await pds.getSchedule(did: "did:plc:test", rkey: "3ldue")
        #expect(job?.status == .published)
        #expect(publishedRecord?.status == .published)
        #expect(publishedRecord?.publishedUri == job?.publishedUri)
    }

    @Test func workerRetriesTransientFailuresForRecovery() async throws {
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
        #expect(job?.status == .scheduled)
        #expect(job?.lastError != nil)
        #expect(job?.nextAttemptAt != nil)
        #expect(failedRecord?.status == .scheduled)
        #expect(failedRecord?.lastError != nil)
    }

    @Test func workerFailsAfterMaxTransientAttempts() async throws {
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let pds = InMemoryPDSClient()
        await pds.setShouldFailPublish(true)
        let record = makeRecord(scheduledFor: "2026-01-01T10:00:00Z")
        try await pds.writeSchedule(did: "did:plc:test", rkey: "3lfailmax", record: record)
        try await store.upsertScheduleJob(
            ScheduledJob(
                did: "did:plc:test",
                rkey: "3lfailmax",
                scheduledFor: record.scheduledFor,
                status: .scheduled,
                attempts: 8,
                lastError: nil,
                publishedUri: nil,
                publishedCid: nil
            ),
            now: "2026-01-01T09:00:00Z"
        )
        let worker = ScheduleWorker(store: store, pdsClient: pds, logger: Logger(label: "test"))

        await worker.runTick(now: ISO8601DateFormatter().date(from: "2026-01-01T10:00:01Z")!)

        let job = try await store.scheduleJob(did: "did:plc:test", rkey: "3lfailmax")
        let failedRecord = try await pds.getSchedule(did: "did:plc:test", rkey: "3lfailmax")
        #expect(job?.status == .failed)
        #expect(failedRecord?.status == .failed)
        #expect(job?.lastError?.classification == .unknown)
    }

    @Test func workerBlocksDependentScheduleUntilParentPublishes() async throws {
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let pds = InMemoryPDSClient()
        var record = makeRecord(scheduledFor: "2026-01-01T10:00:00Z")
        record.dependency = ScheduleDependency(
            dependsOnScheduleUri: "at://did:plc:test/at.skej.schedule/3lparent"
        )
        try await pds.writeSchedule(did: "did:plc:test", rkey: "3lchild", record: record)
        try await store.upsertScheduleJob(
            ScheduledJob(
                did: "did:plc:test",
                rkey: "3lchild",
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

        let job = try await store.scheduleJob(did: "did:plc:test", rkey: "3lchild")
        let blockedRecord = try await pds.getSchedule(did: "did:plc:test", rkey: "3lchild")
        #expect(job?.status == .blocked)
        #expect(blockedRecord?.status == .blocked)
        #expect(blockedRecord?.lastError?.classification == .parentMissing)
    }

    @Test func workerUnblocksDependentScheduleAfterParentPublishes() async throws {
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let pds = InMemoryPDSClient()
        var parent = makeRecord(scheduledFor: "2026-01-01T09:00:00Z")
        parent.status = .published
        parent.publishedUri = "at://did:plc:test/app.bsky.feed.post/parent"
        try await store.writeScheduleRecord(
            did: "did:plc:test",
            rkey: "3lparent",
            record: parent,
            now: "2026-01-01T09:01:00Z"
        )
        var child = makeRecord(scheduledFor: "2026-01-01T10:00:00Z")
        child.status = .blocked
        child.dependency = ScheduleDependency(
            dependsOnScheduleUri: "at://did:plc:test/at.skej.schedule/3lparent"
        )
        try await pds.writeSchedule(did: "did:plc:test", rkey: "3lchild", record: child)
        try await store.upsertScheduleJob(
            ScheduledJob(
                did: "did:plc:test",
                rkey: "3lchild",
                scheduledAt: child.scheduledAt,
                status: .blocked,
                attempts: 0,
                publishRkey: child.publishRkey,
                dependsOnScheduleUri: child.dependency?.dependsOnScheduleUri
            ),
            now: "2026-01-01T09:02:00Z"
        )
        let worker = ScheduleWorker(store: store, pdsClient: pds, logger: Logger(label: "test"))

        await worker.runTick(now: ISO8601DateFormatter().date(from: "2026-01-01T09:30:00Z")!)

        let job = try await store.scheduleJob(did: "did:plc:test", rkey: "3lchild")
        let unblockedRecord = try await pds.getSchedule(did: "did:plc:test", rkey: "3lchild")
        #expect(job?.status == .scheduled)
        #expect(unblockedRecord?.status == .scheduled)
        #expect(unblockedRecord?.dependency?.parentPublishedUri == parent.publishedUri)
    }
}
