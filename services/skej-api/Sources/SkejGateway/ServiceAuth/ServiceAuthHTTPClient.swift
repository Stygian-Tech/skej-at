import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SkejKit

/// DID-key discovery must never follow a resolver redirect to a different authority.
public struct ServiceAuthHTTPClient: HTTPClient {
    public init() {}
    public func data(_ request: HTTPRequest) async throws -> HTTPResponseData {
        guard let url = URL(string: request.url), url.scheme == "https" else { throw HTTPClientError.invalidURL("Invalid identity URL") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (body, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw HTTPClientError.invalidResponse }
        return HTTPResponseData(body: body, headers: [:], statusCode: response.statusCode)
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
