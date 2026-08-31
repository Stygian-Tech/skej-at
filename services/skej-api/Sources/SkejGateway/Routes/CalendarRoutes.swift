import Foundation
import Hummingbird
import SkejKit

public typealias CalendarAccountResolver = @Sendable (Request) async throws -> [ManagedAccount]

public func registerCalendarXRPCRoutes(
    on xrpc: RouterGroup<BasicRequestContext>,
    pdsClient: any PDSClient,
    resolveAccounts: @escaping CalendarAccountResolver
) {
    xrpc.get(RouterPath("at.skej.calendar.list")) { request, _ in
        let parameters = try CalendarQueryParameters(request: request)
        let accessible = try await resolveAccounts(request)
        let accessibleByDID = Dictionary(uniqueKeysWithValues: accessible.map { ($0.did, $0) })
        let selected: [ManagedAccount]
        if parameters.accountDids.isEmpty {
            selected = accessible
        } else {
            guard parameters.accountDids.allSatisfy({ accessibleByDID[$0] != nil }) else {
                throw APIError(
                    status: .forbidden,
                    code: "Forbidden",
                    message: "One or more requested calendar accounts are not accessible"
                )
            }
            selected = parameters.accountDids.compactMap { accessibleByDID[$0] }
        }

        var events: [CalendarEventSummary] = []
        let coordinator = CalendarCoordinator(pdsClient: pdsClient)
        for account in selected {
            let accountEvents = try await coordinator.listEvents(did: account.did)
            events.append(contentsOf: accountEvents.filter { event in
                guard let start = Timestamp.date(from: event.record.startsAt),
                      start >= parameters.from,
                      start < parameters.to
                else { return false }
                return parameters.statuses.isEmpty || parameters.statuses.contains(event.record.status)
            })
        }
        return try jsonResponse(ListCalendarEventsResponse(events: events.sorted {
            if $0.record.startsAt == $1.record.startsAt { return $0.uri < $1.uri }
            return $0.record.startsAt < $1.record.startsAt
        }))
    }
}

private struct ListCalendarEventsResponse: Encodable {
    let events: [CalendarEventSummary]
}

private struct CalendarQueryParameters {
    let from: Date
    let to: Date
    let accountDids: [String]
    let statuses: Set<CalendarEventStatus>

    init(request: Request) throws {
        let allowed = Set(["from", "to", "accountDids", "status"])
        var fromValue: String?
        var toValue: String?
        var accountDids: [String] = []
        var statuses = Set<CalendarEventStatus>()
        for (rawKey, rawValue) in request.uri.queryParameters {
            let key = String(rawKey)
            let value = String(rawValue)
            guard allowed.contains(key) else {
                throw APIError(status: .badRequest, code: "InvalidRequest", message: "Unknown query parameter: \(key)")
            }
            switch key {
            case "from":
                guard fromValue == nil else {
                    throw APIError(status: .badRequest, code: "InvalidRequest", message: "from must not be repeated")
                }
                fromValue = value
            case "to":
                guard toValue == nil else {
                    throw APIError(status: .badRequest, code: "InvalidRequest", message: "to must not be repeated")
                }
                toValue = value
            case "accountDids":
                guard value.hasPrefix("did:"), accountDids.count < 100 else {
                    throw APIError(status: .badRequest, code: "InvalidRequest", message: "accountDids contains an invalid DID")
                }
                accountDids.append(value)
            case "status":
                guard let status = CalendarEventStatus(rawValue: value), statuses.count < 5 else {
                    throw APIError(status: .badRequest, code: "InvalidRequest", message: "status contains an invalid calendar status")
                }
                statuses.insert(status)
            default:
                break
            }
        }
        guard let fromValue, let from = Timestamp.date(from: fromValue),
              let toValue, let to = Timestamp.date(from: toValue),
              from < to,
              to.timeIntervalSince(from) <= 370 * 24 * 60 * 60
        else {
            throw APIError(
                status: .badRequest,
                code: "InvalidRequest",
                message: "from and to must define a valid range no longer than 370 days"
            )
        }
        self.from = from
        self.to = to
        var seen = Set<String>()
        self.accountDids = accountDids.filter { seen.insert($0).inserted }
        self.statuses = statuses
    }
}
