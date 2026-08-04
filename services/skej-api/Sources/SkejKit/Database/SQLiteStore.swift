#if canImport(SQLite3)
@preconcurrency import SQLite3
#elseif canImport(CSQLite)
@preconcurrency import CSQLite
#endif
@preconcurrency import Crypto
import Foundation

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public actor SQLiteStore {
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(path: String) throws {
        if path != ":memory:" {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw SQLiteStoreError.open(message: "Could not open SQLite database")
        }
    }

    public func migrate() throws {
        try exec("PRAGMA foreign_keys = ON")
        try exec("PRAGMA journal_mode = WAL")
        try exec(
            """
            CREATE TABLE IF NOT EXISTS oauth_states (
                state TEXT PRIMARY KEY,
                handle TEXT NOT NULL,
                pkce_verifier TEXT NOT NULL,
                nonce TEXT NOT NULL,
                auth_server TEXT,
                token_endpoint TEXT,
                pds_endpoint TEXT,
                dpop_key_json TEXT,
                expires_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS oauth_sessions (
                did TEXT PRIMARY KEY,
                handle TEXT,
                token_json TEXT NOT NULL,
                dpop_key_json TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS web_sessions (
                session_id TEXT PRIMARY KEY,
                did TEXT NOT NULL,
                handle TEXT,
                display_name TEXT,
                avatar TEXT,
                expires_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS scheduled_jobs (
                did TEXT NOT NULL,
                rkey TEXT NOT NULL,
                scheduled_for TEXT NOT NULL,
                scheduled_at TEXT,
                status TEXT NOT NULL,
                attempts INTEGER NOT NULL DEFAULT 0,
                locked_until TEXT,
                last_error TEXT,
                next_attempt_at TEXT,
                last_attempt_at TEXT,
                publish_rkey TEXT,
                record_type TEXT,
                published_uri TEXT,
                published_cid TEXT,
                depends_on_schedule_uri TEXT,
                parent_published_uri TEXT,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (did, rkey)
            );
            CREATE INDEX IF NOT EXISTS scheduled_jobs_due_idx
                ON scheduled_jobs (status, scheduled_at, scheduled_for);
            CREATE TABLE IF NOT EXISTS pds_schedule_records (
                did TEXT NOT NULL,
                rkey TEXT NOT NULL,
                record_json TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (did, rkey)
            );
            CREATE TABLE IF NOT EXISTS pds_protocol_records (
                did TEXT NOT NULL,
                collection TEXT NOT NULL,
                rkey TEXT NOT NULL,
                record_json TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (did, collection, rkey)
            );
            CREATE TABLE IF NOT EXISTS managed_accounts (
                did TEXT PRIMARY KEY,
                handle TEXT,
                display_name TEXT,
                avatar TEXT,
                pds_endpoint TEXT,
                status TEXT NOT NULL,
                is_default INTEGER NOT NULL DEFAULT 0,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS audit_events (
                id TEXT PRIMARY KEY,
                did TEXT NOT NULL,
                schedule_rkey TEXT,
                action TEXT NOT NULL,
                message TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            """
        )
        try addColumnIfMissing(table: "oauth_states", column: "auth_server", definition: "TEXT")
        try addColumnIfMissing(table: "oauth_states", column: "token_endpoint", definition: "TEXT")
        try addColumnIfMissing(table: "oauth_states", column: "pds_endpoint", definition: "TEXT")
        try addColumnIfMissing(table: "oauth_states", column: "dpop_key_json", definition: "TEXT")
        try addColumnIfMissing(table: "web_sessions", column: "display_name", definition: "TEXT")
        try addColumnIfMissing(table: "web_sessions", column: "avatar", definition: "TEXT")
        try addColumnIfMissing(table: "scheduled_jobs", column: "scheduled_at", definition: "TEXT")
        try addColumnIfMissing(table: "scheduled_jobs", column: "next_attempt_at", definition: "TEXT")
        try addColumnIfMissing(table: "scheduled_jobs", column: "last_attempt_at", definition: "TEXT")
        try addColumnIfMissing(table: "scheduled_jobs", column: "publish_rkey", definition: "TEXT")
        try addColumnIfMissing(table: "scheduled_jobs", column: "record_type", definition: "TEXT")
        try addColumnIfMissing(table: "scheduled_jobs", column: "depends_on_schedule_uri", definition: "TEXT")
        try addColumnIfMissing(table: "scheduled_jobs", column: "parent_published_uri", definition: "TEXT")
    }

    public func createOAuthState(
        state: String,
        handle: String,
        pkceVerifier: String,
        nonce: String,
        authServer: String? = nil,
        tokenEndpoint: String? = nil,
        pdsEndpoint: String? = nil,
        dpopKeyJSON: String? = nil,
        expiresAt: String
    ) throws {
        try run(
            """
            INSERT OR REPLACE INTO oauth_states
                (state, handle, pkce_verifier, nonce, auth_server, token_endpoint, pds_endpoint, dpop_key_json, expires_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [state, handle, pkceVerifier, nonce, authServer, tokenEndpoint, pdsEndpoint, dpopKeyJSON, expiresAt]
        )
    }

    public func consumeOAuthState(state: String, now: String) throws -> OAuthStateRecord? {
        let rows = try query(
            """
            SELECT state, handle, pkce_verifier, nonce, auth_server, token_endpoint, pds_endpoint, dpop_key_json, expires_at
            FROM oauth_states
            WHERE state = ? AND expires_at > ?
            LIMIT 1
            """,
            [state, now]
        )
        try run("DELETE FROM oauth_states WHERE state = ?", [state])
        guard let row = rows.first,
              let state = row["state"],
              let handle = row["handle"],
              let pkceVerifier = row["pkce_verifier"],
              let nonce = row["nonce"],
              let expiresAt = row["expires_at"]
        else { return nil }
        return OAuthStateRecord(
            state: state,
            handle: handle,
            pkceVerifier: pkceVerifier,
            nonce: nonce,
            authServer: row["auth_server"],
            tokenEndpoint: row["token_endpoint"],
            pdsEndpoint: row["pds_endpoint"],
            dpopKeyJSON: row["dpop_key_json"],
            expiresAt: expiresAt
        )
    }

    public func createWebSession(
        sessionID: String,
        did: String,
        handle: String?,
        displayName: String?,
        avatar: String?,
        expiresAt: String
    ) throws {
        try run(
            """
            INSERT OR REPLACE INTO web_sessions
                (session_id, did, handle, display_name, avatar, expires_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            [sessionID, did, handle, displayName, avatar, expiresAt]
        )
    }

    public func viewer(forSessionID sessionID: String, now: String) throws -> Viewer? {
        let rows = try query(
            "SELECT did, handle, display_name, avatar FROM web_sessions WHERE session_id = ? AND expires_at > ? LIMIT 1",
            [sessionID, now]
        )
        guard let row = rows.first else { return nil }
        return Viewer(
            did: row["did"] ?? "",
            handle: row["handle"],
            displayName: row["display_name"],
            avatar: row["avatar"]
        )
    }

    public func deleteWebSession(sessionID: String) throws {
        try run("DELETE FROM web_sessions WHERE session_id = ?", [sessionID])
    }

    public func createOAuthSession(_ session: OAuthSessionRecord, now: String) throws {
        try run(
            """
            INSERT OR REPLACE INTO oauth_sessions
                (did, handle, token_json, dpop_key_json, updated_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            [
                session.did,
                session.handle,
                try encryptAuthMaterial(session.tokenJSON),
                try encryptAuthMaterial(session.dpopKeyJSON),
                now,
            ]
        )
    }

    public func upsertManagedAccount(_ account: ManagedAccount, now: String) throws {
        if account.isDefault {
            try run("UPDATE managed_accounts SET is_default = 0 WHERE did != ?", [account.did])
        }
        try run(
            """
            INSERT INTO managed_accounts
                (did, handle, display_name, avatar, pds_endpoint, status, is_default, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(did) DO UPDATE SET
                handle = excluded.handle,
                display_name = excluded.display_name,
                avatar = excluded.avatar,
                pds_endpoint = excluded.pds_endpoint,
                status = excluded.status,
                is_default = CASE
                    WHEN excluded.is_default = 1 THEN 1
                    ELSE managed_accounts.is_default
                END,
                updated_at = excluded.updated_at
            """,
            [
                account.did,
                account.handle,
                account.displayName,
                account.avatar,
                account.pdsEndpoint,
                account.status.rawValue,
                account.isDefault ? "1" : "0",
                now,
            ]
        )
    }

    public func listManagedAccounts() throws -> [ManagedAccount] {
        try query(
            """
            SELECT did, handle, display_name, avatar, pds_endpoint, status, is_default
            FROM managed_accounts
            ORDER BY is_default DESC, handle ASC, did ASC
            """,
            []
        ).compactMap(account(from:))
    }

    public func managedAccount(did: String) throws -> ManagedAccount? {
        try query(
            """
            SELECT did, handle, display_name, avatar, pds_endpoint, status, is_default
            FROM managed_accounts
            WHERE did = ?
            LIMIT 1
            """,
            [did]
        ).first.flatMap(account(from:))
    }

    public func markAccountNeedsReauth(did: String, now: String) throws {
        try run(
            "UPDATE managed_accounts SET status = 'needs_reauth', updated_at = ? WHERE did = ?",
            [now, did]
        )
    }

    public func oauthSession(did: String) throws -> OAuthSessionRecord? {
        let rows = try query(
            "SELECT did, handle, token_json, dpop_key_json FROM oauth_sessions WHERE did = ? LIMIT 1",
            [did]
        )
        guard let row = rows.first,
              let did = row["did"],
              let tokenJSON = row["token_json"],
              let dpopKeyJSON = row["dpop_key_json"]
        else { return nil }
        return OAuthSessionRecord(
            did: did,
            handle: row["handle"],
            tokenJSON: try decryptAuthMaterial(tokenJSON),
            dpopKeyJSON: try decryptAuthMaterial(dpopKeyJSON)
        )
    }

    public func writeScheduleRecord(
        did: String,
        rkey: String,
        record: SkejScheduleRecord,
        now: String
    ) throws {
        try writeProtocolRecord(did: did, collection: "at.skej.schedule", rkey: rkey, record: record, now: now)
        let data = try encoder.encode(record)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SQLiteStoreError.statement(message: "Could not encode schedule record")
        }
        try run(
            """
            INSERT INTO pds_schedule_records (did, rkey, record_json, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(did, rkey) DO UPDATE SET
                record_json = excluded.record_json,
                updated_at = excluded.updated_at
            """,
            [did, rkey, json, now]
        )
    }

    public func scheduleRecord(did: String, rkey: String) throws -> SkejScheduleRecord? {
        if let record = try protocolRecord(did: did, collection: "at.skej.schedule", rkey: rkey, as: SkejScheduleRecord.self) {
            return record
        }
        let rows = try query(
            """
            SELECT record_json
            FROM pds_schedule_records
            WHERE did = ? AND rkey = ?
            LIMIT 1
            """,
            [did, rkey]
        )
        guard let json = rows.first?["record_json"],
              let data = json.data(using: .utf8)
        else { return nil }
        return try decoder.decode(SkejScheduleRecord.self, from: data)
    }

    public func listScheduleRecords(did: String) throws -> [String: SkejScheduleRecord] {
        let protocolRecords = try listProtocolRecords(did: did, collection: "at.skej.schedule", as: SkejScheduleRecord.self)
        if !protocolRecords.isEmpty { return protocolRecords }
        let rows = try query(
            """
            SELECT rkey, record_json
            FROM pds_schedule_records
            WHERE did = ?
            """,
            [did]
        )
        var records: [String: SkejScheduleRecord] = [:]
        for row in rows {
            guard let rkey = row["rkey"],
                  let json = row["record_json"],
                  let data = json.data(using: .utf8)
            else { continue }
            records[rkey] = try decoder.decode(SkejScheduleRecord.self, from: data)
        }
        return records
    }

    public func deleteScheduleRecord(did: String, rkey: String) throws {
        try run("DELETE FROM pds_protocol_records WHERE did = ? AND collection = ? AND rkey = ?", [did, "at.skej.schedule", rkey])
        try run("DELETE FROM pds_schedule_records WHERE did = ? AND rkey = ?", [did, rkey])
    }

    public func writeProtocolRecord<Value: Codable>(
        did: String,
        collection: String,
        rkey: String,
        record: Value,
        now: String
    ) throws {
        let data = try encoder.encode(record)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SQLiteStoreError.statement(message: "Could not encode protocol record")
        }
        try run(
            """
            INSERT INTO pds_protocol_records (did, collection, rkey, record_json, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(did, collection, rkey) DO UPDATE SET
                record_json = excluded.record_json,
                updated_at = excluded.updated_at
            """,
            [did, collection, rkey, json, now]
        )
    }

    public func protocolRecord<Value: Codable>(
        did: String,
        collection: String,
        rkey: String,
        as type: Value.Type
    ) throws -> Value? {
        let rows = try query(
            """
            SELECT record_json
            FROM pds_protocol_records
            WHERE did = ? AND collection = ? AND rkey = ?
            LIMIT 1
            """,
            [did, collection, rkey]
        )
        guard let json = rows.first?["record_json"],
              let data = json.data(using: .utf8)
        else { return nil }
        return try decoder.decode(type, from: data)
    }

    public func listProtocolRecords<Value: Codable>(
        did: String,
        collection: String,
        as type: Value.Type
    ) throws -> [String: Value] {
        let rows = try query(
            """
            SELECT rkey, record_json
            FROM pds_protocol_records
            WHERE did = ? AND collection = ?
            """,
            [did, collection]
        )
        var records: [String: Value] = [:]
        for row in rows {
            guard let rkey = row["rkey"],
                  let json = row["record_json"],
                  let data = json.data(using: .utf8)
            else { continue }
            records[rkey] = try decoder.decode(type, from: data)
        }
        return records
    }

    public func upsertScheduleJob(_ job: ScheduledJob, now: String) throws {
        let errorJSON = try job.lastError.map(encodeJSON)
        try run(
            """
            INSERT INTO scheduled_jobs
                (
                    did, rkey, scheduled_for, scheduled_at, status, attempts,
                    last_error, next_attempt_at, last_attempt_at, publish_rkey, record_type,
                    published_uri, published_cid, depends_on_schedule_uri, parent_published_uri, updated_at
                )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(did, rkey) DO UPDATE SET
                scheduled_for = excluded.scheduled_for,
                scheduled_at = excluded.scheduled_at,
                status = excluded.status,
                attempts = excluded.attempts,
                last_error = excluded.last_error,
                next_attempt_at = excluded.next_attempt_at,
                last_attempt_at = excluded.last_attempt_at,
                publish_rkey = excluded.publish_rkey,
                record_type = excluded.record_type,
                published_uri = excluded.published_uri,
                published_cid = excluded.published_cid,
                depends_on_schedule_uri = excluded.depends_on_schedule_uri,
                parent_published_uri = excluded.parent_published_uri,
                updated_at = excluded.updated_at
            """,
            [
                job.did,
                job.rkey,
                job.scheduledAt,
                job.scheduledAt,
                job.status.rawValue,
                String(job.attempts),
                errorJSON,
                job.nextAttemptAt,
                job.lastAttemptAt,
                job.publishRkey,
                job.recordType,
                job.publishedUri,
                job.publishedCid,
                job.dependsOnScheduleUri,
                job.parentPublishedUri,
                now,
            ]
        )
    }

    public func listScheduleJobs(did: String) throws -> [ScheduledJob] {
        try query(
            """
            SELECT did, rkey, COALESCE(scheduled_at, scheduled_for) AS scheduled_at, status, attempts,
                   last_error, next_attempt_at, last_attempt_at, publish_rkey, record_type,
                   published_uri, published_cid, depends_on_schedule_uri, parent_published_uri
            FROM scheduled_jobs
            WHERE did = ?
            ORDER BY scheduled_at ASC
            """,
            [did]
        ).compactMap(job(from:))
    }

    public func scheduleJob(did: String, rkey: String) throws -> ScheduledJob? {
        try query(
            """
            SELECT did, rkey, COALESCE(scheduled_at, scheduled_for) AS scheduled_at, status, attempts,
                   last_error, next_attempt_at, last_attempt_at, publish_rkey, record_type,
                   published_uri, published_cid, depends_on_schedule_uri, parent_published_uri
            FROM scheduled_jobs
            WHERE did = ? AND rkey = ?
            LIMIT 1
            """,
            [did, rkey]
        ).first.flatMap(job(from:))
    }

    public func deleteScheduleJob(did: String, rkey: String) throws {
        try run("DELETE FROM scheduled_jobs WHERE did = ? AND rkey = ?", [did, rkey])
    }

    public func claimDueJobs(now: String, limit: Int = 10) throws -> [ScheduledJob] {
        let jobs = try query(
            """
            SELECT did, rkey, COALESCE(scheduled_at, scheduled_for) AS scheduled_at, status, attempts,
                   last_error, next_attempt_at, last_attempt_at, publish_rkey, record_type,
                   published_uri, published_cid, depends_on_schedule_uri, parent_published_uri
            FROM scheduled_jobs
            WHERE status = 'scheduled'
                AND COALESCE(scheduled_at, scheduled_for) <= ?
                AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
            ORDER BY scheduled_at ASC
            LIMIT ?
            """,
            [now, now, String(limit)]
        ).compactMap(job(from:))

        for job in jobs {
            try run(
                """
                UPDATE scheduled_jobs
                SET status = 'publishing',
                    attempts = attempts + 1,
                    last_attempt_at = ?,
                    updated_at = ?
                WHERE did = ? AND rkey = ?
                """,
                [now, now, job.did, job.rkey]
            )
        }

        return jobs
    }

    public func blockedJobs() throws -> [ScheduledJob] {
        try query(
            """
            SELECT did, rkey, COALESCE(scheduled_at, scheduled_for) AS scheduled_at, status, attempts,
                   last_error, next_attempt_at, last_attempt_at, publish_rkey, record_type,
                   published_uri, published_cid, depends_on_schedule_uri, parent_published_uri
            FROM scheduled_jobs
            WHERE status = 'blocked'
            ORDER BY scheduled_at ASC
            """,
            []
        ).compactMap(job(from:))
    }

    public func markJobScheduled(
        did: String,
        rkey: String,
        parentPublishedUri: String?,
        now: String
    ) throws {
        try run(
            """
            UPDATE scheduled_jobs
            SET status = 'scheduled',
                parent_published_uri = ?,
                last_error = NULL,
                updated_at = ?
            WHERE did = ? AND rkey = ?
            """,
            [parentPublishedUri, now, did, rkey]
        )
    }

    public func markJobPublished(
        did: String,
        rkey: String,
        published: PublishedPost,
        now: String
    ) throws {
        try run(
            """
            UPDATE scheduled_jobs
            SET status = 'published',
                published_uri = ?,
                published_cid = ?,
                last_error = NULL,
                next_attempt_at = NULL,
                updated_at = ?
            WHERE did = ? AND rkey = ?
            """,
            [published.uri, published.cid, now, did, rkey]
        )
    }

    public func markJobFailed(did: String, rkey: String, error: ScheduleError, now: String) throws {
        try run(
            """
            UPDATE scheduled_jobs
            SET status = 'failed', last_error = ?, updated_at = ?
            WHERE did = ? AND rkey = ?
            """,
            [try encodeJSON(error), now, did, rkey]
        )
    }

    public func markJobRetry(
        did: String,
        rkey: String,
        error: ScheduleError,
        nextAttemptAt: String,
        now: String
    ) throws {
        try run(
            """
            UPDATE scheduled_jobs
            SET status = 'scheduled',
                last_error = ?,
                next_attempt_at = ?,
                updated_at = ?
            WHERE did = ? AND rkey = ?
            """,
            [try encodeJSON(error), nextAttemptAt, now, did, rkey]
        )
    }

    public func markJobBlocked(
        did: String,
        rkey: String,
        error: ScheduleError,
        now: String
    ) throws {
        try run(
            """
            UPDATE scheduled_jobs
            SET status = 'blocked',
                last_error = ?,
                updated_at = ?
            WHERE did = ? AND rkey = ?
            """,
            [try encodeJSON(error), now, did, rkey]
        )
    }

    public func insertAuditEvent(
        did: String,
        scheduleRkey: String?,
        action: String,
        message: String,
        now: String
    ) throws {
        try run(
            """
            INSERT INTO audit_events (id, did, schedule_rkey, action, message, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            [UUID().uuidString, did, scheduleRkey, action, message, now]
        )
    }

    public func listAuditEvents(did: String, limit: Int = 100) throws -> [AuditEvent] {
        try query(
            """
            SELECT id, did, schedule_rkey, action, message, created_at
            FROM audit_events
            WHERE did = ?
            ORDER BY created_at DESC
            LIMIT ?
            """,
            [did, String(limit)]
        ).compactMap(auditEvent(from:))
    }

    public func findPublishedSchedule(scheduleUri: String) throws -> (did: String, rkey: String, record: SkejScheduleRecord)? {
        guard let parsed = parseScheduleURI(scheduleUri) else { return nil }
        guard let record = try scheduleRecord(did: parsed.did, rkey: parsed.rkey),
              record.status == .published
        else { return nil }
        return (parsed.did, parsed.rkey, record)
    }

    public func updateParentPublishedUri(
        did: String,
        rkey: String,
        parentPublishedUri: String,
        now: String
    ) throws {
        try run(
            """
            UPDATE scheduled_jobs
            SET parent_published_uri = ?, updated_at = ?
            WHERE did = ? AND rkey = ?
            """,
            [parentPublishedUri, now, did, rkey]
        )
    }

    private func job(from row: [String: String]) -> ScheduledJob? {
        guard let did = row["did"],
              let rkey = row["rkey"],
              let scheduledAt = row["scheduled_at"],
              let rawStatus = row["status"],
              let status = scheduleStatus(from: rawStatus)
        else { return nil }
        return ScheduledJob(
            did: did,
            rkey: rkey,
            scheduledAt: scheduledAt,
            status: status,
            attempts: Int(row["attempts"] ?? "0") ?? 0,
            lastError: decodeJSON(ScheduleError.self, from: row["last_error"]),
            nextAttemptAt: row["next_attempt_at"],
            lastAttemptAt: row["last_attempt_at"],
            publishRkey: row["publish_rkey"] ?? rkey,
            recordType: row["record_type"] ?? "app.bsky.feed.post",
            publishedUri: row["published_uri"],
            publishedCid: row["published_cid"],
            dependsOnScheduleUri: row["depends_on_schedule_uri"],
            parentPublishedUri: row["parent_published_uri"]
        )
    }

    private func account(from row: [String: String]) -> ManagedAccount? {
        guard let did = row["did"],
              let rawStatus = row["status"],
              let status = ManagedAccountStatus(rawValue: rawStatus)
        else { return nil }
        return ManagedAccount(
            did: did,
            handle: row["handle"],
            displayName: row["display_name"],
            avatar: row["avatar"],
            pdsEndpoint: row["pds_endpoint"],
            status: status,
            isDefault: row["is_default"] == "1"
        )
    }

    private func auditEvent(from row: [String: String]) -> AuditEvent? {
        guard let id = row["id"],
              let did = row["did"],
              let action = row["action"],
              let message = row["message"],
              let createdAt = row["created_at"]
        else { return nil }
        return AuditEvent(
            id: id,
            did: did,
            scheduleRkey: row["schedule_rkey"],
            action: action,
            message: message,
            createdAt: createdAt
        )
    }

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "SQLite exec failed"
            sqlite3_free(error)
            throw SQLiteStoreError.statement(message: message)
        }
    }

    private func run(_ sql: String, _ values: [String?]) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteStoreError.statement(message: lastError())
        }
    }

    private func query(_ sql: String, _ values: [String?]) throws -> [[String: String]] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        var rows: [[String: String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                if let text = sqlite3_column_text(statement, index) {
                    row[name] = String(cString: text)
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.statement(message: lastError())
        }
        return statement
    }

    private func bind(_ values: [String?], to statement: OpaquePointer?) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            if let value {
                sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
            } else {
                sqlite3_bind_null(statement, index)
            }
        }
    }

    private func lastError() -> String {
        guard let message = sqlite3_errmsg(db) else { return "SQLite error" }
        return String(cString: message)
    }

    private func addColumnIfMissing(table: String, column: String, definition: String) throws {
        let columns = try query("PRAGMA table_info(\(table))", [])
        guard !columns.contains(where: { $0["name"] == column }) else { return }
        try exec("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        guard let string = String(data: try encoder.encode(value), encoding: .utf8) else {
            throw SQLiteStoreError.statement(message: "Could not encode JSON")
        }
        return string
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from string: String?) -> T? {
        guard let string,
              let data = string.data(using: .utf8)
        else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func scheduleStatus(from raw: String) -> ScheduleStatus? {
        raw == "cancelled" ? .canceled : ScheduleStatus(rawValue: raw)
    }

    private func parseScheduleURI(_ uri: String) -> (did: String, rkey: String)? {
        guard uri.starts(with: "at://") else { return nil }
        let parts = uri.dropFirst("at://".count).split(separator: "/").map(String.init)
        guard parts.count == 3,
              parts[1] == "at.skej.schedule"
        else { return nil }
        return (parts[0], parts[2])
    }

    private func encryptAuthMaterial(_ plaintext: String) throws -> String {
        guard let key = authEncryptionKey() else { return plaintext }
        let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: key)
        guard let combined = sealed.combined else {
            throw SQLiteStoreError.statement(message: "Could not encrypt auth material")
        }
        return "aesgcm:v1:\(combined.base64EncodedString())"
    }

    private func decryptAuthMaterial(_ stored: String) throws -> String {
        guard stored.starts(with: "aesgcm:v1:") else { return stored }
        guard let key = authEncryptionKey() else {
            throw SQLiteStoreError.statement(message: "SKEJ_AUTH_ENCRYPTION_KEY is required to decrypt auth material")
        }
        let encoded = String(stored.dropFirst("aesgcm:v1:".count))
        guard let data = Data(base64Encoded: encoded) else {
            throw SQLiteStoreError.statement(message: "Encrypted auth material is malformed")
        }
        let sealed = try AES.GCM.SealedBox(combined: data)
        let opened = try AES.GCM.open(sealed, using: key)
        guard let plaintext = String(data: opened, encoding: .utf8) else {
            throw SQLiteStoreError.statement(message: "Could not decode auth material")
        }
        return plaintext
    }

    private func authEncryptionKey() -> SymmetricKey? {
        guard let raw = ProcessInfo.processInfo.environment["SKEJ_AUTH_ENCRYPTION_KEY"],
              !raw.isEmpty
        else { return nil }
        return SymmetricKey(data: Data(SHA256.hash(data: Data(raw.utf8))))
    }
}

public struct OAuthStateRecord: Equatable, Sendable {
    public let state: String
    public let handle: String
    public let pkceVerifier: String
    public let nonce: String
    public let authServer: String?
    public let tokenEndpoint: String?
    public let pdsEndpoint: String?
    public let dpopKeyJSON: String?
    public let expiresAt: String
}

public struct OAuthSessionRecord: Equatable, Sendable {
    public let did: String
    public let handle: String?
    public let tokenJSON: String
    public let dpopKeyJSON: String

    public init(did: String, handle: String?, tokenJSON: String, dpopKeyJSON: String) {
        self.did = did
        self.handle = handle
        self.tokenJSON = tokenJSON
        self.dpopKeyJSON = dpopKeyJSON
    }
}

public enum SQLiteStoreError: Error, Equatable {
    case open(message: String)
    case statement(message: String)
}
