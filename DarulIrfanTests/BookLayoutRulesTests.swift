import SwiftUI
import XCTest
@testable import DarulIrfan

/// The display rules of the book reader, each tried on a page of a book that
/// the app ships.
final class BookLayoutRulesTests: XCTestCase {
    /// The books these tests read.
    private static let books: Set<String> = [
        "asrar-10-en",
        "book-ocr-sai-hafta-course",
        "tafaseer-parah-1",
        "uploads-books-tareeq-e-saluk-fi-adab-e-shayuk",
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

    // MARK: - The salawat sign among Urdu words

    func testOnlyTheSalawatSignIsEnlargedAndItsLinkIsKept() throws {
        let original = try page("uploads-books-tareeq-e-saluk-fi-adab-e-shayuk", 16).text
        let signs = original.unicodeScalars.filter { $0 == BookTextDrawing.salawat }.count
        XCTAssertGreaterThanOrEqual(signs, 4)

        var linked = AttributedString(original)
        let url = try XCTUnwrap(URL(string: "dibooklink:2"))
        linked.link = url
        let drawn = BookTextDrawing.enlargingSalawat(linked, scale: 1.2)
        XCTAssertEqual(Array(drawn.unicodeScalars), Array(original.unicodeScalars))

        let scalars = drawn.unicodeScalars
        var index = scalars.startIndex
        var enlarged = 0
        while index < scalars.endIndex {
            let next = scalars.index(after: index)
            let part = drawn[index..<next]
            XCTAssertEqual(part.link, url)
            let face = part[AttributeScopes.SwiftUIAttributes.FontAttribute.self]
            if scalars[index] == BookTextDrawing.salawat {
                XCTAssertEqual(face, DIFont.urduSalawat(scale: 1.2))
                enlarged += 1
            } else {
                XCTAssertNil(face)
            }
            index = next
        }
        XCTAssertEqual(enlarged, signs)
    }

    func testTheQuranReadersTafsirKeepsItsDrawing() {
        XCTAssertTrue(BookTextPlace.book.followsBookRules)
        XCTAssertTrue(BookTextPlace.article.followsBookRules)
        XCTAssertFalse(BookTextPlace.hadith.followsBookRules)
        XCTAssertFalse(BookTextPlace.quranReader.followsBookRules)
    }

    // MARK: - The small high rounded zero

    func testEverySmallHighZeroOfAPageIsDrawnInAmiri() throws {
        let text = try page("asrar-10-en", 2).text
        let scalars = Array(text.unicodeScalars)
        let zeros = scalars.indices.filter { scalars[$0].value == MushafFaceGaps.smallHighZero }
        XCTAssertEqual(zeros.count, 12)
        let spans = MushafFaceGaps.spans(in: scalars, showsSmallHighZero: true).filter { $0.face == .smallHighZero }
        for zero in zeros {
            let word = try XCTUnwrap(spans.first { $0.range.contains(zero) })
            // The whole word, so that its letters stay joined.
            let before = word.range.lowerBound - 1
            let after = word.range.upperBound
            if before >= 0 { XCTAssertTrue(scalars[before].properties.isWhitespace) }
            if after < scalars.count { XCTAssertTrue(scalars[after].properties.isWhitespace) }
        }
        XCTAssertFalse(MushafFaceGaps.spans(in: scalars).contains { $0.face == .smallHighZero })
        XCTAssertTrue(BookTextPlace.book.showsSmallHighZero)
        XCTAssertFalse(BookTextPlace.article.showsSmallHighZero)
        XCTAssertFalse(BookTextPlace.quranReader.showsSmallHighZero)
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
