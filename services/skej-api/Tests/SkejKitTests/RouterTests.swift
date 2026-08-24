import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import SkejGateway
import SkejKit
import Testing

@Suite
struct RouterTests {
    @Test func xrpcCreatesAndListsSchedulesWithCanonicalVerbs() async throws {
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))
        var markdownRecord = makeRecord()
        markdownRecord.posts = [
            PostPlan(
                text: "stale",
                source: PostSource(format: .markdown, text: "👋 [Skej](https://skej.at)")
            ),
            PostPlan(
                text: "stale second",
                source: PostSource(format: .markdown, text: "**Second** post")
            ),
        ]
        let inputRecord = markdownRecord

        try await app.test(.router) { client in
            let created: ScheduledPostSummary = try await postJSON(
                client: client,
                uri: "/xrpc/\(SkejXRPCMethod.createSchedule.nsid)",
                headers: didHeaders("did:plc:test"),
                body: SkejCreateScheduleInput(record: inputRecord)
            )
            #expect(created.did == "did:plc:test")
            #expect(created.record.posts.map(\.text) == ["👋 Skej", "Second post"])
            #expect(created.record.posts.allSatisfy { ATProtoTID.isValid($0.publishRkey ?? "") })
            #expect(Set(created.record.posts.compactMap(\.publishRkey)).count == 2)
            #expect(created.record.publishRkey == created.record.posts.first?.publishRkey)
            #expect(created.record.posts.first?.facets?.count == 1)

            var edited = created.record
            edited.posts = [
                PostPlan(
                    text: "tampered",
                    source: PostSource(format: .markdown, text: "[Edited](https://example.com)"),
                    publishRkey: created.record.posts[0].publishRkey
                ),
                created.record.posts[1],
            ]
            let updated: ScheduledPostSummary = try await postJSON(
                client: client,
                uri: "/xrpc/\(SkejXRPCMethod.updateSchedule.nsid)",
                headers: didHeaders("did:plc:test"),
                body: SkejUpdateScheduleInput(rkey: created.rkey, record: edited)
            )
            #expect(updated.record.posts[0].text == "Edited")
            #expect(updated.record.posts[0].publishRkey == created.record.posts[0].publishRkey)

            try await client.execute(
                uri: "/xrpc/\(SkejXRPCMethod.listSchedules.nsid)",
                method: .get,
                headers: didHeaders("did:plc:test")
            ) { response in
                #expect(response.status == .ok)
                let output = try JSONDecoder().decode(ListSchedulesResponse.self, from: Data(buffer: response.body))
                #expect(output.records.map(\.rkey) == [created.rkey])
            }
        }
    }

    @Test func duplicatePreservesMarkdownButRegeneratesAllPublicationIdentity() async throws {
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))
        var source = makeRecord()
        source.posts = [
            PostPlan(text: "first", source: PostSource(format: .markdown, text: "**first**")),
            PostPlan(text: "second", source: PostSource(format: .markdown, text: "[second](https://example.com)")),
        ]
        let sourceRecord = source

        try await app.test(.router) { client in
            let created: ScheduledPostSummary = try await postJSON(
                client: client,
                uri: "/xrpc/\(SkejXRPCMethod.createSchedule.nsid)",
                headers: didHeaders("did:plc:test"),
                body: SkejCreateScheduleInput(record: sourceRecord)
            )
            var published = created.record
            published.status = .published
            published.publishedUri = "at://did:plc:test/app.bsky.feed.post/first"
            published.publishedCid = "bafyfirst"
            published.publishedPosts = [PublishedPostReference(
                rkey: published.posts[0].publishRkey ?? "",
                uri: published.publishedUri ?? "",
                cid: published.publishedCid ?? ""
            )]
            try await services.pdsClient.writeSchedule(did: "did:plc:test", rkey: created.rkey, record: published)

            let duplicate: ScheduledPostSummary = try await postJSON(
                client: client,
                uri: "/xrpc/\(SkejXRPCMethod.duplicateSchedule.nsid)",
                headers: didHeaders("did:plc:test"),
                body: SkejScheduleParameters(rkey: created.rkey)
            )

            #expect(duplicate.status == .draft)
            #expect(duplicate.record.posts.map(\.source) == published.posts.map(\.source))
            #expect(Set(duplicate.record.posts.compactMap(\.publishRkey)).isDisjoint(with: Set(published.posts.compactMap(\.publishRkey))))
            #expect(duplicate.record.publishRkey == duplicate.record.posts.first?.publishRkey)
            #expect(duplicate.record.publishedPosts.isEmpty)
            #expect(duplicate.record.publishedUri == nil)
            #expect(duplicate.record.publishedCid == nil)
        }
    }

    @Test func xrpcValidatesTheCompiledMarkdownProjectionLength() async throws {
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))
        var acceptedRecord = makeRecord()
        acceptedRecord.posts = [PostPlan(
            text: "ignored",
            source: PostSource(format: .markdown, text: "*\(String(repeating: "a", count: 300))*")
        )]
        var rejectedRecord = makeRecord()
        rejectedRecord.posts = [PostPlan(
            text: "short client projection",
            source: PostSource(format: .markdown, text: String(repeating: "a", count: 301))
        )]
        let acceptedInput = acceptedRecord
        let rejectedInput = rejectedRecord

        try await app.test(.router) { client in
            let accepted: ScheduledPostSummary = try await postJSON(
                client: client,
                uri: "/xrpc/\(SkejXRPCMethod.createSchedule.nsid)",
                headers: didHeaders("did:plc:test"),
                body: SkejCreateScheduleInput(record: acceptedInput)
            )
            #expect(accepted.record.posts[0].text.count == 300)

            var requestHeaders = didHeaders("did:plc:test")
            requestHeaders[.contentType] = "application/json"
            try await client.execute(
                uri: "/xrpc/\(SkejXRPCMethod.createSchedule.nsid)",
                method: .post,
                headers: requestHeaders,
                body: try encodedBody(SkejCreateScheduleInput(record: rejectedInput))
            ) { response in
                #expect(response.status == .badRequest)
                let error = try JSONDecoder().decode(ErrorBody.self, from: Data(buffer: response.body))
                #expect(error.error == "invalid_post_text")
                #expect(error.message.contains("300"))
            }
        }
    }

    @Test func developmentSeedIncludesMarkdownThreadReplyAndQuoteFixtures() async throws {
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            let _: OKResponse = try await postJSON(
                client: client,
                uri: "/xrpc/\(SkejXRPCMethod.seedDevelopment.nsid)",
                headers: didHeaders("did:plc:test"),
                body: SkejEmptyInput()
            )
        }

        let records = try await services.pdsClient.listSchedules(did: localDID(for: "any"))
        let unicode = records["demo-markdown-unicode-link"]
        let thread = records["demo-markdown-thread"]
        let reply = records["demo-markdown-reply"]
        let quote = records["demo-markdown-quote"]
        #expect(unicode?.posts[0].text == "👋 Skej makes AT Protocol scheduling easier.")
        #expect(unicode?.posts[0].facets?.count == 1)
        #expect(thread?.posts.count == 3)
        #expect(Set(thread?.posts.compactMap(\.publishRkey) ?? []).count == 3)
        #expect(reply?.dependency?.relationship == .reply)
        #expect(reply?.dependency?.parentPublishedCid != nil)
        #expect(quote?.dependency?.relationship == .quote)
        #expect(quote?.posts[0].embed != nil)
    }

    @Test func xrpcNormalizesUnknownMethodsAndWrongVerbs() async throws {
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            try await client.execute(uri: "/xrpc/at.skej.unknown.method", method: .get) { response in
                #expect(response.status == .notFound)
                let error = try JSONDecoder().decode(ErrorBody.self, from: Data(buffer: response.body))
                #expect(error.error == "XrpcNotSupported")
            }
            try await client.execute(
                uri: "/xrpc/\(SkejXRPCMethod.listSchedules.nsid)",
                method: .post,
                headers: didHeaders("did:plc:test"),
                body: try encodedBody(SkejEmptyInput())
            ) { response in
                #expect(response.status == .methodNotAllowed)
                let error = try JSONDecoder().decode(ErrorBody.self, from: Data(buffer: response.body))
                #expect(error.error == "InvalidRequest")
            }
        }
    }

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

    @Test func createScheduleCanonicalizesLinkFacetsAndLegacyEmbed() async throws {
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))
        var record = makeRecord()
        record.posts = [
            PostPlan(
                text: "Read https://example.com",
                embed: .object([
                    "external": .object([
                        "uri": .string("https://example.com"),
                        "title": .string("Example"),
                        "description": .string("Example description"),
                    ]),
                ])
            ),
        ]
        let body = try encodedBody(CreateScheduleRequest(record: record))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/v1/schedules",
                method: .post,
                headers: didHeaders("did:plc:test"),
                body: body
            ) { response in
                #expect(response.status == .created)
                let summary = try JSONDecoder().decode(
                    ScheduledPostSummary.self,
                    from: Data(String(buffer: response.body).utf8)
                )
                #expect(summary.record.posts.first?.facets?.count == 1)
                guard case let .object(embed)? = summary.record.posts.first?.embed,
                      case let .string(type)? = embed["$type"]
                else {
                    Issue.record("Expected canonical external embed")
                    return
                }
                #expect(type == "app.bsky.embed.external")
            }
        }
    }

    @Test func linkPreviewRequiresAuthentication() async throws {
        let services = try await makeTestServices()
        let app = Application(router: buildRouter(services: services))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/v1/accounts/did:plc:test/link-preview",
                method: .post,
                body: try encodedBody(LinkPreviewRequest(url: "https://example.com"))
            ) { response in
                #expect(response.status == .unauthorized)
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
    var requestHeaders = headers
    requestHeaders[.contentType] = "application/json"
    try await client.execute(
        uri: uri,
        method: method,
        headers: requestHeaders,
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
