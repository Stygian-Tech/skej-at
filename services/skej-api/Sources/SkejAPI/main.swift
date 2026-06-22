import Foundation
import Logging
import SkejKit

@main
struct SkejAPIApp {
    static func main() async throws {
        let config = AppConfig.load()
        let logger = Logger(label: "skej-api")
        let store = try SQLiteStore(path: config.sqlitePath)
        try await store.migrate()
        let services = SkejServices(
            config: config,
            store: store,
            pdsClient: InMemoryPDSClient()
        )
        try await SkejBootstrap.run(config: config, services: services, logger: logger)
    }
}

