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
        let pdsClient: any PDSClient
        let oauthClient: any OAuthClient
        if config.liveATProtoEnabled {
            pdsClient = ATProtoPDSClient(
                store: store,
                clientID: "\(config.publicOrigin)/oauth/client-metadata.json"
            )
            oauthClient = ATProtoOAuthClient(config: config)
        } else {
            pdsClient = SQLitePDSClient(store: store)
            oauthClient = LocalOAuthClient()
        }
        let services = SkejServices(
            config: config,
            store: store,
            pdsClient: pdsClient,
            oauthClient: oauthClient
        )
        try await SkejBootstrap.run(config: config, services: services, logger: logger)
    }
}
