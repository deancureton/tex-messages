import Foundation
import SQLite3

enum SQLiteError: Error, LocalizedError {
    case open(Int32, String)
    case query(String)

    var errorDescription: String? {
        switch self {
        case .open(_, let message), .query(let message): return message
        }
    }
}

enum SQLValue {
    case int(Int64)
    case text(String)
    case blob(Data)
}

private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct SQLRow {
    let statement: OpaquePointer

    func int(_ index: Int32) -> Int64 { sqlite3_column_int64(statement, index) }

    func text(_ index: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: bytes)
    }

    func blob(_ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }
}

final class SQLite {
    private var handle: OpaquePointer?

    init(path: String) throws {
        let code = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil)
        guard code == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            sqlite3_close(handle)
            handle = nil
            throw SQLiteError.open(code, message)
        }
        sqlite3_busy_timeout(handle, 2000)
    }

    deinit { sqlite3_close(handle) }

    func query(_ sql: String, _ params: [SQLValue] = [], row: (SQLRow) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError.query(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }

        for (offset, param) in params.enumerated() {
            let index = Int32(offset + 1)
            switch param {
            case .int(let value):
                sqlite3_bind_int64(statement, index, value)
            case .text(let value):
                sqlite3_bind_text(statement, index, value, -1, transient)
            case .blob(let value):
                _ = value.withUnsafeBytes {
                    sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(value.count), transient)
                }
            }
        }

        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW {
                row(SQLRow(statement: statement))
            } else if code == SQLITE_DONE {
                return
            } else {
                throw SQLiteError.query(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    func columns(of table: String) throws -> Set<String> {
        var names = Set<String>()
        try query("PRAGMA table_info(\(table))") { row in
            if let name = row.text(1) { names.insert(name) }
        }
        return names
    }
}
