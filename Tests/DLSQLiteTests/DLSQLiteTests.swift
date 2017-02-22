import XCTest
@testable import DLSQLite

class DLSQLiteTests: XCTestCase {

    func testLibraryInformation() {
        XCTAssertFalse(SQLite.libVersion.isEmpty)
        print("SQLite library version is `\(SQLite.libVersion)`.")
        XCTAssertNotEqual(SQLite.libVersionNumber, 0)
        print("SQLite library version number is \(SQLite.libVersionNumber).")
        XCTAssertFalse(SQLite.sourceId.isEmpty)
        print("SQLite library source id is `\(SQLite.sourceId)`.")
        print("SQLite library was compiled with `SQLITE_THREADSAFE=\(SQLite.threadSafe.rawValue)`.")
    }

    static var allTests : [(String, (DLSQLiteTests) -> () throws -> Void)] {
        return [
            ("testLibraryInformation", testLibraryInformation),
        ]
    }
}
