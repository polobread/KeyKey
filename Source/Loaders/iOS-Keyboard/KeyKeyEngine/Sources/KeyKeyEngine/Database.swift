import Foundation
import SQLite3

public enum DatabaseError: Error, CustomStringConvertible {
    case cannotOpen(path: String, message: String)
    case cannotPrepare(sql: String, message: String)

    public var description: String {
        switch self {
        case let .cannotOpen(path, message):
            return "cannot open \(path): \(message)"
        case let .cannotPrepare(sql, message):
            return "cannot prepare \(sql): \(message)"
        }
    }
}

/// A read-only SQLite handle over the cooked `KeyKey.db`.
///
/// The keyboard runs under a small memory limit, so the database is opened
/// read-only and queried through prepared statements rather than being read
/// into memory the way the Android port parses `.cin` text.
public final class Database {
    private let handle: OpaquePointer

    public init(url: URL) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let status = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard status == SQLITE_OK, let opened = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "status \(status)"
            sqlite3_close_v2(handle)
            throw DatabaseError.cannotOpen(path: url.path, message: message)
        }
        self.handle = opened
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    public func prepare(_ sql: String) throws -> Statement {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let prepared = statement
        else {
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_finalize(statement)
            throw DatabaseError.cannotPrepare(sql: sql, message: message)
        }
        return Statement(prepared)
    }
}

public final class Statement {
    private let handle: OpaquePointer

    init(_ handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_finalize(handle)
    }

    /// Binds the arguments in order and collects the first column of every row.
    /// The statement is reset afterwards so it can be reused.
    public func firstColumnStrings(_ arguments: [String]) -> [String] {
        bind(arguments)

        var rows: [String] = []
        while sqlite3_step(handle) == SQLITE_ROW {
            if let text = sqlite3_column_text(handle, 0) {
                rows.append(String(cString: text))
            }
        }
        sqlite3_reset(handle)
        return rows
    }

    /// Collects every column of every row as text. Used for the small
    /// collection-name query, not on the typing path.
    public func allRows(_ arguments: [String] = [], columnCount: Int32) -> [[String]] {
        bind(arguments)
        var rows: [[String]] = []
        while sqlite3_step(handle) == SQLITE_ROW {
            var row: [String] = []
            for column in 0..<columnCount {
                if let text = sqlite3_column_text(handle, column) {
                    row.append(String(cString: text))
                } else {
                    row.append("")
                }
            }
            rows.append(row)
        }
        sqlite3_reset(handle)
        return rows
    }

    private func bind(_ arguments: [String]) {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
        for (index, argument) in arguments.enumerated() {
            sqlite3_bind_text(handle, Int32(index + 1), argument, -1, SQLITE_TRANSIENT)
        }
    }
}

// sqlite3_bind_text needs a destructor argument; the macro is not imported.
private let SQLITE_TRANSIENT = unsafeBitCast(
    -1, to: sqlite3_destructor_type.self
)
