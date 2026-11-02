import XCTest
@testable import DarulIrfan

final class HifzPlaybackTimelineTests: XCTestCase {
    private var recording: SurahRecitation {
        SurahRecitation(audioUrl: "file:///practice.wav", durationMs: 3000,
            verses: (1...3).map { RecitationVerse(ayah: $0, fromMs: ($0 - 1) * 1000, toMs: $0 * 1000, words: []) })
    }

    func testRepeatsRecallBoundariesAndCompletion() throws {
        let plan = try HifzPlaybackTimeline(recitation: recording, range: 2...3, repeats: 2, pauseSeconds: 1.5)
        XCTAssertEqual(plan.segments.count, 7)
        XCTAssertEqual(plan.durationMs, 8500)
        XCTAssertEqual(plan.segment(at: 999)?.sourceStartMs, 1000)
        XCTAssertNil(plan.segment(at: 1000)?.sourceStartMs)
        XCTAssertEqual(plan.segment(at: 2500)?.repetition, 2)
        XCTAssertEqual(plan.segment(at: 5000)?.ayah, 3)
        XCTAssertEqual(plan.segment(at: 8499)?.sourceStartMs, 2000)
        XCTAssertNil(plan.segment(at: 8500))
        XCTAssertNil(plan.segment(at: -1))
    }

    func testStartingVerseClampsAndZeroPauseHasNoRecallSegments() throws {
        let plan = try HifzPlaybackTimeline(recitation: recording, range: 1...3, repeats: 2, pauseSeconds: 0, startingAyah: 99)
        XCTAssertEqual(plan.segments.count, 2)
        XCTAssertEqual(plan.segments.map(\.ayah), [3, 3])
        XCTAssertEqual(plan.durationMs, 2000)
    }

    func testInvalidInputsFailBeforePlayback() {
        for pause in [Double.nan, .infinity, -1, 11] {
            XCTAssertThrowsError(try HifzPlaybackTimeline(recitation: recording, range: 1...3, repeats: 2, pauseSeconds: pause))
        }
        XCTAssertThrowsError(try HifzPlaybackTimeline(recitation: recording, range: 1...3, repeats: 21, pauseSeconds: 0))
        XCTAssertThrowsError(try HifzPlaybackTimeline(recitation: recording, range: 1...4, repeats: 1, pauseSeconds: 0))
        var invalid = recording
        invalid.verses[0].toMs = 0
        XCTAssertThrowsError(try HifzPlaybackTimeline(recitation: invalid, range: 1...1, repeats: 1, pauseSeconds: 0))
    }

    func testRoundedSummaryDoesNotRejectPreciseVerseEnd() throws {
        var rounded = recording
        rounded.durationMs = 2000
        XCTAssertEqual(try HifzPlaybackTimeline(recitation: rounded, range: 1...3, repeats: 1, pauseSeconds: 0).durationMs, 3000)
    }

    func testEveryBundledSurahCanPrepareItsCompleteRange() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "quran_word_timings", withExtension: "json"))
        let data = try JSONDecoder().decode(RecitationData.self, from: Data(contentsOf: url))
        XCTAssertEqual(data.surahs.count, 114)
        for (surah, recording) in data.surahs {
            let last = try XCTUnwrap(recording.verses.map(\.ayah).max())
            let plan = try HifzPlaybackTimeline(recitation: recording, range: 1...last, repeats: 2, pauseSeconds: 1)
            XCTAssertEqual(plan.segments.last?.ayah, last, "Surah \(surah)")
        }
    }
}
