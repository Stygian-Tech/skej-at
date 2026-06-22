import Foundation

public struct SkejServices: Sendable {
    public let config: AppConfig
    public let store: SQLiteStore
    public let pdsClient: any PDSClient
    public let oauthClient: any OAuthClient

    public init(config: AppConfig, store: SQLiteStore, pdsClient: any PDSClient, oauthClient: any OAuthClient) {
        self.config = config
        self.store = store
        self.pdsClient = pdsClient
        self.oauthClient = oauthClient
    }
}
