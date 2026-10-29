import XCTest
@testable import DarulIrfan

/// The tafsir text the reader shows (owner, 29 October 2026): Akram-ut-
/// Tafaseer quotes the Qur'an in the mushaf's own words, and the English
/// Asrar-at-Tanzil commentary opens on the ayat, not on the book's
/// introduction to the surah.
final class TafsirTextTests: XCTestCase {

    /// The OCR read 1:4 with its letters right and its vowels wrong; the
    /// commentary now quotes the mushaf.
    func testAkramUtTafaseerQuotesTheMushafsWords() throws {
        try XCTSkipIf(SeedBundle.manifest() == nil, "SeedData resources are not visible to this test host")
        let fatihah = SeedBundle.quranTafsir().filter { $0.editionID == "akram-ut-tafaseer-ur" && $0.surahNumber == 1 }
        XCTAssertFalse(fatihah.isEmpty)
        XCTAssertFalse(fatihah.contains { $0.text.contains("مُلْكُ يَوْمِ الدِّيْنِ") }, "1:4 is still quoted as the OCR read it")
    }

    func testEnglishCommentaryOpensOnTheAyatNotTheSurahIntroduction() throws {
        try XCTSkipIf(SeedBundle.manifest() == nil, "SeedData resources are not visible to this test host")
        let openings = SeedBundle.quranTafsir().filter { $0.editionID == "asrar-at-tanzil-en" && $0.ayahStart == 1 }
        XCTAssertGreaterThan(openings.count, 100)
        let introduced = openings.filter { row in
            row.text.components(separatedBy: "\n\n").prefix(4).contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "Salient Features" }
        }
        XCTAssertTrue(introduced.isEmpty, "Surahs still opening on the introduction: \(introduced.map(\.surahNumber))")
    }

    /// Al-Baqarah's English commentary is cut where it turns to each ayah.
    func testEnglishCommentaryFollowsItsAyat() throws {
        try XCTSkipIf(SeedBundle.manifest() == nil, "SeedData resources are not visible to this test host")
        let starts = Set(SeedBundle.quranTafsir()
            .filter { $0.editionID == "asrar-at-tanzil-en" && $0.surahNumber == 2 }
            .map(\.ayahStart))
        for ayah in [3, 7, 11, 13, 16, 17, 18, 22, 25, 26, 27, 28, 29] {
            XCTAssertTrue(starts.contains(ayah), "2:\(ayah) has no commentary of its own")
        }
    }
}
