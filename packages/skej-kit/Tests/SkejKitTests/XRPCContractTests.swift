import Foundation
@testable import SkejKit
import Testing

@Test func xrpcDescriptorsHaveCanonicalVerbsAndUniqueNSIDs() {
    #expect(SkejXRPCMethod.all.count == 29)
    #expect(Set(SkejXRPCMethod.all.map(\.nsid)).count == SkejXRPCMethod.all.count)
    #expect(SkejXRPCMethod.listSchedules.verb == "GET")
    #expect(SkejXRPCMethod.createSchedule.verb == "POST")
    #expect(SkejXRPCMethod.createSchedule.nsid == "at.skej.schedule.create")
    #expect(SkejXRPCMethod.seedDevelopment.requiresAuthentication == false)
}

@Test func scheduleRecordsPreserveUnknownLexiconFieldsAcrossMutation() throws {
    let data = Data(#"{"$type":"at.skej.schedule","scheduledAt":"2026-08-15T12:00:00Z","timezonePolicy":"absolute_utc","createdAt":"2026-08-15T11:00:00Z","updatedAt":"2026-08-15T11:00:00Z","status":"scheduled","recordType":"app.bsky.feed.post","publishRkey":"3m123456789ab","retry":{"attemptCount":0},"posts":[],"future":{"version":2}}"#.utf8)
    var record = try JSONDecoder().decode(SkejScheduleRecord.self, from: data)
    record.status = .canceled

    let encoded = try JSONEncoder().encode(record)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect((object["future"] as? [String: Int])?["version"] == 2)
    #expect(object["status"] as? String == "canceled")
}

private actor CapturingTransport: SkejXRPCTransport {
    struct Request: Sendable {
        let method: SkejXRPCMethod
        let parameters: [URLQueryItem]
        let body: Data?
    }

    private var request: Request?
    let response: Data

    init(response: Data) {
        self.response = response
    }

    func send(method: SkejXRPCMethod, parameters: [URLQueryItem], body: Data?) async throws -> Data {
        request = Request(method: method, parameters: parameters, body: body)
        return response
    }

    func captured() -> Request? { request }
}

@Test func clientAddressesTopLevelXRPCScheduleQuery() async throws {
    let transport = CapturingTransport(response: Data(#"{"records":[]}"#.utf8))
    let client = SkejXRPCClient(transport: transport)

    let output = try await client.listSchedules(.init(accountDid: "did:plc:test"))

    #expect(output.records.isEmpty)
    let request = await transport.captured()
    #expect(request?.method == .listSchedules)
    #expect(request?.parameters == [URLQueryItem(name: "accountDid", value: "did:plc:test")])
    #expect(request?.body == nil)
}
