import Foundation
import SkejKit
import Testing

@Suite
struct IdentityResolverTests {
    @Test func didResolutionValidatesAgainstPLCDocument() async throws {
        let resolver = IdentityResolver(http: MockIdentityHTTPClient(responses: [
            "https://plc.directory/did:plc:brand": didDocument(),
        ]))

        let identity = try await resolver.resolve("did:plc:brand")

        #expect(identity.did == "did:plc:brand")
        #expect(identity.pdsEndpoint == "https://brand.pds.test")
    }

    @Test func handleResolutionChecksPLCDocumentAfterResolvingHandle() async throws {
        let resolver = IdentityResolver(http: MockIdentityHTTPClient(responses: [
            "https://brand.example/.well-known/atproto-did": Data("did:plc:brand".utf8),
            "https://plc.directory/did:plc:brand": didDocument(),
        ]))

        let identity = try await resolver.resolve("@brand.example")

        #expect(identity.did == "did:plc:brand")
        #expect(identity.pdsEndpoint == "https://brand.pds.test")
    }

    @Test func localResolutionAcceptsHandlesWithoutPLCLookup() async throws {
        let resolver = IdentityResolver(
            http: MockIdentityHTTPClient(responses: [:]),
            allowsLocalIdentifiers: true
        )

        let identity = try await resolver.resolve("making.another.account")

        #expect(identity.did.starts(with: "did:plc:"))
        #expect(identity.pdsEndpoint == "local")
    }

    @Test func localResolutionAcceptsATURIAuthority() async throws {
        let resolver = IdentityResolver(
            http: MockIdentityHTTPClient(responses: [:]),
            allowsLocalIdentifiers: true
        )

        let identity = try await resolver.resolve("at://did:plc:any")

        #expect(identity.did == "did:plc:any")
        #expect(identity.pdsEndpoint == "local")
    }
}

private func didDocument() -> Data {
    Data("""
    {
      "service": [
        {
          "id": "#atproto_pds",
          "type": "AtprotoPersonalDataServer",
          "serviceEndpoint": "https://brand.pds.test/"
        }
      ]
    }
    """.utf8)
}

private struct MockIdentityHTTPClient: HTTPClient {
    let responses: [String: Data]

    func data(_ request: HTTPRequest) async throws -> HTTPResponseData {
        guard let body = responses[request.url] else {
            throw HTTPClientError.badStatus(404, "not found", [:])
        }
        return HTTPResponseData(body: body, headers: [:], statusCode: 200)
    }
}
