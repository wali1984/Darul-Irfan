import Foundation
import SQLite3

// Minimal wrapper over the system SQLite3 C API. Chosen over SwiftData so that
// one store can hold both user data and the content library with FTS5 search,
// with no third-party dependency and fully deterministic tests.

/// Transient destructor constant required when binding Swift strings/blobs.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteError: Error, CustomStringConvertible {
    case openFailed(message: String)
    case prepareFailed(sql: String, message: String)
    case stepFailed(sql: String, message: String)
    case bindFailed(index: Int, message: String)
    case migrationFailed(version: Int, reason: String)

    var description: String {
        switch self {
        case .openFailed(let message): return "SQLite open failed: \(message)"
        case .prepareFailed(let sql, let message): return "SQLite prepare failed (\(message)): \(sql)"
        case .stepFailed(let sql, let message): return "SQLite step failed (\(message)): \(sql)"
        case .bindFailed(let index, let message): return "SQLite bind failed at index \(index): \(message)"
        case .migrationFailed(let version, let reason):
            return "SQLite migration to v\(version) rolled back: \(reason)"
        }
    }
}

/// A value bindable to a SQL parameter.
enum SQLValue {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    static func int(_ value: Int) -> SQLValue { .integer(Int64(value)) }
    static func bool(_ value: Bool) -> SQLValue { .integer(value ? 1 : 0) }
    static func date(_ value: Date) -> SQLValue { .real(value.timeIntervalSince1970) }

    static func optionalText(_ value: String?) -> SQLValue {
        value.map { .text($0) } ?? .null
    }

    static func optionalDate(_ value: Date?) -> SQLValue {
        value.map { .real($0.timeIntervalSince1970) } ?? .null
    }

    static func optionalInt(_ value: Int?) -> SQLValue {
        value.map { .integer(Int64($0)) } ?? .null
    }

    static func optionalReal(_ value: Double?) -> SQLValue {
        value.map { .real($0) } ?? .null
    }
}

/// One row of a query result, with typed column accessors by name.
struct SQLRow {
    private let values: [String: SQLValue]

    init(values: [String: SQLValue]) {
        self.values = values
    }

    func int(_ column: String) -> Int? {
        switch values[column] {
        case .integer(let v): return Int(v)
        case .real(let v): return Int(v)
        default: return nil
        }
    }

    func int64(_ column: String) -> Int64? {
        if case .integer(let v)? = values[column] { return v }
        return nil
    }

    func double(_ column: String) -> Double? {
        switch values[column] {
        case .real(let v): return v
        case .integer(let v): return Double(v)
        default: return nil
        }
    }

    func text(_ column: String) -> String? {
        if case .text(let v)? = values[column] { return v }
        return nil
    }

    func blob(_ column: String) -> Data? {
        if case .blob(let v)? = values[column] { return v }
        return nil
    }

    func bool(_ column: String) -> Bool {
        (int(column) ?? 0) != 0
    }

    func date(_ column: String) -> Date? {
        double(column).map { Date(timeIntervalSince1970: $0) }
    }
}

/// Serialized access to one SQLite connection. All database work in the app
/// funnels through this actor, so no external locking is needed.
actor SQLiteDatabase {
    private var handle: OpaquePointer?

    /// Opens (creating if needed) the database at `url`, or an in-memory
    /// database when `url` is nil (used by unit tests).
    init(url: URL?) throws {
        let path = url?.path ?? ":memory:"
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(db)
            throw SQLiteError.openFailed(message: message)
        }
        self.handle = db
        // WAL improves concurrent read behavior; foreign keys enforce integrity.
        sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
    }

    deinit {
        if let handle {
            sqlite3_close_v2(handle)
        }
    }

    /// Executes a statement with no result rows.
    func execute(_ sql: String, _ parameters: [SQLValue] = []) throws {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteError.stepFailed(sql: sql, message: errorMessage())
        }
    }

    /// Executes multiple semicolon-separated statements (used for migrations).
    func executeScript(_ sql: String) throws {
        guard let handle else { return }
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorPointer)
            throw SQLiteError.stepFailed(sql: sql, message: message)
        }
    }

    /// Runs a query and returns all rows.
    func query(_ sql: String, _ parameters: [SQLValue] = []) throws -> [SQLRow] {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }

        var rows: [SQLRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw SQLiteError.stepFailed(sql: sql, message: errorMessage())
            }
            rows.append(readRow(statement))
        }
        return rows
    }

    /// Executes a batch of parameterized statements inside one transaction,
    /// rolling back if any statement fails. Used by seed/content importers.
    func executeBatch(_ statements: [(sql: String, parameters: [SQLValue])]) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for statement in statements {
                try execute(statement.sql, statement.parameters)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// A post-migration invariant, written as SQL that selects the *violations*.
    /// The migration is sound only while every check returns no rows.
    struct MigrationCheck: Sendable {
        /// Returns one row per problem found. No rows means the check passed.
        let sql: String
        /// What it means when the query does return rows.
        let failure: String
    }

    /// Applies a migration and its invariants inside a single transaction.
    ///
    /// The script, every check, and the `user_version` bump all commit together
    /// or not at all: if any check finds a violation the transaction rolls back
    /// and `user_version` is left untouched, so the next launch retries against
    /// the original database rather than a half-migrated one.
    ///
    /// - Parameter cleanup: statements run after the checks (still inside the
    ///   transaction), e.g. dropping scratch tables the checks needed.
    func migrate(
        to version: Int,
        script: String,
        checks: [MigrationCheck] = [],
        cleanup: String? = nil
    ) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try executeScript(script)
            for check in checks {
                let violations = try query(check.sql)
                guard violations.isEmpty else {
                    throw SQLiteError.migrationFailed(
                        version: version,
                        reason: "\(check.failure) (\(violations.count) violation(s))"
                    )
                }
            }
            if let cleanup { try executeScript(cleanup) }
            try executeScript("PRAGMA user_version = \(version)")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var lastInsertRowID: Int64 {
        handle.map { sqlite3_last_insert_rowid($0) } ?? 0
    }

    /// Current schema version (`PRAGMA user_version`).
    func schemaVersion() throws -> Int {
        try query("PRAGMA user_version").first?.int("user_version") ?? 0
    }

    func setSchemaVersion(_ version: Int) throws {
        try executeScript("PRAGMA user_version = \(version)")
    }

    // MARK: - Internals

    private func prepare(_ sql: String, _ parameters: [SQLValue]) throws -> OpaquePointer {
        guard let handle else {
            throw SQLiteError.prepareFailed(sql: sql, message: "database closed")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError.prepareFailed(sql: sql, message: errorMessage())
        }
        for (offset, value) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let bindResult: Int32
            switch value {
            case .null:
                bindResult = sqlite3_bind_null(statement, index)
            case .integer(let v):
                bindResult = sqlite3_bind_int64(statement, index, v)
            case .real(let v):
                bindResult = sqlite3_bind_double(statement, index, v)
            case .text(let v):
                bindResult = sqlite3_bind_text(statement, index, v, -1, sqliteTransient)
            case .blob(let v):
                bindResult = v.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(v.count), sqliteTransient)
                }
            }
            guard bindResult == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw SQLiteError.bindFailed(index: Int(index), message: errorMessage())
            }
        }
        return statement
    }

    private func readRow(_ statement: OpaquePointer) -> SQLRow {
        var values: [String: SQLValue] = [:]
        let columnCount = sqlite3_column_count(statement)
        for column in 0..<columnCount {
            let name = String(cString: sqlite3_column_name(statement, column))
            switch sqlite3_column_type(statement, column) {
            case SQLITE_INTEGER:
                values[name] = .integer(sqlite3_column_int64(statement, column))
            case SQLITE_FLOAT:
                values[name] = .real(sqlite3_column_double(statement, column))
            case SQLITE_TEXT:
                if let cString = sqlite3_column_text(statement, column) {
                    values[name] = .text(String(cString: cString))
                } else {
                    values[name] = .null
                }
            case SQLITE_BLOB:
                if let bytes = sqlite3_column_blob(statement, column) {
                    let count = Int(sqlite3_column_bytes(statement, column))
                    values[name] = .blob(Data(bytes: bytes, count: count))
                } else {
                    values[name] = .blob(Data())
                }
            default:
                values[name] = .null
            }
        }
        return SQLRow(values: values)
    }

    private func errorMessage() -> String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "database closed"
    }
}
