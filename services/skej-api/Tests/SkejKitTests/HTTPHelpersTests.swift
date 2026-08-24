import Foundation
import Hummingbird
import HTTPTypes
@testable import SkejGateway
import SkejKit
import Testing

@Suite
struct HTTPHelpersTests {
    @Test func authFailuresBecomeReconnectConflictsRatherThan500s() throws {
        for error in [
            PDSClientError.notConfigured,
            HTTPClientError.badStatus(401, "", [:]),
            HTTPClientError.badStatus(403, "", [:]),
            HTTPClientError.badStatus(400, #"{"error":"invalid_grant"}"#, [:]),
        ] as [Error] {
            let response = errorResponse(error)
            #expect(response.status == .conflict)
        }
    }

    @Test func unauthorizedIsNeverUsedForReconnect() throws {
        // A 401 would read as "your Skej session expired" and sign the user out,
        // when in fact only the PDS credentials need refreshing.
        #expect(errorResponse(PDSClientError.notConfigured).status != .unauthorized)
    }

    @Test func transientPDSFailuresStayServerErrors() throws {
        #expect(errorResponse(HTTPClientError.badStatus(503, "", [:])).status == .internalServerError)
        #expect(errorResponse(HTTPClientError.badStatus(429, "", [:])).status == .internalServerError)
    }

    @Test func deliberateAPIErrorsPassThroughUnchanged() throws {
        let response = errorResponse(APIError(status: .notFound, code: "not_found", message: "Schedule not found"))
        #expect(response.status == .notFound)
    }
}
