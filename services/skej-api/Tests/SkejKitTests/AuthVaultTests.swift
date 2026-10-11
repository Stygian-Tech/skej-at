import Foundation
import SkejKit
import Testing
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

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

    @Test func interruptedCleanupRetriesOnReopenWithoutLosingSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("vault.sqlite").path
        let legacy = try SQLiteStore(path: path, authEncryptionSecret: nil)
        try await legacy.migrate()
        let session = OAuthSessionRecord(did: "did:plc:retry", handle: nil, tokenJSON: "private-interrupted-token", dpopKeyJSON: "private-interrupted-key")
        try await legacy.createOAuthSession(session, now: "2026-01-01T00:00:00Z")
        var reader: OpaquePointer?
        #expect(sqlite3_open(path, &reader) == SQLITE_OK)
        defer { sqlite3_close(reader) }
        // Hold a historical snapshot so the post-commit checkpoint cannot truncate.
        #expect(sqlite3_exec(reader, "BEGIN; SELECT * FROM oauth_sessions", nil, nil, nil) == SQLITE_OK)
        let upgrade = try SQLiteStore(path: path, authEncryptionSecret: "retry-key")
        await #expect(throws: (any Error).self) { try await upgrade.migrate() }
        #expect(sqlite3_exec(reader, "COMMIT", nil, nil, nil) == SQLITE_OK)
        let reopened = try SQLiteStore(path: path, authEncryptionSecret: "retry-key")
        try await reopened.migrate()
        #expect(try await reopened.oauthSession(did: session.did) == session)
        for suffix in ["", "-wal"] {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path + suffix)) {
                #expect(data.range(of: Data(session.tokenJSON.utf8)) == nil)
                #expect(data.range(of: Data(session.dpopKeyJSON.utf8)) == nil)
            }
        }
    }

    @Test func corruptCiphertextPreventsPartialLegacyBackfill() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("vault.sqlite").path
        let legacy = try SQLiteStore(path: path, authEncryptionSecret: nil)
        try await legacy.migrate()
        let good = OAuthSessionRecord(did: "did:plc:good", handle: nil, tokenJSON: "legacy-token", dpopKeyJSON: "legacy-key")
        try await legacy.createOAuthSession(good, now: "2026-01-01T00:00:00Z")
        try await legacy.createOAuthSession(OAuthSessionRecord(did: "did:plc:corrupt", handle: nil, tokenJSON: "aesgcm:v1:invalid-ciphertext", dpopKeyJSON: "legacy-key"), now: "2026-01-01T00:00:00Z")
        let upgrade = try SQLiteStore(path: path, authEncryptionSecret: "upgrade-key")
        await #expect(throws: (any Error).self) { try await upgrade.migrate() }
        // A keyless legacy reader could not decode this if a partial upgrade occurred.
        #expect(try await legacy.oauthSession(did: good.did) == good)
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
