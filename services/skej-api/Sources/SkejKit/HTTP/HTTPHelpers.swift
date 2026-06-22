import Foundation
import Hummingbird
import HTTPTypes

public struct ErrorBody: Codable, Sendable {
    public let error: String
    public let message: String
}

public struct APIError: Error, Sendable {
    public let status: HTTPResponse.Status
    public let code: String
    public let message: String

    public init(status: HTTPResponse.Status, code: String, message: String) {
        self.status = status
        self.code = code
        self.message = message
    }
}

public func jsonResponse<T: Encodable>(
    _ body: T,
    status: HTTPResponse.Status = .ok
) throws -> Response {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(body)
    var buffer = ByteBuffer()
    buffer.writeBytes(data)
    var headers = HTTPFields()
    headers[.contentType] = "application/json; charset=utf-8"
    return Response(status: status, headers: headers, body: .init(byteBuffer: buffer))
}

public func decodeJSONBody<T: Decodable>(_ request: Request, as type: T.Type) async throws -> T {
    do {
        let buffer = try await request.body.collect(upTo: 1_048_576)
        return try JSONDecoder().decode(T.self, from: Data(buffer: buffer))
    } catch let error as APIError {
        throw error
    } catch {
        throw APIError(status: .badRequest, code: "invalid_json", message: "Invalid JSON body")
    }
}

public func errorResponse(_ error: Error) -> Response {
    if let apiError = error as? APIError {
        return (try? jsonResponse(
            ErrorBody(error: apiError.code, message: apiError.message),
            status: apiError.status
        )) ?? Response(status: apiError.status)
    }
    return (try? jsonResponse(
        ErrorBody(error: "internal_error", message: "Internal server error"),
        status: .internalServerError
    )) ?? Response(status: .internalServerError)
}

public struct ErrorMiddleware<Context: RequestContext>: RouterMiddleware {
    public init() {}

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        do {
            return try await next(request, context)
        } catch {
            return errorResponse(error)
        }
    }
}

public struct CorsMiddleware<Context: RequestContext>: RouterMiddleware {
    public init() {}

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        if request.method == .options {
            return Response(status: .noContent, headers: corsHeaders(for: request))
        }
        var response = try await next(request, context)
        for field in corsHeaders(for: request) {
            response.headers[field.name] = field.value
        }
        return response
    }

    private func corsHeaders(for request: Request) -> HTTPFields {
        var headers = HTTPFields()
        headers[.accessControlAllowOrigin] = request.headers[.origin] ?? "*"
        headers[.accessControlAllowMethods] = "GET, POST, PATCH, DELETE, OPTIONS"
        headers[.accessControlAllowHeaders] = "Content-Type, Authorization, Cookie, X-Skej-DID"
        headers[.accessControlAllowCredentials] = "true"
        headers[.vary] = "Origin"
        return headers
    }
}
