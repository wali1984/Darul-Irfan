import XCTest
@testable import DarulIrfan

@MainActor
final class HifzPlayerTests: XCTestCase {
    // A local fixture address avoids external audio/network side effects.
    private var recitation: SurahRecitation {
        SurahRecitation(
            audioUrl: "file:///tmp/darul-hifz-unit-fixture.m4a",
            durationMs: 7000,
            verses: (1...7).map { RecitationVerse(ayah: $0, fromMs: ($0 - 1) * 1000, toMs: $0 * 1000, words: []) }
        )
    }

    func testSavedVerseIsRetainedAcrossPauseAndResume() {
        let player = HifzPlayer()
        defer { player.stop() }
        player.start(recitation: recitation, range: 2...7, repeats: 3, pauseSeconds: 1.5, startingAyah: 5)
        XCTAssertEqual(player.currentAyah, 5)
        player.pause()
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentAyah, 5)
        player.resume()
        XCTAssertEqual(player.currentAyah, 5)
        XCTAssertTrue(player.isPlaying)
    }

    func testRestartWithNarrowerRangeClampsSavedVerseAndRejectsOldRange() {
        let player = HifzPlayer()
        defer { player.stop() }
        player.start(recitation: recitation, range: 1...7, repeats: 3, pauseSeconds: 1.5, startingAyah: 6)
        player.pause()
        player.start(recitation: recitation, range: 2...4, repeats: 2, pauseSeconds: 0, startingAyah: 6)
        XCTAssertEqual(player.currentAyah, 4)
        XCTAssertEqual(player.repetition, 1)
        player.practise(ayah: 6)
        XCTAssertEqual(player.currentAyah, 4)
        player.practise(ayah: 2)
        XCTAssertEqual(player.currentAyah, 2)
        player.stop()
        XCTAssertNil(player.currentAyah)
        XCTAssertFalse(player.isPlaying)
    }
}
