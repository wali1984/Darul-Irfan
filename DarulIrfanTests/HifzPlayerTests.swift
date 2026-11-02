import AVFoundation
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
    func testUnavailableAudioOffersRetryAndPreservesInterruptedVerse() async throws {
        let player = HifzPlayer()
        defer { player.stop() }
        var missing = recitation
        missing.audioUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-hifz-\(UUID().uuidString).m4a").absoluteString
        player.start(recitation: missing, range: 1...7, repeats: 3, pauseSeconds: 1.5, startingAyah: 4)
        let deadline = Date().addingTimeInterval(8)
        while !player.playbackFailed && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(player.playbackFailed, "A failed audio item must not keep showing active playback")
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentAyah, 4)
        player.start(recitation: missing, range: 1...7, repeats: 3, pauseSeconds: 1.5, startingAyah: 4)
        XCTAssertFalse(player.playbackFailed, "Retry must clear the previous failure before preparing")
        XCTAssertEqual(player.currentAyah, 4)
        player.stop()
        // Late KVO/notification/seek callbacks must not revive the stopped session.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(player.playbackFailed)
        XCTAssertNil(player.currentAyah)
        XCTAssertFalse(player.isPlaying)
    }

    // Real local PCM avoids both external traffic and missing-file KVO failures,
    // so these tests exercise notification wiring rather than an unrelated error.
    private func localAudio() throws -> (SurahRecitation, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hifz-\(UUID().uuidString).wav")
        let byteCount: UInt32 = 7 * 8000 * 2
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); number(UInt32(36) + byteCount); text("WAVEfmt ")
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(8000)); number(UInt32(16000)); number(UInt16(2)); number(UInt16(16))
        text("data"); number(byteCount); data.append(Data(count: Int(byteCount)))
        try data.write(to: url)
        var recording = recitation
        recording.audioUrl = url.absoluteString
        return (recording, url)
    }

    func testPauseAndStopDuringCompositionPreparationRemainAuthoritative() async throws {
        let (recording, url) = try localAudio()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = HifzPlayer()
        defer { player.stop() }
        player.start(recitation: recording, range: 1...7, repeats: 2, pauseSeconds: 1, startingAyah: 4)
        player.pause()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentAyah, 4)
        player.start(recitation: recording, range: 1...7, repeats: 2, pauseSeconds: 1, startingAyah: 5)
        player.stop()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.currentAyah)
        XCTAssertFalse(player.playbackFailed)
    }

    func testCompositionContainsExactRecitationsAndRecallGaps() async throws {
        let (recording, url) = try localAudio()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try HifzPlaybackTimeline(recitation: recording, range: 2...3, repeats: 2, pauseSeconds: 1.5)
        let composition = try await HifzComposition.make(asset: AVURLAsset(url: url), timeline: plan)
        let duration = try await composition.load(.duration)
        XCTAssertEqual(duration.seconds, 8.5, accuracy: 0.001)
        let tracks = try await composition.loadTracks(withMediaType: .audio)
        let segments = try await XCTUnwrap(tracks.first).load(.segments)
        XCTAssertEqual(segments.filter { !$0.isEmpty }.count, 4)
        XCTAssertEqual(segments.filter { $0.isEmpty }.count, 3)
        XCTAssertEqual(segments.filter { !$0.isEmpty }.map { $0.timeMapping.source.start.seconds }, [1, 1, 2, 2])
    }

    func testCompositionRejectsTimingsBeyondActualFile() async throws {
        let (recording, url) = try localAudio()
        defer { try? FileManager.default.removeItem(at: url) }
        var longer = recording
        longer.durationMs = 9000
        longer.verses = [RecitationVerse(ayah: 1, fromMs: 7000, toMs: 9000, words: [])]
        let plan = try HifzPlaybackTimeline(recitation: longer, range: 1...1, repeats: 1, pauseSeconds: 0)
        do {
            _ = try await HifzComposition.make(asset: AVURLAsset(url: url), timeline: plan)
            XCTFail("Out-of-file timing must fail before installing playback")
        } catch HifzComposition.Failure.invalidSourceDuration {
            // Expected; callers can retain their active playback until preparation succeeds.
        }
    }

    func testAudioInterruptionAndHeadphoneDisconnectPauseWithoutLosingVerse() async throws {
        let (recording, url) = try localAudio()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = HifzPlayer()
        defer { player.stop() }
        for headphones in [false, true] {
            player.start(recitation: recording, range: 1...7, repeats: 3, pauseSeconds: 1.5, startingAyah: 4)
            XCTAssertTrue(player.isPlaying)
            if headphones {
                NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
                    userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
            } else {
                NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
            }
            let deadline = Date().addingTimeInterval(2)
            while player.isPlaying && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertFalse(player.isPlaying)
            XCTAssertFalse(player.playbackFailed, "The notification must pause healthy audio")
            XCTAssertEqual(player.currentAyah, 4)
            XCTAssertEqual(player.repetition, 1)
            player.resume()
            XCTAssertTrue(player.isPlaying)
            XCTAssertEqual(player.currentAyah, 4)
        }
    }

    func testQueuedHeadphoneNotificationCannotPauseReplacementPractice() async throws {
        let (recording, url) = try localAudio()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = HifzPlayer()
        defer { player.stop() }
        player.start(recitation: recording, range: 1...7, repeats: 3, pauseSeconds: 1.5, startingAyah: 2)
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        // The old observer queued a MainActor task; replace its session before it runs.
        player.start(recitation: recording, range: 1...7, repeats: 3, pauseSeconds: 1.5, startingAyah: 5)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(player.isPlaying)
        XCTAssertFalse(player.playbackFailed)
        XCTAssertEqual(player.currentAyah, 5)
    }

}
