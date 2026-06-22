@preconcurrency import SQLite3
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

public enum SQLiteStoreError: Error, Equatable {
    case open(message: String)
    case statement(message: String)
}
