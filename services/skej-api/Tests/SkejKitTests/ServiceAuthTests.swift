import Crypto
import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import libsecp256k1
import Logging
@testable import SkejGateway
import SkejKit
import Testing

@Suite struct ServiceAuthTests {
    @Test func schedulingCorsAllowsExplicitSocialOriginAndRejectsArbitraryCredentialOrigin() async throws {
        let fixture = try await ServiceFixture()
        let app = Application(router: buildRouter(services: fixture.services))
        try await app.test(.router) { client in
            for origin in ["https://testing.thesocialwire.app", "https://untrusted.example"] {
                var headers = HTTPFields(); headers[.origin] = origin
                try await client.execute(uri: "/xrpc/at.skej.schedule.create", method: .options, headers: headers) { response in
                    #expect(response.status == .noContent)
                    #expect(response.headers[.accessControlAllowOrigin] == (origin == "https://testing.thesocialwire.app" ? origin : nil))
                    #expect(response.headers[.accessControlAllowCredentials] == (origin == "https://testing.thesocialwire.app" ? "true" : nil))
                }
            }
        }
    }

    @Test func completionPageRequiresCookieAndRealSchedulerConnectionWithoutLeakingIdentity() async throws {
        for enrolled in [true, false] {
            let fixture = try await ServiceFixture(enrolled: enrolled)
            try await fixture.store.createWebSession(sessionID: "test-cookie", did: fixture.did, handle: nil,
                displayName: nil, avatar: nil, expiresAt: Timestamp.iso8601(Date().addingTimeInterval(3600)))
            let app = Application(router: buildRouter(services: fixture.services))
            try await app.test(.router) { client in
                try await client.execute(uri: "/scheduling/connected", method: .get) { response in
                    #expect(response.status == .unauthorized)
                }
                var headers = HTTPFields(); headers[.cookie] = "skej_session=test-cookie"
                try await client.execute(uri: "/scheduling/connected", method: .get, headers: headers) { response in
                    #expect(response.status == (enrolled ? .ok : .conflict))
                    if enrolled {
                        let text = String(decoding: response.body.readableBytesView, as: UTF8.self)
                        #expect(text.contains("Scheduling Connected"))
                        #expect(text.contains("Check Connection"))
                        #expect(!text.contains(fixture.did))
                        #expect(!text.contains("test-cookie"))
                        #expect(response.headers[.cacheControl] == "no-store")
                    }
                }
            }
        }
    }

    @Test func didWebKeysRequireExplicitTrustedOriginAndExactController() async throws {
        let did = "did:web:brand.example:people:alice"
        let blocked = try await ServiceFixture(did: did)
        let token = try blocked.token(method: "at.skej.schedule.list")
        await #expect(throws: APIError.self) { try await blocked.verifier.verify(token, method: "at.skej.schedule.list", store: blocked.store) }
        let network = SkejATProtoNetwork(environment: .dev, publicOrigin: "https://api.testing.skej.at",
            environmentValues: ["SKEJ_DID_WEB_ORIGINS": "https://brand.example"])
        let allowed = try await ServiceFixture(did: did, network: network)
        #expect(try await allowed.verifier.verify(allowed.token(method: "at.skej.schedule.list"), method: "at.skej.schedule.list", store: allowed.store) == did)
    }

    @Test func localNetworkOverridesCannotAlterHostedTrustAndRequireExplicitPDS() {
        let env = ["SKEJ_LOCAL_PLC_ORIGIN": "https://plc.atmosbox.test", "SKEJ_LOCAL_HANDLE_RESOLVER_ORIGIN": "https://appview.atmosbox.test", "SKEJ_LOCAL_PDS_ORIGINS": "https://pds1.atmosbox.test"]
        let local = SkejATProtoNetwork(environment: .local, publicOrigin: "https://skej.atmosbox.test", environmentValues: env)
        #expect(local.isolated)
        #expect(local.allowsPDS("https://pds1.atmosbox.test"))
        #expect(!local.allowsPDS("https://bsky.social"))
        #expect(!local.allowsOAuthEndpoint("https://public.example/oauth/token"))
        #expect(local.allowsOAuthEndpoint("https://pds1.atmosbox.test/oauth/token"))
        for environment in [AppEnvironment.dev, .prod] {
            let hosted = SkejATProtoNetwork(environment: environment, publicOrigin: "https://skej.at", environmentValues: env)
            #expect(hosted.plcOrigin == "https://plc.directory")
            #expect(hosted.handleResolverOrigin == "https://bsky.social")
            #expect(!hosted.isolated)
        }
    }

    @Test func replayClaimSurvivesOpeningAnotherStore() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try SQLiteStore(path: path)
        try await first.migrate()
        #expect(try await first.claimServiceAuth(issuer: "did:plc:test", jti: "same", expiresAt: 160, now: 100))
        let second = try SQLiteStore(path: path)
        try await second.migrate()
        #expect(try await !second.claimServiceAuth(issuer: "did:plc:test", jti: "same", expiresAt: 160, now: 101))
        #expect(try await second.claimServiceAuth(issuer: "did:plc:test", jti: "same", expiresAt: 220, now: 160))
    }

    @Test func verifiesBothCurvesAndRejectsClaimAndSignatureConfusion() async throws {
        for curve in ["ES256", "ES256K"] {
            let fixture = try await ServiceFixture(curve: curve)
            let good = try fixture.token(method: "at.skej.schedule.list")
            #expect(try await fixture.verifier.verify(good, method: "at.skej.schedule.list", store: fixture.store) == fixture.did)
            await #expect(throws: APIError.self) { try await fixture.verifier.verify(good, method: "at.skej.schedule.list", store: fixture.store) }
            for changes in [
                ["aud": "did:web:other.test#skej_scheduler"],
                ["lxm": "at.skej.schedule.create"],
                ["exp": fixture.instant - 1],
                ["iat": fixture.instant + 10],
                ["exp": fixture.instant + 120],
                ["iss": "did:plc:bbbbbbbbbbbbbbbbbbbbbbbb"],
                ["jti": ""],
            ] as [[String: Any]] {
                let token = try fixture.token(method: "at.skej.schedule.list", changes: changes)
                await #expect(throws: APIError.self) { try await fixture.verifier.verify(token, method: "at.skej.schedule.list", store: fixture.store) }
            }
            for header in [["typ": "at+jwt"], ["kid": "#atproto_label"], ["alg": "HS256"]] {
                let token = try fixture.token(method: "at.skej.schedule.list", headerChanges: header)
                await #expect(throws: APIError.self) { try await fixture.verifier.verify(token, method: "at.skej.schedule.list", store: fixture.store) }
            }
            let pieces = try fixture.token(method: "at.skej.schedule.list").split(separator: ".")
            let tampered = pieces[0] + "." + pieces[1] + "." + base64URLEncode(Data(repeating: 0, count: 64))
            await #expect(throws: APIError.self) { try await fixture.verifier.verify(tampered, method: "at.skej.schedule.list", store: fixture.store) }
        }
    }

    @Test func bearerSchedulesEnterExistingQueueAndPublishThroughWorker() async throws {
        let fixture = try await ServiceFixture()
        let app = Application(router: buildRouter(services: fixture.services))
        try await app.test(.router) { client in
            try await client.execute(uri: "/.well-known/did.json", method: .get) { response in
                #expect(response.status == .ok)
                let value = try JSONDecoder().decode([String: JSONValue].self, from: Data(buffer: response.body))
                #expect(value["id"] == .string("did:web:api.testing.skej.at"))
            }
            try await client.execute(uri: "/xrpc/at.skej.actor.getSession", method: .get,
                headers: fixture.headers("at.skej.actor.getSession")) { response in
                #expect(response.status == .ok)
                let viewer = try JSONDecoder().decode(Viewer.self, from: Data(buffer: response.body))
                #expect(viewer.did == fixture.did)
                #expect(viewer.defaultAccountDid == fixture.did)
            }
            var created: ScheduledPostSummary?
            try await client.execute(uri: "/xrpc/at.skej.schedule.create", method: .post,
                headers: fixture.headers("at.skej.schedule.create"),
                body: encodedBody(SkejCreateScheduleInput(accountDid: fixture.did, record: makeRecord()))) { response in
                #expect(response.status == .created)
                created = try JSONDecoder().decode(ScheduledPostSummary.self, from: Data(buffer: response.body))
            }
            let schedule = try #require(created)
            #expect(try await fixture.store.scheduleJob(did: fixture.did, rkey: schedule.rkey)?.status == .scheduled)
            #expect(schedule.record.calendarEventUri != nil)
            let worker = ScheduleWorker(store: fixture.store, pdsClient: fixture.services.pdsClient, logger: Logger(label: "service-auth-test"))
            await worker.runTick(now: ISO8601DateFormatter().date(from: "2026-01-01T11:00:01Z")!)
            #expect(try await fixture.store.scheduleJob(did: fixture.did, rkey: schedule.rkey)?.status == .published)
            for method in ["update", "cancel"] {
                let body: ByteBuffer = method == "update"
                    ? try encodedBody(SkejUpdateScheduleInput(rkey: schedule.rkey, record: schedule.record))
                    : try encodedBody(SkejScheduleParameters(rkey: schedule.rkey))
                try await client.execute(uri: "/xrpc/at.skej.schedule.\(method)", method: .post,
                    headers: fixture.headers("at.skej.schedule.\(method)"), body: body) { response in
                    #expect(response.status == .conflict)
                }
            }
        }
    }

    @Test func crossActorAndWrongRoutesCannotBorrowTeamAuthority() async throws {
        let fixture = try await ServiceFixture()
        let other = "did:plc:bbbbbbbbbbbbbbbbbbbbbbbb"
        try await fixture.store.upsertManagedAccount(ManagedAccount(did: other), now: Timestamp.iso8601())
        try await fixture.store.upsertViewerAccount(ViewerAccountAccess(viewerDid: fixture.did, accountDid: other,
            accessKind: .owner, capabilities: BrandCapability.allCases, isDefault: false,
            createdAt: Timestamp.iso8601(), updatedAt: Timestamp.iso8601()))
        let app = Application(router: buildRouter(services: fixture.services))
        try await app.test(.router) { client in
            try await client.execute(uri: "/xrpc/at.skej.schedule.list?accountDid=\(other)", method: .get,
                headers: fixture.headers("at.skej.schedule.list")) { response in #expect(response.status == .forbidden) }
            try await client.execute(uri: "/xrpc/at.skej.schedule.create", method: .post,
                headers: fixture.headers("at.skej.schedule.create"),
                body: encodedBody(SkejCreateScheduleInput(accountDid: other, record: makeRecord()))) { response in #expect(response.status == .forbidden) }
            for path in ["/xrpc/at.skej.actor.logout", "/xrpc/at.skej.schedule.publishNow", "/api/accounts", "/health"] {
                try await client.execute(uri: path, method: .post, headers: fixture.headers("at.skej.schedule.create")) { response in
                    #expect(response.status == .unauthorized)
                }
            }
            try await client.execute(uri: "/xrpc/at.skej.actor.getSession", method: .get, headers: didHeaders(fixture.did)) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test func missingGrantNeedsConnectionAndEditLeaseExcludesWorkerClaim() async throws {
        let fixture = try await ServiceFixture(enrolled: false)
        let app = Application(router: buildRouter(services: fixture.services))
        try await app.test(.router) { client in
            try await client.execute(uri: "/xrpc/at.skej.actor.getSession", method: .get,
                headers: fixture.headers("at.skej.actor.getSession")) { response in
                #expect(response.status == .conflict)
                let value = try JSONDecoder().decode(ErrorBody.self, from: Data(buffer: response.body))
                #expect(value.error == "AccountNeedsReauth")
            }
        }
        let record = makeRecord()
        try await fixture.store.upsertScheduleJob(ScheduledJob(did: fixture.did, rkey: "lease", scheduledFor: record.scheduledFor, status: .scheduled, attempts: 0), now: record.createdAt)
        #expect(try await fixture.store.claimScheduleEdit(did: fixture.did, rkey: "lease", leaseID: "a", now: "2026-01-01T10:59:59Z", expiresAt: "2026-01-01T11:05:00Z"))
        #expect(try await fixture.store.claimDueJobs(now: "2026-01-01T11:00:01Z").isEmpty)
        #expect(try await !fixture.store.claimScheduleEdit(did: fixture.did, rkey: "lease", leaseID: "b", now: "2026-01-01T11:00:01Z", expiresAt: "2026-01-01T11:05:00Z"))
        try await fixture.store.releaseScheduleEdit(did: fixture.did, rkey: "lease", leaseID: "a")
        #expect(try await fixture.store.claimDueJobs(now: "2026-01-01T11:00:01Z").count == 1)
        #expect(try await !fixture.store.claimScheduleEdit(did: fixture.did, rkey: "lease", leaseID: "c", now: "2026-01-01T11:00:01Z", expiresAt: "2026-01-01T11:05:00Z"))
    }
}

private struct ServiceFixture: Sendable {
    let did: String
    let instant = 1_800_000_000
    let key: P256.Signing.PrivateKey
    let curve: String
    let store: SQLiteStore
    let verifier: SkejServiceAuthVerifier
    let services: SkejServices

    init(curve: String = "ES256", enrolled: Bool = true, did: String = "did:plc:aaaaaaaaaaaaaaaaaaaaaaaa", network configuredNetwork: SkejATProtoNetwork? = nil) async throws {
        self.did = did
        self.curve = curve
        key = P256.Signing.PrivateKey()
        store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let network = configuredNetwork ?? SkejATProtoNetwork(environment: .dev, publicOrigin: "https://api.testing.skej.at")
        let rawKey = curve == "ES256" ? Data([0x80, 0x24]) + key.publicKey.compressedRepresentation : Data([0xe7, 0x01]) + Self.k256PublicKey()
        let document: [String: JSONValue] = ["id": .string(did), "verificationMethod": .array([.object([
            "id": .string(did + "#atproto"), "controller": .string(did), "type": .string("Multikey"), "publicKeyMultibase": .string("z" + Self.base58(rawKey)),
        ])])]
        verifier = SkejServiceAuthVerifier(network: network, http: IdentityHTTP(body: try JSONEncoder().encode(document)), now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let config = AppConfig(port: 8080, environment: .dev, publicOrigin: "https://api.testing.skej.at", sqlitePath: ":memory:", workerEnabled: false, liveATProtoEnabled: true, network: network)
        services = SkejServices(config: config, store: store, pdsClient: InMemoryPDSClient(), oauthClient: LocalOAuthClient(), serviceAuthVerifier: verifier)
        if enrolled {
            let token = ATProtoTokenPayload(accessToken: "test-access", refreshToken: "test-refresh", tokenType: "DPoP", expiresIn: 3600, scope: "atproto transition:generic", sub: did, pdsEndpoint: "https://pds.test", tokenEndpoint: "https://pds.test/oauth/token")
            try await store.createOAuthSession(OAuthSessionRecord(did: did, handle: nil, tokenJSON: String(decoding: JSONEncoder().encode(token), as: UTF8.self), dpopKeyJSON: DPoPKey().exportJSON()), now: Timestamp.iso8601())
            try await store.upsertManagedAccount(ManagedAccount(did: did, pdsEndpoint: "https://pds.test", isDefault: true), now: Timestamp.iso8601())
        }
    }
    func headers(_ method: String) throws -> HTTPFields {
        var result = HTTPFields()
        result[.authorization] = "Bearer " + (try token(method: method))
        result[.contentType] = "application/json"
        return result
    }
    func token(method: String, changes: [String: Any] = [:], headerChanges: [String: String] = [:]) throws -> String {
        let header = ["typ": "JWT", "alg": curve].merging(headerChanges) { _, b in b }
        let body: [String: Any] = ["iss": did, "aud": "did:web:api.testing.skej.at#skej_scheduler", "lxm": method, "iat": instant, "exp": instant + 60, "jti": UUID().uuidString]
        let input = base64URLEncode(try JSONSerialization.data(withJSONObject: header)) + "." + base64URLEncode(try JSONSerialization.data(withJSONObject: body.merging(changes) { _, b in b }))
        let signature = curve == "ES256" ? try key.signature(for: Data(input.utf8)).rawRepresentation : Self.k256Sign(Data(input.utf8))
        return input + "." + base64URLEncode(signature)
    }
    static func k256PublicKey() -> Data {
        let context = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN))!
        defer { secp256k1_context_destroy(context) }
        var key = secp256k1_pubkey()
        _ = secp256k1_ec_pubkey_create(context, &key, [UInt8](repeating: 1, count: 32))
        var bytes = [UInt8](repeating: 0, count: 33); var count = 33
        _ = secp256k1_ec_pubkey_serialize(context, &bytes, &count, &key, UInt32(SECP256K1_EC_COMPRESSED))
        return Data(bytes)
    }
    static func k256Sign(_ input: Data) -> Data {
        let context = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN))!
        defer { secp256k1_context_destroy(context) }
        var sig = secp256k1_ecdsa_signature()
        _ = secp256k1_ecdsa_sign(context, &sig, Array(SHA256.hash(data: input)), [UInt8](repeating: 1, count: 32), nil, nil)
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = secp256k1_ecdsa_signature_serialize_compact(context, &bytes, &sig)
        return Data(bytes)
    }
    static func base58(_ data: Data) -> String {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        var digits = [Int]()
        for byte in data {
            var carry = Int(byte)
            for i in digits.indices { carry += digits[i] * 256; digits[i] = carry % 58; carry /= 58 }
            while carry > 0 { digits.append(carry % 58); carry /= 58 }
        }
        return String(repeating: "1", count: data.prefix(while: { $0 == 0 }).count) + String(digits.reversed().map { alphabet[$0] })
    }
}
private struct IdentityHTTP: HTTPClient {
    let body: Data
    func data(_ request: SkejKit.HTTPRequest) async throws -> HTTPResponseData { HTTPResponseData(body: body, headers: [:], statusCode: 200) }
}
