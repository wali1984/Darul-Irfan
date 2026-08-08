import Foundation
import XCTest
@testable import DarulIrfan

/// Guards the rule behind the reader's Basmala header.
///
/// The header is drawn for every surah except **Al-Fatihah (1)** and
/// **At-Tawbah (9)**, and its text is read from the mushaf at Al-Fatihah 1:1
/// rather than hardcoded. Both halves of that depend on facts about the bundled
/// seed, so a future mushaf swap could silently break it — printing the Basmala
/// twice, in the wrong script, or not at all. These tests fail loudly instead.
final class QuranBasmalaTests: XCTestCase {

    /// Arabic letters only: drops diacritics, tatweel, and the ayah-end marks,
    /// so orthographic variants of the Basmala still compare equal.
    private func letters(_ text: String) -> String {
        let arabicLetters = UnicodeScalar("\u{0621}")...UnicodeScalar("\u{064A}")
        return String(String.UnicodeScalarView(
            text.unicodeScalars.filter { arabicLetters.contains($0) }
        ))
    }

    private func ayahs() throws -> [QuranAyah] {
        let all = SeedBundle.quranAyahs()
        try XCTSkipIf(all.isEmpty, "Arabic text pack not bundled in this configuration")
        return all
    }

    private func firstAyah(_ ayahs: [QuranAyah], surah: Int) -> QuranAyah? {
        ayahs.first { $0.surahNumber == surah && $0.ayahNumber == 1 }
    }

    /// The header sources its text from 1:1, so 1:1 must actually *be* the
    /// Basmala — true in the Kufan numbering this mushaf follows.
    func testAlFatihahOpeningAyahIsTheBasmala() throws {
        let opening = try XCTUnwrap(firstAyah(try ayahs(), surah: 1))
        XCTAssertEqual(letters(opening.textArabic), "بسماللهالرحمنالرحيم")
    }

    /// At-Tawbah is the one surah of the 114 that has no Basmala. If the seed
    /// ever gained one there it would be an addition to the text, so assert its
    /// absence rather than merely excluding surah 9 in the view.
    func testAtTawbahHasNoBasmala() throws {
        let all = try ayahs()
        let basmala = letters(try XCTUnwrap(firstAyah(all, surah: 1)).textArabic)
        let opening = try XCTUnwrap(firstAyah(all, surah: 9))
        XCTAssertFalse(letters(opening.textArabic).contains(basmala))
    }

    /// No surah other than Al-Fatihah may open with the Basmala as its own ayah
    /// 1 — if one did, the header above it would print the line twice.
    func testNoOtherSurahCarriesTheBasmalaAsItsFirstAyah() throws {
        let all = try ayahs()
        let basmala = letters(try XCTUnwrap(firstAyah(all, surah: 1)).textArabic)
        let duplicating = (2...114).filter { surah in
            guard let opening = firstAyah(all, surah: surah) else { return false }
            return letters(opening.textArabic).hasPrefix(basmala)
        }
        XCTAssertEqual(duplicating, [], "These surahs would render the Basmala twice")
    }

    /// An-Naml 27:30 quotes the Basmala inside Sulayman's letter. That is verse
    /// text, not an opening, and must survive untouched — it is the reason the
    /// rule keys on ayah 1 rather than searching the surah.
    func testAnNamlKeepsTheBasmalaInsideAyahThirty() throws {
        let all = try ayahs()
        let basmala = letters(try XCTUnwrap(firstAyah(all, surah: 1)).textArabic)
        let verse = try XCTUnwrap(all.first { $0.surahNumber == 27 && $0.ayahNumber == 30 })
        XCTAssertTrue(letters(verse.textArabic).contains(basmala))
    }
}
