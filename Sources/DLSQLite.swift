//
//  DLSQLite.swift
//
//  Created by Norio Nomura on 2/22/17.
//
//  MIT License
//
//  Copyright (c) 2017 Norio Nomura
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import Foundation

public struct SQLite {
    /// Run-Time Library Version Numbers
    public static let libVersion = String(cString: sqlite3_libversion())
    public static let libVersionNumber = Int(sqlite3_libversion_number())
    public static let sourceId = String(cString: sqlite3_sourceid())

    /// Test To See If The Library Is Threadsafe
    public static let threadSafe = SQLITE_THREADSAFE(rawValue: sqlite3_threadsafe())!
    public enum SQLITE_THREADSAFE: Int32 {
        case SINGLETHREAD = 0
        case MULTITHREAD = 1
        case SERIALIZED = 2
    }

    /// Database Connection Handle
    public final class Connection {
        public struct Options: OptionSet, RawRepresentable {
            public let rawValue: Int32
            public init(rawValue: Int32) { self.rawValue = rawValue }
            /// SQLITE_OPEN_READONLY
            public static let readonly     = Options(rawValue: 0x00000001)
            /// SQLITE_OPEN_READWRITE
            public static let readwrite    = Options(rawValue: 0x00000002)
            /// SQLITE_OPEN_CREATE
            public static let create       = Options(rawValue: 0x00000004)

            /// SQLITE_OPEN_URI
            public static let uri          = Options(rawValue: 0x00000040)

            /// The `SQLITE_OPEN_NOMUTEX` flag causes the database connection to be in the multi-thread mode
            public static let nomutex      = Options(rawValue: 0x00008000)
            /// The `SQLITE_OPEN_FULLMUTEX` flag causes the connection to be in serialized mode
            public static let fullmutex    = Options(rawValue: 0x00010000)

            /// SQLITE_OPEN_SHAREDCACHE
            public static let sharedcache  = Options(rawValue: 0x00020000)
            /// SQLITE_OPEN_PRIVATECACHE
            public static let privatecache = Options(rawValue: 0x00040000)
        }

        public init(path: String, options: Options = [.readwrite, .create]) throws {
            try check(sqlite3_open_v2(path, &_handle, options.rawValue, nil))
        }

        public func prepare(for sql: String, tail: UnsafeMutablePointer<String.Index>? = nil) throws -> Statement {
            return try Statement(self, for: sql, tail: tail)
        }

        @discardableResult
        fileprivate func check(_ code: sqlite3_result, _ sql: String? = nil) throws -> sqlite3_result {
            if let error = Error(code, self, sql) { throw error }
            return code
        }

        fileprivate var handle: sqlite3 { return _handle! }
        fileprivate var _handle: sqlite3?
        deinit { _ = sqlite3_close_v2(_handle) }
    }

    /// Prepared Statement Object
    public final class Statement: CustomStringConvertible, IteratorProtocol, Sequence {
        public let sql: String

        fileprivate init(_ connection: Connection, for sql: String, tail: UnsafeMutablePointer<String.Index>?) throws {
            var optionalHandle: sqlite3_stmt?
            let offset = try sql.utf8CString.withUnsafeBufferPointer { ptr -> Int in
                var tail: UnsafePointer<CChar> = ptr.baseAddress!
                try connection.check(sqlite3_prepare_v2(connection.handle, ptr.baseAddress!, -1, &optionalHandle, &tail), sql)
                return tail - ptr.baseAddress!
            }

            self.connection = connection
            handle = optionalHandle!
            let utf8 = sql.utf8
            let index = utf8.index(utf8.startIndex, offsetBy: offset, limitedBy: utf8.endIndex)?
                .samePosition(in: sql) ?? sql.endIndex
            tail?.pointee = index
            self.sql = sql.substring(to: index)
        }

        public func step() throws -> Bool {
            return try connection.check(sqlite3_step(handle), sql) == 100 // SQLITE_ROW
        }

        public func reset() {
            _ = sqlite3_reset(handle)
        }

        public lazy var columnNames: [String] = { [unowned self] in
            (0..<self.columnCount).map { sqlite3_column_name(self.handle, $0).map(String.init(cString:)) ?? "" }
            }()

        // IteratorProtocol
        public func next() -> Cursor? {
            return try! step() ? Cursor(statement: self) : nil
        }

        // Sequence
        public func makeIterator() -> Statement {
            reset()
            return self
        }

        // CustomStringConvertible
        public var description: String { return sql }

        // private
        fileprivate let connection: Connection
        fileprivate let handle: sqlite3_stmt
        deinit { _ = sqlite3_finalize(handle) }
        fileprivate lazy var columnCount: column_index = { [unowned self] in sqlite3_column_count(self.handle) }()
    }

    /// Cursors provide access to Statement's current row
    public struct Cursor: CustomStringConvertible, RandomAccessCollection, Sequence {
        // Sequence
        public func makeIterator() -> AnyIterator<Value> {
            var index = startIndex
            let endIndex = self.endIndex
            return AnyIterator {
                defer { index += 1 }
                return index < endIndex ? self[index] : nil
            }
        }

        // Collection
        public typealias Index = Int
        public let startIndex: Index = 0 // always 0
        public var endIndex: Index { return Int(statement.columnCount) }
        public subscript(i: Index) -> Value {
            assert(startIndex..<endIndex ~= i)
            return Value(handle: sqlite3_column_value(statement.handle, Int32(i)))
        }
        public func index(after i: Index) -> Index { return i.advanced(by: 1) }

        // BidirectionalCollection
        public func index(before i: Index) -> Index { return i.advanced(by: -1) }

        // RandomAccessCollection
        public func index(_ i: Index, offsetBy n: Int) -> Index { return i.advanced(by: n) }
        public func distance(from start: Index, to end: Index) -> Index { return start.distance(to: end) }

        // CustomStringConvertible
        public var description: String { return "\(Array(self))" }

        // fileprivate
        fileprivate let statement: Statement
    }

    /// Dynamically Typed Value Object
    public struct Value: CustomStringConvertible {
        /// SQLITE_INTEGER
        public var int64: Int64 { return sqlite3_value_int64(handle) }
        public var int: Int { return Int(int64) }

        /// SQLITE_FLOAT
        public var double: Double { return sqlite3_value_double(handle) }

        /// SQLITE_TEXT
        public var string: String { return sqlite3_value_text(handle).map(String.init(cString:)) ?? "" }

        /// SQLITE_BLOB
        public var blob: UnsafeRawBufferPointer {
            return UnsafeRawBufferPointer(start: sqlite3_value_blob(handle), count: Int(sqlite3_value_bytes(handle)))
        }
        public var data: Data { return Data(bytes: blob.baseAddress!, count: blob.count) }

        public var any: Any {
            switch sqlite3_value_type(handle) {
            case 1: return int     // SQLITE_INTEGER
            case 2: return double  // SQLITE_FLOAT
            case 3: return string  // SQLITE_TEXT
            case 4: return data    // SQLITE_BLOB
            case 5: return NSNull()// SQLITE_NULL
            default: fatalError("unreachable")
            }
        }

        // CustomStringConvertible
        public var description: String { return String(describing: any) }

        // fileprivate
        fileprivate let handle: sqlite3_value
    }

    /// Error Codes And Messages
    public struct Error: Swift.Error, CustomStringConvertible {
        public let errorCode: Int32
        public let message: String
        public let sql: String?
        public var description: String { return "\(message)\(sql.map { " (\($0))" } ?? "") (code: \(errorCode))" }
        // fileprivate
        fileprivate init?(_ code: sqlite3_result, _ connection: Connection, _ sql: String? = nil) {
            if [0, 100, 101].contains(code) { return nil }
            errorCode = code
            let cString = connection._handle.map(sqlite3_errmsg) ?? sqlite3_errstr(code)
            message = cString.map(String.init(cString:)) ?? "Unknown error"
            self.sql = sql
        }
    }

    // MARK: - SQLie APIs are declared as private
    #if os(Linux)
    private static let library = DynamicLinkLibrary(path: "libsqlite3.so")
    #else
    private static let library = DynamicLinkLibrary(path: "libsqlite3.dylib")
    #endif

    /// Run-Time Library Version Numbers
    private static let sqlite3_libversion: @convention(c) () -> UnsafePointer<Int8> = library.load(symbol: "sqlite3_libversion")
    private static let sqlite3_sourceid: @convention(c) () -> UnsafePointer<Int8> = library.load(symbol: "sqlite3_sourceid")
    private static let sqlite3_libversion_number: @convention(c) () -> Int32 = library.load(symbol: "sqlite3_libversion_number")

    /// Test To See If The Library Is Threadsafe
    private static let sqlite3_threadsafe: @convention(c) () -> Int32 = library.load(symbol: "sqlite3_threadsafe")

    /// SQLite db handle
    fileprivate typealias sqlite3 = OpaquePointer

    /// Result codes
    fileprivate typealias sqlite3_result = Int32

    // Connection Connection Handle
    private static let sqlite3_open_v2: @convention(c) (
        UnsafePointer<CChar>,                       // Connection filename (UTF-8)
        UnsafeMutablePointer<sqlite3?>,             // OUT: SQLite db handle
        Int32,                                      // Flags
        UnsafePointer<CChar>?                       // Name of VFS module to use
        ) -> sqlite3_result = library.load(symbol: "sqlite3_open_v2")
    private static let sqlite3_close_v2: @convention(c) (sqlite3?) -> sqlite3_result = library.load(symbol: "sqlite3_close_v2")

    /// Statement handle
    fileprivate typealias sqlite3_stmt = OpaquePointer

    // Prepared Statement Object
    private static let sqlite3_prepare_v2: @convention(c) (
        sqlite3,                                    // Connection handle
        UnsafePointer<CChar>,                       // SQL statement, UTF-8 encoded
        Int32,                                      // Maximum length of SQL statement in bytes.
        UnsafeMutablePointer<sqlite3_stmt?>,        // OUT: Statement handle
        UnsafeMutablePointer<UnsafePointer<CChar>>? // OUT: Pointer to unused portion of SQL statement
        ) -> sqlite3_result = library.load(symbol: "sqlite3_prepare_v2")
    private static let sqlite3_finalize: @convention(c) (sqlite3_stmt) -> sqlite3_result = library.load(symbol: "sqlite3_finalize")
    private static let sqlite3_step: @convention(c) (sqlite3_stmt) -> sqlite3_result = library.load(symbol: "sqlite3_step")
    private static let sqlite3_reset: @convention(c) (sqlite3_stmt) -> sqlite3_result = library.load(symbol: "sqlite3_reset")

    /// Column number. The leftmost column is number 0.
    fileprivate typealias column_index = Int32

    // Column Names In A Result Set
    private static let sqlite3_column_name: @convention(c) (sqlite3_stmt, column_index) -> UnsafePointer<Int8>? = library.load(symbol: "sqlite3_column_name")

    // Number Of Columns In A Result Set
    private static let sqlite3_column_count: @convention(c) (sqlite3_stmt) -> column_index = library.load(symbol: "sqlite3_column_count")

    // Result Values From A Query
    private static let sqlite3_column_value: @convention(c) (sqlite3_stmt, column_index) -> sqlite3_value = library.load(symbol: "sqlite3_column_value")

    /// Value handle
    fileprivate typealias sqlite3_value = OpaquePointer

    // Dynamically Typed Value Object
    private static let sqlite3_value_blob: @convention(c) (sqlite3_value) -> UnsafeRawPointer? = library.load(symbol: "sqlite3_value_blob")
    private static let sqlite3_value_bytes: @convention(c) (sqlite3_value) -> Int32 = library.load(symbol: "sqlite3_value_bytes")
    private static let sqlite3_value_double: @convention(c) (sqlite3_value) -> Double = library.load(symbol: "sqlite3_value_double")
    private static let sqlite3_value_int64: @convention(c) (sqlite3_value) -> Int64 = library.load(symbol: "sqlite3_value_int64")
    private static let sqlite3_value_text: @convention(c) (sqlite3_value) -> UnsafePointer<UInt8>? = library.load(symbol: "sqlite3_value_text")
    private static let sqlite3_value_type: @convention(c) (sqlite3_value) -> Int32 = library.load(symbol: "sqlite3_value_type")

    // Error Codes And Messages
    private static let sqlite3_errmsg: @convention(c) (sqlite3?) -> UnsafePointer<Int8>? = library.load(symbol: "sqlite3_errmsg")
    private static let sqlite3_errstr: @convention(c) (sqlite3_result) -> UnsafePointer<Int8>? = library.load(symbol: "sqlite3_errstr")
}

private struct DynamicLinkLibrary {
    let path: String
    let handle: UnsafeMutableRawPointer

    init(path: String) {
        guard let handle = dlopen(path, RTLD_LAZY) else { fatalError("Failed to load \(path)") }
        self.path = path
        self.handle = handle
    }

    func load<T>(symbol: String) -> T {
        if let sym = dlsym(handle, symbol) {
            return unsafeBitCast(sym, to: T.self)
        }
        let errorString = String(validatingUTF8: dlerror()) ?? "unknown error"
        fatalError("Finding symbol \(symbol) failed: \(errorString)")
    }
}
