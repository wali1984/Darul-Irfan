import CryptoKit
import Foundation
import XCTest
@testable import DarulIrfan

/// The Shajra, recreated in the app's own theme (owner, 30 October 2026):
/// its 13 links in order, every line exactly as parity-spec/redesign/
/// shajra.json has it, the ways that open it, and the Licences row that left
/// Settings and search (the credits stay at the foot of About Darul Irfan).
final class ShajraTests: XCTestCase {

    // BEGIN GENERATED from parity-spec/redesign/shajra.json
    // SHA-256 (lowercase hex) and UTF-8 length of every string, computed
    // from the JSON when ShajraText.swift was generated from it.
    private static let expectedLines: [(urdu: String, urduBytes: Int, english: String, englishBytes: Int)] = [
        ("864de8180c3877750accc55ab976549736bcd434ac1d59abf54b9c82e235f112", 102, "d517e4f576c28e3bf594cb0d7d29c05dd35bba6b4263f63c5bf3c0d0067bf71e", 58),
        ("2f8f78c73127de93004c9ff540a397e343ed23824b4a4d73b54f013cdf96cb19", 88, "abbe4777672b5873de8c62eb5ef105978e4ce4f0372d85e45a44750fd8fc32a9", 53),
        ("481f0f722c59b9f1216c8d314c675e0cdc51a5ad29e6d2232780f39d98422c2a", 86, "afdb874fbae0f33dfc4cf26130fce8eddbe7d41c0d5c0b548f0a04eb99a147f6", 60),
        ("e6318b7e580a909725e0d86ad2379f00a560dc117f37ca3da596e468a912c2a5", 88, "9c494198c34a69a8008971607665ec16b56eae043d37a6625618bbed7c3209af", 41),
        ("502b820c7a507fd4d1fb046812abc1928df8a73be43845ed52a83750fb124060", 92, "ef84c21fb9606826748b1801e63b047f2e9f43cb9c1a5775f524483794db187b", 56),
        ("3e0b708ee030cb8f82a17d8ddb1affbe1c25637f3e7f1d685960ffff3e1c3f85", 110, "6750b4b2ec552929040413ca90f24bfaba4ce9a7973a7f0f0ad32a5d3b130064", 58),
        ("368e3b89a034dce34b85421a5c684b8734c85fa62eafa941d5198b7726ea18f1", 113, "9e70944639ad5070baf247f61baf45f5a7a25be599aee58a94c58655693dfc3a", 66),
        ("bb9d3fcc8d072a729fed0884c03d1c0beb885b23ce7cbf497ee7bfb7556b63a6", 103, "9fb880ab7ad0f85cb637e7787feb38aba87a809e6686140993e7486c656ddd12", 74),
        ("872dfd39feaa4fd3f9ad57da0b184c60e9eb5842cef2d6f8fe2741b4f1bd79e8", 134, "dd9a24d365bb0336db9253fa1615ea79255700208653864913c5e646e3d30b6f", 66),
        ("a1e2a6fc8e7cfc99492e73797671ebc49924d6f5d9d60f6c16480d4cc932247c", 102, "c8f691282e083edc58f815f49b6086802a4a75cd6927b2fddffbea0da8d06f62", 54),
        ("df626efda4a0ba6ae4f6af4f3b59cfe30748f76ee16ae2e372c9ea73e10f5dae", 128, "7b3a4c1834642fdb00d2acf333adb4c258f4c46c7852fb1fdde6c79e185a0ac7", 64),
        ("896053f6dbcef574658e7c6d13dc9186614c699463bf83fd63ee6408eeed70bf", 143, "0a34149916e5765cdd87b769c2648f4d3ef7a20ce5dc91de8d114cc598542773", 69),
        ("75c20e0716c35ac1e834f2c1078996c81f7d4a2740c467e1fcad57fc7850d3a9", 164, "f135a4d4ad738de4b0239f08ab87e8748a3121671f763b4e2810c31f22615aa1", 60),
    ]
    private static let expectedTitleUrdu = "d1c4ecb3a25dd006f710ba37cefd020f7ea6da89f9383ec417dd6c0a24c51524"
    private static let expectedTitleEnglish = "0b7d1b14db9ca34999816946208131c658ff2fd634f3639c676847d99344695d"
    private static let expectedClosingArabic = "d18e9dbeda97fd336f7efc2c7753c0ed6fa076cedd1a2ff2e7af8c56313d94d6"
    /// Every line in order, each entry as "index TAB kind TAB urdu TAB english",
    /// then the two titles and the closing dua, one per line.
    private static let expectedWhole = "44d6db3375e03a8012426072687cde3bac655772a1e47beb71ffb507ee1dc98d"
    // END GENERATED

    private func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - The chain

    func testThirteenLinksInOrder() {
        XCTAssertEqual(ShajraText.entries.count, 13)
        XCTAssertEqual(ShajraText.entries.map(\.index), Array(0...12))
        XCTAssertEqual(Set(ShajraText.entries.map(\.id)).count, 13)
    }

    func testTheChainRunsFromTheHolyProphetToThePresentSheikh() {
        XCTAssertEqual(ShajraText.entries.first?.kind, .prophet)
        XCTAssertEqual(ShajraText.entries.last?.kind, .presentSheikh)
        XCTAssertEqual(
            ShajraText.entries.dropFirst().dropLast().map(\.kind),
            Array(repeating: ShajraEntry.Kind.sheikh, count: 11)
        )
        XCTAssertEqual(ShajraText.entries.first?.english.hasPrefix("The Holy Prophet Muhammad"), true)
        XCTAssertEqual(ShajraText.entries.last?.english.hasPrefix("Hadhrat Ameer Abdul Qadeer Awan"), true)
    }

    // MARK: - Byte for byte

    /// Each line is shajra.json's, byte for byte: the same UTF-8 length and
    /// the same digest. (Swift's == would accept another normalisation of
    /// the same letters; the bytes would not.)
    func testEveryLineIsShajraJsonByteForByte() {
        XCTAssertEqual(ShajraText.entries.count, Self.expectedLines.count)
        for (entry, expected) in zip(ShajraText.entries, Self.expectedLines) {
            XCTAssertEqual(entry.urdu.utf8.count, expected.urduBytes, "Urdu line \(entry.index)")
            XCTAssertEqual(sha256(entry.urdu), expected.urdu, "Urdu line \(entry.index)")
            XCTAssertEqual(entry.english.utf8.count, expected.englishBytes, "English line \(entry.index)")
            XCTAssertEqual(sha256(entry.english), expected.english, "English line \(entry.index)")
        }
    }

    func testTheTitlesAndTheClosingDuaAreShajraJsonByteForByte() {
        XCTAssertEqual(sha256(ShajraText.titleUrdu), Self.expectedTitleUrdu)
        XCTAssertEqual(sha256(ShajraText.titleEnglish), Self.expectedTitleEnglish)
        XCTAssertEqual(sha256(ShajraText.closingArabic), Self.expectedClosingArabic)
        // The header sets the Urdu title on two lines: its first two words,
        // then the rest. Together they are the title, byte for byte.
        let joined = ShajraText.titleUrduLead + " " + ShajraText.titleUrduSilsila
        XCTAssertEqual(Array(joined.utf8), Array(ShajraText.titleUrdu.utf8))
        XCTAssertEqual(ShajraText.titleUrduLead.split(separator: " ").count, 2)
    }

    /// One digest over everything, in the JSON's order: no line moved,
    /// added or dropped.
    func testTheWholeShajraMatchesItsSource() {
        var text = ""
        for entry in ShajraText.entries {
            text += "\(entry.index)\t\(entry.kind.rawValue)\t\(entry.urdu)\t\(entry.english)\n"
        }
        text += "\(ShajraText.titleUrdu)\n\(ShajraText.titleEnglish)\n\(ShajraText.closingArabic)\n"
        XCTAssertEqual(sha256(text), Self.expectedWhole)
    }

    // MARK: - The ways in

    /// The library's Shajra page opens the new view wherever it is reached
    /// (search, topics, Saved); no other page does.
    func testTheLibrarysShajraPageOpensTheNewView() {
        XCTAssertEqual(ShajraRoute.libraryItemID, "page-shajra-silsila-naqshbandia-owaisiah")
        XCTAssertTrue(ShajraRoute.opensShajraView(itemID: "page-shajra-silsila-naqshbandia-owaisiah"))
        XCTAssertFalse(ShajraRoute.opensShajraView(itemID: "page-silsila-naqshbandia-owaisiah"))
        XCTAssertFalse(ShajraRoute.opensShajraView(itemID: ""))
    }

    /// Halqah › Silsila: the Shajra row, and only it, opens the new view.
    func testTheHalqahShajraRowOpensTheNewView() {
        XCTAssertEqual(SilsilaEntry.about.filter(\.opensShajra).map(\.category), [.shajra])
        XCTAssertFalse(SilsilaEntry.teachings.contains { $0.opensShajra })
    }

    /// The bundled library still has one Shajra page, under the id the
    /// route sends to the new view.
    func testTheBundledShajraPageIsTheOneTheRouteOpens() throws {
        try XCTSkipIf(SeedBundle.manifest() == nil, "SeedData resources are not visible to this test host")
        let pages = SeedBundle.libraryItems().filter { $0.category == .shajra }
        XCTAssertEqual(pages.map(\.id), [ShajraRoute.libraryItemID])
    }

    // MARK: - Motion

    /// The rows arrive in turn, 0.14 s apart, and the light on the trunk
    /// waits until the trunk has drawn.
    func testTheChainArrivesInTurn() {
        let delays = ShajraText.entries.map { ShajraMotion.rowDelay($0.index) }
        for (earlier, later) in zip(delays, delays.dropFirst()) {
            XCTAssertEqual(later - earlier, ShajraMotion.rowStagger, accuracy: 0.0001)
        }
        XCTAssertEqual(ShajraMotion.rowStagger, 0.14, accuracy: 0.0001)
        XCTAssertEqual(ShajraMotion.trunkLight(elapsed: 0).brightness, 0)
        XCTAssertEqual(ShajraMotion.trunkLight(elapsed: ShajraMotion.trunkDelay + ShajraMotion.trunkDuration).brightness, 0)
        let firstPass = ShajraMotion.lightStart + ShajraMotion.lightTravel / 2
        XCTAssertGreaterThan(ShajraMotion.trunkLight(elapsed: firstPass).brightness, 0.9)
        XCTAssertEqual(ShajraMotion.trunkLight(elapsed: firstPass).position, 0.5, accuracy: 0.0001)
    }

    // MARK: - Licences

    /// The Licences row left Settings and search's "In the app"; the credits
    /// are linked at the foot of About Darul Irfan instead.
    func testSearchNoLongerListsLicences() {
        XCTAssertNil(SearchAppDestination(rawValue: "licences"))
        XCTAssertFalse(SearchAppDestination.allCases.contains { $0.nameKeys.contains("Licences") })
        let english: (SearchAppDestination) -> [String] = { $0.nameKeys }
        XCTAssertTrue(SearchAppDestination.matches(for: "licences", names: english).isEmpty)
        XCTAssertTrue(SearchAppDestination.matches(for: "Licences").isEmpty)
        XCTAssertFalse(SettingsEntry.allCases.map(\.title).contains("Licences"))
    }
}
