#if canImport(SQLite3)
@preconcurrency import SQLite3
#elseif canImport(CSQLite)
@preconcurrency import CSQLite
#endif
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
                expires_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS scheduled_jobs (
                did TEXT NOT NULL,
                rkey TEXT NOT NULL,
                scheduled_for TEXT NOT NULL,
                status TEXT NOT NULL,
                attempts INTEGER NOT NULL DEFAULT 0,
                locked_until TEXT,
                last_error TEXT,
                published_uri TEXT,
                published_cid TEXT,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (did, rkey)
            );
            CREATE INDEX IF NOT EXISTS scheduled_jobs_due_idx
                ON scheduled_jobs (status, scheduled_for);
            CREATE TABLE IF NOT EXISTS pds_schedule_records (
                did TEXT NOT NULL,
                rkey TEXT NOT NULL,
                record_json TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (did, rkey)
            );
            """
        )
    }

    public func createOAuthState(
        state: String,
        handle: String,
        pkceVerifier: String,
        nonce: String,
        expiresAt: String
    ) throws {
        try run(
            "INSERT OR REPLACE INTO oauth_states (state, handle, pkce_verifier, nonce, expires_at) VALUES (?, ?, ?, ?, ?)",
            [state, handle, pkceVerifier, nonce, expiresAt]
        )
    }

    public func consumeOAuthState(state: String, now: String) throws -> OAuthStateRecord? {
        let rows = try query(
            """
            SELECT state, handle, pkce_verifier, nonce, expires_at
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
            expiresAt: expiresAt
        )
    }

    public func createWebSession(
        sessionID: String,
        did: String,
        handle: String?,
        expiresAt: String
    ) throws {
        try run(
            "INSERT OR REPLACE INTO web_sessions (session_id, did, handle, expires_at) VALUES (?, ?, ?, ?)",
            [sessionID, did, handle, expiresAt]
        )
    }

    public func viewer(forSessionID sessionID: String, now: String) throws -> Viewer? {
        let rows = try query(
            "SELECT did, handle FROM web_sessions WHERE session_id = ? AND expires_at > ? LIMIT 1",
            [sessionID, now]
        )
        guard let row = rows.first else { return nil }
        return Viewer(did: row["did"] ?? "", handle: row["handle"], displayName: row["handle"])
    }

    public func deleteWebSession(sessionID: String) throws {
        try run("DELETE FROM web_sessions WHERE session_id = ?", [sessionID])
    }

    public func writeScheduleRecord(
        did: String,
        rkey: String,
        record: SkejScheduleRecord,
        now: String
    ) throws {
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
        try run("DELETE FROM pds_schedule_records WHERE did = ? AND rkey = ?", [did, rkey])
    }

    public func upsertScheduleJob(_ job: ScheduledJob, now: String) throws {
        try run(
            """
            INSERT INTO scheduled_jobs
                (did, rkey, scheduled_for, status, attempts, last_error, published_uri, published_cid, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(did, rkey) DO UPDATE SET
                scheduled_for = excluded.scheduled_for,
                status = excluded.status,
                last_error = excluded.last_error,
                published_uri = excluded.published_uri,
                published_cid = excluded.published_cid,
                updated_at = excluded.updated_at
            """,
            [
                job.did,
                job.rkey,
                job.scheduledFor,
                job.status.rawValue,
                String(job.attempts),
                job.lastError,
                job.publishedUri,
                job.publishedCid,
                now,
            ]
        )
    }

    public func listScheduleJobs(did: String) throws -> [ScheduledJob] {
        try query(
            """
            SELECT did, rkey, scheduled_for, status, attempts, last_error, published_uri, published_cid
            FROM scheduled_jobs
            WHERE did = ? AND status != 'cancelled'
            ORDER BY scheduled_for ASC
            """,
            [did]
        ).compactMap(job(from:))
    }

    public func scheduleJob(did: String, rkey: String) throws -> ScheduledJob? {
        try query(
            """
            SELECT did, rkey, scheduled_for, status, attempts, last_error, published_uri, published_cid
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
            SELECT did, rkey, scheduled_for, status, attempts, last_error, published_uri, published_cid
            FROM scheduled_jobs
            WHERE status = 'scheduled' AND scheduled_for <= ?
            ORDER BY scheduled_for ASC
            LIMIT ?
            """,
            [now, String(limit)]
        ).compactMap(job(from:))

        for job in jobs {
            try run(
                "UPDATE scheduled_jobs SET status = 'publishing', attempts = attempts + 1, updated_at = ? WHERE did = ? AND rkey = ?",
                [now, job.did, job.rkey]
            )
        }

        return jobs
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
            SET status = 'published', published_uri = ?, published_cid = ?, last_error = NULL, updated_at = ?
            WHERE did = ? AND rkey = ?
            """,
            [published.uri, published.cid, now, did, rkey]
        )
    }

    public func markJobFailed(did: String, rkey: String, error: String, now: String) throws {
        try run(
            """
            UPDATE scheduled_jobs
            SET status = 'failed', last_error = ?, updated_at = ?
            WHERE did = ? AND rkey = ?
            """,
            [error, now, did, rkey]
        )
    }

    private func job(from row: [String: String]) -> ScheduledJob? {
        guard let did = row["did"],
              let rkey = row["rkey"],
              let scheduledFor = row["scheduled_for"],
              let rawStatus = row["status"],
              let status = ScheduleStatus(rawValue: rawStatus)
        else { return nil }
        return ScheduledJob(
            did: did,
            rkey: rkey,
            scheduledFor: scheduledFor,
            status: status,
            attempts: Int(row["attempts"] ?? "0") ?? 0,
            lastError: row["last_error"],
            publishedUri: row["published_uri"],
            publishedCid: row["published_cid"]
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
}

public struct OAuthStateRecord: Equatable, Sendable {
    public let state: String
    public let handle: String
    public let pkceVerifier: String
    public let nonce: String
    public let expiresAt: String
}

public enum SQLiteStoreError: Error, Equatable {
    case open(message: String)
    case statement(message: String)
}
