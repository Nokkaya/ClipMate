import Foundation
import SQLite3

public enum StoreError: Error, CustomStringConvertible {
    case openFailed(Int32)
    case sql(String)

    public var description: String {
        switch self {
        case .openFailed(let code): return "数据库打开失败（错误码 \(code)）"
        case .sql(let message): return "SQL 错误：\(message)"
        }
    }
}

/// SQL 绑定值。
public enum SQLValue {
    case text(String?)
    case int(Int64)
    case double(Double)
    case blob(Data?)
}

/// sqlite3_bind_text 系列要求 SQLITE_TRANSIENT（让 SQLite 自行拷贝缓冲区）。
let SQLITE_TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

public final class Statement {
    private let handle: OpaquePointer

    init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_finalize(handle)
    }

    public func bind(_ values: [SQLValue]) {
        for (offset, value) in values.enumerated() {
            bind(Int32(offset + 1), value)
        }
    }

    public func bind(_ index: Int32, _ value: SQLValue) {
        switch value {
        case .text(let string):
            if let string {
                sqlite3_bind_text(handle, index, string, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(handle, index)
            }
        case .int(let value):
            sqlite3_bind_int64(handle, index, value)
        case .double(let value):
            sqlite3_bind_double(handle, index, value)
        case .blob(let data):
            if let data, !data.isEmpty {
                data.withUnsafeBytes { raw in
                    _ = sqlite3_bind_blob(handle, index, raw.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                }
            } else if data != nil {
                sqlite3_bind_zeroblob(handle, index, 0)
            } else {
                sqlite3_bind_null(handle, index)
            }
        }
    }

    /// 执行写语句（INSERT/UPDATE/DELETE）。
    public func run() throws {
        defer {
            sqlite3_reset(handle)
            sqlite3_clear_bindings(handle)
        }
        let rc = sqlite3_step(handle)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            let msg = sqlite3_errmsg(sqlite3_db_handle(handle)).map { String(cString: $0) } ?? "未知错误"
            throw StoreError.sql(msg)
        }
    }

    /// SELECT 迭代：返回是否还有下一行。
    public func step() -> Bool {
        sqlite3_step(handle) == SQLITE_ROW
    }

    public func columnInt(_ i: Int32) -> Int64 { sqlite3_column_int64(handle, i) }
    public func columnDouble(_ i: Int32) -> Double { sqlite3_column_double(handle, i) }

    public func columnText(_ i: Int32) -> String? {
        guard sqlite3_column_type(handle, i) != SQLITE_NULL,
              let ptr = sqlite3_column_text(handle, i) else { return nil }
        return String(cString: ptr)
    }

    public func columnData(_ i: Int32) -> Data? {
        guard sqlite3_column_type(handle, i) != SQLITE_NULL else { return nil }
        guard let pointer = sqlite3_column_blob(handle, i) else { return Data() }
        let count = Int(sqlite3_column_bytes(handle, i))
        return Data(bytes: pointer, count: count)
    }
}

/// 系统 SQLite3 的薄封装。WAL 模式；FTS5 可用性运行时探测（不可用时上层降级 LIKE 检索）。
public final class Database {
    private let handle: OpaquePointer
    public let hasFTS5: Bool

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(url.path, &db, flags, nil)
        guard rc == SQLITE_OK, let opened = db else {
            if let db { sqlite3_close_v2(db) }
            throw StoreError.openFailed(rc)
        }
        handle = opened
        hasFTS5 = Database.probeFTS5(handle: opened)
        try execute("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=3000;")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    private static func probeFTS5(handle: OpaquePointer) -> Bool {
        var errorMessage: UnsafeMutablePointer<CChar>?
        var ok = sqlite3_exec(handle, "CREATE VIRTUAL TABLE IF NOT EXISTS temp.fts5_probe USING fts5(x)",
                              nil, nil, &errorMessage) == SQLITE_OK
        if ok {
            ok = sqlite3_exec(handle, "DROP TABLE IF EXISTS temp.fts5_probe",
                              nil, nil, &errorMessage) == SQLITE_OK
        }
        if let errorMessage { sqlite3_free(errorMessage) }
        return ok
    }

    public func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if rc != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "未知错误"
            sqlite3_free(errorMessage)
            throw StoreError.sql(message)
        }
    }

    public func prepare(_ sql: String) throws -> Statement {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StoreError.sql(String(cString: sqlite3_errmsg(handle)))
        }
        return Statement(handle: statement)
    }

    public var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    /// PRAGMA user_version（schema 版本号）。
    public var userVersion: Int {
        guard let statement = try? prepare("PRAGMA user_version"), statement.step() else { return 0 }
        return Int(statement.columnInt(0))
    }
}
