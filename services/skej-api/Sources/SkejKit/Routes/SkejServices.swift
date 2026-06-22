import Foundation

public struct SkejServices: Sendable {
    public let config: AppConfig
    public let store: SQLiteStore
    public let pdsClient: any PDSClient

    public init(config: AppConfig, store: SQLiteStore, pdsClient: any PDSClient) {
        self.config = config
        self.store = store
        self.pdsClient = pdsClient
    }
}

