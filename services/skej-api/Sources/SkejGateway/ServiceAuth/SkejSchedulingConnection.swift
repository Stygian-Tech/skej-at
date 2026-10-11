import Foundation
import SkejKit

/// A delegation JWT cannot replace the scheduler's independently enrolled OAuth grant.
enum SkejSchedulingConnection {
    static func require(did: String, services: SkejServices) async throws -> ManagedAccount {
        guard let stored = try await services.store.oauthSession(did: did),
              let token = try? JSONDecoder().decode(ATProtoTokenPayload.self, from: Data(stored.tokenJSON.utf8)),
              token.sub == did, !token.accessToken.isEmpty, token.accessToken != "local",
              token.refreshToken?.isEmpty == false, token.tokenType.lowercased() == "dpop",
              services.config.network.allowsPDS(token.pdsEndpoint),
              services.config.network.allowsOAuthEndpoint(token.tokenEndpoint),
              (try? DPoPKey(json: stored.dpopKeyJSON)) != nil,
              let account = try await services.store.managedAccount(did: did), account.status == .active
        else {
            throw APIError(status: .conflict, code: "AccountNeedsReauth", message: "Connect this account in Skej before scheduling")
        }
        try await services.pdsClient.verifySchedulingConnection(did: did)
        return account
    }
}
