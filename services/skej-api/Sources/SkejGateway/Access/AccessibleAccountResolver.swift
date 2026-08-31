import Foundation
import SkejKit

struct AccessibleAccountResolver: Sendable {
    let store: SQLiteStore
    let pdsClient: any PDSClient

    func accessibleAccounts(for viewer: Viewer) async throws -> [ManagedAccount] {
        let explicit = try await store.listViewerAccounts(viewerDid: viewer.did)
        let permissions = try await effectivePermissions(for: viewer)
        var authorizedDids = Set(explicit.map(\.accountDid))
        authorizedDids.formUnion(permissions.map(\.brandDid))
        authorizedDids.insert(viewer.did)

        let defaultDid = explicit.first(where: \.isDefault)?.accountDid ?? viewer.did
        var accounts: [ManagedAccount] = []
        for did in authorizedDids {
            var account = try await store.managedAccount(did: did) ?? ManagedAccount(did: did)
            if did == viewer.did {
                account.handle = account.handle ?? viewer.handle
                account.displayName = account.displayName ?? viewer.displayName
                account.avatar = account.avatar ?? viewer.avatar
            }
            guard account.status != .disabled else { continue }
            account.isDefault = did == defaultDid
            accounts.append(account)
        }
        return accounts.sorted {
            if $0.isDefault != $1.isDefault { return $0.isDefault }
            return ($0.handle ?? $0.did).localizedCaseInsensitiveCompare($1.handle ?? $1.did) == .orderedAscending
        }
    }

    func effectivePermission(for viewer: Viewer, brandDid: String) async throws -> EffectiveBrandPermission? {
        if brandDid == viewer.did {
            return EffectiveBrandPermission(brandDid: brandDid, capabilities: BrandCapability.allCases)
        }
        if let explicit = try await store.viewerAccount(viewerDid: viewer.did, accountDid: brandDid),
           explicit.accessKind != .team {
            return EffectiveBrandPermission(brandDid: brandDid, capabilities: BrandCapability.allCases)
        }
        return try await effectivePermissions(for: viewer).first { $0.brandDid == brandDid }
    }

    func effectivePermissions(for viewer: Viewer) async throws -> [EffectiveBrandPermission] {
        let graph = try await loadTeamGraph(for: viewer)
        var capabilitiesByBrand: [String: Set<BrandCapability>] = [:]

        for team in graph.teams where team.value.status == .active {
            let teamUri = ATURI.record(did: team.did, collection: "at.skej.team", rkey: team.rkey)
            let isOwner = team.value.ownerAdminDid == viewer.did
            let membership = graph.members.first {
                $0.value.teamUri == teamUri && $0.value.memberDid == viewer.did && $0.value.status == .active
            }
            guard isOwner || membership != nil else { continue }

            let memberGroupUris = Set(membership?.value.groupUris ?? [])
            let groups = graph.groups.filter {
                $0.value.teamUri == teamUri &&
                    $0.value.status == .active &&
                    ($0.value.memberDids.contains(viewer.did) || memberGroupUris.contains(recordURI($0, collection: "at.skej.team.group")))
            }
            let groupUris = Set(groups.map { recordURI($0, collection: "at.skej.team.group") })

            let activeBrands = Set(graph.brands.filter {
                $0.value.teamUri == teamUri && $0.value.status == .active
            }.map(\.value.brandDid))

            if isOwner {
                for brandDid in activeBrands {
                    capabilitiesByBrand[brandDid, default: []].formUnion(BrandCapability.allCases)
                }
            }

            for grant in graph.grants where grant.value.teamUri == teamUri && grant.value.status == .active {
                let direct = grant.value.granteeType == .member && grant.value.grantee == viewer.did
                let throughGroup = grant.value.granteeType == .group && groupUris.contains(grant.value.grantee)
                guard direct || throughGroup else { continue }
                // Existing deployments may have a grant before the corresponding
                // brand designation was cached, so the grant itself remains the
                // authority for that specific DID.
                capabilitiesByBrand[grant.value.brandDid, default: []].formUnion(grant.value.capabilities)
            }
        }

        return capabilitiesByBrand.map { brandDid, capabilities in
            EffectiveBrandPermission(
                brandDid: brandDid,
                capabilities: BrandCapability.allCases.filter(capabilities.contains)
            )
        }.sorted { $0.brandDid < $1.brandDid }
    }

    private func loadTeamGraph(for viewer: Viewer) async throws -> TeamGraph {
        var teams = try await store.listProtocolRecords(collection: "at.skej.team", as: SkejTeamRecord.self)
        var members = try await store.listProtocolRecords(collection: "at.skej.team.member", as: TeamMemberRecord.self)
        var groups = try await store.listProtocolRecords(collection: "at.skej.team.group", as: TeamGroupRecord.self)
        var grants = try await store.listProtocolRecords(collection: "at.skej.team.brandGrant", as: BrandGrantRecord.self)
        var brands = try await store.listProtocolRecords(collection: "at.skej.brand", as: SkejBrandRecord.self)

        // The cache is authoritative for reverse lookup. Refresh every known
        // account as a candidate owner, but never treat that global legacy list
        // as authorization by itself.
        var candidateDids = Set(try await store.listManagedAccounts().map(\.did))
        candidateDids.insert(viewer.did)
        for did in candidateDids {
            teams = merge(teams, try await fetch(did: did, collection: "at.skej.team", as: SkejTeamRecord.self))
            members = merge(members, try await fetch(did: did, collection: "at.skej.team.member", as: TeamMemberRecord.self))
            groups = merge(groups, try await fetch(did: did, collection: "at.skej.team.group", as: TeamGroupRecord.self))
            grants = merge(grants, try await fetch(did: did, collection: "at.skej.team.brandGrant", as: BrandGrantRecord.self))
            brands = merge(brands, try await fetch(did: did, collection: "at.skej.brand", as: SkejBrandRecord.self))
        }
        return TeamGraph(teams: teams, members: members, groups: groups, grants: grants, brands: brands)
    }

    private func fetch<Value: Codable & Sendable>(
        did: String,
        collection: String,
        as type: Value.Type
    ) async throws -> [StoredProtocolRecord<Value>] {
        try await pdsClient.listRecords(did: did, collection: collection, as: type).map {
            StoredProtocolRecord(did: did, rkey: $0.key, value: $0.value)
        }
    }

    private func merge<Value>(
        _ cached: [StoredProtocolRecord<Value>],
        _ refreshed: [StoredProtocolRecord<Value>]
    ) -> [StoredProtocolRecord<Value>] where Value: Codable & Sendable {
        var records = Dictionary(uniqueKeysWithValues: cached.map { ("\($0.did)/\($0.rkey)", $0) })
        for record in refreshed { records["\(record.did)/\(record.rkey)"] = record }
        return Array(records.values)
    }

    private func recordURI<Value>(_ record: StoredProtocolRecord<Value>, collection: String) -> String {
        ATURI.record(did: record.did, collection: collection, rkey: record.rkey)
    }
}

struct ProEntitlementResolver: Sendable {
    let config: AppConfig
    let store: SQLiteStore

    func isProEnabled(for viewerDid: String, now: String = Timestamp.iso8601()) async throws -> Bool {
        guard config.proFeaturesEnabled else { return false }
        if try await store.proEntitlement(scope: .actor, subject: viewerDid)?.isActive(at: now) == true {
            return true
        }
        let teamEntitlements = try await store.listProEntitlements().filter {
            $0.scope == .team && $0.isActive(at: now)
        }
        guard !teamEntitlements.isEmpty else { return false }
        let entitledTeamUris = Set(teamEntitlements.map(\.subject))
        let teams = try await store.listProtocolRecords(collection: "at.skej.team", as: SkejTeamRecord.self)
        if teams.contains(where: {
            $0.value.ownerAdminDid == viewerDid &&
                entitledTeamUris.contains(ATURI.record(did: $0.did, collection: "at.skej.team", rkey: $0.rkey))
        }) {
            return true
        }
        let members = try await store.listProtocolRecords(collection: "at.skej.team.member", as: TeamMemberRecord.self)
        return members.contains {
            $0.value.memberDid == viewerDid && $0.value.status == .active && entitledTeamUris.contains($0.value.teamUri)
        }
    }

    func requireAdministrator(_ viewerDid: String) throws {
        guard config.adminDids.contains(viewerDid) else {
            throw APIError(status: .forbidden, code: "forbidden", message: "Skej administrator access required")
        }
    }
}

private struct TeamGraph {
    let teams: [StoredProtocolRecord<SkejTeamRecord>]
    let members: [StoredProtocolRecord<TeamMemberRecord>]
    let groups: [StoredProtocolRecord<TeamGroupRecord>]
    let grants: [StoredProtocolRecord<BrandGrantRecord>]
    let brands: [StoredProtocolRecord<SkejBrandRecord>]
}
