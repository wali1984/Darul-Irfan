import CoreText
import SwiftUI
import XCTest
@testable import DarulIrfan

/// What the mushaf face leaves blank is given another face, and only that.
final class MushafFaceGapsTests: XCTestCase {
    private typealias FontKey = AttributeScopes.SwiftUIAttributes.FontAttribute

    /// The words given a face, in the order they stand, with that face.
    private func faced(_ text: String, showsSmallHighZero: Bool = false) -> [String] {
        let scalars = Array(text.unicodeScalars)
        return MushafFaceGaps.spans(in: scalars, showsSmallHighZero: showsSmallHighZero).map { span in
            var words = String.UnicodeScalarView()
            words.append(contentsOf: scalars[span.range])
            switch span.face {
            case .signs: return "signs:" + String(words)
            case .marker: return "marker:" + String(words)
            case .smallHighZero: return "zero:" + String(words)
            case .urdu: return "urdu:" + String(words)
            }
        }
    }

    func testAyahNumbers() {
        XCTAssertEqual(faced("\u{FD3F}\u{0661}\u{0662}\u{FD3E}"), ["signs:\u{0661}\u{0662}"])
        XCTAssertEqual(faced("\u{FD3F}\u{0662}\u{0665}\u{0665}\u{FD3E}"), ["signs:\u{0662}\u{0665}\u{0665}"])
        // The mushaf face draws U+0660, and all of the Urdu digits.
        XCTAssertEqual(faced("\u{FD3F}\u{0661}\u{0660}\u{FD3E}"), ["signs:\u{0661}"])
        XCTAssertEqual(faced("\u{FD3F}\u{06F1}\u{06F2}\u{FD3E}"), [])
    }

    func testACircleTakesItsNumberWhole() {
        for number in ["\u{0665}", "\u{06F5}", "\u{0661}\u{0660}", "\u{06F1}\u{06F2}", "\u{06F2}\u{06F5}\u{06F5}"] {
            XCTAssertEqual(faced("قوم \u{06DD}" + number + " ثم"), ["marker:\u{06DD}" + number])
        }
        XCTAssertEqual(faced("قوم \u{06DD} ثم"), [])
    }

    func testCitationsAndDashes() {
        XCTAssertEqual(faced("(البقرۃ:255)"), ["signs:(", "signs:)"])
        XCTAssertEqual(faced("باب - الفصل \u{2013} \u{2014}"), ["signs:-", "signs:\u{2013}", "signs:\u{2014}"])
    }

    func testAWordWithAnUrduLetterIsTakenWhole() {
        XCTAssertEqual(faced("زَهْرَةٌ (پھول)"), ["signs:(", "urdu:پھول", "signs:)"])
        XCTAssertEqual(faced("پ\u{06F1}\u{06F3}-ع"), ["urdu:پ", "signs:-"])
        XCTAssertEqual(faced("قال ہونٹوں سے"), ["urdu:ہونٹوں"])
    }

    func testOldPauseSignsAndTheMushafsOwnMarkAreLeftAlone() {
        XCTAssertEqual(faced("\u{069A} \u{06BC} \u{067C} \u{06DF} \u{E022}"), [])
    }

    func testABooksWordWithTheSmallHighZeroKeepsItsLettersJoined() {
        let word = "\u{0648}\u{064E}\u{0645}\u{064E}\u{0644}\u{064E}\u{0627}\u{06DF}\u{0626}\u{0650}\u{06C1}\u{0656}"
        let plain = "\u{0648}\u{064E}\u{0645}\u{064E}\u{0644}\u{064E}\u{0627}\u{06DF}"
        XCTAssertEqual(faced("قال " + plain + " ثم", showsSmallHighZero: true), ["zero:" + plain])
        // Amiri Quran has no U+06C1: what follows the alif stays in the
        // mushaf face, where it joins.
        XCTAssertEqual(faced("قال " + word + " ثم", showsSmallHighZero: true), ["zero:" + plain])
        // Standing alone, the sign keeps the space it sits on.
        XCTAssertEqual(faced("قال \u{06DF}", showsSmallHighZero: true), ["zero: \u{06DF}"])
        // The circle comes first, and this rule before the Urdu letters'.
        XCTAssertEqual(faced("\u{06DD}\u{0661}\u{06DF}", showsSmallHighZero: true), ["marker:\u{06DD}\u{0661}", "zero:\u{06DF}"])
        XCTAssertEqual(faced("پ\u{06DF}", showsSmallHighZero: true), ["zero:پ\u{06DF}"])
        // Unasked, as on every other screen, nothing changes.
        XCTAssertEqual(faced(word), [])
    }

    func testTheAyatAreNotTouched() {
        let ayat = SeedBundle.quranAyahs()
        XCTAssertEqual(ayat.count, 6236)
        let touched = ayat.filter { !MushafFaceGaps.spans(in: $0.textArabic.unicodeScalars).isEmpty }
        XCTAssertEqual(touched.map { "\($0.surahNumber):\($0.ayahNumber)" }, [])
    }

    func testFillingKeepsTheTextAndItsLinksAndChangesOnlyTheGaps() throws {
        // U+06DD and the digit after it are one character, and change face together.
        let original = "قوم \u{06DD}\u{0661}\u{0662} پھول (عند)"
        var linked = AttributedString(original)
        let url = try XCTUnwrap(URL(string: "book-link:3"))
        linked.link = url

        let filled = MushafFaceGaps.filling(linked, scale: 1)
        var text = String.UnicodeScalarView()
        text.append(contentsOf: filled.unicodeScalars)
        XCTAssertEqual(Array(text), Array(original.unicodeScalars))

        var signs = String.UnicodeScalarView()
        var urdu = String.UnicodeScalarView()
        let scalars = filled.unicodeScalars
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let next = scalars.index(after: index)
            let part = filled[index..<next]
            XCTAssertEqual(part.link, url)
            if let face = part[FontKey.self] {
                if face == DIFont.mushafSigns(scale: 1) || face == DIFont.mushafMarker(scale: 1) {
                    signs.append(scalars[index])
                } else if face == DIFont.mushafUrduWord(scale: 1) {
                    urdu.append(scalars[index])
                } else {
                    XCTFail("an unexpected face")
                }
            }
            index = next
        }
        XCTAssertEqual(String(signs), "\u{06DD}\u{0661}\u{0662}()")
        XCTAssertEqual(String(urdu), "پھول")
    }

    /// The lists are what the bundled face really leaves blank.
    func testTheListsMatchTheBundledFace() {
        AppFonts.registerBundledFonts()
        let mushaf = CTFontCreateWithName(AppFonts.quranArabicName as CFString, 20, nil)
        let candidates = Array(UInt32(0x21)...0x7E) + Array(UInt32(0x600)...0x6FF) + Array(UInt32(0x2010)...0x2027)
        var blank = Set<UInt32>()
        for value in candidates {
            guard let scalar = Unicode.Scalar(value) else { continue }
            switch scalar.properties.generalCategory {
            case .format, .lineSeparator, .paragraphSeparator: continue
            default: break
            }
            var character = UniChar(value)
            var glyph = CGGlyph()
            guard CTFontGetGlyphsForCharacters(mushaf, &character, &glyph, 1) else { continue }
            if CTFontCreatePathForGlyph(mushaf, glyph, nil)?.isEmpty ?? true { blank.insert(value) }
        }
        let leftBlank: Set<UInt32> = [0x067C, 0x069A, 0x06BC, 0x06DF]
        XCTAssertEqual(blank, MushafFaceGaps.signs.union(MushafFaceGaps.letters).union(leftBlank))

        let amiri = CTFontCreateWithName(AppFonts.generalArabicName as CFString, 20, nil)
        for value in MushafFaceGaps.signs.subtracting([0x2010, 0x2011]) {
            var character = UniChar(value)
            var glyph = CGGlyph()
            XCTAssertTrue(CTFontGetGlyphsForCharacters(amiri, &character, &glyph, 1), String(value, radix: 16))
            XCTAssertFalse(CTFontCreatePathForGlyph(amiri, glyph, nil)?.isEmpty ?? true, String(value, radix: 16))
        }
    }
}
