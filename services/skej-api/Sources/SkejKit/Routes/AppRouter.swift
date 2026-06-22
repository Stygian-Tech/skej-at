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
        try jsonResponse(OAuthMetadata.webClientMetadata(publicOrigin: services.config.publicOrigin))
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
        let secure = services.config.environment == .prod ? "; Secure" : ""
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
        headers[HTTPField.Name("Set-Cookie")!] =
            "skej_session=deleted; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
        return try jsonResponse(OKResponse(ok: true), status: .ok).withHeaders(headers)
    }

    v1.get("schedules") { request, _ in
        let viewer = try await authenticate(request, services: services)
        let jobs = try await services.store.listScheduleJobs(did: viewer.did)
        let pdsRecords = try await services.pdsClient.listSchedules(did: viewer.did)
        let records = jobs.compactMap { job -> ScheduledPostSummary? in
            if let record = pdsRecords[job.rkey] {
                return summary(job: job, record: record)
            }
            guard job.status == .failed else { return nil }
            return summary(job: job, record: failedFallbackRecord(job: job))
        }
        return try jsonResponse(ListSchedulesResponse(records: records))
    }

    v1.post("schedules") { request, _ in
        let viewer = try await authenticate(request, services: services)
        let body = try await decodeJSONBody(request, as: CreateScheduleRequest.self)
        try validate(record: body.record)
        let rkey = newRkey()
        let now = Timestamp.iso8601()
        try await services.pdsClient.writeSchedule(did: viewer.did, rkey: rkey, record: body.record)
        let job = ScheduledJob(
            did: viewer.did,
            rkey: rkey,
            scheduledFor: body.record.scheduledFor,
            status: .scheduled,
            attempts: 0,
            lastError: nil,
            publishedUri: nil,
            publishedCid: nil
        )
        try await services.store.upsertScheduleJob(job, now: now)
        return try jsonResponse(summary(job: job, record: body.record), status: .created)
    }

    v1.patch("schedules/:rkey") { request, context in
        let viewer = try await authenticate(request, services: services)
        let rkey = try context.parameters.require("rkey")
        let body = try await decodeJSONBody(request, as: CreateScheduleRequest.self)
        try validate(record: body.record)
        let existing = try await services.store.scheduleJob(did: viewer.did, rkey: rkey)
        guard existing != nil else {
            throw APIError(status: .notFound, code: "not_found", message: "Schedule not found")
        }
        try await services.pdsClient.writeSchedule(did: viewer.did, rkey: rkey, record: body.record)
        let job = ScheduledJob(
            did: viewer.did,
            rkey: rkey,
            scheduledFor: body.record.scheduledFor,
            status: .scheduled,
            attempts: existing?.attempts ?? 0,
            lastError: nil,
            publishedUri: nil,
            publishedCid: nil
        )
        try await services.store.upsertScheduleJob(job, now: Timestamp.iso8601())
        return try jsonResponse(summary(job: job, record: body.record))
    }

    v1.delete("schedules/:rkey") { request, context in
        let viewer = try await authenticate(request, services: services)
        let rkey = try context.parameters.require("rkey")
        try await services.pdsClient.deleteSchedule(did: viewer.did, rkey: rkey)
        try await services.store.deleteScheduleJob(did: viewer.did, rkey: rkey)
        return try jsonResponse(OKResponse(ok: true))
    }

    v1.post("schedules/:rkey/publish-now") { request, context in
        let viewer = try await authenticate(request, services: services)
        let rkey = try context.parameters.require("rkey")
        guard let record = try await services.pdsClient.getSchedule(did: viewer.did, rkey: rkey),
              let job = try await services.store.scheduleJob(did: viewer.did, rkey: rkey)
        else {
            throw APIError(status: .notFound, code: "not_found", message: "Schedule not found")
        }
        let published = try await services.pdsClient.publishThread(did: viewer.did, record: record)
        try await services.pdsClient.deleteSchedule(did: viewer.did, rkey: rkey)
        try await services.store.markJobPublished(
            did: viewer.did,
            rkey: rkey,
            published: published,
            now: Timestamp.iso8601()
        )
        var updated = job
        updated.status = .published
        updated.publishedUri = published.uri
        updated.publishedCid = published.cid
        return try jsonResponse(summary(job: updated, record: record))
    }

    return router
}

private func authenticate(_ request: Request, services: SkejServices) async throws -> Viewer {
    if services.config.environment != .prod,
       let did = request.headers[HTTPField.Name("X-Skej-DID")!],
       !did.isEmpty
    {
        return Viewer(did: did, handle: "local.skej.at", displayName: "Local", avatar: nil)
    }
    if let sessionID = cookie(named: "skej_session", in: request.headers[.cookie] ?? ""),
       let viewer = try await services.store.viewer(forSessionID: sessionID, now: Timestamp.iso8601())
    {
        return viewer
    }
    throw APIError(status: .unauthorized, code: "unauthorized", message: "Sign in required")
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
    guard !record.posts.isEmpty else {
        throw APIError(status: .badRequest, code: "empty_posts", message: "Add at least one post")
    }
    guard Timestamp.date(from: record.scheduledFor) != nil else {
        throw APIError(status: .badRequest, code: "invalid_schedule", message: "Invalid scheduledFor")
    }
}

private func summary(job: ScheduledJob, record: SkejScheduleRecord) -> ScheduledPostSummary {
    ScheduledPostSummary(
        rkey: job.rkey,
        did: job.did,
        scheduledFor: job.scheduledFor,
        status: job.status,
        record: record,
        attempts: job.attempts,
        lastError: job.lastError,
        publishedUri: job.publishedUri,
        publishedCid: job.publishedCid
    )
}

private func failedFallbackRecord(job: ScheduledJob) -> SkejScheduleRecord {
    SkejScheduleRecord(
        type: "at.skej.schedule",
        scheduledFor: job.scheduledFor,
        createdAt: job.scheduledFor,
        updatedAt: Timestamp.iso8601(),
        status: .failed,
        lastError: job.lastError,
        posts: [
            PostPlan(
                text: job.lastError ?? "Failed schedule record could not be loaded from the PDS.",
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
