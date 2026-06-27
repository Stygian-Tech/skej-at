import Foundation
import Logging

public struct ScheduleWorker: Sendable {
    public let store: SQLiteStore
    public let pdsClient: any PDSClient
    public let logger: Logger
    private let maxAttempts = 8

    public init(store: SQLiteStore, pdsClient: any PDSClient, logger: Logger) {
        self.store = store
        self.pdsClient = pdsClient
        self.logger = logger
    }

    public func runTick(now: Date = Date()) async {
        let nowString = Timestamp.iso8601(now)
        do {
            try await unblockReadyDependencies(nowString: nowString)
            let due = try await store.claimDueJobs(now: nowString)
            logger.info("schedule worker claimed \(due.count) due jobs")
            for job in due {
                await publish(job: job, now: now, nowString: nowString)
            }
        } catch {
            logger.error("schedule worker tick failed: \(String(describing: error))")
        }
    }

    private func unblockReadyDependencies(nowString: String) async throws {
        let blocked = try await store.blockedJobs()
        for job in blocked {
            guard let dependency = job.dependsOnScheduleUri,
                  let parent = try await store.findPublishedSchedule(scheduleUri: dependency),
                  let parentPublishedUri = parent.record.publishedUri
            else { continue }
            if var record = try await pdsClient.getSchedule(did: job.did, rkey: job.rkey) {
                record.status = .scheduled
                record.lastError = nil
                record.dependency = ScheduleDependency(
                    dependsOnScheduleUri: dependency,
                    parentPublishedUri: parentPublishedUri
                )
                record.updatedAt = nowString
                try await pdsClient.writeSchedule(did: job.did, rkey: job.rkey, record: record)
            }
            try await store.markJobScheduled(
                did: job.did,
                rkey: job.rkey,
                parentPublishedUri: parentPublishedUri,
                now: nowString
            )
            try await store.insertAuditEvent(
                did: job.did,
                scheduleRkey: job.rkey,
                action: "dependency_unblocked",
                message: "Parent published as \(parentPublishedUri).",
                now: nowString
            )
        }
    }

    private func publish(job: ScheduledJob, now: Date, nowString: String) async {
        do {
            guard var record = try await pdsClient.getSchedule(did: job.did, rkey: job.rkey) else {
                throw ScheduleError(code: .recordInvalid, message: "Schedule record missing from PDS")
            }

            if record.status == .canceled {
                try await store.insertAuditEvent(
                    did: job.did,
                    scheduleRkey: job.rkey,
                    action: "publish_skipped_canceled",
                    message: "Canceled schedule was skipped by worker.",
                    now: nowString
                )
                return
            }

            if let dependency = record.dependency {
                guard let parent = try await store.findPublishedSchedule(scheduleUri: dependency.dependsOnScheduleUri),
                      let parentPublishedUri = parent.record.publishedUri
                else {
                    let error = ScheduleError(
                        code: .parentUnavailable,
                        message: "Parent schedule has not published yet.",
                        classification: .parentMissing
                    )
                    record.status = .blocked
                    record.lastError = error
                    record.updatedAt = nowString
                    try await pdsClient.writeSchedule(did: job.did, rkey: job.rkey, record: record)
                    try await store.markJobBlocked(did: job.did, rkey: job.rkey, error: error, now: nowString)
                    try await store.insertAuditEvent(
                        did: job.did,
                        scheduleRkey: job.rkey,
                        action: "dependency_blocked",
                        message: error.message,
                        now: nowString
                    )
                    return
                }
                record.dependency = ScheduleDependency(
                    dependsOnScheduleUri: dependency.dependsOnScheduleUri,
                    parentPublishedUri: parentPublishedUri
                )
                try await store.updateParentPublishedUri(
                    did: job.did,
                    rkey: job.rkey,
                    parentPublishedUri: parentPublishedUri,
                    now: nowString
                )
            }

            record.status = .publishing
            record.retry.attemptCount = job.attempts + 1
            record.retry.lastAttemptAt = nowString
            record.retry.nextAttemptAt = nil
            record.lastError = nil
            record.updatedAt = nowString
            try await pdsClient.writeSchedule(did: job.did, rkey: job.rkey, record: record)
            try await store.insertAuditEvent(
                did: job.did,
                scheduleRkey: job.rkey,
                action: "publish_attempt_started",
                message: "Publish attempt \(record.retry.attemptCount) started.",
                now: nowString
            )

            let published = try await pdsClient.publishThread(did: job.did, record: record)
            record.status = .published
            record.publishedUri = published.uri
            record.publishedCid = published.cid
            record.updatedAt = nowString
            record.lastError = nil
            try await pdsClient.writeSchedule(did: job.did, rkey: job.rkey, record: record)
            try await store.markJobPublished(did: job.did, rkey: job.rkey, published: published, now: nowString)
            try await store.insertAuditEvent(
                did: job.did,
                scheduleRkey: job.rkey,
                action: "publish_succeeded",
                message: "Published \(published.uri).",
                now: nowString
            )
            logger.info("published schedule \(job.rkey) for \(job.did) as \(published.uri)")
        } catch let error as ScheduleError {
            await handlePublishError(error, job: job, now: now, nowString: nowString)
        } catch {
            await handlePublishError(classify(error), job: job, now: now, nowString: nowString)
        }
    }

    private func handlePublishError(_ error: ScheduleError, job: ScheduledJob, now: Date, nowString: String) async {
        let shouldRetry = isRetryable(error) && job.attempts < maxAttempts
        if var record = try? await pdsClient.getSchedule(did: job.did, rkey: job.rkey) {
            record.status = shouldRetry ? .scheduled : .failed
            record.lastError = error
            record.retry.attemptCount = job.attempts + 1
            record.retry.lastAttemptAt = nowString
            record.retry.nextAttemptAt = shouldRetry ? nextAttemptDate(now: now, attempts: job.attempts + 1) : nil
            record.updatedAt = nowString
            try? await pdsClient.writeSchedule(did: job.did, rkey: job.rkey, record: record)
        }

        do {
            if error.classification == .authInvalid {
                try await store.markAccountNeedsReauth(did: job.did, now: nowString)
                try await store.insertAuditEvent(
                    did: job.did,
                    scheduleRkey: job.rkey,
                    action: "account_needs_reauth",
                    message: error.message,
                    now: nowString
                )
            }

            if shouldRetry {
                let nextAttemptAt = nextAttemptDate(now: now, attempts: job.attempts + 1)
                try await store.markJobRetry(
                    did: job.did,
                    rkey: job.rkey,
                    error: error,
                    nextAttemptAt: nextAttemptAt,
                    now: nowString
                )
                try await store.insertAuditEvent(
                    did: job.did,
                    scheduleRkey: job.rkey,
                    action: "retry_scheduled",
                    message: "Retry scheduled for \(nextAttemptAt): \(error.message)",
                    now: nowString
                )
            } else {
                try await store.markJobFailed(did: job.did, rkey: job.rkey, error: error, now: nowString)
                try await store.insertAuditEvent(
                    did: job.did,
                    scheduleRkey: job.rkey,
                    action: "publish_failed",
                    message: error.message,
                    now: nowString
                )
            }
        } catch {
            logger.error("failed to persist publish error for \(job.rkey): \(String(describing: error))")
        }
    }

    private func classify(_ error: Error) -> ScheduleError {
        if case PDSClientError.notConfigured = error {
            return ScheduleError(code: .authInvalid, message: "Reconnect this account before publishing.")
        }
        if case HTTPClientError.badStatus(let status, let body, let headers) = error {
            if status == 401 || status == 403 {
                return ScheduleError(code: .authInvalid, message: "Reconnect this account before publishing.")
            }
            if status == 400 {
                return ScheduleError(code: .recordInvalid, message: body.isEmpty ? "PDS rejected the record." : body)
            }
            if status == 429 {
                return ScheduleError(
                    code: .rateLimited,
                    message: "PDS rate limited this publish attempt.",
                    retryAfter: headers["retry-after"]
                )
            }
            if status >= 500 {
                return ScheduleError(code: .transientNetwork, message: "PDS is temporarily unavailable.")
            }
        }
        return ScheduleError(code: .unknown, message: String(describing: error))
    }

    private func isRetryable(_ error: ScheduleError) -> Bool {
        switch error.classification {
        case .transientNetwork, .rateLimited, .unknown:
            true
        case .authInvalid, .recordInvalid, .parentMissing, .parentUnavailable:
            false
        }
    }

    private func nextAttemptDate(now: Date, attempts: Int) -> String {
        let capped = min(max(attempts, 1), 8)
        let base = min(pow(2.0, Double(capped)) * 60.0, 60.0 * 60.0)
        let jitter = Double.random(in: 0...30)
        return Timestamp.iso8601(now.addingTimeInterval(base + jitter))
    }
}

public enum Timestamp {
    public static func iso8601(_ date: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    public static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
