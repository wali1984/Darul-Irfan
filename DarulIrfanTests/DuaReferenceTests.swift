import XCTest
@testable import DarulIrfan

final class DuaReferenceTests: XCTestCase {
    func testNavigationRejectsMissingAndOutOfBoundsReferences() {
        let counts = [1: 7, 2: 286]
        XCTAssertEqual(DuaQuranReference.parse("Quran 1:1-7", ayahCounts: counts), DuaQuranReference(surah: 1, firstAyah: 1, lastAyah: 7))
        XCTAssertEqual(DuaQuranReference.parse(" Qur'an 2:285–286 ", ayahCounts: counts), DuaQuranReference(surah: 2, firstAyah: 285, lastAyah: 286))
        for source in ["Quran 1:8", "Quran 1:1-8", "Quran 1:0", "Quran 1:7-1", "Quran 3:1", "Quran 2:287", "Quran 1:1 trailing", "Sahih Muslim 1"] {
            XCTAssertNil(DuaQuranReference.parse(source, ayahCounts: counts), source)
        }
    }
}
