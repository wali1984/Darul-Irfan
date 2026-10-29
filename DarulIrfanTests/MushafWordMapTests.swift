import XCTest
@testable import DarulIrfan

/// The reader draws the mushaf (quran_ayahs.json), never the reciter's word
/// list, which follows the recitation - its repeats, and in some ayat a word
/// missing or spelt otherwise. The timings only say which mushaf word to
/// tint, through `MushafWordMap`; these tests hold both halves of that.
final class MushafWordMapTests: XCTestCase {

    private func letters(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter {
            $0.properties.generalCategory == .otherLetter
        }))
    }

    private func verse(_ surah: Int, _ ayah: Int) -> RecitationVerse? {
        RecitationProvider.shared.recitation(forSurah: surah)?.verse(ayah)
    }

    private func mushaf(_ surah: Int, _ ayah: Int) throws -> String {
        let ayahs = SeedBundle.quranAyahs()
        try XCTSkipIf(ayahs.isEmpty, "Arabic text pack not bundled in this configuration")
        return try XCTUnwrap(ayahs.first { $0.surahNumber == surah && $0.ayahNumber == ayah }).textArabic
    }

    /// Tinting any word of any ayah leaves the text exactly the mushaf's, and
    /// the tinted word holds the letters of the word being recited.
    func testEveryTintLeavesTheMushafTextExactlyAsItIs() throws {
        let ayahs = SeedBundle.quranAyahs()
        try XCTSkipIf(ayahs.isEmpty, "Arabic text pack not bundled in this configuration")
        var mapped = 0
        for ayah in ayahs {
            guard let verse = verse(ayah.surahNumber, ayah.ayahNumber),
                  let map = MushafWordMap(text: ayah.textArabic, words: verse.words) else { continue }
            mapped += 1
            for position in map.ranges.keys {
                let pieces = try XCTUnwrap(map.pieces(of: ayah.textArabic, position: position))
                XCTAssertEqual(pieces.before + pieces.word + pieces.after, ayah.textArabic, "\(ayah.id) word \(position)")
                let recited = verse.words.first { $0.position == position }?.text ?? ""
                XCTAssertTrue(letters(pieces.word).contains(letters(recited)), "\(ayah.id) word \(position)")
            }
        }
        // 6,055 of the 6,236 ayat when this was written; the others, whose
        // timings drop or misspell a word, are shown untinted.
        XCTAssertGreaterThan(mapped, 6_000)
    }

    /// 2:14: the reciter repeats five words. Each mushaf word still has one
    /// place, and the repeat tints the same words again.
    func testARepeatedPhraseTintsTheSameMushafWords() throws {
        let text = try mushaf(2, 14)
        let words = try XCTUnwrap(verse(2, 14)).words
        XCTAssertGreaterThan(words.count, Set(words.map(\.position)).count, "the timings repeat words")
        let map = try XCTUnwrap(MushafWordMap(text: text, words: words))
        XCTAssertEqual(map.ranges.count, Set(words.map(\.position)).count)
        let seventh = try XCTUnwrap(map.pieces(of: text, position: 7))
        XCTAssertEqual(letters(seventh.word), letters("وَاِذَا"))
    }

    /// 2:214: the timings leave a word out. The ayah gets no map and no tint,
    /// rather than a tint on the wrong word.
    func testTimingsThatMissAWordGiveNoMap() throws {
        let text = try mushaf(2, 214)
        let words = try XCTUnwrap(verse(2, 214)).words
        XCTAssertNil(MushafWordMap(text: text, words: words))
    }

    /// Words the mushaf runs together: after a letter that does not join on
    /// (reh), the tint can stop between them; after one that does (meem), the
    /// whole run is tinted so no letter loses its joined shape.
    func testWordsRunTogetherAreCutOnlyWhereLettersDoNotJoin() throws {
        let joinedAfterReh = "وَمَكَرَاللّٰهُ"
        let rehMap = try XCTUnwrap(MushafWordMap(text: joinedAfterReh, words: [
            RecitationWord(position: 1, text: "وَمَكَرَ", startMs: 0, endMs: 100),
            RecitationWord(position: 2, text: "اللّٰهُ", startMs: 100, endMs: 200),
        ]))
        XCTAssertEqual(rehMap.pieces(of: joinedAfterReh, position: 1)?.word, "وَمَكَرَ")

        let joinedAfterMeem = "بِكُمْوَلَا"
        let meemMap = try XCTUnwrap(MushafWordMap(text: joinedAfterMeem, words: [
            RecitationWord(position: 1, text: "بِكُمْ", startMs: 0, endMs: 100),
            RecitationWord(position: 2, text: "وَلَا", startMs: 100, endMs: 200),
        ]))
        XCTAssertEqual(meemMap.pieces(of: joinedAfterMeem, position: 1)?.word, joinedAfterMeem)
        XCTAssertEqual(meemMap.pieces(of: joinedAfterMeem, position: 2)?.word, joinedAfterMeem)
    }

    /// A word list that does not spell the text gives no map.
    func testAWrongWordGivesNoMap() {
        XCTAssertNil(MushafWordMap(text: "قُلْ هُوَ اللّٰهُ اَحَدٌ", words: [
            RecitationWord(position: 1, text: "قُلْ", startMs: 0, endMs: 1),
            RecitationWord(position: 2, text: "هُوَ", startMs: 1, endMs: 2),
            RecitationWord(position: 3, text: "اللّٰهُ", startMs: 2, endMs: 3),
            RecitationWord(position: 4, text: "الصَّمَدُ", startMs: 3, endMs: 4),
        ]))
    }
}
