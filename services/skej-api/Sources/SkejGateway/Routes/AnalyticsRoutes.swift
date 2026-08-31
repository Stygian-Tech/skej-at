import Foundation
import Hummingbird
import SkejKit

public typealias AnalyticsAccountResolver = @Sendable (Request) async throws -> [ManagedAccount]

/// Registers the analytics query without owning viewer/account authorization.
/// AppRouter supplies its canonical access resolver so analytics cannot drift
/// from the rest of the Pro account surface.
public func registerAnalyticsXRPCRoutes(
    on xrpc: RouterGroup<BasicRequestContext>,
    store: any EngagementStore,
    resolveAccounts: @escaping AnalyticsAccountResolver
) {
    xrpc.get(RouterPath("at.skej.analytics.getEngagement")) { request, _ in
        let parameters = try AnalyticsQueryParameters(request: request)
        let accessible = try await resolveAccounts(request)
        let requested = Set(parameters.accountDids)
        let selected: [ManagedAccount]
        if requested.isEmpty {
            selected = accessible
        } else {
            let accessibleByDID = Dictionary(uniqueKeysWithValues: accessible.map { ($0.did, $0) })
            guard requested.allSatisfy({ accessibleByDID[$0] != nil }) else {
                throw APIError(
                    status: .forbidden,
                    code: "Forbidden",
                    message: "One or more requested accounts are not accessible"
                )
            }
            selected = parameters.accountDids.compactMap { accessibleByDID[$0] }
        }

        do {
            return try jsonResponse(try await EngagementAnalyticsService(store: store).report(
                accounts: selected,
                from: parameters.from,
                to: parameters.to,
                bucket: parameters.bucket,
                timezone: parameters.timezone
            ))
        } catch EngagementAnalyticsError.invalidRange {
            throw APIError(
                status: .badRequest,
                code: "InvalidRequest",
                message: "Analytics range must be positive and no longer than 366 days"
            )
        } catch EngagementAnalyticsError.invalidTimezone {
            throw APIError(
                status: .badRequest,
                code: "InvalidRequest",
                message: "timezone must be a valid IANA timezone identifier"
            )
        }
    }
}

private struct AnalyticsQueryParameters {
    let from: Date
    let to: Date
    let bucket: EngagementBucket
    let timezone: String
    let accountDids: [String]

    init(request: Request) throws {
        let allowed = Set(["from", "to", "bucket", "timezone", "accountDids"])
        var singleValues: [String: String] = [:]
        var accountDids: [String] = []
        for (rawKey, rawValue) in request.uri.queryParameters {
            let key = String(rawKey)
            let value = String(rawValue)
            guard allowed.contains(key) else {
                throw APIError(status: .badRequest, code: "InvalidRequest", message: "Unknown query parameter: \(key)")
            }
            if key == "accountDids" {
                guard value.hasPrefix("did:"), value.utf8.count <= 2_048, accountDids.count < 100 else {
                    throw APIError(status: .badRequest, code: "InvalidRequest", message: "accountDids contains an invalid DID")
                }
                accountDids.append(value)
            } else {
                guard singleValues.updateValue(value, forKey: key) == nil else {
                    throw APIError(status: .badRequest, code: "InvalidRequest", message: "Query parameter \(key) must not be repeated")
                }
            }
        }
        guard let fromValue = singleValues["from"], let from = Timestamp.date(from: fromValue),
              let toValue = singleValues["to"], let to = Timestamp.date(from: toValue),
              let bucketValue = singleValues["bucket"], let bucket = EngagementBucket(rawValue: bucketValue),
              let timezone = singleValues["timezone"], !timezone.isEmpty, timezone.utf8.count <= 128
        else {
            throw APIError(
                status: .badRequest,
                code: "InvalidRequest",
                message: "from, to, bucket, and timezone are required"
            )
        }
        self.from = from
        self.to = to
        self.bucket = bucket
        self.timezone = timezone
        var seen = Set<String>()
        self.accountDids = accountDids.filter { seen.insert($0).inserted }
    }
}
