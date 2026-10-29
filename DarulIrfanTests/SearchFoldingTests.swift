import XCTest
@testable import DarulIrfan

/// Arabic and Urdu are matched however they were typed: without harakat, on
/// an Arabic or an Urdu keyboard (IOSR-002). The folded form is only matched,
/// never shown: results show the original text.
final class SearchFoldingTests: XCTestCase {

    func testHarakatAndLetterFormsFold() {
        XCTAssertEqual(SearchNormalizer.normalize("بِسْمِ اللّٰهِ"), "بسم اللہ")
        XCTAssertEqual(SearchNormalizer.normalize("الصَّلٰوةَ"), "الصلوہ")
        XCTAssertEqual(SearchNormalizer.normalize("أحمد"), "احمد")
        XCTAssertEqual(SearchNormalizer.normalize("كتاب"), SearchNormalizer.normalize("کتاب"))
        XCTAssertEqual(SearchNormalizer.normalize("ايمان"), SearchNormalizer.normalize("ایمان"))
        XCTAssertEqual(SearchNormalizer.normalize("۲۵۵"), "255")
        XCTAssertEqual(SearchNormalizer.normalize("Prayer"), "Prayer")
    }

    func testQueryTermsAreFoldedLikeTheIndex() {
        XCTAssertEqual(SearchIndexService.searchTerms(from: "الرَّحْمٰن  ك"), ["الرحمن", "ک"])
        XCTAssertEqual(SearchIndexService.ftsMatchExpression(from: "الحمد"), "\"الحمد\"*")
    }

    /// The snippet comes from the original text, harakat and all, with the
    /// matched word marked.
    func testSnippetKeepsTheOriginalText() throws {
        let text = "اَلْحَمْدُ لِلّٰهِ رَبِّ الْعٰلَمِيْنَ"
        let snippet = try XCTUnwrap(SearchSnippet.make(from: text, terms: ["الحمد"]))
        XCTAssertTrue(snippet.contains("\u{2039}اَلْحَمْدُ\u{203A}"), snippet)
        XCTAssertTrue(snippet.contains("رَبِّ"))
    }
}
