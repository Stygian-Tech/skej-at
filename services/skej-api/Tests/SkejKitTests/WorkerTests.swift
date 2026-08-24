import Foundation
import Logging
@testable import SkejKit
import Testing

@Suite
struct WorkerTests {
    @Test func workerRetriesTemporaryOAuthClientMetadataFailure() {
        let body =
            #"{"error":"invalid_client_metadata","error_description":"Unable to obtain client metadata"}"#

        let error = ScheduleWorker.classify(HTTPClientError.badStatus(400, body, [:]))

        #expect(error.classification == .transientNetwork)
        #expect(ScheduleWorker.isRetryable(error))
    }

    @Test func workerRequiresReauthForExpiredOAuthGrant() {
        let body = #"{"error":"invalid_grant","error_description":"Session expired"}"#

        let error = ScheduleWorker.classify(HTTPClientError.badStatus(400, body, [:]))

        #expect(error.classification == .authInvalid)
        #expect(!ScheduleWorker.isRetryable(error))
    }

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
        #expect(publishedRecord?.publishedPosts.count == 1)
        #expect(publishedRecord?.publishedPosts.first?.uri == publishedRecord?.publishedUri)
        #expect(publishedRecord?.publishedPosts.first?.cid == publishedRecord?.publishedCid)
    }

    @Test func workerAssignsAndPersistsStableRkeysForEveryThreadPost() async throws {
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let pds = InMemoryPDSClient()
        var record = makeRecord(scheduledFor: "2026-01-01T10:00:00Z")
        record.posts = [PostPlan(text: "one"), PostPlan(text: "two"), PostPlan(text: "three")]
        try await pds.writeSchedule(did: "did:plc:test", rkey: "3lthread", record: record)
        try await store.upsertScheduleJob(
            ScheduledJob(
                did: "did:plc:test",
                rkey: "3lthread",
                scheduledAt: record.scheduledAt,
                status: .scheduled,
                attempts: 0,
                publishRkey: record.publishRkey
            ),
            now: "2026-01-01T09:00:00Z"
        )
        let worker = ScheduleWorker(store: store, pdsClient: pds, logger: Logger(label: "test"))

        await worker.runTick(now: ISO8601DateFormatter().date(from: "2026-01-01T10:00:01Z")!)

        let published = try await pds.getSchedule(did: "did:plc:test", rkey: "3lthread")
        let postRkeys = published?.posts.compactMap(\.publishRkey) ?? []
        #expect(postRkeys.count == 3)
        #expect(Set(postRkeys).count == 3)
        #expect(postRkeys.allSatisfy(ATProtoTID.isValid))
        #expect(published?.publishedPosts.map(\.rkey) == postRkeys)
        #expect(published?.publishRkey == postRkeys.first)
        #expect(published?.publishedUri == published?.publishedPosts.first?.uri)
    }

    @Test func workerUpgradesLegacyPublishRkeyToTID() async throws {
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let pds = InMemoryPDSClient()
        var record = makeRecord(scheduledFor: "2026-01-01T10:00:00Z")
        record.publishRkey = "01KZ7M5Z3M6D4TZS9F67ESBWC1"
        try await pds.writeSchedule(did: "did:plc:test", rkey: "3llegacy", record: record)
        try await store.upsertScheduleJob(
            ScheduledJob(
                did: "did:plc:test",
                rkey: "3llegacy",
                scheduledAt: record.scheduledAt,
                status: .scheduled,
                attempts: 0,
                publishRkey: record.publishRkey
            ),
            now: "2026-01-01T09:00:00Z"
        )
        let worker = ScheduleWorker(store: store, pdsClient: pds, logger: Logger(label: "test"))

        await worker.runTick(now: ISO8601DateFormatter().date(from: "2026-01-01T10:00:01Z")!)

        let job = try await store.scheduleJob(did: "did:plc:test", rkey: "3llegacy")
        let publishedRecord = try await pds.getSchedule(did: "did:plc:test", rkey: "3llegacy")
        #expect(job?.status == .published)
        #expect(job?.publishRkey == publishedRecord?.publishRkey)
        #expect(ATProtoTID.isValid(job?.publishRkey ?? ""))
        #expect(job?.publishedUri?.hasSuffix("/\(job?.publishRkey ?? "")") == true)
    }

    @Test func workerHydratesMissingExternalThumbnailBeforePublishing() async throws {
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let pds = InMemoryPDSClient()
        var record = makeRecord(scheduledFor: "2026-01-01T10:00:00Z")
        record.posts = [
            PostPlan(
                text: "https://example.com/article",
                embed: .object([
                    "$type": .string("app.bsky.embed.external"),
                    "external": .object([
                        "uri": .string("https://example.com/article"),
                        "title": .string("Article"),
                        "description": .string("Description"),
                    ]),
                ])
            ),
        ]
        try await pds.writeSchedule(did: "did:plc:test", rkey: "3lthumb", record: record)
        try await store.upsertScheduleJob(
            ScheduledJob(
                did: "did:plc:test",
                rkey: "3lthumb",
                scheduledAt: record.scheduledAt,
                status: .scheduled,
                attempts: 0,
                publishRkey: record.publishRkey
            ),
            now: "2026-01-01T09:00:00Z"
        )
        let hydrator = StubLinkPreviewHydrator()
        let worker = ScheduleWorker(
            store: store,
            pdsClient: pds,
            logger: Logger(label: "test"),
            linkPreviewHydrator: hydrator
        )

        await worker.runTick(now: ISO8601DateFormatter().date(from: "2026-01-01T10:00:01Z")!)

        let publishedRecord = try await pds.getSchedule(did: "did:plc:test", rkey: "3lthumb")
        guard case let .object(embed)? = publishedRecord?.posts.first?.embed,
              case let .object(external)? = embed["external"],
              case let .object(thumb)? = external["thumb"],
              case let .string(mimeType)? = thumb["mimeType"]
        else {
            Issue.record("Expected the worker to persist a hydrated thumbnail")
            return
        }
        #expect(mimeType == "image/png")
        #expect(await hydrator.requestedURLs() == ["https://example.com/article"])
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

        let stableRkeys = failedRecord?.posts.compactMap(\.publishRkey) ?? []
        await pds.setShouldFailPublish(false)
        await worker.runTick(now: ISO8601DateFormatter().date(from: "2026-01-01T12:00:01Z")!)

        let recovered = try await pds.getSchedule(did: "did:plc:test", rkey: "3lfail")
        #expect(recovered?.status == .published)
        #expect(recovered?.posts.compactMap(\.publishRkey) == stableRkeys)
        #expect(recovered?.publishedPosts.map(\.rkey) == stableRkeys)
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
        parent.publishedCid = "bafyparent"
        try await store.writeScheduleRecord(
            did: "did:plc:test",
            rkey: "3lparent",
            record: parent,
            now: "2026-01-01T09:01:00Z"
        )
        var child = makeRecord(scheduledFor: "2026-01-01T10:00:00Z")
        child.status = .blocked
        child.dependency = ScheduleDependency(
            dependsOnScheduleUri: "at://did:plc:test/at.skej.schedule/3lparent",
            relationship: .reply
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
        #expect(unblockedRecord?.dependency?.parentPublishedCid == parent.publishedCid)
    }
}

private actor StubLinkPreviewHydrator: LinkPreviewHydrating {
    private var urls: [String] = []

    func hydrate(did: String, url: String) async throws -> ExternalEmbed {
        urls.append(url)
        return ExternalEmbed(
            external: ExternalEmbedContent(
                uri: url,
                title: "Hydrated article",
                description: "Hydrated description",
                thumb: ATProtoBlobReference(
                    ref: ATProtoCIDLink(link: "bafythumb"),
                    mimeType: "image/png",
                    size: 4
                )
            )
        )
    }

    func requestedURLs() -> [String] {
        urls
    }
}
