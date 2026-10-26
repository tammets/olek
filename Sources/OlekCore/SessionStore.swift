import Foundation

/// The single point of access to the database.
///
/// Calls are synchronous: each write is a tiny transaction, and being synchronous lets the app
/// persist state inside sleep and termination callbacks, which do not wait for async work.
public final class SessionStore: @unchecked Sendable {
    // @unchecked is sound because every use of `db` happens while holding `lock`.
    private let db: Database
    private let lock = NSLock()

    public convenience init(url: URL, now: Date = Date()) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try self.init(path: url.path, now: now)
    }

    public static func inMemory(now: Date = Date()) throws -> SessionStore {
        try SessionStore(path: ":memory:", now: now)
    }

    init(path: String, now: Date) throws {
        db = try Database(path: path)
        try Migrations.migrate(db)
        try db.run(
            "INSERT OR IGNORE INTO setting (key, value) VALUES ('first_launch_at', ?)",
            [.text(String(now.unixSeconds))]
        )
    }

    // MARK: Reading

    public func openSession() throws -> Session? {
        try locked { try fetchOpen() }
    }

    public func session(id: Int64) throws -> Session? {
        try locked { try fetch(id: id) }
    }

    /// Sessions that intersect `interval`. Open sessions are included if they started before its end.
    public func sessions(overlapping interval: DateInterval) throws -> [Session] {
        try locked {
            try db.query(
                "\(Self.select) WHERE start_at < ? AND (end_at IS NULL OR end_at > ?) ORDER BY start_at",
                [.int(interval.end.unixSeconds), .int(interval.start.unixSeconds)],
                Self.session
            )
        }
    }

    public func firstLaunchDate() throws -> Date? {
        try locked {
            try db.query("SELECT value FROM setting WHERE key = 'first_launch_at'") { row in
                row.text(0).flatMap(Int64.init).map(Date.init(unixSeconds:))
            }.first ?? nil
        }
    }

    // MARK: Tracking

    @discardableResult
    public func start(at time: Date, now: Date) throws -> Session {
        try locked {
            try db.transaction {
                if try fetchOpen() != nil { throw SessionError.alreadyRunning }
                try validate(id: nil, start: time, end: nil, now: now)
                let start = time.unixSeconds
                let stamp = now.unixSeconds
                try db.run(
                    """
                    INSERT INTO session (start_at, end_at, heartbeat_at, created_at, updated_at)
                    VALUES (?, NULL, ?, ?, ?)
                    """,
                    [.int(start), .int(stamp), .int(stamp), .int(stamp)]
                )
                return Session(
                    id: db.lastInsertRowID,
                    start: Date(unixSeconds: start),
                    heartbeat: Date(unixSeconds: stamp)
                )
            }
        }
    }

    /// Stops the open session at `time`, which may be in the past.
    @discardableResult
    public func stop(at time: Date, now: Date) throws -> StopResult {
        try locked {
            try db.transaction {
                guard var session = try fetchOpen() else { throw SessionError.notRunning }
                guard time.unixSeconds <= now.unixSeconds else { throw SessionError.inFuture }
                let end = Date(unixSeconds: time.unixSeconds)
                if end <= session.start {
                    try db.run("DELETE FROM session WHERE id = ?", [.int(session.id)])
                    return .discarded(session)
                }
                try db.run(
                    "UPDATE session SET end_at = ?, updated_at = ? WHERE id = ?",
                    [.int(end.unixSeconds), .int(now.unixSeconds), .int(session.id)]
                )
                session.end = end
                return .stopped(session)
            }
        }
    }

    public func recordHeartbeat(at time: Date) throws {
        try locked {
            try db.run(
                "UPDATE session SET heartbeat_at = ? WHERE end_at IS NULL",
                [.int(time.unixSeconds)]
            )
        }
    }

    // MARK: Editing

    /// Saves new start, end, and note values for an existing session after validating them.
    /// Setting `end` to `nil` reopens the session.
    @discardableResult
    public func update(_ session: Session, now: Date) throws -> Session {
        try locked {
            try db.transaction {
                guard try fetch(id: session.id) != nil else { throw SessionError.notFound }
                try validate(id: session.id, start: session.start, end: session.end, now: now)
                let stamp = now.unixSeconds
                try db.run(
                    """
                    UPDATE session
                    SET start_at = ?, end_at = ?, note = ?, updated_at = ?,
                        heartbeat_at = CASE WHEN ? IS NULL THEN ? ELSE heartbeat_at END
                    WHERE id = ?
                    """,
                    [
                        .int(session.start.unixSeconds),
                        session.end.map { .int($0.unixSeconds) } ?? .null,
                        session.note.map { .text($0) } ?? .null,
                        .int(stamp),
                        session.end.map { .int($0.unixSeconds) } ?? .null,
                        .int(stamp),
                        .int(session.id),
                    ]
                )
                guard let saved = try fetch(id: session.id) else { throw SessionError.notFound }
                return saved
            }
        }
    }

    /// Reopens a stopped session so it runs until now again.
    @discardableResult
    public func reopen(id: Int64, now: Date) throws -> Session {
        guard var session = try self.session(id: id) else { throw SessionError.notFound }
        session.end = nil
        return try update(session, now: now)
    }

    // MARK: Private

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private static let select = "SELECT id, start_at, end_at, heartbeat_at, note FROM session"

    private static func session(_ row: Row) -> Session {
        Session(
            id: row.int(0),
            start: Date(unixSeconds: row.int(1)),
            end: row.optionalInt(2).map(Date.init(unixSeconds:)),
            heartbeat: row.optionalInt(3).map(Date.init(unixSeconds:)),
            note: row.text(4)
        )
    }

    private func fetchOpen() throws -> Session? {
        try db.query("\(Self.select) WHERE end_at IS NULL", [], Self.session).first
    }

    private func fetch(id: Int64) throws -> Session? {
        try db.query("\(Self.select) WHERE id = ?", [.int(id)], Self.session).first
    }

    /// Shared rules for every write path. An open session counts as running until `now`.
    private func validate(id: Int64?, start: Date, end: Date?, now: Date) throws {
        let startSeconds = start.unixSeconds
        let nowSeconds = now.unixSeconds
        guard startSeconds <= nowSeconds else { throw SessionError.inFuture }

        if let end {
            guard end.unixSeconds <= nowSeconds else { throw SessionError.inFuture }
            guard end.unixSeconds > startSeconds else { throw SessionError.endNotAfterStart }
        } else if let open = try fetchOpen(), open.id != id {
            throw SessionError.alreadyRunning
        }

        let endSeconds = end?.unixSeconds ?? nowSeconds
        let conflict = try db.query(
            """
            SELECT id FROM session
            WHERE id != ? AND start_at < ? AND COALESCE(end_at, ?) > ?
            LIMIT 1
            """,
            [.int(id ?? -1), .int(max(endSeconds, startSeconds)), .int(nowSeconds), .int(startSeconds)]
        ) { $0.int(0) }.first
        if let conflict { throw SessionError.overlaps(with: conflict) }
    }
}
