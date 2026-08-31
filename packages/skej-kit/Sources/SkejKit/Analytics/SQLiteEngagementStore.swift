import Foundation

extension SQLiteStore: EngagementStore {
    func migrateEngagement() throws {
        try exec(
            """
            CREATE TABLE IF NOT EXISTS engagement_account_state (
                account_did TEXT PRIMARY KEY,
                last_discovered_at TEXT,
                coverage_started_at TEXT,
                last_error TEXT
            );
            CREATE TABLE IF NOT EXISTS engagement_posts (
                post_uri TEXT PRIMARY KEY,
                account_did TEXT NOT NULL,
                indexed_at TEXT NOT NULL,
                schedule_rkey TEXT,
                first_observed_at TEXT NOT NULL,
                last_checked_at TEXT,
                availability TEXT NOT NULL DEFAULT 'available',
                last_error TEXT
            );
            CREATE INDEX IF NOT EXISTS engagement_posts_account_indexed_idx
                ON engagement_posts (account_did, indexed_at DESC);
            CREATE INDEX IF NOT EXISTS engagement_posts_due_idx
                ON engagement_posts (account_did, last_checked_at, indexed_at);
            CREATE TABLE IF NOT EXISTS engagement_snapshots (
                post_uri TEXT NOT NULL,
                observed_at TEXT NOT NULL,
                like_count INTEGER NOT NULL,
                repost_count INTEGER NOT NULL,
                reply_count INTEGER NOT NULL,
                quote_count INTEGER NOT NULL,
                bookmark_count INTEGER NOT NULL,
                complete INTEGER NOT NULL,
                PRIMARY KEY (post_uri, observed_at),
                FOREIGN KEY (post_uri) REFERENCES engagement_posts(post_uri) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS engagement_snapshots_observed_idx
                ON engagement_snapshots (observed_at, post_uri);
            """
        )
    }

    public func engagementCollectionState(accountDid: String) throws -> EngagementAccountCollectionState? {
        try query(
            """
            SELECT account_did, last_discovered_at, coverage_started_at, last_error
            FROM engagement_account_state WHERE account_did = ? LIMIT 1
            """,
            [accountDid]
        ).first.map(collectionState(from:))
    }

    public func setEngagementCollectionState(_ state: EngagementAccountCollectionState) throws {
        try run(
            """
            INSERT INTO engagement_account_state
                (account_did, last_discovered_at, coverage_started_at, last_error)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(account_did) DO UPDATE SET
                last_discovered_at = excluded.last_discovered_at,
                coverage_started_at = COALESCE(engagement_account_state.coverage_started_at, excluded.coverage_started_at),
                last_error = excluded.last_error
            """,
            [state.accountDid, state.lastDiscoveredAt, state.coverageStartedAt, state.lastError]
        )
    }

    public func knownEngagementPostURIs(accountDid: String) throws -> Set<String> {
        Set(try query(
            "SELECT post_uri FROM engagement_posts WHERE account_did = ?",
            [accountDid]
        ).compactMap { $0["post_uri"] })
    }

    public func upsertEngagementPosts(_ posts: [EngagementPostCandidate], observedAt: String) throws {
        guard !posts.isEmpty else { return }
        try transaction {
            for post in posts {
                try run(
                    """
                    INSERT INTO engagement_posts
                        (post_uri, account_did, indexed_at, schedule_rkey, first_observed_at, availability)
                    VALUES (?, ?, ?, ?, ?, 'available')
                    ON CONFLICT(post_uri) DO UPDATE SET
                        account_did = excluded.account_did,
                        indexed_at = excluded.indexed_at,
                        schedule_rkey = COALESCE(engagement_posts.schedule_rkey, excluded.schedule_rkey)
                    """,
                    [post.uri, post.accountDid, post.indexedAt, post.scheduleRkey, observedAt]
                )
            }
        }
    }

    public func correlateEngagementPosts(accountDid: String, schedulePosts: [String: String]) throws {
        guard !schedulePosts.isEmpty else { return }
        try transaction {
            for (postURI, scheduleRkey) in schedulePosts {
                try run(
                    """
                    UPDATE engagement_posts SET schedule_rkey = ?
                    WHERE account_did = ? AND post_uri = ?
                    """,
                    [scheduleRkey, accountDid, postURI]
                )
            }
        }
    }

    public func engagementPostsDue(
        accountDids: [String],
        now: String,
        recentCutoff: String,
        recentIntervalSeconds: Int,
        oldIntervalSeconds: Int
    ) throws -> [TrackedEngagementPost] {
        guard !accountDids.isEmpty, let nowDate = Timestamp.date(from: now) else { return [] }
        let recentDue = Timestamp.iso8601(nowDate.addingTimeInterval(TimeInterval(-recentIntervalSeconds)))
        let oldDue = Timestamp.iso8601(nowDate.addingTimeInterval(TimeInterval(-oldIntervalSeconds)))
        let placeholders = Array(repeating: "?", count: accountDids.count).joined(separator: ",")
        return try query(
            """
            SELECT post_uri, account_did, indexed_at, schedule_rkey, first_observed_at,
                   last_checked_at, availability, last_error
            FROM engagement_posts
            WHERE account_did IN (\(placeholders))
              AND (
                (indexed_at >= ? AND (last_checked_at IS NULL OR last_checked_at <= ?))
                OR
                (indexed_at < ? AND (last_checked_at IS NULL OR last_checked_at <= ?))
              )
            ORDER BY indexed_at DESC, post_uri ASC
            """,
            accountDids + [recentCutoff, recentDue, recentCutoff, oldDue]
        ).compactMap(trackedPost(from:))
    }

    public func recordEngagementBatch(
        posts: [TrackedEngagementPost],
        observations: [EngagementObservation],
        checkedAt: String
    ) throws {
        let observationByURI = Dictionary(uniqueKeysWithValues: observations.map { ($0.postURI, $0) })
        try transaction {
            for post in posts {
                guard let observation = observationByURI[post.uri] else {
                    try run(
                        """
                        UPDATE engagement_posts
                        SET last_checked_at = ?, availability = 'unavailable', last_error = 'post_unavailable'
                        WHERE post_uri = ?
                        """,
                        [checkedAt, post.uri]
                    )
                    continue
                }

                try run(
                    """
                    UPDATE engagement_posts
                    SET last_checked_at = ?, availability = 'available', last_error = NULL
                    WHERE post_uri = ?
                    """,
                    [checkedAt, post.uri]
                )
                let previous = try query(
                    """
                    SELECT like_count, repost_count, reply_count, quote_count, bookmark_count, complete
                    FROM engagement_snapshots WHERE post_uri = ?
                    ORDER BY observed_at DESC LIMIT 1
                    """,
                    [post.uri]
                ).first
                guard previous.map({ snapshotChanged(row: $0, observation: observation) }) ?? true else { continue }
                try run(
                    """
                    INSERT OR REPLACE INTO engagement_snapshots
                        (post_uri, observed_at, like_count, repost_count, reply_count,
                         quote_count, bookmark_count, complete)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        post.uri, observation.observedAt,
                        String(observation.counts.likes), String(observation.counts.reposts),
                        String(observation.counts.replies), String(observation.counts.quotes),
                        String(observation.counts.bookmarks), observation.complete ? "1" : "0",
                    ]
                )
            }
        }
    }

    public func trackedEngagementPosts(accountDids: [String]) throws -> [TrackedEngagementPost] {
        guard !accountDids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: accountDids.count).joined(separator: ",")
        return try query(
            """
            SELECT post_uri, account_did, indexed_at, schedule_rkey, first_observed_at,
                   last_checked_at, availability, last_error
            FROM engagement_posts WHERE account_did IN (\(placeholders))
            ORDER BY indexed_at DESC, post_uri ASC
            """,
            accountDids
        ).compactMap(trackedPost(from:))
    }

    public func engagementSnapshots(accountDids: [String], through: String) throws -> [EngagementSnapshot] {
        guard !accountDids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: accountDids.count).joined(separator: ",")
        return try query(
            """
            SELECT s.post_uri, p.account_did, s.observed_at, s.like_count, s.repost_count,
                   s.reply_count, s.quote_count, s.bookmark_count, s.complete
            FROM engagement_snapshots s
            JOIN engagement_posts p ON p.post_uri = s.post_uri
            WHERE p.account_did IN (\(placeholders)) AND s.observed_at <= ?
            ORDER BY s.observed_at ASC, s.post_uri ASC
            """,
            accountDids + [through]
        ).compactMap(snapshot(from:))
    }

    private func transaction(_ operation: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE")
        do {
            try operation()
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    private func collectionState(from row: [String: String]) -> EngagementAccountCollectionState {
        EngagementAccountCollectionState(
            accountDid: row["account_did"] ?? "",
            lastDiscoveredAt: row["last_discovered_at"],
            coverageStartedAt: row["coverage_started_at"],
            lastError: row["last_error"]
        )
    }

    private func trackedPost(from row: [String: String]) -> TrackedEngagementPost? {
        guard let uri = row["post_uri"], let accountDid = row["account_did"],
              let indexedAt = row["indexed_at"], let firstObservedAt = row["first_observed_at"]
        else { return nil }
        return TrackedEngagementPost(
            uri: uri,
            accountDid: accountDid,
            indexedAt: indexedAt,
            scheduleRkey: row["schedule_rkey"],
            firstObservedAt: firstObservedAt,
            lastCheckedAt: row["last_checked_at"],
            availability: row["availability"].flatMap(EngagementPostAvailability.init(rawValue:)) ?? .available,
            lastError: row["last_error"]
        )
    }

    private func snapshot(from row: [String: String]) -> EngagementSnapshot? {
        guard let uri = row["post_uri"], let accountDid = row["account_did"],
              let observedAt = row["observed_at"]
        else { return nil }
        return EngagementSnapshot(
            postURI: uri,
            accountDid: accountDid,
            observedAt: observedAt,
            counts: EngagementCounts(
                likes: Int(row["like_count"] ?? "0") ?? 0,
                reposts: Int(row["repost_count"] ?? "0") ?? 0,
                replies: Int(row["reply_count"] ?? "0") ?? 0,
                quotes: Int(row["quote_count"] ?? "0") ?? 0,
                bookmarks: Int(row["bookmark_count"] ?? "0") ?? 0
            ),
            complete: row["complete"] == "1"
        )
    }

    private func snapshotChanged(row: [String: String], observation: EngagementObservation) -> Bool {
        Int(row["like_count"] ?? "0") != observation.counts.likes ||
            Int(row["repost_count"] ?? "0") != observation.counts.reposts ||
            Int(row["reply_count"] ?? "0") != observation.counts.replies ||
            Int(row["quote_count"] ?? "0") != observation.counts.quotes ||
            Int(row["bookmark_count"] ?? "0") != observation.counts.bookmarks ||
            (row["complete"] == "1") != observation.complete
    }
}
