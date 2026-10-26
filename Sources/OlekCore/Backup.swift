import Foundation

public struct BackupSummary: Equatable, Sendable {
    public var sessionCount: Int
    public var firstSession: Date?
    public var lastSession: Date?
    public var schemaVersion: Int
}

public enum BackupError: Error, Equatable, LocalizedError {
    case notADatabase
    case damaged(String)
    case notAnOlekBackup
    case newerVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .notADatabase: String(localized: "This file is not an Olek backup.")
        case .damaged(let detail): String(localized: "The backup is damaged: \(detail)")
        case .notAnOlekBackup: String(localized: "This database does not contain Olek data.")
        case .newerVersion: String(localized: "This backup was made by a newer version of Olek. Update Olek first.")
        }
    }
}

extension SessionStore {
    /// Writes a self-contained copy of the database to `url`, replacing any file there.
    public func backup(to url: URL) throws {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(atPath: url.path + suffix)
        }
        let target = try Database(path: url.path)
        try withDatabase { try $0.copy(into: target) }
        // A single file is easier to move around than a WAL database with side files.
        try target.execute("PRAGMA journal_mode = DELETE")
    }

    /// Checks that `url` is an intact Olek database this version can read, without changing it.
    public static func inspectBackup(at url: URL) throws -> BackupSummary {
        let db: Database
        do {
            db = try Database(path: url.path, readOnly: true)
            _ = try db.userVersion()
        } catch {
            throw BackupError.notADatabase
        }
        let integrity = (try? db.query("PRAGMA integrity_check") { $0.text(0) ?? "" }) ?? []
        guard integrity == ["ok"] else {
            throw BackupError.damaged(integrity.prefix(3).joined(separator: "; "))
        }
        let tables = Set(try db.query("SELECT name FROM sqlite_master WHERE type = 'table'") { $0.text(0) ?? "" })
        guard tables.isSuperset(of: ["session", "day_override", "setting"]) else {
            throw BackupError.notAnOlekBackup
        }
        let version = try db.userVersion()
        guard version <= Migrations.latestVersion else { throw BackupError.newerVersion(version) }

        let stats = try db.query("SELECT count(*), min(start_at), max(start_at) FROM session") { row in
            (Int(row.int(0)), row.optionalInt(1), row.optionalInt(2))
        }.first ?? (0, nil, nil)
        return BackupSummary(
            sessionCount: stats.0,
            firstSession: stats.1.map(Date.init(unixSeconds:)),
            lastSession: stats.2.map(Date.init(unixSeconds:)),
            schemaVersion: version
        )
    }

    /// Replaces all data with the backup at `url`. The current data is first saved to
    /// `safetyCopy`, so a restore can always be undone by restoring that file.
    @discardableResult
    public func restore(from url: URL, safetyCopy: URL) throws -> BackupSummary {
        let summary = try Self.inspectBackup(at: url)
        try FileManager.default.createDirectory(at: safetyCopy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try backup(to: safetyCopy)
        let source = try Database(path: url.path, readOnly: true)
        try withDatabase { db in
            try source.copy(into: db)
            try Migrations.migrate(db)
        }
        return summary
    }
}
