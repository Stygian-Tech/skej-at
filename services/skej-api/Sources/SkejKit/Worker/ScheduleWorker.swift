import Foundation
import Logging

public struct ScheduleWorker: Sendable {
    public let store: SQLiteStore
    public let pdsClient: any PDSClient
    public let logger: Logger

    public init(store: SQLiteStore, pdsClient: any PDSClient, logger: Logger) {
        self.store = store
        self.pdsClient = pdsClient
        self.logger = logger
    }

    public func runTick(now: Date = Date()) async {
        let nowString = Timestamp.iso8601(now)
        do {
            let due = try await store.claimDueJobs(now: nowString)
            for job in due {
                await publish(job: job, nowString: nowString)
            }
        } catch {
            logger.error("schedule worker tick failed: \(String(describing: error))")
        }
    }

    private func publish(job: ScheduledJob, nowString: String) async {
        do {
            guard var record = try await pdsClient.getSchedule(did: job.did, rkey: job.rkey) else {
                throw APIError(
                    status: .notFound,
                    code: "schedule_missing",
                    message: "Schedule record missing from PDS"
                )
            }
            record.status = .publishing
            record.updatedAt = nowString
            try await pdsClient.writeSchedule(did: job.did, rkey: job.rkey, record: record)

            let published = try await pdsClient.publishThread(did: job.did, record: record)
            try await pdsClient.deleteSchedule(did: job.did, rkey: job.rkey)
            try await store.markJobPublished(
                did: job.did,
                rkey: job.rkey,
                published: published,
                now: nowString
            )
        } catch {
            let message = String(describing: error)
            try? await store.markJobFailed(did: job.did, rkey: job.rkey, error: message, now: nowString)
        }
    }
}

public enum Timestamp {
    public static func iso8601(_ date: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

