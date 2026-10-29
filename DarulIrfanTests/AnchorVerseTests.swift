import Foundation
import XCTest
@testable import DarulIrfan

/// The anchor verse (13:28) is shown from constants; they must stay the
/// words of the Silsila's own Akram-ut-Tarajum as the bundle carries it.
final class AnchorVerseTests: XCTestCase {

    func testAnchorVerseMatchesTheBundledAkramUtTarajum() throws {
        try XCTSkipIf(
            SeedBundle.manifest() == nil,
            "SeedData resources are not visible to this test host; skipping bundle-dependent seed test"
        )
        let translations = SeedBundle.quranTranslations()
            .filter { $0.surahNumber == 13 && $0.ayahNumber == 28 }
        let english = try XCTUnwrap(translations.first { $0.editionID == "akram-ut-tarajum-en" })
        let urdu = try XCTUnwrap(translations.first { $0.editionID == "akram-ut-tarajum-ur" })

        XCTAssertTrue(english.text.hasSuffix(DIBrand.anchorVerseEnglish), "English anchor verse: \(english.text)")
        XCTAssertTrue(urdu.text.hasSuffix(DIBrand.anchorVerseUrdu), "Urdu anchor verse: \(urdu.text)")
    }

    func testUrduReadersAreRecognisedByLocale() {
        XCTAssertTrue(DIBrand.readsUrdu(Locale(identifier: "ur")))
        XCTAssertTrue(DIBrand.readsUrdu(Locale(identifier: "ur_PK")))
        XCTAssertFalse(DIBrand.readsUrdu(Locale(identifier: "en_US")))
    }
}
