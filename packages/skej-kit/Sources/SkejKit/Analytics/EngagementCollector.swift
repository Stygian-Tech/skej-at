import Foundation
import Logging

public struct EngagementCollectorConfiguration: Equatable, Sendable {
    public let discoveryWindowDays: Int
    public let recentWindowDays: Int
    public let recentIntervalSeconds: Int
    public let oldIntervalSeconds: Int

    public init(
        discoveryWindowDays: Int = 90,
        recentWindowDays: Int = 7,
        recentIntervalSeconds: Int = 15 * 60,
        oldIntervalSeconds: Int = 6 * 60 * 60
    ) {
        self.discoveryWindowDays = max(1, discoveryWindowDays)
        self.recentWindowDays = max(1, recentWindowDays)
        self.recentIntervalSeconds = max(60, recentIntervalSeconds)
        self.oldIntervalSeconds = max(self.recentIntervalSeconds, oldIntervalSeconds)
    }
}

public struct EngagementCollector: Sendable {
    private let store: any EngagementStore
    private let provider: any EngagementProvider
    private let configuration: EngagementCollectorConfiguration
    private let logger: Logger

    public init(
        store: any EngagementStore,
        provider: any EngagementProvider,
        configuration: EngagementCollectorConfiguration = EngagementCollectorConfiguration(),
        logger: Logger = Logger(label: "skej.engagement")
    ) {
        self.store = store
        self.provider = provider
        self.configuration = configuration
        self.logger = logger
    }

    /// Discovers every authored Bluesky post in the rolling window, then
    /// hydrates due post views. `schedulePostsByAccount` maps post URI to the
    /// originating Skej schedule rkey, including every post in a thread.
    public func runTick(
        accountDids: [String],
        schedulePostsByAccount: [String: [String: String]] = [:],
        now: Date = Date()
    ) async {
        let uniqueAccounts = Array(Set(accountDids)).sorted()
        guard !uniqueAccounts.isEmpty else { return }
        let nowString = Timestamp.iso8601(now)
        let discoveryCutoff = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: -configuration.discoveryWindowDays, to: now) ?? now

        for accountDid in uniqueAccounts {
            do {
                let state = try await store.engagementCollectionState(accountDid: accountDid)
                let known = try await store.knownEngagementPostURIs(accountDid: accountDid)
                // A first pass must walk the full 90-day window even when Skej
                // schedule URIs have already been inserted into the inventory.
                let stopAtKnown = state?.lastDiscoveredAt == nil ? Set<String>() : known
                let discovered = try await provider.discoverAuthoredPosts(
                    accountDid: accountDid,
                    since: discoveryCutoff,
                    stopAtKnown: stopAtKnown
                )
                try await store.upsertEngagementPosts(discovered, observedAt: nowString)
                try await store.correlateEngagementPosts(
                    accountDid: accountDid,
                    schedulePosts: schedulePostsByAccount[accountDid] ?? [:]
                )
                try await store.setEngagementCollectionState(EngagementAccountCollectionState(
                    accountDid: accountDid,
                    lastDiscoveredAt: nowString,
                    coverageStartedAt: state?.coverageStartedAt ?? nowString,
                    lastError: nil
                ))
            } catch {
                let previous = try? await store.engagementCollectionState(accountDid: accountDid)
                try? await store.setEngagementCollectionState(EngagementAccountCollectionState(
                    accountDid: accountDid,
                    lastDiscoveredAt: previous?.lastDiscoveredAt,
                    coverageStartedAt: previous?.coverageStartedAt ?? nowString,
                    lastError: String(describing: error)
                ))
                logger.warning("engagement discovery failed", metadata: [
                    "account": "\(accountDid)",
                    "error": "\(String(describing: error))",
                ])
            }
        }

        do {
            let recentCutoff = Calendar(identifier: .gregorian)
                .date(byAdding: .day, value: -configuration.recentWindowDays, to: now) ?? now
            let due = try await store.engagementPostsDue(
                accountDids: uniqueAccounts,
                now: nowString,
                recentCutoff: Timestamp.iso8601(recentCutoff),
                recentIntervalSeconds: configuration.recentIntervalSeconds,
                oldIntervalSeconds: configuration.oldIntervalSeconds
            )
            for start in stride(from: 0, to: due.count, by: BlueskyEngagementProvider.getPostsBatchLimit) {
                let end = min(start + BlueskyEngagementProvider.getPostsBatchLimit, due.count)
                let batch = Array(due[start ..< end])
                let observations = try await provider.fetchObservations(
                    postURIs: batch.map(\.uri),
                    observedAt: nowString
                )
                try await store.recordEngagementBatch(
                    posts: batch,
                    observations: observations,
                    checkedAt: nowString
                )
            }
        } catch {
            logger.warning("engagement hydration failed", metadata: [
                "error": "\(String(describing: error))",
            ])
        }
    }
}
