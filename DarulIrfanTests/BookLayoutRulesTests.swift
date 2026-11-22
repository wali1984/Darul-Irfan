import SwiftUI
import XCTest
@testable import DarulIrfan

/// The display rules of the book reader, each tried on a page of a book that
/// the app ships.
final class BookLayoutRulesTests: XCTestCase {
    /// The books these tests read.
    private static let books: Set<String> = [
        "asrar-10-en",
        "book-hayyat-e-tayyabah-i",
        "book-ocr-gard-e-safar",
        "book-ocr-hamd-o-naat",
        "book-ocr-pardah",
        "book-ocr-sai-hafta-course",
        "tafaseer-parah-1",
        "uploads-books-maktobaat",
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

    // MARK: - Numbers in their stored order

    func testDatesPhonesAndReferencesAreIsolated() throws {
        let cases = [
            ("uploads-books-maktobaat", 8, "13-9-63"),
            ("uploads-books-tareeq-e-saluk-fi-adab-e-shayuk", 16, "3 : 164"),
            ("book-ocr-hamd-o-naat", 3, "0300-6658928"),
            ("book-ocr-sai-hafta-course", 2, "12-13"),
        ]
        for (bookID, number, token) in cases {
            let text = try page(bookID, number).text
            let drawn = BookTextDrawing.isolatingNumbers([text]).joined()
            XCTAssertTrue(drawn.contains("\u{2066}\(token)\u{2069}"), token)
            // The isolates are all that drawing adds.
            let without = drawn
                .replacingOccurrences(of: "\u{2066}", with: "", options: .literal)
                .replacingOccurrences(of: "\u{2069}", with: "", options: .literal)
            XCTAssertEqual(Array(without.unicodeScalars), Array(text.unicodeScalars))
        }
    }

    func testNumbersStoredBackToFrontAreLeftAlone() throws {
        let text = try page("book-hayyat-e-tayyabah-i", 156).text
        XCTAssertTrue(text.contains("57-1956"))
        let whole = text as NSString
        XCTAssertFalse(BookTextDrawing.numberTokens(in: text).map { whole.substring(with: $0) }.contains("57-1956"))
        for untouched in ["70-7-4", "25-1924", "4:103", "102-101"] {
            XCTAssertEqual(BookTextDrawing.numberTokens(in: "تاریخ \(untouched) کو"), [], untouched)
        }
        XCTAssertEqual(BookTextDrawing.isolatingNumbers(["آیت 79:18-19 ہے"]), ["آیت \u{2066}79:18-19\u{2069} ہے"])
    }

    func testALinkThatEndsInsideANumberKeepsItsWords() {
        XCTAssertEqual(
            BookTextDrawing.isolatingNumbers(["آیت ", "3 : 1", "64 ہے"]),
            ["آیت ", "\u{2066}3 : 1", "64\u{2069} ہے"]
        )
    }

    // MARK: - Pages without text

    func testAnEmptyPageAndAMissingPageEachKeepACard() throws {
        let pardah = BookTextEntry.entries(of: pages("book-ocr-pardah"))
        XCTAssertEqual(pardah.first, .noText(1...1))
        XCTAssertEqual(pardah.dropFirst().first?.id, 2)

        let safar = BookTextEntry.entries(of: pages("book-ocr-gard-e-safar"))
        XCTAssertEqual(BookTextEntry.holding(6, in: safar), .noText(6...6))
        XCTAssertEqual(BookTextEntry.holding(7, in: safar)?.id, 7)
    }

    func testNeighboursShareACardAndABookWithoutTextHasNone() {
        func blank(_ number: Int, _ text: String = "") -> BookPage {
            BookPage(bookID: "b", page: number, text: text, blocks: 0, unresolvedBlocks: 0)
        }
        let book = [blank(2), blank(3, "متن"), blank(6, "متن"), blank(8)]
        XCTAssertEqual(
            BookTextEntry.entries(of: book),
            [.noText(1...2), .page(book[1]), .noText(4...5), .page(book[2]), .noText(7...8)]
        )
        XCTAssertEqual(BookTextEntry.entries(of: [blank(1), blank(2)]), [])
    }

    func testNoSentenceCrossesAPageWithoutText() throws {
        let safar = pages("book-ocr-gard-e-safar")
        let before = try page("book-ocr-gard-e-safar", 5)
        let after = try page("book-ocr-gard-e-safar", 7)
        let together = BookPageFormatter.format(pages: safar)
        // Nothing is added to the page before the card from the page after it.
        XCTAssertEqual(
            together[before.id]?.blocks.last,
            BookPageFormatter.format(page: before).blocks.last
        )
        XCTAssertEqual(
            together[after.id]?.blocks.first,
            BookPageFormatter.format(page: after).blocks.first
        )
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
