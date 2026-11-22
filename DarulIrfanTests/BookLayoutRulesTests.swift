import SwiftUI
import XCTest
@testable import DarulIrfan

/// The display rules of the book reader, each tried on a page of a book that
/// the app ships.
final class BookLayoutRulesTests: XCTestCase {
    /// The books these tests read.
    private static let books: Set<String> = [
        "book-ocr-sai-hafta-course",
        "tafaseer-parah-1",
    ]
    private static let shipped: [BookPage] = SeedBundle.bookPages().filter { books.contains($0.bookID) }

    private func pages(_ bookID: String) -> [BookPage] {
        Self.shipped.filter { $0.bookID == bookID }.sorted { $0.page < $1.page }
    }

    private func page(_ bookID: String, _ number: Int) throws -> BookPage {
        try XCTUnwrap(Self.shipped.first { $0.bookID == bookID && $0.page == number }, "\(bookID) p\(number)")
    }

    private func tables(_ page: BookPageFormatter.Page) -> [[[String]]] {
        page.blocks.compactMap { block in
            guard case .table(let rows) = block else { return nil }
            return rows
        }
    }

    // MARK: - An empty cell keeps its column

    func testAnEntryWithoutASerialNumberKeepsItsColumns() throws {
        let formatted = BookPageFormatter.format(page: try page("tafaseer-parah-1", 5))
        let rows = try XCTUnwrap(tables(formatted).first)
        XCTAssertEqual(rows[1], ["", "از دل خیزد بر دل ریزد", "7"])
        // A title without a page number keeps that column too.
        XCTAssertEqual(rows[3], ["", "سورۃ الفاتحہ", ""])
        XCTAssertEqual(rows[4], ["1", "دعا مانگنے کا طریقہ", "13"])
        XCTAssertTrue(rows.allSatisfy { $0.count == 3 })
    }

    func testASyllabusRowStaysUnderItsColumns() throws {
        let formatted = BookPageFormatter.format(page: try page("book-ocr-sai-hafta-course", 2))
        let rows = try XCTUnwrap(tables(formatted).first)
        XCTAssertEqual(Array(rows[1].prefix(5)), ["", "", "عبادات", "......", "9"])
    }
}
