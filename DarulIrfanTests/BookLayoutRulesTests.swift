import SwiftUI
import XCTest
@testable import DarulIrfan

/// The display rules of the book reader, each tried on a page of a book that
/// the app ships.
final class BookLayoutRulesTests: XCTestCase {
    /// The books these tests read.
    private static let books: Set<String> = [
        "asrar-10-en",
        "asrar-10-ur",
        "asrar-100-en",
        "asrar-11-ur",
        "asrar-16-en",
        "asrar-18-en",
        "asrar-2-en",
        "asrar-23-ur",
        "asrar-5-en",
        "asrar-6-ur",
        "book-hayyat-e-tayyabah-i",
        "book-ocr-gard-e-safar",
        "book-ocr-hamd-o-naat",
        "book-ocr-hasht-roza-course",
        "book-ocr-pardah",
        "book-ocr-sai-hafta-course",
        "book-ocr-shajarah-e-silsilah-e-nisbaat-e-owaisiah",
        "tafaseer-parah-1",
        "tafaseer-parah-28",
        "tafaseer-parah-4",
        "tafaseer-parah-9",
        "uploads-books-maktobaat",
        "uploads-books-tasawwuf-aur-tameer-e-seraat",
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

    // MARK: - A sentence the page break cuts

    /// The words page `number` takes from the next one.
    private func carried(_ bookID: String, _ number: Int) throws -> String? {
        let first = try page(bookID, number)
        let next = try page(bookID, number + 1)
        let laid = try XCTUnwrap(BookPageFormatter.format(pages: [first, next])[first.id])
        guard let carried = laid.carried, case .paragraph(let runs)? = laid.blocks.last else { return nil }
        return (runs[carried.run].text as NSString).substring(from: carried.offset)
    }

    func testTheClosingQuoteGoesWithItsSentence() throws {
        let moved = try carried("book-ocr-pardah", 3)
        let words = try XCTUnwrap(moved)
        XCTAssertTrue(words.hasSuffix("احکام شامل ہیں۔\""), words)
        let pair = [try page("book-ocr-pardah", 3), try page("book-ocr-pardah", 4)]
        let laid = try XCTUnwrap(BookPageFormatter.format(pages: pair)[pair[1].id])
        // Page 4 no longer opens with a paragraph that is only a quote mark.
        guard case .paragraph(let runs)? = laid.blocks.first else { return XCTFail("\(laid.blocks)") }
        XCTAssertTrue(runs[0].text.hasPrefix("عیسائی مذہب"), runs[0].text)
        XCTAssertEqual(try carried("asrar-18-en", 24), "believe this simple fact.\"")
        XCTAssertEqual(try carried("asrar-10-en", 11), "brotherhood.")
    }

    func testAnEndedSentenceASerialNumberAndASplitWordTakeNothing() throws {
        let cases: [(String, Int)] = [
            // "4۔" and "10." stay with their items.
            ("uploads-books-tareeq-e-saluk-fi-adab-e-shayuk", 129),
            ("asrar-100-en", 1),
            // "i.e." is not cut after its "i.".
            ("asrar-16-en", 21),
            // A full stop inside the quote that closes the page.
            ("book-hayyat-e-tayyabah-i", 200),
            // A row of stars is no sentence.
            ("asrar-5-en", 37),
        ]
        for (bookID, number) in cases {
            XCTAssertNil(try carried(bookID, number), "\(bookID) p\(number)")
        }
    }

    func testAtMost240CharactersAreCarried() throws {
        let cases: [(String, Int)] = [
            ("asrar-11-ur", 31), ("asrar-23-ur", 14), ("asrar-6-ur", 27),
            ("book-ocr-sai-hafta-course", 156), ("tafaseer-parah-4", 160), ("tafaseer-parah-9", 108),
        ]
        for (bookID, number) in cases {
            XCTAssertNil(try carried(bookID, number), "\(bookID) p\(number) has 241")
        }
        // The stop is one of the 240.
        func offered(_ letters: Int) -> BookPageFormatter.Carried? {
            let cut = BookPage(bookID: "b", page: 1, text: "یہ جملہ اس صفحے پر پورا نہیں ہوا اور",
                               blocks: 1, unresolvedBlocks: 0, layout: "p")
            let next = BookPage(bookID: "b", page: 2, text: String(repeating: "ا", count: letters) + "۔ دوسرا جملہ۔",
                                blocks: 1, unresolvedBlocks: 0, layout: "p")
            return BookPageFormatter.format(pages: [cut, next])[cut.id]?.carried
        }
        XCTAssertNotNil(offered(239))
        XCTAssertNil(offered(240))
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

    func testArabicIndicDigitsKeepTheirOrderToo() throws {
        let text = try page("uploads-books-tasawwuf-aur-tameer-e-seraat", 67).text
        let token = "\u{0666}\u{0667} : \u{0661}\u{0660}"
        XCTAssertTrue(text.contains(token))
        // An isolate alone leaves them turned round, as these digits are not strong.
        XCTAssertTrue(BookTextDrawing.isolatingNumbers([text]).joined().contains("\u{2066}\u{202D}\(token)\u{202C}\u{2069}"))
    }

    func testANumberAfterLatinLettersIsLeftWithItsWord() throws {
        let text = try page("book-ocr-hamd-o-naat", 3).text
        let after = "Ph:+92 41 2615359"
        XCTAssertTrue(text.contains(after))
        XCTAssertTrue(BookTextDrawing.isolatingNumbers([text]).joined().contains(after))
        // Another block's Latin does not reach a number on a later line.
        XCTAssertEqual(
            BookTextDrawing.isolatingNumbers(["Tel\n0300-6658928"]),
            ["Tel\n\u{2066}0300-6658928\u{2069}"]
        )
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

    @MainActor
    func testACardAtTheEndCountsToTheBooksLastPage() {
        let entries = BookTextEntry.entries(of: pages("book-ocr-hasht-roza-course"))
        XCTAssertEqual(entries.last, .noText(207...208))
        let session = BookReaderSession()
        session.pageNumbers = entries.map(\.id)
        session.lastPage = entries.last?.lastPage
        XCTAssertEqual(session.pageNumbers.last, 207)
        XCTAssertEqual(session.pageTotal, 208)
        XCTAssertEqual(BookTextEntry.holding(208, in: entries)?.id, 207)
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

    // MARK: - A reference is found in its whole paragraph

    func testALinkAcrossAQuotationInsideAParagraphIsWhole() throws {
        let bookID = "tafaseer-parah-28"
        let laid = BookPageFormatter.format(page: try page(bookID, 108))
        let links = try XCTUnwrap(BookLinkProvider.shared.links(bookID: bookID)[108])
        let verse = try XCTUnwrap(links.first { $0.t == "q:61:4" })
        var linked: [String] = []
        for case .paragraph(let runs) in laid.blocks {
            let byRun = BookLinkMatcher.pieces(ofParagraph: runs, carried: nil, links: links, carriedLinks: [])
            let parts = byRun.flatMap { $0 }.filter { piece in piece.link.map { links[$0] == verse } ?? false }
            if !parts.isEmpty { linked.append(parts.map(\.text).joined(separator: " ")) }
            // No run on its own holds these words.
            XCTAssertFalse(runs.contains { $0.text.contains(verse.m) })
        }
        XCTAssertEqual(linked, [verse.m])
    }

    func testALinkAcrossTheCutOfAQuotationIsFound() throws {
        let bookID = "asrar-10-ur"
        let laid = BookPageFormatter.format(page: try page(bookID, 2))
        let links = try XCTUnwrap(BookLinkProvider.shared.links(bookID: bookID)[2])
        var alone = 0
        var whole = 0
        for (index, block) in laid.blocks.enumerated() {
            let text: String
            switch block {
            case .quran(let words), .arabic(let words): text = words
            default: continue
            }
            let cut = laid.cutQuotation(at: index)
            alone += BookLinkMatcher.pieces(of: text, links: links).filter { $0.link != nil }.count
            whole += BookLinkMatcher.pieces(of: text, cutFrom: cut, links: links).filter { $0.link != nil }.count
        }
        XCTAssertGreaterThan(whole, alone)
    }

    func testCarriedWordsTakeTheNextPagesLinksAndOnlyThose() throws {
        let bookID = "asrar-2-en"
        let first = try page(bookID, 26)
        let next = try page(bookID, 27)
        let laid = try XCTUnwrap(BookPageFormatter.format(pages: [first, next])[first.id])
        let carried = try XCTUnwrap(laid.carried)
        guard case .paragraph(let runs)? = laid.blocks.last else { return XCTFail("\(laid.blocks)") }
        let found = BookLinkProvider.shared.links(bookID: bookID)
        let own = found[26] ?? []
        let theirs = try XCTUnwrap(found[27])
        let byRun = BookLinkMatcher.pieces(ofParagraph: runs, carried: carried, links: own, carriedLinks: theirs)
        let piece = try XCTUnwrap(byRun.flatMap { $0 }.first { $0.text == "(7:172)" })
        let index = try XCTUnwrap(piece.link)
        XCTAssertGreaterThanOrEqual(index, own.count)
        XCTAssertEqual((own + theirs)[index].t, "q:7:172")
        // The same words without a carry open nothing of the next page's.
        let without = BookLinkMatcher.pieces(ofParagraph: runs, carried: nil, links: own, carriedLinks: theirs)
        XCTAssertFalse(without.flatMap { $0 }.contains { ($0.link ?? -1) >= own.count })
    }

    // MARK: - Links are underlined

    func testALinkIsUnderlinedAndTheSalawatLineIsNot() throws {
        let bookID = "book-ocr-shajarah-e-silsilah-e-nisbaat-e-owaisiah"
        let parts = try XCTUnwrap(BookPageFormatter.laidOutParts(of: try page(bookID, 2)))
        let links = try XCTUnwrap(BookLinkProvider.shared.links(bookID: bookID)[2])

        // "بِسْمِ اللّٰہِ" opens 1:1; the fifth line, the salawat, opens nothing.
        let linked = BookLinkMatcher.pieces(of: parts[1].text, links: links).filter { $0.link != nil }
        let piece = try XCTUnwrap(linked.first)
        let drawn = BookTextDrawing.link(piece.text, index: try XCTUnwrap(piece.link))
        XCTAssertNotNil(drawn.link)
        XCTAssertNotNil(drawn[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self])
        XCTAssertEqual(Array(drawn.unicodeScalars), Array(piece.text.unicodeScalars))

        XCTAssertFalse(BookLinkMatcher.pieces(of: parts[4].text, links: links).contains { $0.link != nil })
    }

    // MARK: - Tables on a phone

    /// What a 360 pt screen leaves a table: the list, the sheet and the
    /// table's own padding.
    private let tableWidthOnAPhone = 360.0 - 2 * 16 - 2 * 22 - 2 * 8

    func testNoWordOfATableIsBrokenOnAPhone() throws {
        AppFonts.registerBundledFonts()
        let formatted = BookPageFormatter.format(page: try page("book-ocr-sai-hafta-course", 2))
        let found = tables(formatted)
        XCTAssertFalse(found.isEmpty)
        let font = DIFont.urduBodyUIFont(scale: 0.85, typeSize: .large)
        for rows in found {
            let layout = BookPageFormatter.tableLayout(rows)
            let minimums = BookTableMeasure.columnMinimums(rows, layout: layout, font: font, enlargesSalawat: true)
            if let widths = BookPageFormatter.tableWidths(
                available: tableWidthOnAPhone, spacing: 8, minimums: minimums, layout: layout
            ) {
                for (width, minimum) in zip(widths, minimums) {
                    XCTAssertGreaterThanOrEqual(width + 0.001, minimum)
                }
                XCTAssertLessThanOrEqual(widths.reduce(0, +) + 8 * Double(widths.count - 1), tableWidthOnAPhone + 0.001)
            } else {
                // Stacked, every cell has the whole width.
                for minimum in minimums {
                    XCTAssertLessThanOrEqual(minimum, tableWidthOnAPhone)
                }
            }
        }
    }

    func testTwoColumnsOfLongTextStackUnder480() throws {
        let formatted = BookPageFormatter.format(page: try page("uploads-books-tareeq-e-saluk-fi-adab-e-shayuk", 16))
        let rows = try XCTUnwrap(tables(formatted).last)
        let layout = BookPageFormatter.tableLayout(rows)
        XCTAssertTrue(layout.hasLongTextColumns)
        XCTAssertNil(BookPageFormatter.tableWidths(available: 479, spacing: 8, minimums: [90, 90], layout: layout))
        XCTAssertNotNil(BookPageFormatter.tableWidths(available: 480, spacing: 8, minimums: [90, 90], layout: layout))
    }

    func testColumnsShareOnlyWhatTheLongestWordsLeave() {
        let layout = BookPageFormatter.TableLayout(weights: [1, 3], hasHeaderRow: false, hasLongTextColumns: false)
        XCTAssertEqual(
            BookPageFormatter.tableWidths(available: 188, spacing: 8, minimums: [60, 40], layout: layout),
            [80, 100]
        )
        XCTAssertNil(BookPageFormatter.tableWidths(available: 100, spacing: 8, minimums: [60, 40], layout: layout))
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
