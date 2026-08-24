import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import SkejGateway
import SkejKit
import Testing

@Suite
struct ProFeatureGateTests {
    struct CapturedResponse: Equatable {
        let status: HTTPResponse.Status
        let body: String
        let contentType: String?
    }

    private func capture(
        _ client: some TestClientProtocol,
        uri: String,
        method: HTTPRequest.Method,
        headers: HTTPFields = .init(),
        body: ByteBuffer? = nil
    ) async throws -> CapturedResponse {
        try await client.execute(uri: uri, method: method, headers: headers, body: body) { response in
            CapturedResponse(
                status: response.status,
                body: String(buffer: response.body),
                contentType: response.headers[.contentType]
            )
        }
    }

    @Test func gatedRoutesAreIndistinguishableFromUnknownRoutes() async throws {
        let services = try await makeTestServices(proFeaturesEnabled: false)
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            let unknownGet = try await capture(client, uri: "/v1/definitely-not-a-route", method: .get, headers: didHeaders("did:plc:me"))
            let unknownPost = try await capture(client, uri: "/v1/definitely-not-a-route", method: .post, headers: didHeaders("did:plc:me"))
            #expect(unknownGet.status == .notFound)

            for uri in ["/v1/teams", "/v1/teams/abc/members", "/v1/brands/did:plc:me/profile"] {
                let gated = try await capture(client, uri: uri, method: .get, headers: didHeaders("did:plc:me"))
                #expect(gated == unknownGet, "GET \(uri) should match the unknown-route response")
            }
            let gatedPost = try await capture(
                client,
                uri: "/v1/teams",
                method: .post,
                headers: didHeaders("did:plc:me"),
                body: try encodedBody(["title": "Team"])
            )
            #expect(gatedPost == unknownPost)

            let seed = try await capture(client, uri: "/v1/dev/seed", method: .post, headers: didHeaders("did:plc:me"))
            #expect(seed == unknownPost)

            let unknownXRPC = try await capture(client, uri: "/xrpc/at.skej.unknown.method", method: .get, headers: didHeaders("did:plc:me"))
            let gatedXRPC = try await capture(client, uri: "/xrpc/at.skej.team.list", method: .get, headers: didHeaders("did:plc:me"))
            #expect(gatedXRPC == unknownXRPC)
        }
    }

    @Test func otherAccountsAreIndistinguishableFromUnknownRoutes() async throws {
        let services = try await makeTestServices(proFeaturesEnabled: false)
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            let unknown = try await capture(client, uri: "/v1/definitely-not-a-route", method: .get, headers: didHeaders("did:plc:me"))
            let otherAccount = try await capture(client, uri: "/v1/accounts/did:plc:other/schedules", method: .get, headers: didHeaders("did:plc:me"))
            #expect(otherAccount == unknown)

            let selfAccount = try await capture(client, uri: "/v1/accounts/did:plc:me/schedules", method: .get, headers: didHeaders("did:plc:me"))
            #expect(selfAccount.status == .ok)
        }
    }

    @Test func accountListOnlyContainsSelfWhenProIsOff() async throws {
        let services = try await makeTestServices(proFeaturesEnabled: false)
        let brandAccount = try JSONDecoder().decode(
            ManagedAccount.self,
            from: Data(
                #"{"did":"did:plc:brand","handle":"brand.example.com","status":"active","isDefault":false}"#.utf8
            )
        )
        try await services.store.upsertManagedAccount(brandAccount, now: "2026-01-01T10:00:00Z")
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            let response = try await capture(client, uri: "/v1/accounts", method: .get, headers: didHeaders("did:plc:me"))
            #expect(response.status == .ok)
            #expect(response.body.contains("did:plc:me"))
            #expect(!response.body.contains("did:plc:brand"))
        }
    }

    @Test func draftStatusBehavesLikeAnUnknownStatusWhenProIsOff() async throws {
        let services = try await makeTestServices(proFeaturesEnabled: false)
        let app = Application(router: buildRouter(services: services))

        var draft = makeRecord()
        draft.status = .draft
        let draftBody = try encodedBody(CreateScheduleRequest(record: draft))

        try await app.test(.router) { client in
            // Unrecognized statuses decode to .failed and are stored as
            // scheduled posts; draft must be indistinguishable from that.
            let created = try await capture(client, uri: "/v1/schedules", method: .post, headers: didHeaders("did:plc:me"), body: draftBody)
            #expect(created.status == .created)
            #expect(created.body.contains("\"status\":\"scheduled\""))
            #expect(!created.body.contains("\"status\":\"draft\""))
        }
    }

    @Test func viewerReportsProFlag() async throws {
        let off = try await makeTestServices(proFeaturesEnabled: false)
        let offApp = Application(router: buildRouter(services: off))
        try await offApp.test(.router) { client in
            let me = try await capture(client, uri: "/v1/me", method: .get, headers: didHeaders("did:plc:me"))
            #expect(me.body.contains("\"proFeaturesEnabled\":false"))
        }

        let on = try await makeTestServices()
        let onApp = Application(router: buildRouter(services: on))
        try await onApp.test(.router) { client in
            let me = try await capture(client, uri: "/v1/me", method: .get, headers: didHeaders("did:plc:me"))
            #expect(me.body.contains("\"proFeaturesEnabled\":true"))
        }
    }

    @Test func teamsRoutesStillWorkWhenProIsOn() async throws {
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            let response = try await capture(client, uri: "/v1/teams", method: .get, headers: didHeaders("did:plc:me"))
            #expect(response.status == .ok)
        }
    }

    @Test func unknownRoutesReturnNotFound() async throws {
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            let response = try await capture(client, uri: "/v1/definitely-not-a-route", method: .get)
            #expect(response.status == .notFound)
            #expect(response.body.contains("not_found"))
        }
    }
}
