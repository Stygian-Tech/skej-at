import Foundation
import Logging
import SkejKit

/// Resolves the current Pro analytics audience before every tick. This keeps
/// collection aligned with entitlement and team-capability changes without
/// persisting a second authorization model in the analytics subsystem.
actor EngagementCollectorRuntime {
    private let services: SkejServices
    private let collector: EngagementCollector
    private let logger: Logger

    init(services: SkejServices, logger: Logger) {
        self.services = services
        self.logger = logger
        self.collector = EngagementCollector(
            store: services.store,
            provider: BlueskyEngagementProvider(origin: services.config.engagementAppViewOrigin),
            configuration: EngagementCollectorConfiguration(
                recentIntervalSeconds: services.config.engagementRecentIntervalSeconds,
                oldIntervalSeconds: services.config.engagementOldIntervalSeconds
            ),
            logger: logger
        )
    }

    func runTick(now: Date = Date()) async {
        do {
            let accountDids = try await collectibleAccountDIDs(now: now)
            let correlations = await scheduleCorrelations(accountDids: accountDids)
            await collector.runTick(
                accountDids: accountDids,
                schedulePostsByAccount: correlations,
                now: now
            )
        } catch {
            logger.warning("engagement collector audience resolution failed", metadata: [
                "error": "\(String(describing: error))",
            ])
        }
    }

    private func collectibleAccountDIDs(now: Date) async throws -> [String] {
        let viewerDids: [String]
        if services.config.environment == .prod {
            let nowString = Timestamp.iso8601(now)
            let active = try await services.store.listProEntitlements().filter { $0.isActive(at: nowString) }
            var entitledViewers = Set(active.filter { $0.scope == .actor }.map(\.subject))
            let entitledTeams = Set(active.filter { $0.scope == .team }.map(\.subject))
            if !entitledTeams.isEmpty {
                let teams = try await services.store.listProtocolRecords(
                    collection: "at.skej.team",
                    as: SkejTeamRecord.self
                )
                for team in teams where entitledTeams.contains(
                    ATURI.record(did: team.did, collection: "at.skej.team", rkey: team.rkey)
                ) {
                    entitledViewers.insert(team.value.ownerAdminDid)
                }
                let members = try await services.store.listProtocolRecords(
                    collection: "at.skej.team.member",
                    as: TeamMemberRecord.self
                )
                for member in members where member.value.status == .active && entitledTeams.contains(member.value.teamUri) {
                    entitledViewers.insert(member.value.memberDid)
                }
            }
            viewerDids = entitledViewers.sorted()
        } else {
            viewerDids = try await services.store.listManagedAccounts().map(\.did)
        }

        var accountDids = Set<String>()
        for viewerDid in Set(viewerDids) {
            let viewer = Viewer(did: viewerDid)
            guard try await services.entitlementResolver.isProEnabled(for: viewerDid) else { continue }
            let accounts = try await services.accountResolver.accessibleAccounts(for: viewer)
            for account in accounts {
                let permission = try await services.accountResolver.effectivePermission(
                    for: viewer,
                    brandDid: account.did
                )
                guard permission?.capabilities.contains(.viewAnalytics) == true else { continue }
                accountDids.insert(account.did)
            }
        }
        return accountDids.sorted()
    }

    private func scheduleCorrelations(accountDids: [String]) async -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for accountDid in accountDids {
            do {
                let schedules = try await services.pdsClient.listSchedules(did: accountDid)
                var postToSchedule: [String: String] = [:]
                for (rkey, record) in schedules {
                    for published in record.publishedPosts {
                        postToSchedule[published.uri] = rkey
                    }
                    if let publishedURI = record.publishedUri {
                        postToSchedule[publishedURI] = rkey
                    }
                }
                result[accountDid] = postToSchedule
            } catch {
                logger.warning("engagement schedule correlation failed", metadata: [
                    "account": "\(accountDid)",
                    "error": "\(String(describing: error))",
                ])
            }
        }
        return result
    }
}
