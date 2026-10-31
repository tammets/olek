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

    public func allSessions() throws -> [Session] {
        try locked { try db.query("\(Self.select) ORDER BY start_at", [], Self.session) }
    }

    /// The session that started most recently, open or closed.
    public func latestSession() throws -> Session? {
        try locked { try db.query("\(Self.select) ORDER BY start_at DESC LIMIT 1", [], Self.session).first }
    }

    // MARK: Settings

    public func workSettings() throws -> WorkSettings {
        try setting("work", as: WorkSettings.self) ?? WorkSettings()
    }

    public func saveWorkSettings(_ settings: WorkSettings) throws {
        try saveSetting("work", settings)
    }

    public func reminderSettings() throws -> ReminderSettings {
        try setting("reminders", as: ReminderSettings.self) ?? ReminderSettings()
    }

    public func saveReminderSettings(_ settings: ReminderSettings) throws {
        try saveSetting("reminders", settings)
    }

    public func generalSettings() throws -> GeneralSettings {
        try setting("general", as: GeneralSettings.self) ?? GeneralSettings()
    }

    public func saveGeneralSettings(_ settings: GeneralSettings) throws {
        try saveSetting("general", settings)
    }

    // MARK: Day overrides

    public func dayOverrides() throws -> [DayOverride] {
        try locked {
            try db.query("SELECT date, kind, expected_minutes, note FROM day_override ORDER BY date") { row in
                guard let date = row.text(0).flatMap(LocalDate.init),
                      let kind = row.text(1).flatMap(DayOverride.Kind.init(rawValue:)) else { return nil }
                return DayOverride(date: date, kind: kind, expectedMinutes: row.optionalInt(2).map(Int.init), note: row.text(3))
            }.compactMap { $0 }
        }
    }

    public func setDayOverride(_ override: DayOverride, now: Date) throws {
        if override.kind == .customWorking || override.kind == .minutes {
            guard let minutes = override.expectedMinutes, (0...(24 * 60)).contains(minutes) else {
                throw SessionError.invalidExpectedMinutes
            }
        }
        try locked {
            let stamp = now.unixSeconds
            try db.run(
                """
                INSERT INTO day_override (date, kind, expected_minutes, note, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(date) DO UPDATE SET
                    kind = excluded.kind, expected_minutes = excluded.expected_minutes,
                    note = excluded.note, updated_at = excluded.updated_at
                """,
                [
                    .text(override.date.description),
                    .text(override.kind.rawValue),
                    override.expectedMinutes.map { .int(Int64($0)) } ?? .null,
                    override.note.map { .text($0) } ?? .null,
                    .int(stamp),
                    .int(stamp),
                ]
            )
        }
    }

    public func removeDayOverride(on date: LocalDate) throws {
        try locked { try db.run("DELETE FROM day_override WHERE date = ?", [.text(date.description)]) }
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

    /// Adds a finished session, e.g. one that was forgotten.
    @discardableResult
    public func add(start: Date, end: Date, note: String? = nil, now: Date) throws -> Session {
        try locked {
            try db.transaction {
                try validate(id: nil, start: start, end: end, now: now)
                let stamp = now.unixSeconds
                try db.run(
                    """
                    INSERT INTO session (start_at, end_at, heartbeat_at, note, created_at, updated_at)
                    VALUES (?, ?, NULL, ?, ?, ?)
                    """,
                    [.int(start.unixSeconds), .int(end.unixSeconds), note.map { .text($0) } ?? .null, .int(stamp), .int(stamp)]
                )
                guard let saved = try fetch(id: db.lastInsertRowID) else { throw SessionError.notFound }
                return saved
            }
        }
    }

    public func delete(id: Int64) throws {
        try locked {
            try db.transaction {
                guard try fetch(id: id) != nil else { throw SessionError.notFound }
                try db.run("DELETE FROM session WHERE id = ?", [.int(id)])
            }
        }
    }

    /// Cuts the span `from..<to` out of a session, leaving two sessions with a gap between them.
    /// Works on a running session too; the second part keeps running.
    @discardableResult
    public func insertBreak(sessionID: Int64, from: Date, to: Date, now: Date) throws -> (before: Session, after: Session) {
        try locked {
            try db.transaction {
                guard let session = try fetch(id: sessionID) else { throw SessionError.notFound }
                let breakStart = from.unixSeconds
                let breakEnd = to.unixSeconds
                let sessionEnd = session.end?.unixSeconds ?? now.unixSeconds
                guard breakStart > session.start.unixSeconds, breakEnd < sessionEnd, breakEnd > breakStart else {
                    throw SessionError.breakOutsideSession
                }
                let stamp = now.unixSeconds
                // Close the first part before inserting the second, so at most one session is ever open.
                try db.run(
                    "UPDATE session SET end_at = ?, updated_at = ? WHERE id = ?",
                    [.int(breakStart), .int(stamp), .int(session.id)]
                )
                try db.run(
                    """
                    INSERT INTO session (start_at, end_at, heartbeat_at, note, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    [
                        .int(breakEnd),
                        session.end.map { .int($0.unixSeconds) } ?? .null,
                        session.isOpen ? .int(stamp) : .null,
                        session.note.map { .text($0) } ?? .null,
                        .int(stamp),
                        .int(stamp),
                    ]
                )
                guard let before = try fetch(id: session.id), let after = try fetch(id: db.lastInsertRowID) else {
                    throw SessionError.notFound
                }
                return (before, after)
            }
        }
    }

    /// Removes `span` from one session: splits it when the span falls inside, trims it when the
    /// span covers an edge. Does nothing when the session is gone, no longer overlaps the span,
    /// or lies entirely inside it, since deleting it is too drastic for an answer about time away.
    public func removeSpan(_ span: DateInterval, fromSession id: Int64, now: Date) throws {
        guard var session = try session(id: id) else { return }
        let end = session.end ?? now
        guard span.start < end, span.end > session.start else { return }
        if span.start > session.start, span.end < end {
            try insertBreak(sessionID: id, from: span.start, to: span.end, now: now)
        } else if span.start <= session.start, span.end < end {
            session.start = span.end
            try update(session, now: now)
        } else if span.start > session.start, !session.isOpen {
            session.end = span.start
            try update(session, now: now)
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

    private func setting<T: Decodable>(_ key: String, as type: T.Type) throws -> T? {
        let value = try locked {
            try db.query("SELECT value FROM setting WHERE key = ?", [.text(key)]) { $0.text(0) }.first ?? nil
        }
        guard let value else { return nil }
        return try JSONDecoder().decode(T.self, from: Data(value.utf8))
    }

    private func saveSetting<T: Encodable>(_ key: String, _ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(value), as: UTF8.self)
        try locked {
            try db.run(
                "INSERT INTO setting (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                [.text(key), .text(json)]
            )
        }
    }

    /// Raw database access for maintenance tasks such as backup, under the store's lock.
    func withDatabase<T>(_ body: (Database) throws -> T) throws -> T {
        try locked { try body(db) }
    }

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
