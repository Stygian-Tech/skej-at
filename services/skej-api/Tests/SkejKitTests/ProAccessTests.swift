import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import SkejGateway
import SkejKit
import Testing

@Suite
struct ProAccessTests {
    @Test func legacyGlobalAccountsAreNotExposedToAnEntitledViewer() async throws {
        let services = try await makeTestServices()
        try await services.store.upsertManagedAccount(
            ManagedAccount(did: "did:plc:legacy-secondary", handle: "legacy.example"),
            now: "2026-08-30T12:00:00Z"
        )
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/xrpc/at.skej.account.list",
                method: .get,
                headers: didHeaders("did:plc:test")
            ) { response in
                let body = String(buffer: response.body)
                #expect(response.status == .ok)
                #expect(body.contains("did:plc:test"))
                #expect(!body.contains("did:plc:legacy-secondary"))
            }
        }
    }

    @Test func invitationLifecycleUsesAuthenticatedTeamAdministration() async throws {
        let services = try await makeTestServices()
        let now = Timestamp.iso8601()
        try await services.pdsClient.writeRecord(
            did: "did:plc:test",
            collection: "at.skej.team",
            rkey: "team",
            record: SkejTeamRecord(
                ownerAdminDid: "did:plc:test",
                title: "Test Team",
                createdAt: now,
                updatedAt: now
            )
        )
        try await services.pdsClient.writeRecord(
            did: "did:plc:test",
            collection: "at.skej.team.member",
            rkey: "admin",
            record: TeamMemberRecord(
                teamUri: "at://did:plc:test/at.skej.team/team",
                memberDid: "did:plc:admin",
                role: .admin,
                createdAt: now,
                updatedAt: now
            )
        )
        let app = Application(router: buildRouter(services: services))
        let input = SkejCreateInviteInput(teamRkey: "team", invitedHandle: "invitee.example", role: .user)

        try await app.test(.router) { client in
            var createdInvite: TeamInvite?
            try await client.execute(
                uri: "/xrpc/at.skej.team.createInvite",
                method: .post,
                headers: jsonHeaders("did:plc:test"),
                body: try encodedBody(input)
            ) { response in
                #expect(response.status == .ok)
                createdInvite = try JSONDecoder().decode(TeamInvite.self, from: Data(buffer: response.body))
            }
            let invite = try #require(createdInvite)
            #expect(invite.status == .pending)

            try await client.execute(
                uri: "/xrpc/at.skej.team.listInvites?teamRkey=team",
                method: .get,
                headers: didHeaders("did:plc:test")
            ) { response in
                let list = try JSONDecoder().decode(ListTeamInvitesResponse.self, from: Data(buffer: response.body))
                #expect(list.invites.map(\.id) == [invite.id])
            }

            try await client.execute(
                uri: "/xrpc/at.skej.team.revokeInvite",
                method: .post,
                headers: jsonHeaders("did:plc:admin"),
                body: try encodedBody(SkejRevokeInviteInput(inviteId: invite.id))
            ) { response in
                #expect(response.status == .ok)
            }
            #expect(try await services.store.teamInvite(token: invite.token)?.status == .revoked)
        }
    }

    @Test func viewerAccountsStayViewerScopedAndMigrationOnlyMapsSelf() async throws {
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let now = "2026-08-30T12:00:00Z"
        try await store.upsertManagedAccount(ManagedAccount(did: "did:plc:viewer"), now: now)
        try await store.upsertManagedAccount(ManagedAccount(did: "did:plc:legacy-secondary"), now: now)
        try await store.createOAuthSession(
            OAuthSessionRecord(did: "did:plc:viewer", handle: nil, tokenJSON: "{}", dpopKeyJSON: "{}"),
            now: now
        )

        try await store.migrate()

        #expect(try await store.listViewerAccounts(viewerDid: "did:plc:viewer").map(\.accountDid) == ["did:plc:viewer"])
        #expect(try await store.viewerAccount(viewerDid: "did:plc:viewer", accountDid: "did:plc:legacy-secondary") == nil)
    }

    @Test func oauthStateRoundTripsConnectionPurposeAndContext() async throws {
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        try await store.createOAuthState(
            state: "state",
            handle: "brand.example",
            pkceVerifier: "pkce",
            nonce: "nonce",
            purpose: .brandConnection,
            initiatorDid: "did:plc:viewer",
            returnTo: "/app/account",
            expiresAt: "2026-08-31T12:00:00Z"
        )

        let state = try await store.consumeOAuthState(state: "state", now: "2026-08-30T12:00:00Z")
        #expect(state?.purpose == .brandConnection)
        #expect(state?.initiatorDid == "did:plc:viewer")
        #expect(state?.returnTo == "/app/account")
        #expect(try await store.consumeOAuthState(state: "state", now: "2026-08-30T12:00:00Z") == nil)
    }

    @Test func entitlementsSupportActorAndTeamScopes() async throws {
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let now = "2026-08-30T12:00:00Z"
        let actor = ProEntitlement(subject: "did:plc:viewer", status: .active, createdAt: now, updatedAt: now)
        let team = ProEntitlement(
            scope: .team,
            subject: "at://did:plc:owner/at.skej.team/team",
            status: .active,
            expiresAt: "2026-08-31T12:00:00Z",
            createdAt: now,
            updatedAt: now
        )
        try await store.upsertProEntitlement(actor)
        try await store.upsertProEntitlement(team)

        #expect(try await store.proEntitlement(scope: .actor, subject: actor.subject) == actor)
        #expect(try await store.proEntitlement(scope: .team, subject: team.subject) == team)
        #expect(team.isActive(at: now))
        #expect(!team.isActive(at: "2026-09-01T12:00:00Z"))
    }

    @Test func legacyGroupAndGrantRecordsDecodeAsActive() throws {
        let group = try JSONDecoder().decode(TeamGroupRecord.self, from: Data(#"""
        {
          "$type":"at.skej.team.group","teamUri":"at://did:plc:o/at.skej.team/t",
          "name":"Editors","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"
        }
        """#.utf8))
        let grant = try JSONDecoder().decode(BrandGrantRecord.self, from: Data(#"""
        {
          "$type":"at.skej.team.brandGrant","teamUri":"at://did:plc:o/at.skej.team/t",
          "brandDid":"did:plc:brand","granteeType":"member","grantee":"did:plc:user",
          "capabilities":["viewAnalytics"],"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"
        }
        """#.utf8))

        #expect(group.status == .active)
        #expect(grant.status == .active)
        #expect(grant.capabilities == [.viewAnalytics])
    }
}

private func jsonHeaders(_ did: String) -> HTTPFields {
    var headers = didHeaders(did)
    headers[.contentType] = "application/json"
    return headers
}
