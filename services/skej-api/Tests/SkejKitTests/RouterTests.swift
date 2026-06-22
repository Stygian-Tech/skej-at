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
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            try await client.execute(uri: "/oauth/client-metadata.json", method: .get) { response in
                #expect(response.status == .ok)
                let body = String(buffer: response.body)
                #expect(body.contains("repo:at.skej.schedule"))
                #expect(body.contains("private_key_jwt"))
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
}
