import Foundation
import Hummingbird
import HTTPTypes
import SkejKit

func makeTestServices() async throws -> SkejServices {
    let store = try SQLiteStore(path: ":memory:")
    try await store.migrate()
    return SkejServices(
        config: AppConfig(
            port: 8080,
            environment: .test,
            publicOrigin: "http://localhost",
            sqlitePath: ":memory:",
            workerEnabled: false
        ),
        store: store,
        pdsClient: InMemoryPDSClient()
    )
}

func makeRecord(scheduledFor: String = "2026-01-01T11:00:00Z") -> SkejScheduleRecord {
    SkejScheduleRecord(
        type: "at.skej.schedule",
        scheduledFor: scheduledFor,
        createdAt: "2026-01-01T10:00:00Z",
        updatedAt: "2026-01-01T10:00:00Z",
        status: .scheduled,
        lastError: nil,
        posts: [
            PostPlan(
                text: "hello from skej",
                facets: nil,
                reply: nil,
                embed: nil,
                langs: ["en"],
                labels: nil,
                tags: ["skej"]
            ),
        ]
    )
}

func encodedBody<T: Encodable>(_ value: T) throws -> ByteBuffer {
    var buffer = ByteBuffer()
    buffer.writeBytes(try JSONEncoder().encode(value))
    return buffer
}

func didHeaders(_ did: String) -> HTTPFields {
    var fields = HTTPFields()
    fields[HTTPField.Name("X-Skej-DID")!] = did
    return fields
}
