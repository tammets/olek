/// Forward-only schema migrations, tracked with SQLite's `user_version`.
/// Never edit a shipped migration; append a new one instead.
enum Migrations {
    static let all: [String] = [
        // v1
        """
        CREATE TABLE session (
            id            INTEGER PRIMARY KEY,
            start_at      INTEGER NOT NULL,
            end_at        INTEGER,
            heartbeat_at  INTEGER,
            note          TEXT,
            created_at    INTEGER NOT NULL,
            updated_at    INTEGER NOT NULL,
            CHECK (end_at IS NULL OR end_at > start_at)
        );
        CREATE UNIQUE INDEX session_single_open ON session(end_at) WHERE end_at IS NULL;
        CREATE INDEX session_start ON session(start_at);

        CREATE TABLE day_override (
            date              TEXT PRIMARY KEY,
            kind              TEXT NOT NULL,
            expected_minutes  INTEGER,
            note              TEXT,
            created_at        INTEGER NOT NULL,
            updated_at        INTEGER NOT NULL
        );

        CREATE TABLE setting (
            key    TEXT PRIMARY KEY,
            value  TEXT NOT NULL
        );
        """,
    ]

    static var latestVersion: Int { all.count }

    static func migrate(_ db: Database) throws {
        let current = try db.userVersion()
        guard current <= latestVersion else {
            throw DatabaseError.newerSchema(found: current, supported: latestVersion)
        }
        for (index, sql) in all.enumerated() where index >= current {
            try db.transaction {
                try db.execute(sql)
                try db.execute("PRAGMA user_version = \(index + 1)")
            }
        }
    }
}
