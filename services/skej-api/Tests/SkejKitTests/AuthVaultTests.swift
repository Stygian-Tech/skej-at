import Foundation
import SkejKit
import Testing

@Suite struct AuthVaultTests {
    @Test func liveStorageRequiresKey() throws {
        #expect(throws: (any Error).self) {
            try SQLiteStore(path: ":memory:", authEncryptionSecret: nil, requiresAuthEncryption: true)
        }
    }

    @Test func legacyBackfillPreservesSessionsAndScrubsDatabaseAndWAL() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("vault.sqlite").path
        let legacy = try SQLiteStore(path: path, authEncryptionSecret: nil)
        try await legacy.migrate()
        let token = "private-refresh-token-legacy-unique"
        let key = "private-dpop-key-legacy-unique"
        let verifier = "private-pkce-verifier-legacy-unique"
        let session = OAuthSessionRecord(did: "did:plc:test", handle: nil, tokenJSON: token, dpopKeyJSON: key)
        try await legacy.createOAuthSession(session, now: "2026-01-01T00:00:00Z")
        try await legacy.createOAuthState(state: "state", handle: "test", pkceVerifier: verifier, nonce: "nonce", dpopKeyJSON: key, expiresAt: "2099-01-01T00:00:00Z")
        let encrypted = try SQLiteStore(path: path, authEncryptionSecret: "test-vault-key", requiresAuthEncryption: true)
        try await encrypted.migrate()
        #expect(try await encrypted.oauthSession(did: session.did) == session)
        // Repeat migration is idempotent and validates the configured key.
        try await encrypted.migrate()
        for suffix in ["", "-wal"] {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path + suffix)) {
                for secret in [token, key, verifier] { #expect(data.range(of: Data(secret.utf8)) == nil) }
            }
        }
        let wrong = try SQLiteStore(path: path, authEncryptionSecret: "wrong-key")
        await #expect(throws: (any Error).self) { try await wrong.migrate() }
        let missing = try SQLiteStore(path: path, authEncryptionSecret: nil)
        await #expect(throws: (any Error).self) { try await missing.migrate() }
        #expect(try await encrypted.oauthSession(did: session.did) == session)
        let state = try await encrypted.consumeOAuthState(state: "state", now: "2026-01-01T00:00:00Z")
        #expect(state?.pkceVerifier == verifier)
        #expect(state?.dpopKeyJSON == key)
    }

    @Test func newPendingSecretsAreEncryptedAndRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("vault.sqlite").path
        let store = try SQLiteStore(path: path, authEncryptionSecret: "test-key")
        try await store.migrate()
        try await store.createOAuthState(state: "new", handle: "handle", pkceVerifier: "private-new-pkce", nonce: "nonce", dpopKeyJSON: "private-new-key", expiresAt: "2099-01-01T00:00:00Z")
        for suffix in ["", "-wal"] {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path + suffix)) {
                #expect(data.range(of: Data("private-new-pkce".utf8)) == nil)
                #expect(data.range(of: Data("private-new-key".utf8)) == nil)
            }
        }
        let state = try await store.consumeOAuthState(state: "new", now: "2026-01-01T00:00:00Z")
        #expect(state?.pkceVerifier == "private-new-pkce")
        #expect(state?.dpopKeyJSON == "private-new-key")
    }
}
