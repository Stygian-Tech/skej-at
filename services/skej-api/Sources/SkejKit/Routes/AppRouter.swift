import Crypto
import Foundation
import Hummingbird
import HTTPTypes

public func buildRouter(services: SkejServices) -> Router<BasicRequestContext> {
    let router = Router(context: BasicRequestContext.self)
    router.add(middleware: ErrorMiddleware())
    router.add(middleware: CorsMiddleware())

    router.get("health") { _, _ in
        try jsonResponse(["status": "ok", "service": "skej-api"])
    }

    router.get("oauth/client-metadata.json") { _, _ in
        try jsonResponse(OAuthMetadata.webClientMetadata(
            publicOrigin: services.config.publicOrigin,
            redirectOrigin: services.config.webOrigin
        ))
    }

    router.get("oauth/jwks.json") { _, _ in
        try jsonResponse(OAuthMetadata.jwks())
    }

    router.get("oauth/start") { request, _ in
        let handle = (request.uri.queryParameters.get("handle") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !handle.isEmpty else {
            throw APIError(status: .badRequest, code: "missing_handle", message: "Bluesky handle is required")
        }
        let state = randomToken()
        let pkceVerifier = randomToken()
        let nonce = randomToken()
        let start = try await services.oauthClient.start(
            handle: handle,
            state: state,
            pkceVerifier: pkceVerifier,
            nonce: nonce
        )
        try await services.store.createOAuthState(
            state: state,
            handle: handle,
            pkceVerifier: pkceVerifier,
            nonce: nonce,
            authServer: start.authServer,
            tokenEndpoint: start.tokenEndpoint,
            pdsEndpoint: start.pdsEndpoint,
            dpopKeyJSON: start.dpopKeyJSON,
            expiresAt: Timestamp.iso8601(Date().addingTimeInterval(600))
        )
        var headers = HTTPFields()
        headers[.location] = start.redirectURL
        return Response(status: .found, headers: headers)
    }

    router.get("oauth/callback") { request, _ in
        guard let state = request.uri.queryParameters.get("state") else {
            throw APIError(status: .badRequest, code: "missing_state", message: "OAuth state is required")
        }
        guard let code = request.uri.queryParameters.get("code") else {
            throw APIError(status: .badRequest, code: "missing_code", message: "OAuth authorization code is required")
        }
        let now = Timestamp.iso8601()
        guard let oauthState = try await services.store.consumeOAuthState(state: state, now: now) else {
            throw APIError(status: .badRequest, code: "invalid_state", message: "OAuth state expired or was already used")
        }
        let completion = try await services.oauthClient.complete(state: oauthState, code: code)
        let session = randomToken()
        try await services.store.createOAuthSession(completion.session, now: now)
        try await services.store.upsertManagedAccount(
            ManagedAccount(
                did: completion.viewer.did,
                handle: completion.viewer.handle,
                displayName: completion.viewer.displayName,
                avatar: completion.viewer.avatar,
                pdsEndpoint: oauthState.pdsEndpoint,
                status: .active,
                isDefault: true
            ),
            now: now
        )
        try await services.store.insertAuditEvent(
            did: completion.viewer.did,
            scheduleRkey: nil,
            action: "account_connected",
            message: "Connected \(completion.viewer.handle ?? completion.viewer.did).",
            now: now
        )
        try await services.store.createWebSession(
            sessionID: session,
            did: completion.viewer.did,
            handle: completion.viewer.handle,
            displayName: completion.viewer.displayName,
            avatar: completion.viewer.avatar,
            expiresAt: Timestamp.iso8601(Date().addingTimeInterval(60 * 60 * 24 * 30))
        )
        var headers = HTTPFields()
        headers[.location] = "/app"
        let secure = services.config.environment == .local || services.config.environment == .test ? "" : "; Secure"
        headers[HTTPField.Name("Set-Cookie")!] =
            "skej_session=\(session); Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000\(secure)"
        return Response(status: .found, headers: headers)
    }

    let v1 = router.group("v1")

    v1.get("me") { request, _ in
        let viewer = try await authenticate(request, services: services)
        return try jsonResponse(viewer)
    }

    v1.post("logout") { request, _ in
        if let sessionID = cookie(named: "skej_session", in: request.headers[.cookie] ?? "") {
            try await services.store.deleteWebSession(sessionID: sessionID)
        }
        var headers = HTTPFields()
        let secure = services.config.environment == .local || services.config.environment == .test ? "" : "; Secure"
        headers[HTTPField.Name("Set-Cookie")!] =
            "skej_session=deleted; Path=/; HttpOnly; SameSite=Lax; Max-Age=0\(secure)"
        return try jsonResponse(OKResponse(ok: true), status: .ok).withHeaders(headers)
    }

    v1.get("accounts") { request, _ in
        _ = try await authenticate(request, services: services)
        let accounts = try await services.store.listManagedAccounts()
        return try jsonResponse(ListAccountsResponse(accounts: accounts))
    }

    v1.get("teams") { request, _ in
        let viewer = try await authenticate(request, services: services)
        let teams = try await listVisibleTeams(viewer: viewer, services: services)
        return try jsonResponse(ListTeamsResponse(teams: teams))
    }

    v1.post("teams") { request, _ in
        let viewer = try await authenticate(request, services: services)
        let body = try await decodeJSONBody(request, as: CreateTeamRequest.self)
        let now = Timestamp.iso8601()
        let rkey = newRkey()
        let record = SkejTeamRecord(
            ownerAdminDid: viewer.did,
            title: body.title.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now,
            updatedAt: now
        )
        try validate(team: record)
        try await services.pdsClient.writeRecord(did: viewer.did, collection: "at.skej.team", rkey: rkey, record: record)
        let uri = ATURI.record(did: viewer.did, collection: "at.skej.team", rkey: rkey)
        try await services.store.insertAuditEvent(
            did: viewer.did,
            scheduleRkey: nil,
            action: "team_created",
            message: "Created team \(record.title).",
            now: now
        )
        return try jsonResponse(TeamSummary(rkey: rkey, uri: uri, record: record), status: .created)
    }

    v1.get("teams/:teamRkey") { request, context in
        let viewer = try await authenticate(request, services: services)
        let team = try await requireVisibleTeam(rkey: try context.parameters.require("teamRkey"), viewer: viewer, services: services)
        return try jsonResponse(team)
    }

    v1.patch("teams/:teamRkey") { request, context in
        let viewer = try await authenticate(request, services: services)
        var team = try await requireTeamAdmin(rkey: try context.parameters.require("teamRkey"), viewer: viewer, services: services)
        let body = try await decodeJSONBody(request, as: UpdateTeamRequest.self)
        if let title = body.title {
            team.record.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let status = body.status {
            team.record.status = status
        }
        team.record.updatedAt = Timestamp.iso8601()
        try validate(team: team.record)
        try await services.pdsClient.writeRecord(did: teamOwnerDid(team.uri), collection: "at.skej.team", rkey: team.rkey, record: team.record)
        return try jsonResponse(team)
    }

    v1.post("teams/:teamRkey/transfer-owner") { request, context in
        let viewer = try await authenticate(request, services: services)
        var team = try await requireOwnedTeam(rkey: try context.parameters.require("teamRkey"), viewer: viewer, services: services)
        let body = try await decodeJSONBody(request, as: TransferTeamOwnerRequest.self)
        team.record.ownerAdminDid = body.ownerAdminDid
        team.record.updatedAt = Timestamp.iso8601()
        try await services.pdsClient.writeRecord(did: viewer.did, collection: "at.skej.team", rkey: team.rkey, record: team.record)
        return try jsonResponse(team)
    }

    v1.get("teams/:teamRkey/members") { request, context in
        let viewer = try await authenticate(request, services: services)
        let team = try await requireVisibleTeam(rkey: try context.parameters.require("teamRkey"), viewer: viewer, services: services)
        return try jsonResponse(ListMembersResponse(members: try await listTeamMembers(team: team, services: services)))
    }

    v1.post("teams/:teamRkey/members") { request, context in
        let viewer = try await authenticate(request, services: services)
        let team = try await requireTeamAdmin(rkey: try context.parameters.require("teamRkey"), viewer: viewer, services: services)
        let body = try await decodeJSONBody(request, as: UpsertMemberRequest.self)
        let now = Timestamp.iso8601()
        let rkey = body.memberDid.replacingOccurrences(of: ":", with: "_")
        let record = TeamMemberRecord(
            teamUri: team.uri,
            memberDid: body.memberDid,
            role: body.role,
            status: body.status ?? .active,
            groupUris: body.groupUris ?? [],
            createdAt: now,
            updatedAt: now
        )
        try await services.pdsClient.writeRecord(did: teamOwnerDid(team.uri), collection: "at.skej.team.member", rkey: rkey, record: record)
        return try jsonResponse(TeamMemberSummary(rkey: rkey, uri: ATURI.record(did: teamOwnerDid(team.uri), collection: "at.skej.team.member", rkey: rkey), record: record), status: .created)
    }

    v1.patch("teams/:teamRkey/members/:memberDid") { request, context in
        let viewer = try await authenticate(request, services: services)
        let team = try await requireTeamAdmin(rkey: try context.parameters.require("teamRkey"), viewer: viewer, services: services)
        let body = try await decodeJSONBody(request, as: UpsertMemberRequest.self)
        let memberDid = try context.parameters.require("memberDid")
        guard memberDid == body.memberDid else {
            throw APIError(status: .badRequest, code: "invalid_member", message: "Member DID mismatch")
        }
        let now = Timestamp.iso8601()
        let rkey = memberDid.replacingOccurrences(of: ":", with: "_")
        let existing = try await services.pdsClient.getRecord(did: teamOwnerDid(team.uri), collection: "at.skej.team.member", rkey: rkey, as: TeamMemberRecord.self)
        let record = TeamMemberRecord(
            teamUri: team.uri,
            memberDid: memberDid,
            role: body.role,
            status: body.status ?? existing?.status ?? .active,
            groupUris: body.groupUris ?? existing?.groupUris ?? [],
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        try await services.pdsClient.writeRecord(did: teamOwnerDid(team.uri), collection: "at.skej.team.member", rkey: rkey, record: record)
        return try jsonResponse(TeamMemberSummary(rkey: rkey, uri: ATURI.record(did: teamOwnerDid(team.uri), collection: "at.skej.team.member", rkey: rkey), record: record))
    }

    v1.get("teams/:teamRkey/groups") { request, context in
        let viewer = try await authenticate(request, services: services)
        let team = try await requireVisibleTeam(rkey: try context.parameters.require("teamRkey"), viewer: viewer, services: services)
        return try jsonResponse(ListGroupsResponse(groups: try await listTeamGroups(team: team, services: services)))
    }

    v1.post("teams/:teamRkey/groups") { request, context in
        let viewer = try await authenticate(request, services: services)
        let team = try await requireTeamAdmin(rkey: try context.parameters.require("teamRkey"), viewer: viewer, services: services)
        let body = try await decodeJSONBody(request, as: UpsertGroupRequest.self)
        let now = Timestamp.iso8601()
        let rkey = newRkey()
        let record = TeamGroupRecord(
            teamUri: team.uri,
            name: body.name,
            memberDids: body.memberDids ?? [],
            brandGrantUris: body.brandGrantUris ?? [],
            createdAt: now,
            updatedAt: now
        )
        try await services.pdsClient.writeRecord(did: teamOwnerDid(team.uri), collection: "at.skej.team.group", rkey: rkey, record: record)
        return try jsonResponse(TeamGroupSummary(rkey: rkey, uri: ATURI.record(did: teamOwnerDid(team.uri), collection: "at.skej.team.group", rkey: rkey), record: record), status: .created)
    }

    v1.patch("teams/:teamRkey/groups/:groupRkey") { request, context in
        let viewer = try await authenticate(request, services: services)
        let team = try await requireTeamAdmin(rkey: try context.parameters.require("teamRkey"), viewer: viewer, services: services)
        let rkey = try context.parameters.require("groupRkey")
        let body = try await decodeJSONBody(request, as: UpsertGroupRequest.self)
        let now = Timestamp.iso8601()
        let existing = try await services.pdsClient.getRecord(did: teamOwnerDid(team.uri), collection: "at.skej.team.group", rkey: rkey, as: TeamGroupRecord.self)
        let record = TeamGroupRecord(
            teamUri: team.uri,
            name: body.name,
            memberDids: body.memberDids ?? existing?.memberDids ?? [],
            brandGrantUris: body.brandGrantUris ?? existing?.brandGrantUris ?? [],
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        try await services.pdsClient.writeRecord(did: teamOwnerDid(team.uri), collection: "at.skej.team.group", rkey: rkey, record: record)
        return try jsonResponse(TeamGroupSummary(rkey: rkey, uri: ATURI.record(did: teamOwnerDid(team.uri), collection: "at.skej.team.group", rkey: rkey), record: record))
    }

    v1.get("teams/:teamRkey/brand-grants") { request, context in
        let viewer = try await authenticate(request, services: services)
        let team = try await requireVisibleTeam(rkey: try context.parameters.require("teamRkey"), viewer: viewer, services: services)
        return try jsonResponse(ListBrandGrantsResponse(grants: try await listBrandGrants(team: team, services: services)))
    }

    v1.post("teams/:teamRkey/brand-grants") { request, context in
        let viewer = try await authenticate(request, services: services)
        let team = try await requireTeamAdmin(rkey: try context.parameters.require("teamRkey"), viewer: viewer, services: services)
        let body = try await decodeJSONBody(request, as: UpsertBrandGrantRequest.self)
        let now = Timestamp.iso8601()
        let rkey = newRkey()
        let record = BrandGrantRecord(
            teamUri: team.uri,
            brandDid: body.brandDid,
            granteeType: body.granteeType,
            grantee: body.grantee,
            capabilities: Array(Set(body.capabilities)),
            createdAt: now,
            updatedAt: now
        )
        try await services.pdsClient.writeRecord(did: teamOwnerDid(team.uri), collection: "at.skej.team.brandGrant", rkey: rkey, record: record)
        return try jsonResponse(BrandGrantSummary(rkey: rkey, uri: ATURI.record(did: teamOwnerDid(team.uri), collection: "at.skej.team.brandGrant", rkey: rkey), record: record), status: .created)
    }

    v1.patch("teams/:teamRkey/brand-grants/:grantRkey") { request, context in
        let viewer = try await authenticate(request, services: services)
        let team = try await requireTeamAdmin(rkey: try context.parameters.require("teamRkey"), viewer: viewer, services: services)
        let rkey = try context.parameters.require("grantRkey")
        let body = try await decodeJSONBody(request, as: UpsertBrandGrantRequest.self)
        let now = Timestamp.iso8601()
        let existing = try await services.pdsClient.getRecord(did: teamOwnerDid(team.uri), collection: "at.skej.team.brandGrant", rkey: rkey, as: BrandGrantRecord.self)
        let record = BrandGrantRecord(
            teamUri: team.uri,
            brandDid: body.brandDid,
            granteeType: body.granteeType,
            grantee: body.grantee,
            capabilities: Array(Set(body.capabilities)),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        try await services.pdsClient.writeRecord(did: teamOwnerDid(team.uri), collection: "at.skej.team.brandGrant", rkey: rkey, record: record)
        return try jsonResponse(BrandGrantSummary(rkey: rkey, uri: ATURI.record(did: teamOwnerDid(team.uri), collection: "at.skej.team.brandGrant", rkey: rkey), record: record))
    }

    v1.get("teams/:teamRkey/brands") { request, context in
        let viewer = try await authenticate(request, services: services)
        let team = try await requireVisibleTeam(rkey: try context.parameters.require("teamRkey"), viewer: viewer, services: services)
        return try jsonResponse(ListBrandsResponse(brands: try await listBrands(team: team, services: services)))
    }

    v1.post("teams/:teamRkey/brands") { request, context in
        let viewer = try await authenticate(request, services: services)
        let team = try await requireTeamAdmin(rkey: try context.parameters.require("teamRkey"), viewer: viewer, services: services)
        let body = try await decodeJSONBody(request, as: UpsertBrandRequest.self)
        let now = Timestamp.iso8601()
        let rkey = body.brandDid.replacingOccurrences(of: ":", with: "_")
        let record = SkejBrandRecord(
            teamUri: team.uri,
            ownerAdminDid: team.record.ownerAdminDid,
            brandDid: body.brandDid,
            status: body.status ?? .active,
            createdAt: now,
            updatedAt: now
        )
        try await services.pdsClient.writeRecord(did: body.brandDid, collection: "at.skej.brand", rkey: rkey, record: record)
        return try jsonResponse(BrandSummary(rkey: rkey, uri: ATURI.record(did: body.brandDid, collection: "at.skej.brand", rkey: rkey), record: record), status: .created)
    }

    v1.patch("teams/:teamRkey/brands/:brandDid") { request, context in
        let viewer = try await authenticate(request, services: services)
        let team = try await requireTeamAdmin(rkey: try context.parameters.require("teamRkey"), viewer: viewer, services: services)
        let brandDid = try context.parameters.require("brandDid")
        let body = try await decodeJSONBody(request, as: UpsertBrandRequest.self)
        guard brandDid == body.brandDid else {
            throw APIError(status: .badRequest, code: "invalid_brand", message: "Brand DID mismatch")
        }
        let now = Timestamp.iso8601()
        let rkey = brandDid.replacingOccurrences(of: ":", with: "_")
        let existing = try await services.pdsClient.getRecord(did: brandDid, collection: "at.skej.brand", rkey: rkey, as: SkejBrandRecord.self)
        let record = SkejBrandRecord(
            teamUri: team.uri,
            ownerAdminDid: team.record.ownerAdminDid,
            brandDid: brandDid,
            status: body.status ?? existing?.status ?? .active,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        try await services.pdsClient.writeRecord(did: brandDid, collection: "at.skej.brand", rkey: rkey, record: record)
        return try jsonResponse(BrandSummary(rkey: rkey, uri: ATURI.record(did: brandDid, collection: "at.skej.brand", rkey: rkey), record: record))
    }

    v1.get("brands/:did/profile") { request, context in
        let did = try context.parameters.require("did")
        let viewer = try await authorize(did: did, request: request, services: services)
        _ = try await requireBrandCapability(.create, brandDid: did, viewer: viewer, services: services)
        let profile = try await services.pdsClient.getBrandProfile(did: did)
        return try jsonResponse(profile)
    }

    v1.patch("brands/:did/profile") { request, context in
        let did = try context.parameters.require("did")
        let viewer = try await authorize(did: did, request: request, services: services)
        _ = try await requireBrandCapability(.manage, brandDid: did, viewer: viewer, services: services)
        let body = try await decodeJSONBody(request, as: UpdateBrandProfileRequest.self)
        let profile = try await services.pdsClient.updateBrandProfile(did: did, profile: body)
        try await services.store.insertAuditEvent(
            did: did,
            scheduleRkey: nil,
            action: "brand_profile_updated",
            message: "Brand profile updated.",
            now: Timestamp.iso8601()
        )
        return try jsonResponse(profile)
    }

    v1.get("accounts/:did/schedules") { request, context in
        let did = try context.parameters.require("did")
        let viewer = try await authorize(did: did, request: request, services: services)
        _ = try await requireAnyBrandCapability([.create, .approve, .manage], brandDid: did, viewer: viewer, services: services)
        return try await listSchedules(did: did, services: services)
    }

    v1.post("accounts/:did/schedules") { request, context in
        let did = try context.parameters.require("did")
        let viewer = try await authorize(did: did, request: request, services: services)
        let body = try await decodeJSONBody(request, as: CreateScheduleRequest.self)
        return try await createSchedule(did: did, body: body, viewer: viewer, services: services)
    }

    v1.patch("accounts/:did/schedules/:rkey") { request, context in
        let did = try context.parameters.require("did")
        let rkey = try context.parameters.require("rkey")
        let viewer = try await authorize(did: did, request: request, services: services)
        let body = try await decodeJSONBody(request, as: CreateScheduleRequest.self)
        return try await updateSchedule(did: did, rkey: rkey, body: body, viewer: viewer, services: services)
    }

    v1.post("accounts/:did/schedules/:rkey/cancel") { request, context in
        let did = try context.parameters.require("did")
        let rkey = try context.parameters.require("rkey")
        let viewer = try await authorize(did: did, request: request, services: services)
        _ = try await requireBrandCapability(.approve, brandDid: did, viewer: viewer, services: services)
        return try await cancelSchedule(did: did, rkey: rkey, services: services)
    }

    v1.post("accounts/:did/schedules/:rkey/retry") { request, context in
        let did = try context.parameters.require("did")
        let rkey = try context.parameters.require("rkey")
        let viewer = try await authorize(did: did, request: request, services: services)
        _ = try await requireBrandCapability(.approve, brandDid: did, viewer: viewer, services: services)
        return try await retrySchedule(did: did, rkey: rkey, services: services)
    }

    v1.post("accounts/:did/schedules/:rkey/duplicate") { request, context in
        let did = try context.parameters.require("did")
        let rkey = try context.parameters.require("rkey")
        let viewer = try await authorize(did: did, request: request, services: services)
        _ = try await requireBrandCapability(.create, brandDid: did, viewer: viewer, services: services)
        return try await duplicateSchedule(did: did, rkey: rkey, services: services)
    }

    v1.post("accounts/:did/schedules/:rkey/publish-now") { request, context in
        let did = try context.parameters.require("did")
        let rkey = try context.parameters.require("rkey")
        let viewer = try await authorize(did: did, request: request, services: services)
        _ = try await requireBrandCapability(.approve, brandDid: did, viewer: viewer, services: services)
        return try await publishNow(did: did, rkey: rkey, services: services)
    }

    v1.post("accounts/:did/schedules/:rkey/view") { request, context in
        let did = try context.parameters.require("did")
        let rkey = try context.parameters.require("rkey")
        _ = try await authorize(did: did, request: request, services: services)
        try await services.store.insertAuditEvent(
            did: did,
            scheduleRkey: rkey,
            action: "schedule_viewed",
            message: "Viewed schedule \(rkey).",
            now: Timestamp.iso8601()
        )
        return try jsonResponse(OKResponse(ok: true))
    }

    v1.get("accounts/:did/audit") { request, context in
        let did = try context.parameters.require("did")
        _ = try await authorize(did: did, request: request, services: services)
        let events = try await services.store.listAuditEvents(did: did)
        return try jsonResponse(ListAuditEventsResponse(events: events))
    }

    v1.get("schedules") { request, _ in
        let viewer = try await authenticate(request, services: services)
        let did = viewer.defaultAccountDid ?? viewer.did
        _ = try await requireAnyBrandCapability([.create, .approve, .manage], brandDid: did, viewer: viewer, services: services)
        return try await listSchedules(did: did, services: services)
    }

    v1.post("schedules") { request, _ in
        let viewer = try await authenticate(request, services: services)
        let body = try await decodeJSONBody(request, as: CreateScheduleRequest.self)
        return try await createSchedule(did: viewer.defaultAccountDid ?? viewer.did, body: body, viewer: viewer, services: services)
    }

    v1.patch("schedules/:rkey") { request, context in
        let viewer = try await authenticate(request, services: services)
        let rkey = try context.parameters.require("rkey")
        let body = try await decodeJSONBody(request, as: CreateScheduleRequest.self)
        return try await updateSchedule(did: viewer.defaultAccountDid ?? viewer.did, rkey: rkey, body: body, viewer: viewer, services: services)
    }

    v1.delete("schedules/:rkey") { request, context in
        let viewer = try await authenticate(request, services: services)
        let rkey = try context.parameters.require("rkey")
        _ = try await requireBrandCapability(.approve, brandDid: viewer.defaultAccountDid ?? viewer.did, viewer: viewer, services: services)
        return try await cancelSchedule(did: viewer.defaultAccountDid ?? viewer.did, rkey: rkey, services: services)
    }

    v1.post("schedules/:rkey/publish-now") { request, context in
        let viewer = try await authenticate(request, services: services)
        let rkey = try context.parameters.require("rkey")
        _ = try await requireBrandCapability(.approve, brandDid: viewer.defaultAccountDid ?? viewer.did, viewer: viewer, services: services)
        return try await publishNow(did: viewer.defaultAccountDid ?? viewer.did, rkey: rkey, services: services)
    }

    v1.post("dev/seed") { _, _ in
        guard services.config.environment != .prod else {
            throw APIError(status: .notFound, code: "not_found", message: "Not found")
        }
        try await seedDemoData(services: services)
        return try jsonResponse(OKResponse(ok: true))
    }

    return router
}

private func seedDemoData(services: SkejServices) async throws {
    let now = Date()
    let nowString = Timestamp.iso8601(now)
    let ownerDid = localDID(for: "any")
    let adminDid = localDID(for: "sam.skej.at")
    let userDid = localDID(for: "alex.skej.at")
    let producerDid = localDID(for: "maya.skej.at")
    let studioDid = localDID(for: "studio.skej.at")
    let appDid = localDID(for: "skej.app")
    let teamRkey = "demo-team"
    let teamUri = ATURI.record(did: ownerDid, collection: "at.skej.team", rkey: teamRkey)
    let approversGroupRkey = "demo-approvers"
    let creatorsGroupRkey = "demo-creators"
    let approversGroupUri = ATURI.record(did: ownerDid, collection: "at.skej.team.group", rkey: approversGroupRkey)
    let creatorsGroupUri = ATURI.record(did: ownerDid, collection: "at.skej.team.group", rkey: creatorsGroupRkey)

    let accounts: [ManagedAccount] = [
        ManagedAccount(did: ownerDid, handle: "any", displayName: "any", avatar: nil, pdsEndpoint: "local", status: .active, isDefault: true),
        ManagedAccount(did: adminDid, handle: "sam.skej.at", displayName: "Sam", avatar: nil, pdsEndpoint: "local", status: .active, isDefault: false),
        ManagedAccount(did: userDid, handle: "alex.skej.at", displayName: "Alex", avatar: nil, pdsEndpoint: "local", status: .active, isDefault: false),
        ManagedAccount(did: producerDid, handle: "maya.skej.at", displayName: "Maya", avatar: nil, pdsEndpoint: "local", status: .active, isDefault: false),
        ManagedAccount(did: studioDid, handle: "studio.skej.at", displayName: "Skej Studio", avatar: nil, pdsEndpoint: "local", status: .active, isDefault: false),
        ManagedAccount(did: appDid, handle: "skej.app", displayName: "Skej App", avatar: nil, pdsEndpoint: "local", status: .active, isDefault: false),
    ]
    for account in accounts {
        try await services.store.upsertManagedAccount(account, now: nowString)
    }

    let team = SkejTeamRecord(
        ownerAdminDid: ownerDid,
        title: "Skej Launch Team",
        status: .active,
        createdAt: iso(daysFromNow: -14, from: now),
        updatedAt: nowString
    )
    try await services.pdsClient.writeRecord(did: ownerDid, collection: "at.skej.team", rkey: teamRkey, record: team)

    let members: [(String, TeamRole, [String])] = [
        (ownerDid, .admin, [approversGroupUri, creatorsGroupUri]),
        (adminDid, .admin, [approversGroupUri, creatorsGroupUri]),
        (userDid, .user, [creatorsGroupUri]),
        (producerDid, .user, [creatorsGroupUri]),
    ]
    for (did, role, groupUris) in members {
        let record = TeamMemberRecord(
            teamUri: teamUri,
            memberDid: did,
            role: role,
            status: .active,
            groupUris: groupUris,
            createdAt: nowString,
            updatedAt: nowString
        )
        try await services.pdsClient.writeRecord(
            did: ownerDid,
            collection: "at.skej.team.member",
            rkey: demoRkey(for: did),
            record: record
        )
    }

    let grants: [(String, String, GrantGranteeType, String, [BrandCapability])] = [
        ("grant-any-owner", ownerDid, .member, ownerDid, [.create, .approve, .manage]),
        ("grant-studio-owner", studioDid, .member, ownerDid, [.create, .approve, .manage]),
        ("grant-app-owner", appDid, .member, ownerDid, [.create, .approve, .manage]),
        ("grant-studio-approvers", studioDid, .group, approversGroupUri, [.create, .approve]),
        ("grant-app-approvers", appDid, .group, approversGroupUri, [.create, .approve]),
        ("grant-studio-creators", studioDid, .group, creatorsGroupUri, [.create]),
        ("grant-app-creators", appDid, .group, creatorsGroupUri, [.create]),
    ]
    for (rkey, brandDid, granteeType, grantee, capabilities) in grants {
        let record = BrandGrantRecord(
            teamUri: teamUri,
            brandDid: brandDid,
            granteeType: granteeType,
            grantee: grantee,
            capabilities: capabilities,
            createdAt: nowString,
            updatedAt: nowString
        )
        try await services.pdsClient.writeRecord(did: ownerDid, collection: "at.skej.team.brandGrant", rkey: rkey, record: record)
    }

    let approvers = TeamGroupRecord(
        teamUri: teamUri,
        name: "Approvers",
        memberDids: [ownerDid, adminDid],
        brandGrantUris: [
            ATURI.record(did: ownerDid, collection: "at.skej.team.brandGrant", rkey: "grant-studio-approvers"),
            ATURI.record(did: ownerDid, collection: "at.skej.team.brandGrant", rkey: "grant-app-approvers"),
        ],
        createdAt: nowString,
        updatedAt: nowString
    )
    try await services.pdsClient.writeRecord(did: ownerDid, collection: "at.skej.team.group", rkey: approversGroupRkey, record: approvers)

    let creators = TeamGroupRecord(
        teamUri: teamUri,
        name: "Creators",
        memberDids: [ownerDid, adminDid, userDid, producerDid],
        brandGrantUris: [
            ATURI.record(did: ownerDid, collection: "at.skej.team.brandGrant", rkey: "grant-studio-creators"),
            ATURI.record(did: ownerDid, collection: "at.skej.team.brandGrant", rkey: "grant-app-creators"),
        ],
        createdAt: nowString,
        updatedAt: nowString
    )
    try await services.pdsClient.writeRecord(did: ownerDid, collection: "at.skej.team.group", rkey: creatorsGroupRkey, record: creators)

    for brandDid in [ownerDid, studioDid, appDid] {
        let brand = SkejBrandRecord(
            teamUri: teamUri,
            ownerAdminDid: ownerDid,
            brandDid: brandDid,
            status: .active,
            createdAt: nowString,
            updatedAt: nowString
        )
        try await services.pdsClient.writeRecord(did: brandDid, collection: "at.skej.brand", rkey: demoRkey(for: brandDid), record: brand)
    }

    try await seedSchedule(
        did: ownerDid,
        rkey: "demo-any-published-recap",
        title: "Launch Recap",
        text: "Yesterday's launch recap is ready for the team archive.",
        status: .published,
        scheduledAt: iso(daysFromNow: -5, hour: 10, from: now),
        teamUri: teamUri,
        createdByDid: userDid,
        approvedByDid: ownerDid,
        services: services
    )
    try await seedSchedule(
        did: ownerDid,
        rkey: "demo-any-canceled-social",
        title: "Canceled Partner Teaser",
        text: "Holding this teaser until partner copy is approved.",
        status: .canceled,
        scheduledAt: iso(daysFromNow: -2, hour: 14, from: now),
        teamUri: teamUri,
        createdByDid: producerDid,
        approvedByDid: adminDid,
        services: services
    )
    try await seedSchedule(
        did: ownerDid,
        rkey: "demo-any-draft-approval",
        title: "Draft Waiting For Approval",
        text: "Proposed copy from the creator group for tomorrow's product update.",
        status: .draft,
        scheduledAt: iso(daysFromNow: 1, hour: 9, from: now),
        teamUri: teamUri,
        createdByDid: userDid,
        approvedByDid: nil,
        services: services
    )
    try await seedSchedule(
        did: ownerDid,
        rkey: "demo-any-scheduled-roadmap",
        title: "Roadmap Reminder",
        text: "A quick reminder that the public roadmap walk-through starts this afternoon.",
        status: .scheduled,
        scheduledAt: iso(daysFromNow: 2, hour: 13, from: now),
        teamUri: teamUri,
        createdByDid: adminDid,
        approvedByDid: ownerDid,
        services: services
    )
    try await seedSchedule(
        did: ownerDid,
        rkey: "demo-any-failed-media",
        title: "Failed Media Post",
        text: "This post failed because one of the linked assets needs attention.",
        status: .failed,
        scheduledAt: iso(daysFromNow: -1, hour: 16, from: now),
        teamUri: teamUri,
        createdByDid: producerDid,
        approvedByDid: ownerDid,
        lastError: ScheduleError(code: .recordInvalid, message: "Image alt text is missing."),
        services: services
    )
    try await seedSchedule(
        did: ownerDid,
        rkey: "demo-any-blocked-reply",
        title: "Blocked Follow-Up",
        text: "Follow-up post that waits until the parent campaign post is available.",
        status: .blocked,
        scheduledAt: iso(daysFromNow: 3, hour: 11, from: now),
        teamUri: teamUri,
        createdByDid: userDid,
        approvedByDid: adminDid,
        lastError: ScheduleError(code: .parentUnavailable, message: "Parent post is not published yet."),
        dependency: ScheduleDependency(dependsOnScheduleUri: ATURI.schedule(did: ownerDid, rkey: "demo-any-scheduled-roadmap")),
        services: services
    )
    try await seedSchedule(
        did: studioDid,
        rkey: "demo-studio-scheduled",
        title: "Studio Case Study",
        text: "New case study: how teams coordinate ATmosphere posts across brand accounts.",
        status: .scheduled,
        scheduledAt: iso(daysFromNow: 4, hour: 15, from: now),
        teamUri: teamUri,
        createdByDid: adminDid,
        approvedByDid: ownerDid,
        services: services
    )
    try await seedSchedule(
        did: appDid,
        rkey: "demo-app-published",
        title: "App Changelog",
        text: "This week's app changelog is live with calendar and approval workflow updates.",
        status: .published,
        scheduledAt: iso(daysFromNow: -7, hour: 12, from: now),
        teamUri: teamUri,
        createdByDid: producerDid,
        approvedByDid: adminDid,
        services: services
    )

    try await services.store.insertAuditEvent(did: ownerDid, scheduleRkey: nil, action: "demo_seeded", message: "Loaded demo team, brand, and schedule data.", now: nowString)
    try await services.store.insertAuditEvent(did: studioDid, scheduleRkey: nil, action: "demo_seeded", message: "Loaded demo brand schedule data.", now: nowString)
    try await services.store.insertAuditEvent(did: appDid, scheduleRkey: nil, action: "demo_seeded", message: "Loaded demo brand schedule data.", now: nowString)
}

private func seedSchedule(
    did: String,
    rkey: String,
    title: String,
    text: String,
    status: ScheduleStatus,
    scheduledAt: String,
    teamUri: String,
    createdByDid: String,
    approvedByDid: String?,
    lastError: ScheduleError? = nil,
    dependency: ScheduleDependency? = nil,
    services: SkejServices
) async throws {
    let now = Timestamp.iso8601()
    let publishRkey = "publish-\(rkey)"
    let publishedUri = status == .published ? ATURI.published(did: did, recordType: "app.bsky.feed.post", publishRkey: publishRkey) : nil
    let record = SkejScheduleRecord(
        scheduledAt: scheduledAt,
        title: title,
        teamUri: teamUri,
        createdByDid: createdByDid,
        approvedByDid: approvedByDid,
        approvedAt: approvedByDid == nil ? nil : now,
        timezonePolicy: .userLocal,
        userTimezone: "America/Chicago",
        createdAt: iso(daysFromNow: -10),
        updatedAt: now,
        status: status,
        recordType: "app.bsky.feed.post",
        publishRkey: publishRkey,
        publishedUri: publishedUri,
        publishedCid: publishedUri == nil ? nil : "bafy\(publishRkey)",
        retry: RetryState(
            attemptCount: status == .failed ? 3 : 0,
            lastAttemptAt: status == .failed ? scheduledAt : nil,
            nextAttemptAt: status == .failed ? iso(daysFromNow: 0, hour: 18) : nil,
            maxAttempts: 8
        ),
        lastError: lastError,
        dependency: dependency,
        posts: [PostPlan(text: text, langs: ["en"], tags: ["skej", "demo"])]
    )
    try await services.pdsClient.writeSchedule(did: did, rkey: rkey, record: record)
    try await services.store.upsertScheduleJob(job(did: did, rkey: rkey, record: record, attempts: status == .failed ? 3 : 0), now: now)
}

private func demoRkey(for did: String) -> String {
    did.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: ".", with: "_")
}

private func iso(daysFromNow days: Int, hour: Int? = nil, from date: Date = Date()) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
    var target = calendar.date(byAdding: .day, value: days, to: date) ?? date
    if let hour {
        var components = calendar.dateComponents([.year, .month, .day], from: target)
        components.hour = hour
        components.minute = 0
        components.second = 0
        target = calendar.date(from: components) ?? target
    }
    return Timestamp.iso8601(target)
}

private func listSchedules(did: String, services: SkejServices) async throws -> Response {
    let jobs = try await services.store.listScheduleJobs(did: did)
    let pdsRecords = try await services.pdsClient.listSchedules(did: did)
    let records = jobs.compactMap { job -> ScheduledPostSummary? in
        if let record = pdsRecords[job.rkey] {
            return summary(job: job, record: record)
        }
        guard job.status == .failed else { return nil }
        return summary(job: job, record: failedFallbackRecord(job: job))
    }
    return try jsonResponse(ListSchedulesResponse(records: records))
}

private func createSchedule(did: String, body: CreateScheduleRequest, viewer: Viewer, services: SkejServices) async throws -> Response {
    var record = body.record
    try validate(record: record)
    let now = Timestamp.iso8601()
    let rkey = newRkey()
    let permission = try await requireBrandCapability(record.status == .draft ? .create : .approve, brandDid: did, viewer: viewer, services: services)
    record.publishRkey = record.publishRkey.isEmpty ? ULID.generate() : record.publishRkey
    record.status = record.status == .draft ? .draft : .scheduled
    record.teamUri = record.teamUri ?? permission?.teamUri
    record.createdByDid = record.createdByDid ?? viewer.did
    if record.status == .scheduled {
        record.approvedByDid = record.approvedByDid ?? viewer.did
        record.approvedAt = record.approvedAt ?? now
    }
    record.updatedAt = now
    try await services.pdsClient.writeSchedule(did: did, rkey: rkey, record: record)
    let job = job(did: did, rkey: rkey, record: record)
    try await services.store.upsertScheduleJob(job, now: now)
    try await services.store.insertAuditEvent(
        did: did,
        scheduleRkey: rkey,
        action: "schedule_created",
        message: record.status == .draft ? "Draft proposed for \(record.scheduledAt)." : "Schedule created for \(record.scheduledAt).",
        now: now
    )
    return try jsonResponse(summary(job: job, record: record), status: .created)
}

private func updateSchedule(did: String, rkey: String, body: CreateScheduleRequest, viewer: Viewer, services: SkejServices) async throws -> Response {
    let existing = try await services.store.scheduleJob(did: did, rkey: rkey)
    guard existing != nil else {
        throw APIError(status: .notFound, code: "not_found", message: "Schedule not found")
    }
    var record = body.record
    try validate(record: record)
    let now = Timestamp.iso8601()
    let existingRecord = try await services.pdsClient.getSchedule(did: did, rkey: rkey)
    if record.status == .scheduled, existingRecord?.status == .draft {
        let permission = try await requireBrandCapability(.approve, brandDid: did, viewer: viewer, services: services)
        record.teamUri = record.teamUri ?? existingRecord?.teamUri ?? permission?.teamUri
        record.approvedByDid = viewer.did
        record.approvedAt = now
    } else {
        _ = try await requireBrandCapability(record.status == .draft ? .create : .approve, brandDid: did, viewer: viewer, services: services)
    }
    record.createdByDid = record.createdByDid ?? existingRecord?.createdByDid ?? viewer.did
    record.publishRkey = record.publishRkey.isEmpty ? (existing?.publishRkey ?? ULID.generate()) : record.publishRkey
    record.updatedAt = now
    try await services.pdsClient.writeSchedule(did: did, rkey: rkey, record: record)
    let updated = job(did: did, rkey: rkey, record: record, attempts: existing?.attempts ?? 0)
    try await services.store.upsertScheduleJob(updated, now: now)
    try await services.store.insertAuditEvent(
        did: did,
        scheduleRkey: rkey,
        action: "schedule_edited",
        message: "Schedule edited.",
        now: now
    )
    return try jsonResponse(summary(job: updated, record: record))
}

private func cancelSchedule(did: String, rkey: String, services: SkejServices) async throws -> Response {
    guard var record = try await services.pdsClient.getSchedule(did: did, rkey: rkey),
          let existing = try await services.store.scheduleJob(did: did, rkey: rkey)
    else {
        throw APIError(status: .notFound, code: "not_found", message: "Schedule not found")
    }
    let now = Timestamp.iso8601()
    record.status = .canceled
    record.updatedAt = now
    try await services.pdsClient.writeSchedule(did: did, rkey: rkey, record: record)
    var updated = existing
    updated.status = .canceled
    try await services.store.upsertScheduleJob(updated, now: now)
    try await services.store.insertAuditEvent(
        did: did,
        scheduleRkey: rkey,
        action: "schedule_canceled",
        message: "Schedule canceled.",
        now: now
    )
    return try jsonResponse(summary(job: updated, record: record))
}

private func retrySchedule(did: String, rkey: String, services: SkejServices) async throws -> Response {
    guard var record = try await services.pdsClient.getSchedule(did: did, rkey: rkey),
          var existing = try await services.store.scheduleJob(did: did, rkey: rkey)
    else {
        throw APIError(status: .notFound, code: "not_found", message: "Schedule not found")
    }
    let now = Timestamp.iso8601()
    record.status = .scheduled
    record.lastError = nil
    record.retry.nextAttemptAt = nil
    record.updatedAt = now
    existing.status = .scheduled
    existing.lastError = nil
    existing.nextAttemptAt = nil
    try await services.pdsClient.writeSchedule(did: did, rkey: rkey, record: record)
    try await services.store.upsertScheduleJob(existing, now: now)
    try await services.store.insertAuditEvent(
        did: did,
        scheduleRkey: rkey,
        action: "retry_requested",
        message: "Manual retry requested.",
        now: now
    )
    return try jsonResponse(summary(job: existing, record: record))
}

private func duplicateSchedule(did: String, rkey: String, services: SkejServices) async throws -> Response {
    guard var record = try await services.pdsClient.getSchedule(did: did, rkey: rkey) else {
        throw APIError(status: .notFound, code: "not_found", message: "Schedule not found")
    }
    let now = Timestamp.iso8601()
    let newRkey = newRkey()
    record.status = .draft
    record.publishRkey = ULID.generate()
    record.publishedUri = nil
    record.publishedCid = nil
    record.lastError = nil
    record.retry = RetryState()
    record.createdAt = now
    record.updatedAt = now
    try await services.pdsClient.writeSchedule(did: did, rkey: newRkey, record: record)
    let newJob = job(did: did, rkey: newRkey, record: record)
    try await services.store.upsertScheduleJob(newJob, now: now)
    try await services.store.insertAuditEvent(
        did: did,
        scheduleRkey: newRkey,
        action: "schedule_duplicated",
        message: "Duplicated from \(rkey).",
        now: now
    )
    return try jsonResponse(summary(job: newJob, record: record), status: .created)
}

private func publishNow(did: String, rkey: String, services: SkejServices) async throws -> Response {
    guard var record = try await services.pdsClient.getSchedule(did: did, rkey: rkey),
          var existing = try await services.store.scheduleJob(did: did, rkey: rkey)
    else {
        throw APIError(status: .notFound, code: "not_found", message: "Schedule not found")
    }
    let now = Timestamp.iso8601()
    record.status = .publishing
    record.updatedAt = now
    try await services.pdsClient.writeSchedule(did: did, rkey: rkey, record: record)
    let published = try await services.pdsClient.publishThread(did: did, record: record)
    record.status = .published
    record.publishedUri = published.uri
    record.publishedCid = published.cid
    record.updatedAt = now
    try await services.pdsClient.writeSchedule(did: did, rkey: rkey, record: record)
    try await services.store.markJobPublished(did: did, rkey: rkey, published: published, now: now)
    existing.status = .published
    existing.publishedUri = published.uri
    existing.publishedCid = published.cid
    try await services.store.insertAuditEvent(
        did: did,
        scheduleRkey: rkey,
        action: "publish_now_succeeded",
        message: "Published \(published.uri).",
        now: now
    )
    return try jsonResponse(summary(job: existing, record: record))
}

private struct BrandPermissionContext {
    let teamUri: String?
    let capabilities: Set<BrandCapability>
}

private func listVisibleTeams(viewer: Viewer, services: SkejServices) async throws -> [TeamSummary] {
    let accounts = try await services.store.listManagedAccounts()
    var ownerDids = Set(accounts.map(\.did))
    ownerDids.insert(viewer.did)
    var summaries: [TeamSummary] = []
    for ownerDid in ownerDids {
        let records = try await services.pdsClient.listRecords(did: ownerDid, collection: "at.skej.team", as: SkejTeamRecord.self)
        let ownerTeams = records.map { rkey, record in
            TeamSummary(
                rkey: rkey,
                uri: ATURI.record(did: ownerDid, collection: "at.skej.team", rkey: rkey),
                record: record
            )
        }
        for team in ownerTeams {
            if team.record.ownerAdminDid == viewer.did {
                summaries.append(team)
                continue
            }
            if try await activeMember(team: team, memberDid: viewer.did, services: services) != nil {
                summaries.append(team)
            }
        }
    }
    return summaries.sorted { $0.record.title < $1.record.title }
}

private func requireVisibleTeam(rkey: String, viewer: Viewer, services: SkejServices) async throws -> TeamSummary {
    guard let team = try await listVisibleTeams(viewer: viewer, services: services).first(where: { $0.rkey == rkey }) else {
        throw APIError(status: .notFound, code: "not_found", message: "Team not found")
    }
    return team
}

private func requireOwnedTeam(rkey: String, viewer: Viewer, services: SkejServices) async throws -> TeamSummary {
    let team = try await requireVisibleTeam(rkey: rkey, viewer: viewer, services: services)
    guard team.record.ownerAdminDid == viewer.did else {
        throw APIError(status: .forbidden, code: "forbidden", message: "Only the owning admin can do that")
    }
    return team
}

private func requireTeamAdmin(rkey: String, viewer: Viewer, services: SkejServices) async throws -> TeamSummary {
    let team = try await requireVisibleTeam(rkey: rkey, viewer: viewer, services: services)
    if team.record.ownerAdminDid == viewer.did { return team }
    guard let member = try await activeMember(team: team, memberDid: viewer.did, services: services),
          member.record.role == .admin
    else {
        throw APIError(status: .forbidden, code: "forbidden", message: "Team admin access required")
    }
    return team
}

private func listTeamMembers(team: TeamSummary, services: SkejServices) async throws -> [TeamMemberSummary] {
    let ownerDid = teamOwnerDid(team.uri)
    return try await services.pdsClient
        .listRecords(did: ownerDid, collection: "at.skej.team.member", as: TeamMemberRecord.self)
        .filter { $0.value.teamUri == team.uri }
        .map { TeamMemberSummary(rkey: $0.key, uri: ATURI.record(did: ownerDid, collection: "at.skej.team.member", rkey: $0.key), record: $0.value) }
}

private func listTeamGroups(team: TeamSummary, services: SkejServices) async throws -> [TeamGroupSummary] {
    let ownerDid = teamOwnerDid(team.uri)
    return try await services.pdsClient
        .listRecords(did: ownerDid, collection: "at.skej.team.group", as: TeamGroupRecord.self)
        .filter { $0.value.teamUri == team.uri }
        .map { TeamGroupSummary(rkey: $0.key, uri: ATURI.record(did: ownerDid, collection: "at.skej.team.group", rkey: $0.key), record: $0.value) }
}

private func listBrandGrants(team: TeamSummary, services: SkejServices) async throws -> [BrandGrantSummary] {
    let ownerDid = teamOwnerDid(team.uri)
    return try await services.pdsClient
        .listRecords(did: ownerDid, collection: "at.skej.team.brandGrant", as: BrandGrantRecord.self)
        .filter { $0.value.teamUri == team.uri }
        .map { BrandGrantSummary(rkey: $0.key, uri: ATURI.record(did: ownerDid, collection: "at.skej.team.brandGrant", rkey: $0.key), record: $0.value) }
}

private func listBrands(team: TeamSummary, services: SkejServices) async throws -> [BrandSummary] {
    let grants = try await listBrandGrants(team: team, services: services)
    var brandDids = Set(grants.map(\.record.brandDid))
    brandDids.insert(team.record.ownerAdminDid)
    var brands: [BrandSummary] = []
    for brandDid in brandDids {
        let records = try await services.pdsClient.listRecords(did: brandDid, collection: "at.skej.brand", as: SkejBrandRecord.self)
        brands.append(contentsOf: records.compactMap { rkey, record in
            guard record.teamUri == team.uri else { return nil }
            return BrandSummary(rkey: rkey, uri: ATURI.record(did: brandDid, collection: "at.skej.brand", rkey: rkey), record: record)
        })
    }
    return brands
}

private func activeMember(team: TeamSummary, memberDid: String, services: SkejServices) async throws -> TeamMemberSummary? {
    try await listTeamMembers(team: team, services: services).first {
        $0.record.memberDid == memberDid && $0.record.status == .active
    }
}

@discardableResult
private func requireAnyBrandCapability(
    _ capabilities: Set<BrandCapability>,
    brandDid: String,
    viewer: Viewer,
    services: SkejServices
) async throws -> BrandPermissionContext? {
    for capability in capabilities {
        if let context = try await brandPermissionContext(brandDid: brandDid, viewer: viewer, services: services),
           context.capabilities.contains(capability) {
            return context
        }
    }
    if try await brandPermissionContext(brandDid: brandDid, viewer: viewer, services: services) == nil,
       viewer.did == brandDid {
        return BrandPermissionContext(teamUri: nil, capabilities: Set(BrandCapability.allCases))
    }
    throw APIError(status: .forbidden, code: "forbidden", message: "You do not have permission for this brand")
}

@discardableResult
private func requireBrandCapability(
    _ capability: BrandCapability,
    brandDid: String,
    viewer: Viewer,
    services: SkejServices
) async throws -> BrandPermissionContext? {
    try await requireAnyBrandCapability([capability], brandDid: brandDid, viewer: viewer, services: services)
}

private func brandPermissionContext(brandDid: String, viewer: Viewer, services: SkejServices) async throws -> BrandPermissionContext? {
    let teams = try await listVisibleTeams(viewer: viewer, services: services)
    for team in teams {
        let grants = try await listBrandGrants(team: team, services: services).filter { $0.record.brandDid == brandDid }
        guard !grants.isEmpty else { continue }
        let member = try await activeMember(team: team, memberDid: viewer.did, services: services)
        let groups = try await listTeamGroups(team: team, services: services)
        let memberGroupUris = Set(member?.record.groupUris ?? [])
        let matchingGroupUris = Set(groups.filter { group in
            group.record.memberDids.contains(viewer.did) || memberGroupUris.contains(group.uri)
        }.map(\.uri))
        var capabilities = Set<BrandCapability>()
        for grant in grants {
            let appliesDirectly = grant.record.granteeType == .member && grant.record.grantee == viewer.did
            let appliesThroughGroup = grant.record.granteeType == .group && matchingGroupUris.contains(grant.record.grantee)
            if appliesDirectly || appliesThroughGroup {
                capabilities.formUnion(grant.record.capabilities)
            }
        }
        if !capabilities.isEmpty {
            return BrandPermissionContext(teamUri: team.uri, capabilities: capabilities)
        }
    }
    return nil
}

private func teamOwnerDid(_ teamUri: String) -> String {
    guard teamUri.starts(with: "at://") else { return "" }
    let remainder = teamUri.dropFirst("at://".count)
    return remainder.split(separator: "/").first.map(String.init) ?? ""
}

private func validate(team: SkejTeamRecord) throws {
    guard !team.title.isEmpty else {
        throw APIError(status: .badRequest, code: "invalid_team", message: "Team title is required")
    }
    guard team.ownerAdminDid.starts(with: "did:") else {
        throw APIError(status: .badRequest, code: "invalid_owner", message: "Owner admin DID is invalid")
    }
}

private func authenticate(_ request: Request, services: SkejServices) async throws -> Viewer {
    if services.config.environment != .prod,
       let did = request.headers[HTTPField.Name("X-Skej-DID")!],
       !did.isEmpty
    {
        let handle = request.headers[HTTPField.Name("X-Skej-Handle")!] ?? "local.skej.at"
        let viewer = Viewer(did: did, handle: handle, displayName: handle, avatar: nil)
        try await services.store.upsertManagedAccount(
            ManagedAccount(
                did: did,
                handle: handle,
                displayName: handle,
                avatar: nil,
                pdsEndpoint: "local",
                status: .active,
                isDefault: true
            ),
            now: Timestamp.iso8601()
        )
        return viewer
    }
    if let sessionID = cookie(named: "skej_session", in: request.headers[.cookie] ?? ""),
       let viewer = try await services.store.viewer(forSessionID: sessionID, now: Timestamp.iso8601())
    {
        return viewer
    }
    throw APIError(status: .unauthorized, code: "unauthorized", message: "Sign in required")
}

private func authorize(did: String, request: Request, services: SkejServices) async throws -> Viewer {
    let viewer = try await authenticate(request, services: services)
    guard services.config.environment != .prod || viewer.did == did || viewer.defaultAccountDid == did else {
        throw APIError(status: .forbidden, code: "forbidden", message: "Account is not available in this session")
    }
    return viewer
}

private func cookie(named name: String, in header: String) -> String? {
    header.split(separator: ";").compactMap { part -> (String, String)? in
        let pieces = part.split(separator: "=", maxSplits: 1)
        guard pieces.count == 2 else { return nil }
        return (
            pieces[0].trimmingCharacters(in: .whitespacesAndNewlines),
            pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }.first { $0.0 == name }?.1
}

private func validate(record: SkejScheduleRecord) throws {
    guard record.type == "at.skej.schedule" else {
        throw APIError(status: .badRequest, code: "invalid_type", message: "Expected at.skej.schedule")
    }
    guard !record.posts.isEmpty || record.shadowRecord != nil else {
        throw APIError(status: .badRequest, code: "empty_record", message: "Add a post or shadow record")
    }
    guard Timestamp.date(from: record.scheduledAt) != nil else {
        throw APIError(status: .badRequest, code: "invalid_schedule", message: "Invalid scheduledAt")
    }
    if let title = record.title, title.count > 120 {
        throw APIError(status: .badRequest, code: "invalid_title", message: "Title must be 120 characters or fewer")
    }
    guard !record.publishRkey.isEmpty else {
        throw APIError(status: .badRequest, code: "missing_publish_rkey", message: "publishRkey is required")
    }
}

private func job(did: String, rkey: String, record: SkejScheduleRecord, attempts: Int = 0) -> ScheduledJob {
    ScheduledJob(
        did: did,
        rkey: rkey,
        scheduledAt: record.scheduledAt,
        status: record.status,
        attempts: attempts,
        lastError: record.lastError,
        nextAttemptAt: record.retry.nextAttemptAt,
        lastAttemptAt: record.retry.lastAttemptAt,
        publishRkey: record.publishRkey,
        recordType: record.recordType,
        publishedUri: record.publishedUri,
        publishedCid: record.publishedCid,
        dependsOnScheduleUri: record.dependency?.dependsOnScheduleUri,
        parentPublishedUri: record.dependency?.parentPublishedUri
    )
}

private func summary(job: ScheduledJob, record: SkejScheduleRecord) -> ScheduledPostSummary {
    ScheduledPostSummary(
        rkey: job.rkey,
        did: job.did,
        scheduleUri: ATURI.schedule(did: job.did, rkey: job.rkey),
        scheduledAt: job.scheduledAt,
        status: job.status,
        record: record,
        attempts: job.attempts,
        lastError: job.lastError,
        nextAttemptAt: job.nextAttemptAt,
        publishedUri: job.publishedUri ?? record.publishedUri,
        publishedCid: job.publishedCid ?? record.publishedCid
    )
}

private func failedFallbackRecord(job: ScheduledJob) -> SkejScheduleRecord {
    SkejScheduleRecord(
        scheduledAt: job.scheduledAt,
        createdAt: job.scheduledAt,
        updatedAt: Timestamp.iso8601(),
        status: .failed,
        publishRkey: job.publishRkey,
        lastError: job.lastError,
        posts: [
            PostPlan(
                text: job.lastError?.message ?? "Failed schedule record could not be loaded from the PDS.",
                langs: ["en"]
            ),
        ]
    )
}

private func newRkey() -> String {
    "3l\(UInt64(Date().timeIntervalSince1970 * 1000).toString36())\(UInt32.random(in: 0...9999).toString36())"
}

private func randomToken() -> String {
    let bytes = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    return bytes.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private extension FixedWidthInteger {
    func toString36() -> String {
        String(Int64(self), radix: 36)
    }
}

private extension Response {
    func withHeaders(_ fields: HTTPFields) -> Response {
        var copy = self
        for field in fields {
            copy.headers[field.name] = field.value
        }
        return copy
    }
}
