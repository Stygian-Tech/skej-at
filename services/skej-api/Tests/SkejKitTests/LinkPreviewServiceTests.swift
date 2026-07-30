import Foundation
import SkejKit
import Testing

@Suite
struct LinkPreviewServiceTests {
    @Test func hydratesOpenGraphMetadataAndRelativeThumbnail() async throws {
        let pageURL = URL(string: "https://example.com/start")!
        let finalPageURL = URL(string: "https://cdn.example.com/articles/post")!
        let imageURL = URL(string: "https://cdn.example.com/card.png")!
        let http = StubLinkPreviewHTTPClient(responses: [
            pageURL.absoluteString: LinkPreviewHTTPResponse(
                body: Data("""
                <html><head>
                  <title>HTML fallback</title>
                  <meta property="og:title" content="Open Graph title">
                  <meta name="twitter:title" content="Twitter title">
                  <meta property="og:description" content="Open Graph description">
                  <meta property="og:image" content="/card.png">
                </head></html>
                """.utf8),
                mimeType: "text/html",
                finalURL: finalPageURL
            ),
            imageURL.absoluteString: LinkPreviewHTTPResponse(
                body: Data([0x89, 0x50, 0x4e, 0x47]),
                mimeType: "image/png",
                finalURL: imageURL
            ),
        ])
        let service = LinkPreviewService(pdsClient: InMemoryPDSClient(), http: http)

        let embed = try await service.hydrate(
            did: "did:plc:test",
            url: pageURL.absoluteString
        )

        #expect(embed.type == "app.bsky.embed.external")
        #expect(embed.external.uri == pageURL.absoluteString)
        #expect(embed.external.title == "Open Graph title")
        #expect(embed.external.description == "Open Graph description")
        guard let thumb = embed.external.thumb else {
            Issue.record("Expected an uploaded thumbnail blob")
            return
        }
        #expect(thumb.type == "blob")
        #expect(thumb.ref.link == "bafyinmemory4")
        #expect(thumb.mimeType == "image/png")
        #expect(thumb.size == 4)
        #expect(await http.requestedURLs() == [pageURL, imageURL])
        #expect(await http.requestLimits() == [2_000_000, 1_000_000])
    }

    @Test func fallsBackToHTMLTitleAndAllowsMissingThumbnail() async throws {
        let pageURL = URL(string: "https://example.com/no-card")!
        let http = StubLinkPreviewHTTPClient(responses: [
            pageURL.absoluteString: LinkPreviewHTTPResponse(
                body: Data("<html><head><title>Fallback title</title></head></html>".utf8),
                mimeType: "text/html",
                finalURL: pageURL
            ),
        ])
        let service = LinkPreviewService(pdsClient: InMemoryPDSClient(), http: http)

        let embed = try await service.hydrate(
            did: "did:plc:test",
            url: pageURL.absoluteString
        )

        #expect(embed.external.title == "Fallback title")
        #expect(embed.external.description == "")
        #expect(embed.external.thumb == nil)
    }

    @Test func usesTwitterThenHostnameFallbacks() async throws {
        let twitterURL = URL(string: "https://example.com/twitter")!
        let emptyURL = URL(string: "https://fallback.example/no-metadata")!
        let http = StubLinkPreviewHTTPClient(responses: [
            twitterURL.absoluteString: LinkPreviewHTTPResponse(
                body: Data("""
                <html><head>
                  <meta name="twitter:title" content="Twitter title">
                  <meta name="twitter:description" content="Twitter description">
                </head></html>
                """.utf8),
                mimeType: "text/html",
                finalURL: twitterURL
            ),
            emptyURL.absoluteString: LinkPreviewHTTPResponse(
                body: Data("<html><head></head></html>".utf8),
                mimeType: "text/html",
                finalURL: emptyURL
            ),
        ])
        let service = LinkPreviewService(pdsClient: InMemoryPDSClient(), http: http)

        let twitter = try await service.hydrate(
            did: "did:plc:test",
            url: twitterURL.absoluteString
        )
        let empty = try await service.hydrate(
            did: "did:plc:test",
            url: emptyURL.absoluteString
        )

        #expect(twitter.external.title == "Twitter title")
        #expect(twitter.external.description == "Twitter description")
        #expect(empty.external.title == "fallback.example")
        #expect(empty.external.description == "")
    }

    @Test func enforcesPageSizeAndPropagatesTimeouts() async {
        let oversizedURL = URL(string: "https://example.com/oversized")!
        let timeoutURL = URL(string: "https://example.com/timeout")!
        let http = StubLinkPreviewHTTPClient(
            responses: [
                oversizedURL.absoluteString: LinkPreviewHTTPResponse(
                    body: Data(repeating: 0x20, count: 2_000_001),
                    mimeType: "text/html",
                    finalURL: oversizedURL
                ),
            ],
            errors: [timeoutURL.absoluteString: URLError(.timedOut)]
        )
        let service = LinkPreviewService(pdsClient: InMemoryPDSClient(), http: http)

        await #expect(throws: LinkPreviewError.responseTooLarge) {
            _ = try await service.hydrate(
                did: "did:plc:test",
                url: oversizedURL.absoluteString
            )
        }
        await #expect(throws: URLError.self) {
            _ = try await service.hydrate(
                did: "did:plc:test",
                url: timeoutURL.absoluteString
            )
        }
    }

    @Test func rejectsPrivateAndCredentialedURLs() async {
        #expect(throws: LinkPreviewError.unsafeURL) {
            try SafeURLValidator.validate(URL(string: "http://127.0.0.1/private")!)
        }
        #expect(throws: LinkPreviewError.unsafeURL) {
            try SafeURLValidator.validate(URL(string: "http://[::1]/private")!)
        }
        #expect(throws: LinkPreviewError.unsafeURL) {
            try SafeURLValidator.validate(URL(string: "http://169.254.169.254/metadata")!)
        }
        #expect(throws: LinkPreviewError.unsafeURL) {
            try SafeURLValidator.validate(URL(string: "http://10.0.0.1/private")!)
        }
        #expect(throws: LinkPreviewError.unsafeURL) {
            try SafeURLValidator.validate(URL(string: "http://[::ffff:127.0.0.1]/private")!)
        }
        #expect(throws: LinkPreviewError.unsafeURL) {
            try SafeURLValidator.validate(URL(string: "https://192.0.2.1/documentation")!)
        }

        let service = LinkPreviewService(
            pdsClient: InMemoryPDSClient(),
            http: StubLinkPreviewHTTPClient(responses: [:])
        )
        await #expect(throws: LinkPreviewError.invalidURL) {
            _ = try await service.hydrate(
                did: "did:plc:test",
                url: "https://user:password@example.com"
            )
        }
    }

    @Test func rejectsNonHTMLDocuments() async {
        let pageURL = URL(string: "https://example.com/file.pdf")!
        let service = LinkPreviewService(
            pdsClient: InMemoryPDSClient(),
            http: StubLinkPreviewHTTPClient(responses: [
                pageURL.absoluteString: LinkPreviewHTTPResponse(
                    body: Data("%PDF".utf8),
                    mimeType: "application/pdf",
                    finalURL: pageURL
                ),
            ])
        )

        await #expect(throws: LinkPreviewError.unsupportedContentType) {
            _ = try await service.hydrate(
                did: "did:plc:test",
                url: pageURL.absoluteString
            )
        }
    }
}

private actor StubLinkPreviewHTTPClient: LinkPreviewHTTPClient {
    private let responses: [String: LinkPreviewHTTPResponse]
    private let errors: [String: Error]
    private var requests: [URL] = []
    private var limits: [Int] = []

    init(
        responses: [String: LinkPreviewHTTPResponse],
        errors: [String: Error] = [:]
    ) {
        self.responses = responses
        self.errors = errors
    }

    func fetch(url: URL, accept: String, maxBytes: Int) async throws -> LinkPreviewHTTPResponse {
        requests.append(url)
        limits.append(maxBytes)
        if let error = errors[url.absoluteString] {
            throw error
        }
        guard let response = responses[url.absoluteString] else {
            throw LinkPreviewError.invalidResponse
        }
        guard response.body.count <= maxBytes else {
            throw LinkPreviewError.responseTooLarge
        }
        return response
    }

    func requestedURLs() -> [URL] {
        requests
    }

    func requestLimits() -> [Int] {
        limits
    }
}
