import Foundation
@testable import SkejKit
import Testing

@Suite
struct ATProtoPDSClientTests {
    @Test func primesAndCachesDPoPNonceBeforeBlobUpload() async throws {
        let did = "did:plc:test"
        let pdsEndpoint = "https://pds.example.com"
        let store = try SQLiteStore(path: ":memory:")
        try await store.migrate()
        let token = ATProtoTokenPayload(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            tokenType: "DPoP",
            expiresIn: 3_600,
            scope: "atproto",
            sub: did,
            pdsEndpoint: pdsEndpoint,
            tokenEndpoint: "https://auth.example.com/token"
        )
        let key = DPoPKey()
        try await store.createOAuthSession(
            OAuthSessionRecord(
                did: did,
                handle: "test.example.com",
                tokenJSON: String(decoding: try JSONEncoder().encode(token), as: UTF8.self),
                dpopKeyJSON: try key.exportJSON()
            ),
            now: "2026-08-05T00:00:00Z"
        )
        let http = NonceChallengeHTTPClient()
        let client = ATProtoPDSClient(store: store, http: http)

        let blob = try await client.uploadBlob(
            did: did,
            data: Data([0x89, 0x50, 0x4e, 0x47]),
            mimeType: "image/png"
        )

        #expect(blob.ref.link == "bafytest")
        #expect(blob.mimeType == "image/png")
        #expect(blob.size == 4)
        let requests = await http.requests()
        #expect(requests.count == 3)
        #expect(requests.map(\.method) == ["GET", "GET", "POST"])
        #expect(dpopNonce(in: requests[0]) == nil)
        #expect(dpopNonce(in: requests[1]) == "nonce-1")
        #expect(dpopNonce(in: requests[2]) == "nonce-2")
        #expect(requests[2].url == "\(pdsEndpoint)/xrpc/com.atproto.repo.uploadBlob")
    }
}

private actor NonceChallengeHTTPClient: HTTPClient {
    private var recordedRequests: [HTTPRequest] = []

    func data(_ request: HTTPRequest) async throws -> HTTPResponseData {
        recordedRequests.append(request)
        if request.url.hasSuffix("/xrpc/com.atproto.server.getSession") {
            guard dpopNonce(in: request) != nil else {
                throw HTTPClientError.badStatus(
                    401,
                    #"{"error":"use_dpop_nonce"}"#,
                    ["dpop-nonce": "nonce-1"]
                )
            }
            return HTTPResponseData(
                body: Data("{}".utf8),
                headers: ["dpop-nonce": "nonce-2"],
                statusCode: 200
            )
        }
        return HTTPResponseData(
            body: Data(#"{"blob":{"$type":"blob","ref":{"$link":"bafytest"},"mimeType":"image/png","size":4}}"#.utf8),
            headers: [:],
            statusCode: 200
        )
    }

    func requests() -> [HTTPRequest] {
        recordedRequests
    }
}

private func dpopNonce(in request: HTTPRequest) -> String? {
    guard let proof = request.headers["DPoP"] else { return nil }
    let parts = proof.split(separator: ".")
    guard parts.count == 3 else { return nil }
    var encoded = String(parts[1])
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
    guard let data = Data(base64Encoded: encoded),
          let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return payload["nonce"] as? String
}
