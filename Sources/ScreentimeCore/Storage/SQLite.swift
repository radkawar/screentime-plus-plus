import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct SQLiteError: Error, CustomStringConvertible {
    public var code: Int32
    public var message: String
    public var description: String { "SQLite \(code): \(message)" }
}

/// Minimal synchronous SQLite connection. Callers serialize access.
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(path, &handle, flags, nil)
        guard status == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw SQLiteError(code: status, message: message)
        }
        sqlite3_busy_timeout(handle, 2_000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("PRAGMA foreign_keys=ON")
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, sql, nil, nil, &error)
        if status != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(error)
            throw SQLiteError(code: status, message: message)
        }
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    func run(_ sql: String, _ bindings: [SQLiteValue] = []) throws {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE || status == SQLITE_ROW else { throw error(status) }
    }

    func query(_ sql: String, _ bindings: [SQLiteValue] = [], row: (SQLiteRow) throws -> Void) throws {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return }
            guard status == SQLITE_ROW else { throw error(status) }
            try row(SQLiteRow(statement: statement!))
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ bindings: [SQLiteValue]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard status == SQLITE_OK else { throw error(status) }
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .null: sqlite3_bind_null(statement, index)
            case .integer(let integer): sqlite3_bind_int64(statement, index, integer)
            case .real(let real): sqlite3_bind_double(statement, index, real)
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT)
            }
        }
        return statement
    }

    private func error(_ status: Int32) -> SQLiteError {
        SQLiteError(code: status, message: String(cString: sqlite3_errmsg(handle)))
    }
}

enum SQLiteValue {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)

    static func optional(_ text: String?) -> SQLiteValue {
        text.map(SQLiteValue.text) ?? .null
    }
}

struct SQLiteRow {
    let statement: OpaquePointer

    func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
    func int(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }

    func string(_ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
            let text = sqlite3_column_text(statement, column)
        else { return nil }
        return String(cString: text)
    }
}
