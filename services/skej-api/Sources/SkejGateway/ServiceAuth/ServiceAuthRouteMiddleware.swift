import Hummingbird
import HTTPTypes

/// A valid service token does not authorize Skej's cookie-based team/admin APIs.
public struct ServiceAuthRouteMiddleware<Context: RequestContext>: RouterMiddleware {
    public init() {}
    static func allows(_ request: Request) -> Bool {
        switch (request.method, request.uri.path) {
        case (.get, "/xrpc/at.skej.actor.getSession"), (.get, "/xrpc/at.skej.schedule.list"),
             (.post, "/xrpc/at.skej.schedule.create"), (.post, "/xrpc/at.skej.schedule.update"),
             (.post, "/xrpc/at.skej.schedule.cancel"):
            true
        default:
            false
        }
    }
    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        if request.headers[.authorization] != nil && !Self.allows(request) {
            throw APIError(status: .unauthorized, code: "InvalidServiceAuth", message: "Service authentication is not valid for this route")
        }
        return try await next(request, context)
    }
}
