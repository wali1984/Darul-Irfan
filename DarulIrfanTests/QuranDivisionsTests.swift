import XCTest
@testable import DarulIrfan

/// The parahs are the Silsila's printed ones (Akram-ut-Tarajum), the IndoPak
/// division, not the Madani juz list the table held before.
final class QuranDivisionsTests: XCTestCase {

    func testParahsOpenWhereTheSilsilaPrintsThem() {
        let printed: [[Int]] = [
            [1, 1], [2, 142], [2, 253], [3, 92], [4, 24], [4, 148], [5, 83], [6, 111],
            [7, 88], [8, 41], [9, 94], [11, 6], [12, 53], [15, 2], [17, 1], [18, 75],
            [21, 1], [23, 1], [25, 21], [27, 60], [29, 45], [33, 31], [36, 22], [39, 32],
            [41, 47], [46, 1], [51, 31], [58, 1], [67, 1], [78, 1],
        ]
        XCTAssertEqual(QuranDivisions.juzStarts, printed)
    }

    func testEveryStartIsARealAyahInOrder() {
        let starts = QuranDivisions.juzStarts
        for start in starts {
            XCTAssertTrue((1...114).contains(start[0]))
            XCTAssertTrue((1...QuranDivisions.ayahCounts[start[0] - 1]).contains(start[1]))
        }
        for (earlier, later) in zip(starts, starts.dropFirst()) {
            XCTAssertTrue((earlier[0], earlier[1]) < (later[0], later[1]))
        }
    }

    func testAnAyahIsInTheParahThatPrintsIt() {
        XCTAssertEqual(QuranDivisions.juz(surah: 1, ayah: 1), 1)
        XCTAssertEqual(QuranDivisions.juz(surah: 3, ayah: 91), 3)
        XCTAssertEqual(QuranDivisions.juz(surah: 3, ayah: 92), 4)
        XCTAssertEqual(QuranDivisions.juz(surah: 15, ayah: 1), 13)
        XCTAssertEqual(QuranDivisions.juz(surah: 15, ayah: 2), 14)
        XCTAssertEqual(QuranDivisions.juz(surah: 36, ayah: 21), 22)
        XCTAssertEqual(QuranDivisions.juz(surah: 36, ayah: 22), 23)
        XCTAssertEqual(QuranDivisions.juz(surah: 114, ayah: 6), 30)
        XCTAssertEqual(QuranDivisions.juzStarting(surah: 27, ayah: 60), 20)
        XCTAssertNil(QuranDivisions.juzStarting(surah: 27, ayah: 56))
    }

    /// "Play to the end of Juz (Para)" stops where the printed parah ends.
    func testJuzPlaybackStopsAtTheEndOfThePrintedParah() {
        let fromYaSin = QuranListenRange.ayahs(from: ListenAyah(surah: 36, ayah: 1), scope: .juz)
        XCTAssertEqual(fromYaSin.last, ListenAyah(surah: 36, ayah: 21))
        let parah4 = QuranListenRange.ayahs(from: ListenAyah(surah: 3, ayah: 92), scope: .juz)
        XCTAssertEqual(parah4.first, ListenAyah(surah: 3, ayah: 92))
        XCTAssertEqual(parah4.last, ListenAyah(surah: 4, ayah: 23))
        let parah20 = QuranListenRange.ayahs(from: ListenAyah(surah: 27, ayah: 60), scope: .juz)
        XCTAssertEqual(parah20.last, ListenAyah(surah: 29, ayah: 44))
    }
}
