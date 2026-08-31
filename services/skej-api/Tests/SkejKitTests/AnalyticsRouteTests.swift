import Foundation
import Hummingbird
import HummingbirdTesting
import SkejGateway
import SkejKit
import Testing

@Suite("Analytics XRPC")
struct AnalyticsRouteTests {
    @Test("filters requested accounts through canonical viewer access")
    func accountFilters() async throws {
        let services = try await makeTestServices()
        let now = "2026-08-30T00:00:00Z"
        for account in [
            ManagedAccount(did: "did:plc:test", handle: "test.example"),
            ManagedAccount(did: "did:plc:brand", handle: "brand.example"),
        ] {
            try await services.store.upsertManagedAccount(account, now: now)
        }
        try await services.store.upsertViewerAccount(ViewerAccountAccess(
            viewerDid: "did:plc:test",
            accountDid: "did:plc:brand",
            accessKind: .connected,
            capabilities: BrandCapability.allCases,
            createdAt: now,
            updatedAt: now
        ))
        let app = Application(router: buildRouter(services: services))
        let base = "/xrpc/\(SkejXRPCMethod.getEngagement.nsid)?from=2026-08-01T00:00:00Z&to=2026-08-31T00:00:00Z&bucket=day&timezone=UTC"

        try await app.test(.router) { client in
            try await client.execute(
                uri: base + "&accountDids=did:plc:test&accountDids=did:plc:brand",
                method: .get,
                headers: didHeaders("did:plc:test")
            ) { response in
                #expect(response.status == .ok)
                let output = try JSONDecoder().decode(GetEngagementOutput.self, from: Data(buffer: response.body))
                #expect(Set(output.accounts.map(\.account.did)) == ["did:plc:test", "did:plc:brand"])
            }

            try await client.execute(
                uri: base + "&accountDids=did:plc:unauthorized",
                method: .get,
                headers: didHeaders("did:plc:test")
            ) { response in
                #expect(response.status == .forbidden)
            }
        }
    }

    @Test("is absent when Pro features are disabled")
    func proGate() async throws {
        let services = try await makeTestServices(proFeaturesEnabled: false)
        let app = Application(router: buildRouter(services: services))
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/xrpc/at.skej.analytics.getEngagement?from=2026-08-01T00:00:00Z&to=2026-08-31T00:00:00Z&bucket=day&timezone=UTC",
                method: .get,
                headers: didHeaders("did:plc:test")
            ) { response in
                #expect(response.status == .notFound)
            }
        }
    }
}
