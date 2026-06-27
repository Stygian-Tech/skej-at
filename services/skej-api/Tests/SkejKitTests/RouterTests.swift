import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import SkejKit
import Testing

@Suite
struct RouterTests {
    @Test func healthReturnsOK() async throws {
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            try await client.execute(uri: "/health", method: .get) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body).contains("skej-api"))
            }
        }
    }

    @Test func schedulesRequireAuth() async throws {
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/schedules", method: .get) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test func createAndListSchedule() async throws {
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))
        let body = try encodedBody(CreateScheduleRequest(record: makeRecord()))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/v1/schedules",
                method: .post,
                headers: didHeaders("did:plc:test"),
                body: body
            ) { response in
                #expect(response.status == .created)
                #expect(String(buffer: response.body).contains("at.skej.schedule"))
            }

            try await client.execute(
                uri: "/v1/schedules",
                method: .get,
                headers: didHeaders("did:plc:test")
            ) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body).contains("hello from skej"))
            }
        }
    }

    @Test func createScheduleAcceptsBrowserISODate() async throws {
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))
        let body = try encodedBody(CreateScheduleRequest(
            record: makeRecord(scheduledFor: "2099-01-01T11:00:00.000Z")
        ))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/v1/schedules",
                method: .post,
                headers: didHeaders("did:plc:test"),
                body: body
            ) { response in
                #expect(response.status == .created)
            }
        }
    }

    @Test func oauthMetadataUsesSkejOrigin() async throws {
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let services = SkejServices(
            config: AppConfig(
                port: 8080,
                environment: .dev,
                publicOrigin: "https://api.testing.skej.at",
                webOrigin: "https://testing.skej.at",
                sqlitePath: ":memory:",
                workerEnabled: false
            ),
            store: store,
            pdsClient: InMemoryPDSClient(),
            oauthClient: LocalOAuthClient()
        )
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            try await client.execute(uri: "/oauth/client-metadata.json", method: .get) { response in
                #expect(response.status == .ok)
                let metadata = try JSONDecoder().decode(
                    OAuthMetadataResponse.self,
                    from: Data(String(buffer: response.body).utf8)
                )
                #expect(metadata.clientID == "https://api.testing.skej.at/oauth/client-metadata.json")
                #expect(metadata.clientURI == "https://api.testing.skej.at")
                #expect(metadata.redirectURIs == ["https://testing.skej.at/oauth/callback"])
                let body = String(buffer: response.body)
                #expect(body.contains("transition:generic"))
                #expect(body.contains("\"token_endpoint_auth_method\":\"none\""))
            }
        }
    }

    @Test func oauthStartAndCallbackCreateSessionForHandle() async throws {
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            var callback = ""
            try await client.execute(uri: "/oauth/start?handle=alex.skej.at", method: .get) { response in
                #expect(response.status == .found)
                callback = response.headers[.location] ?? ""
                #expect(callback.starts(with: "/oauth/callback?state="))
            }

            var cookie = ""
            try await client.execute(uri: callback, method: .get) { response in
                #expect(response.status == .found)
                #expect(response.headers[.location] == "/app")
                cookie = response.headers[HTTPField.Name("Set-Cookie")!] ?? ""
                #expect(cookie.contains("skej_session="))
            }

            var headers = HTTPFields()
            headers[.cookie] = cookie.split(separator: ";").first.map(String.init) ?? ""
            try await client.execute(uri: "/v1/me", method: .get, headers: headers) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body).contains("alex.skej.at"))
            }

            try await client.execute(uri: "/v1/logout", method: .post, headers: headers) { response in
                #expect(response.status == .ok)
            }

            try await client.execute(uri: "/v1/me", method: .get, headers: headers) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test func oauthCallbackKeepsHostScopedSessionForWebRewrite() async throws {
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let services = SkejServices(
            config: AppConfig(
                port: 8080,
                environment: .dev,
                publicOrigin: "https://api.testing.skej.at",
                webOrigin: "https://testing.skej.at",
                sqlitePath: ":memory:",
                workerEnabled: false
            ),
            store: store,
            pdsClient: InMemoryPDSClient(),
            oauthClient: LocalOAuthClient()
        )
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            var callback = ""
            try await client.execute(uri: "/oauth/start?handle=alex.skej.at", method: .get) { response in
                callback = response.headers[.location] ?? ""
            }

            try await client.execute(uri: callback, method: .get) { response in
                #expect(response.status == .found)
                #expect(response.headers[.location] == "/app")
                let cookie = response.headers[HTTPField.Name("Set-Cookie")!] ?? ""
                #expect(cookie.contains("skej_session="))
                #expect(cookie.contains("Secure"))
                #expect(!cookie.contains("Domain="))
            }
        }
    }

    @Test func failedJobsStayVisibleWhenPDSRecordIsMissing() async throws {
        let services = try await makeTestServices()
        try await services.store.upsertScheduleJob(
            ScheduledJob(
                did: "did:plc:test",
                rkey: "3lmissing",
                scheduledFor: "2026-01-01T11:00:00Z",
                status: .failed,
                attempts: 2,
                lastError: ScheduleError(code: .recordInvalid, message: "PDS rejected scheduled record"),
                publishedUri: nil,
                publishedCid: nil
            ),
            now: "2026-01-01T11:01:00Z"
        )
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/v1/schedules",
                method: .get,
                headers: didHeaders("did:plc:test")
            ) { response in
                #expect(response.status == .ok)
                let body = String(buffer: response.body)
                #expect(body.contains("\"status\":\"failed\""))
                #expect(body.contains("PDS rejected scheduled record"))
            }
        }
    }

    @Test func permissionGrantAllowsDraftAndApprovalFlow() async throws {
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            let team = try await createTeam(client: client, ownerDid: "did:plc:owner")
            let _: TeamMemberSummary = try await postJSON(
                client: client,
                uri: "/v1/teams/\(team.rkey)/members",
                headers: didHeaders("did:plc:owner"),
                body: UpsertMemberRequest(memberDid: "did:plc:user", role: .user, status: .active, groupUris: [])
            )
            let _: BrandGrantSummary = try await postJSON(
                client: client,
                uri: "/v1/teams/\(team.rkey)/brand-grants",
                headers: didHeaders("did:plc:owner"),
                body: UpsertBrandGrantRequest(
                    brandDid: "did:plc:brand",
                    granteeType: .member,
                    grantee: "did:plc:user",
                    capabilities: [.create]
                )
            )
            let _: BrandGrantSummary = try await postJSON(
                client: client,
                uri: "/v1/teams/\(team.rkey)/brand-grants",
                headers: didHeaders("did:plc:owner"),
                body: UpsertBrandGrantRequest(
                    brandDid: "did:plc:brand",
                    granteeType: .member,
                    grantee: "did:plc:owner",
                    capabilities: [.approve, .manage]
                )
            )

            var draft = makeRecord()
            draft.status = .draft
            let created: ScheduledPostSummary = try await postJSON(
                client: client,
                uri: "/v1/accounts/did:plc:brand/schedules",
                headers: didHeaders("did:plc:user"),
                body: CreateScheduleRequest(record: draft)
            )
            #expect(created.status == .draft)
            #expect(created.record.createdByDid == "did:plc:user")

            var scheduled = created.record
            scheduled.status = .scheduled
            let approved: ScheduledPostSummary = try await patchJSON(
                client: client,
                uri: "/v1/accounts/did:plc:brand/schedules/\(created.rkey)",
                headers: didHeaders("did:plc:owner"),
                body: CreateScheduleRequest(record: scheduled)
            )
            #expect(approved.status == .scheduled)
            #expect(approved.record.approvedByDid == "did:plc:owner")
        }
    }

    @Test func adminWithoutBrandGrantCannotApproveOrEditProfile() async throws {
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            let team = try await createTeam(client: client, ownerDid: "did:plc:owner")
            let _: TeamMemberSummary = try await postJSON(
                client: client,
                uri: "/v1/teams/\(team.rkey)/members",
                headers: didHeaders("did:plc:owner"),
                body: UpsertMemberRequest(memberDid: "did:plc:admin", role: .admin, status: .active, groupUris: [])
            )
            let _: BrandGrantSummary = try await postJSON(
                client: client,
                uri: "/v1/teams/\(team.rkey)/brand-grants",
                headers: didHeaders("did:plc:owner"),
                body: UpsertBrandGrantRequest(
                    brandDid: "did:plc:brand",
                    granteeType: .member,
                    grantee: "did:plc:owner",
                    capabilities: [.create]
                )
            )
            var draft = makeRecord()
            draft.status = .draft
            let created: ScheduledPostSummary = try await postJSON(
                client: client,
                uri: "/v1/accounts/did:plc:brand/schedules",
                headers: didHeaders("did:plc:owner"),
                body: CreateScheduleRequest(record: draft)
            )

            var scheduled = created.record
            scheduled.status = .scheduled
            try await client.execute(
                uri: "/v1/accounts/did:plc:brand/schedules/\(created.rkey)",
                method: .patch,
                headers: didHeaders("did:plc:admin"),
                body: try encodedBody(CreateScheduleRequest(record: scheduled))
            ) { response in
                #expect(response.status == .forbidden)
            }

            try await client.execute(
                uri: "/v1/brands/did:plc:brand/profile",
                method: .patch,
                headers: didHeaders("did:plc:admin"),
                body: try encodedBody(UpdateBrandProfileRequest(displayName: "Brand", description: "Nope", avatar: nil))
            ) { response in
                #expect(response.status == .forbidden)
            }
        }
    }

    @Test func manageGrantAllowsBrandProfileEdit() async throws {
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            let team = try await createTeam(client: client, ownerDid: "did:plc:owner")
            let _: BrandGrantSummary = try await postJSON(
                client: client,
                uri: "/v1/teams/\(team.rkey)/brand-grants",
                headers: didHeaders("did:plc:owner"),
                body: UpsertBrandGrantRequest(
                    brandDid: "did:plc:brand",
                    granteeType: .member,
                    grantee: "did:plc:owner",
                    capabilities: [.manage]
                )
            )

            let profile: BrandProfile = try await patchJSON(
                client: client,
                uri: "/v1/brands/did:plc:brand/profile",
                headers: didHeaders("did:plc:owner"),
                body: UpdateBrandProfileRequest(displayName: "Skej Brand", description: "Business account", avatar: nil)
            )
            #expect(profile.displayName == "Skej Brand")
            #expect(profile.description == "Business account")
        }
    }
}

private struct OAuthMetadataResponse: Decodable {
    let clientID: String
    let clientURI: String
    let redirectURIs: [String]

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientURI = "client_uri"
        case redirectURIs = "redirect_uris"
    }
}

private func createTeam(client: some TestClientProtocol, ownerDid: String) async throws -> TeamSummary {
    try await postJSON(
        client: client,
        uri: "/v1/teams",
        headers: didHeaders(ownerDid),
        body: CreateTeamRequest(title: "Launch Team")
    )
}

private func postJSON<RequestBody: Encodable, ResponseBody: Decodable>(
    client: some TestClientProtocol,
    uri: String,
    headers: HTTPFields,
    body: RequestBody
) async throws -> ResponseBody {
    try await executeJSON(client: client, uri: uri, method: .post, headers: headers, body: body)
}

private func patchJSON<RequestBody: Encodable, ResponseBody: Decodable>(
    client: some TestClientProtocol,
    uri: String,
    headers: HTTPFields,
    body: RequestBody
) async throws -> ResponseBody {
    try await executeJSON(client: client, uri: uri, method: .patch, headers: headers, body: body)
}

private func executeJSON<RequestBody: Encodable, ResponseBody: Decodable>(
    client: some TestClientProtocol,
    uri: String,
    method: HTTPRequest.Method,
    headers: HTTPFields,
    body: RequestBody
) async throws -> ResponseBody {
    var decoded: ResponseBody?
    try await client.execute(
        uri: uri,
        method: method,
        headers: headers,
        body: try encodedBody(body)
    ) { response in
        #expect(response.status == .ok || response.status == .created)
        decoded = try JSONDecoder().decode(ResponseBody.self, from: Data(String(buffer: response.body).utf8))
    }
    guard let decoded else {
        throw CancellationError()
    }
    return decoded
}
