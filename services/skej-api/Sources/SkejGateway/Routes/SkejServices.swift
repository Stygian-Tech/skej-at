import Foundation
import SkejKit

public struct SkejServices: Sendable {
    public let serviceAuthVerifier: SkejServiceAuthVerifier
    public let config: AppConfig
    public let store: SQLiteStore
    public let pdsClient: any PDSClient
    public let oauthClient: any OAuthClient
    public let mentionSearchClient: any ActorMentionSearching

    var accountResolver: AccessibleAccountResolver {
        AccessibleAccountResolver(store: store, pdsClient: pdsClient)
    }

    var entitlementResolver: ProEntitlementResolver {
        ProEntitlementResolver(config: config, store: store)
    }

    public init(
        config: AppConfig,
        store: SQLiteStore,
        pdsClient: any PDSClient,
        oauthClient: any OAuthClient,
        mentionSearchClient: any ActorMentionSearching = PublicActorMentionSearchClient(),
        serviceAuthVerifier: SkejServiceAuthVerifier? = nil
    ) {
        self.serviceAuthVerifier = serviceAuthVerifier ?? SkejServiceAuthVerifier(network: config.network)
        self.config = config
        self.store = store
        self.pdsClient = pdsClient
        self.oauthClient = oauthClient
        self.mentionSearchClient = mentionSearchClient
    }
}
