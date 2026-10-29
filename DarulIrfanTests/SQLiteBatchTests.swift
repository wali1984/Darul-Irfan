import Foundation
import XCTest
@testable import DarulIrfan

/// `SQLiteDatabase.executeBatch` prepares each distinct statement once and
/// re-binds it per row. Every row must still land with its own values, rows
/// must see the ones before them, and a failure must undo the whole batch.
final class SQLiteBatchTests: XCTestCase {

    private var database: SQLiteDatabase!

    override func setUp() async throws {
        database = try SQLiteDatabase(url: nil)
        try await database.executeScript("CREATE TABLE t (id INTEGER PRIMARY KEY, label TEXT, score REAL);")
    }

    override func tearDown() {
        database = nil
    }

    func testRepeatedStatementInsertsEveryRowWithItsOwnValues() async throws {
        let insert = "INSERT INTO t (id, label, score) VALUES (?, ?, ?)"
        var statements: [(sql: String, parameters: [SQLValue])] = (1...2_000).map { index in
            (insert, [.int(index), index.isMultiple(of: 2) ? .text("even \(index)") : .null, .real(Double(index) / 2)])
        }
        // A later statement sees the rows before it in the same batch.
        statements.append(("UPDATE t SET label = 'last' WHERE id = (SELECT MAX(id) FROM t)", []))
        try await database.executeBatch(statements)

        let count = try await database.query("SELECT COUNT(*) AS n FROM t").first?.int("n")
        XCTAssertEqual(count, 2_000)
        let row = try await database.query("SELECT label, score FROM t WHERE id = 1234").first
        XCTAssertEqual(row?.text("label"), "even 1234")
        XCTAssertEqual(row?.double("score"), 617)
        let odd = try await database.query("SELECT label FROM t WHERE id = 7").first
        XCTAssertNil(odd?.text("label"), "A NULL is not left over from the row before")
        let last = try await database.query("SELECT label FROM t WHERE id = 2000").first
        XCTAssertEqual(last?.text("label"), "last")
    }

    func testAFailingRowUndoesTheWholeBatch() async throws {
        let insert = "INSERT INTO t (id, label, score) VALUES (?, ?, ?)"
        let statements: [(sql: String, parameters: [SQLValue])] = [
            (insert, [.int(1), .text("one"), .real(1)]),
            (insert, [.int(2), .text("two"), .real(2)]),
            // Same primary key: fails.
            (insert, [.int(1), .text("again"), .real(3)]),
        ]
        do {
            try await database.executeBatch(statements)
            XCTFail("The duplicate key must fail the batch")
        } catch {}

        let count = try await database.query("SELECT COUNT(*) AS n FROM t").first?.int("n")
        XCTAssertEqual(count, 0, "Nothing from a failed batch stays")
        // The connection is usable afterwards.
        try await database.executeBatch([(insert, [.int(5), .text("five"), .real(5)])])
        let after = try await database.query("SELECT COUNT(*) AS n FROM t").first?.int("n")
        XCTAssertEqual(after, 1)
    }
}
