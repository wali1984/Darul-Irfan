import XCTest
@testable import DarulIrfan

/// The notes beside the ayat say whose tafsir a bayan is, by its recording
/// date (owner, 29 October 2026): up to December 2017 Hazrat Ameer Muhammad
/// Akram Awan (RA), after that Hazrat Ameer Abdul Qadeer Awan (MZA).
final class BayanAttributionTests: XCTestCase {

    private func link(_ mediaID: String) -> AyahBayanLink {
        AyahBayanLink(surah: 1, ayahStart: 1, ayahEnd: 7, mediaID: mediaID, title: "")
    }

    func testTheRecordingDateDecidesTheSheikh() {
        XCTAssertEqual(link("lecture-2437-2005-01-07-surah-al-fatihah-1-7").recordedYear, 2005)
        XCTAssertEqual(link("lecture-2437-2005-01-07-surah-al-fatihah-1-7").sheikh, .akramAwan)
        XCTAssertEqual(link("lecture-3300-2017-12-01-surah-al-baqarah-1-5").sheikh, .akramAwan)
        XCTAssertEqual(link("lecture-3400-2018-01-05-surah-al-baqarah-1-5").sheikh, .abdulQadeerAwan)
        XCTAssertEqual(link("lecture-2396-2024-03-29-ait-ul-kursi-ki-fazeelat").sheikh, .abdulQadeerAwan)
    }

    /// A link whose id carries no date would be filed under a sheikh by
    /// default, unnoticed; every bundled one has its date.
    func testEveryBundledLinkCarriesItsRecordingDate() throws {
        try XCTSkipIf(SeedBundle.manifest() == nil, "SeedData resources are not visible to this test host")
        var undated: [String] = []
        for surah in 1...114 {
            for link in AyahBayanLinkProvider.shared.links(surah: surah) where link.recordedYear == nil {
                undated.append(link.mediaID)
            }
        }
        XCTAssertTrue(undated.isEmpty, "Links with no recording date: \(undated.prefix(5))")
    }

    /// Ayat al-Kursi has the 2024 bayans on its virtues.
    func testAyatAlKursiOffersHazratAbdulQadeerAwansTafsir() throws {
        try XCTSkipIf(SeedBundle.manifest() == nil, "SeedData resources are not visible to this test host")
        let sheikhs = Set(AyahBayanLinkProvider.shared.links(surah: 2, ayah: 255).map(\.sheikh))
        XCTAssertTrue(sheikhs.contains(.abdulQadeerAwan))
    }
}
