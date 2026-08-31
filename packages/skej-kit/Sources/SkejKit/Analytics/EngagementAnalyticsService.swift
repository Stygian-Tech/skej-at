import Foundation

public enum EngagementAnalyticsError: Error, Equatable, Sendable {
    case invalidRange
    case invalidTimezone
}

public struct EngagementAnalyticsService: Sendable {
    private let store: any EngagementStore
    private let staleAfterSeconds: TimeInterval

    public init(store: any EngagementStore, staleAfterSeconds: TimeInterval = 30 * 60) {
        self.store = store
        self.staleAfterSeconds = staleAfterSeconds
    }

    public func report(
        accounts: [ManagedAccount],
        from: Date,
        to: Date,
        bucket: EngagementBucket,
        timezone: String,
        now: Date = Date()
    ) async throws -> GetEngagementOutput {
        guard from < to, to.timeIntervalSince(from) <= 366 * 24 * 60 * 60 else {
            throw EngagementAnalyticsError.invalidRange
        }
        guard let timeZone = TimeZone(identifier: timezone) else {
            throw EngagementAnalyticsError.invalidTimezone
        }

        let accountDids = accounts.map(\.did)
        let tracked = try await store.trackedEngagementPosts(accountDids: accountDids)
        let snapshots = try await store.engagementSnapshots(
            accountDids: accountDids,
            through: Timestamp.iso8601(to)
        )
        let states = try await accountDids.asyncCompactMap {
            try await store.engagementCollectionState(accountDid: $0)
        }
        let postsByAccount = Dictionary(grouping: tracked, by: \.accountDid)
        let snapshotsByPost = Dictionary(grouping: snapshots, by: \.postURI)
        var partial = states.contains { $0.lastError != nil }
        var accountSeries: [EngagementAccountSeries] = []

        for account in accounts {
            let posts = postsByAccount[account.did] ?? []
            var lifetime = EngagementCounts.zero
            var period = EngagementCounts.zero
            var buckets: [Date: EngagementCounts] = [:]

            for post in posts {
                let postSnapshots = (snapshotsByPost[post.uri] ?? []).sorted { $0.observedAt < $1.observedAt }
                guard let latest = postSnapshots.last else {
                    partial = true
                    continue
                }
                lifetime = lifetime + latest.counts
                partial = partial || !latest.complete

                let indexedAt = Timestamp.date(from: post.indexedAt) ?? .distantPast
                let baselineIndex = postSnapshots.lastIndex {
                    (Timestamp.date(from: $0.observedAt) ?? .distantFuture) <= from
                }
                var previous: EngagementCounts
                var startIndex: Int
                if let baselineIndex {
                    previous = postSnapshots[baselineIndex].counts
                    startIndex = baselineIndex + 1
                } else if indexedAt >= from {
                    previous = .zero
                    startIndex = 0
                } else {
                    // An older post first observed inside this range contributes
                    // only changes after its first baseline, not its lifetime.
                    previous = postSnapshots.first?.counts ?? .zero
                    startIndex = min(1, postSnapshots.count)
                    partial = true
                }

                for snapshot in postSnapshots.dropFirst(startIndex) {
                    guard let observedAt = Timestamp.date(from: snapshot.observedAt),
                          observedAt > from, observedAt <= to
                    else { continue }
                    let delta = snapshot.counts - previous
                    previous = snapshot.counts
                    period = period + delta
                    let start = bucketStart(for: observedAt, bucket: bucket, timeZone: timeZone)
                    buckets[start] = (buckets[start] ?? .zero) + delta
                    partial = partial || !snapshot.complete
                }
            }

            let points = bucketDates(from: from, to: to, bucket: bucket, timeZone: timeZone).map {
                EngagementPoint(bucketStart: Timestamp.iso8601($0), counts: buckets[$0] ?? .zero)
            }
            accountSeries.append(EngagementAccountSeries(
                account: EngagementAccountIdentity(
                    did: account.did,
                    handle: account.handle,
                    displayName: account.displayName,
                    avatar: account.avatar
                ),
                trackedPostCount: posts.count,
                unavailablePostCount: posts.filter { $0.availability == .unavailable }.count,
                lifetime: EngagementTotals(lifetime),
                period: EngagementTotals(period),
                points: points
            ))
            partial = partial || posts.contains { $0.availability == .unavailable }
        }

        let coverage = states.compactMap(\.coverageStartedAt).min()
        let lastCollected = tracked.compactMap(\.lastCheckedAt).max()
        let stale = lastCollected.flatMap(Timestamp.date(from:)).map {
            now.timeIntervalSince($0) > staleAfterSeconds
        } ?? true
        let status: EngagementDataStatus = partial ? .partial : (stale ? .stale : .live)
        return GetEngagementOutput(
            generatedAt: Timestamp.iso8601(now),
            coverageStartedAt: coverage,
            lastCollectedAt: lastCollected,
            status: status,
            accounts: accountSeries.sorted {
                ($0.account.handle ?? $0.account.did) < ($1.account.handle ?? $1.account.did)
            }
        )
    }

    private func bucketStart(for date: Date, bucket: EngagementBucket, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        switch bucket {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    private func bucketDates(
        from: Date,
        to: Date,
        bucket: EngagementBucket,
        timeZone: TimeZone
    ) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let component: Calendar.Component = bucket == .day ? .day : .weekOfYear
        var value = bucketStart(for: from, bucket: bucket, timeZone: timeZone)
        var dates: [Date] = []
        while value <= to {
            dates.append(value)
            guard let next = calendar.date(byAdding: component, value: 1, to: value), next > value else { break }
            value = next
        }
        return dates
    }
}

private extension Sequence {
    func asyncCompactMap<T>(_ transform: (Element) async throws -> T?) async rethrows -> [T] {
        var values: [T] = []
        for element in self {
            if let value = try await transform(element) {
                values.append(value)
            }
        }
        return values
    }
}
