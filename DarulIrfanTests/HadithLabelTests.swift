import XCTest
@testable import DarulIrfan

/// The book labels and narrator links of the October 2026 hadith follow-ups
/// (HAD-006/018/023): a book the source prints as "35b" is shown so, an
/// opening book the source does not number is never "Book 0", and the
/// source's id for an unnamed narrator (1131) is not a link.
final class HadithLabelTests: XCTestCase {
    private func book(_ sections: [HadithSection]) -> HadithBook {
        HadithBook(id: "nasai", titleEnglish: "Sunan an-Nasa'i", titleUrdu: "سنن نسائی",
                   hadithCount: 3, hasArabic: true, hasEnglish: true, hasUrdu: true,
                   sectionCount: sections.count, sections: sections)
    }

    func testLabelledBookIsPrintedByItsLabel() {
        let nasai = book([
            HadithSection(number: 35, titleEnglish: "The Book of Oaths and Vows",
                          titleArabic: "كتاب الأيمان والنذور", hadithCount: 1),
            HadithSection(number: 0, titleEnglish: "The Book of Agriculture",
                          titleArabic: "كتاب المزارعة", hadithCount: 83, label: "35b"),
        ])
        XCTAssertEqual(nasai.printedSectionNumber(0), "35b")
        XCTAssertEqual(nasai.printedSectionNumber(35), "35")
        XCTAssertEqual(nasai.section(number: 0)?.displayNumber, "35b")
        XCTAssertEqual(nasai.section(number: 0)?.isUnnumbered, false)
    }

    func testUnnumberedOpeningBookHasNoNumber() {
        let muslim = book([
            HadithSection(number: 0, titleEnglish: "Introduction", titleArabic: "المقدمة", hadithCount: 93),
            HadithSection(number: 1, titleEnglish: "The Book of Faith", titleArabic: "كتاب الإيمان", hadithCount: 431),
        ])
        XCTAssertNil(muslim.printedSectionNumber(0))
        XCTAssertEqual(muslim.section(number: 0)?.isUnnumbered, true)
        XCTAssertEqual(muslim.printedSectionNumber(1), "1")
        // A number the catalogue does not list is shown as it is; 0 never.
        XCTAssertEqual(muslim.printedSectionNumber(7), "7")
        XCTAssertNil(book([]).printedSectionNumber(0))
    }

    func testLabelDecodesFromTheCatalogueAndRoundTrips() throws {
        let json = #"{"number":0,"titleEnglish":"The Book of Agriculture","titleArabic":"كتاب المزارعة","hadithCount":83,"label":"35b"}"#
        let section = try JSONDecoder().decode(HadithSection.self, from: Data(json.utf8))
        XCTAssertEqual(section.displayNumber, "35b")
        let again = try JSONDecoder().decode(HadithSection.self, from: JSONEncoder().encode(section))
        XCTAssertEqual(again.label, "35b")
        let older = #"{"number":0,"titleEnglish":"Introduction","titleArabic":"المقدمة","hadithCount":93}"#
        XCTAssertNil(try JSONDecoder().decode(HadithSection.self, from: Data(older.utf8)).label)
    }

    func testUnnamedNarratorIsNotALink() {
        XCTAssertNil(HadithSegment(kind: .isnad, text: "رَجُلٌ", narratorId: 1131).linkedNarratorID)
        XCTAssertEqual(HadithSegment(kind: .isnad, text: "قَالَ ابْنُ شِهَابٍ", narratorId: 7272).linkedNarratorID, 7272)
        XCTAssertNil(HadithSegment(kind: .isnad, text: "عَنْ", narratorId: nil).linkedNarratorID)
        XCTAssertNil(HadithSegment(kind: .matn, text: "إِنَّمَا الأَعْمَالُ", narratorId: 7272).linkedNarratorID)
        XCTAssertNil(HadithSegment(kind: .verse, text: "اللَّهُ لاَ إِلَهَ إِلاَّ هُوَ", surah: 2, ayahStart: 255).linkedNarratorID)
    }
}
