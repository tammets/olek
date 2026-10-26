import Foundation
import SQLite3

enum DatabaseError: Error, CustomStringConvertible {
    case open(String)
    case statement(String, sql: String)
    case newerSchema(found: Int, supported: Int)

    var description: String {
        switch self {
        case .open(let message):
            "Could not open database: \(message)"
        case .statement(let message, let sql):
            "SQLite error: \(message) in \(sql)"
        case .newerSchema(let found, let supported):
            "Database schema version \(found) is newer than this app supports (\(supported)). Update Olek."
        }
    }
}

enum SQLValue {
    case int(Int64)
    case text(String)
    case null
}

struct Row {
    fileprivate let statement: OpaquePointer

    func int(_ column: Int32) -> Int64 {
        sqlite3_column_int64(statement, column)
    }

    func optionalInt(_ column: Int32) -> Int64? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : int(column)
    }

    func text(_ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }
}

// Tells SQLite to copy bound strings, since Swift may free them before the statement runs.
private var transient: sqlite3_destructor_type {
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

/// Thin wrapper over the SQLite C API. Not thread-safe; `SessionStore` serializes access.
final class Database {
    private let handle: OpaquePointer

    init(path: String, readOnly: Bool = false) throws {
        var db: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        let status = sqlite3_open_v2(path, &db, flags, nil)
        guard status == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "status \(status)"
            sqlite3_close(db)
            throw DatabaseError.open(message)
        }
        handle = db
        sqlite3_busy_timeout(db, 2_000)
        if !readOnly {
            try execute("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;")
        }
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Runs one or more statements without parameters.
    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? lastError
            sqlite3_free(error)
            throw DatabaseError.statement(message, sql: sql)
        }
    }

    func run(_ sql: String, _ parameters: [SQLValue] = []) throws {
        try withStatement(sql, parameters) { statement in
            let status = sqlite3_step(statement)
            guard status == SQLITE_DONE || status == SQLITE_ROW else {
                throw DatabaseError.statement(lastError, sql: sql)
            }
        }
    }

    func query<T>(_ sql: String, _ parameters: [SQLValue] = [], _ map: (Row) throws -> T) throws -> [T] {
        try withStatement(sql, parameters) { statement in
            var results: [T] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    results.append(try map(Row(statement: statement)))
                case SQLITE_DONE:
                    return results
                default:
                    throw DatabaseError.statement(lastError, sql: sql)
                }
            }
        }
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func userVersion() throws -> Int {
        try query("PRAGMA user_version") { Int($0.int(0)) }.first ?? 0
    }

    /// Copies this whole database into `target`, replacing its contents, using SQLite's online
    /// backup API. Safe while this database is open and in use.
    func copy(into target: Database) throws {
        guard let backup = sqlite3_backup_init(target.handle, "main", handle, "main") else {
            throw DatabaseError.statement(target.lastError, sql: "backup")
        }
        let status = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        guard status == SQLITE_DONE else {
            throw DatabaseError.statement(target.lastError, sql: "backup")
        }
    }

    var lastInsertRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    private var lastError: String {
        String(cString: sqlite3_errmsg(handle))
    }

    private func withStatement<T>(
        _ sql: String,
        _ parameters: [SQLValue],
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        var pointer: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &pointer, nil) == SQLITE_OK, let statement = pointer else {
            throw DatabaseError.statement(lastError, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in parameters.enumerated() {
            let position = Int32(index + 1)
            let status = switch value {
            case .int(let number): sqlite3_bind_int64(statement, position, number)
            case .text(let string): sqlite3_bind_text(statement, position, string, -1, transient)
            case .null: sqlite3_bind_null(statement, position)
            }
            guard status == SQLITE_OK else {
                throw DatabaseError.statement(lastError, sql: sql)
            }
        }
        return try body(statement)
    }
}
