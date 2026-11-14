import XCTest
@testable import DarulIrfan

/// The links in a book's text: where a page cites or quotes an ayah, quotes a
/// narration or names a narrator, and what each of those opens.
final class BookLinkTests: XCTestCase {

    func testAReferenceInAParagraphBecomesItsOwnPiece() {
        let links = [BookLink(m: "(Al-Baqarah: 255)", t: "q:2:255")]
        let pieces = BookLinkMatcher.pieces(of: "As the verse says (Al-Baqarah: 255) and so on.", links: links)
        XCTAssertEqual(pieces, [
            BookLinkMatcher.Piece(text: "As the verse says ", link: nil),
            BookLinkMatcher.Piece(text: "(Al-Baqarah: 255)", link: 0),
            BookLinkMatcher.Piece(text: " and so on.", link: nil),
        ])
    }

    func testEveryPlaceANameStandsIsLinked() {
        let links = [BookLink(m: "Abu Hurayra", t: "n:4396")]
        let pieces = BookLinkMatcher.pieces(of: "Abu Hurayra said, and Abu Hurayra heard", links: links)
        XCTAssertEqual(pieces.map(\.text), ["Abu Hurayra", " said, and ", "Abu Hurayra", " heard"])
        XCTAssertEqual(pieces.map(\.link), [0, nil, 0, nil])
    }

    func testTheLongerWordingWinsOverAShorterOneInsideIt() {
        let links = [
            BookLink(m: "Umar", t: "n:5913"),
            BookLink(m: "Umar ibn Abd al-Aziz", t: "n:5974"),
        ]
        let pieces = BookLinkMatcher.pieces(of: "Umar ibn Abd al-Aziz wrote to Umar", links: links)
        XCTAssertEqual(pieces.map(\.text), ["Umar ibn Abd al-Aziz", " wrote to ", "Umar"])
        XCTAssertEqual(pieces.map(\.link), [1, nil, 0])
    }

    func testTextWithoutALinkStaysOnePlainPiece() {
        let links = [BookLink(m: "(An-Nur: 35)", t: "q:24:35")]
        XCTAssertEqual(
            BookLinkMatcher.pieces(of: "No reference here.", links: links),
            [BookLinkMatcher.Piece(text: "No reference here.", link: nil)]
        )
        XCTAssertEqual(
            BookLinkMatcher.pieces(of: "No links at all.", links: []),
            [BookLinkMatcher.Piece(text: "No links at all.", link: nil)]
        )
    }

    func testUrduWordsAreFoundAsTheyAreWritten() {
        let links = [BookLink(m: "حضرت ابو ہریرہ", t: "n:4396")]
        let pieces = BookLinkMatcher.pieces(of: "ایک بار حضرت ابو ہریرہ نے فرمایا", links: links)
        XCTAssertEqual(pieces.map(\.text), ["ایک بار ", "حضرت ابو ہریرہ", " نے فرمایا"])
        XCTAssertEqual(pieces.map(\.link), [nil, 0, nil])
    }

    func testATargetIsReadFromItsText() {
        XCTAssertEqual(BookLinkTarget("q:2:255"), .ayah(surah: 2, ayah: 255))
        XCTAssertEqual(BookLinkTarget("q:2:255-257"), .ayah(surah: 2, ayah: 255))
        XCTAssertEqual(BookLinkTarget("h:bukhari|6|6"), .hadith(canonicalID: "bukhari|6|6"))
        XCTAssertEqual(BookLinkTarget("h:muslim|8:1|12"), .hadith(canonicalID: "muslim|8:1|12"))
        XCTAssertEqual(BookLinkTarget("n:4396"), .narrator(id: 4396))
    }

    func testATargetThatCannotBeReadIsNoLink() {
        XCTAssertNil(BookLinkTarget(""))
        XCTAssertNil(BookLinkTarget("q:2"))
        XCTAssertNil(BookLinkTarget("q:115:1"))
        XCTAssertNil(BookLinkTarget("q:2:0"))
        XCTAssertNil(BookLinkTarget("n:abc"))
        XCTAssertNil(BookLinkTarget("x:1"))
        XCTAssertNil(BookLinkTarget("h:"))
    }

    func testAnAppraisalNamesItsScholarInTheReadersLanguage() {
        let appraisal = NarratorAppraisal(
            scholar: "al-Dhahabi",
            scholarArabic: "الذهبي",
            textArabic: "ثقة",
            textEnglish: "Trustworthy.",
            textUrdu: "یہ ثقہ (قابلِ اعتماد) ہیں۔",
            scholarUrdu: "ذہبی"
        )
        XCTAssertEqual(appraisal.scholarName(languageCode: "en"), "al-Dhahabi")
        XCTAssertEqual(appraisal.scholarName(languageCode: "ur"), "ذہبی")

        let arabicOnly = NarratorAppraisal(scholarArabic: "الذهبي", textArabic: "ثقة")
        XCTAssertEqual(arabicOnly.scholarName(languageCode: "en"), "الذهبي")
        XCTAssertEqual(arabicOnly.scholarName(languageCode: "ur"), "الذهبي")
        XCTAssertNil(NarratorAppraisal(textArabic: "ثقة").scholarName(languageCode: "en"))
    }
}
