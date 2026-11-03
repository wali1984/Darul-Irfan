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

    func testRemoteOwnerFollowsReplacementAndRetainsPausedPractice() {
        let first = HifzPlayer()
        let second = HifzPlayer()
        defer { first.stop(); second.stop() }
        first.start(recitation: recitation, range: 1...7, repeats: 2, pauseSeconds: 1, surahNumber: 1)
        XCTAssertTrue(HifzPlayer.active === first)
        first.pause()
        XCTAssertTrue(first.ownsRemoteControls)
        second.start(recitation: recitation, range: 2...7, repeats: 2, pauseSeconds: 1, surahNumber: 2)
        XCTAssertNil(first.currentAyah)
        XCTAssertFalse(first.ownsRemoteControls)
        XCTAssertTrue(HifzPlayer.active === second)
        XCTAssertEqual(second.surahNumber, 2)
        first.stop()
        XCTAssertTrue(HifzPlayer.active === second, "Stale cleanup must not clear the replacement")
        second.stop()
        XCTAssertNil(HifzPlayer.active)
        XCTAssertFalse(second.ownsRemoteControls)
    }

    func testReturningToPracticeReattachesToRetainedSessionAndSettings() {
        weak var retained: HifzPlayer?
        do {
            let screenPlayer = HifzPlayer.forSurah(1)
            screenPlayer.start(recitation: recitation, range: 2...7, repeats: 4,
                pauseSeconds: 2.5, startingAyah: 5, surahNumber: 1)
            screenPlayer.pause()
            retained = screenPlayer
        }
        XCTAssertNotNil(retained, "Leaving the view must not release the active session")
        let returned = HifzPlayer.forSurah(1)
        defer { returned.stop() }
        XCTAssertTrue(returned === retained)
        XCTAssertEqual(returned.currentAyah, 5)
        XCTAssertEqual(returned.settings?.range, 2...7)
        XCTAssertEqual(returned.settings?.repeats, 4)
        XCTAssertEqual(returned.settings?.pauseSeconds, 2.5)
        XCTAssertFalse(returned.isPlaying, "Reopening the page must preserve an explicit pause")
        let otherPage = HifzPlayer.forSurah(2)
        XCTAssertFalse(otherPage === returned)
        XCTAssertTrue(HifzPlayer.active === returned, "Browsing another surah must not stop practice")
        otherPage.stop()
        XCTAssertTrue(HifzPlayer.active === returned)
        returned.stop()
        XCTAssertNil(HifzPlayer.active)
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

    func testCompositionPadsSmallEndMarkerOverrunWithoutReadingBeyondEOF() async throws {
        let (recording, url) = try localAudio()
        defer { try? FileManager.default.removeItem(at: url) }
        var finalVerse = recording
        finalVerse.verses = [RecitationVerse(ayah: 1, fromMs: 6000, toMs: 7100, words: [])]
        let plan = try HifzPlaybackTimeline(recitation: finalVerse, range: 1...1, repeats: 2, pauseSeconds: 1)
        let composition = try await HifzComposition.make(asset: AVURLAsset(url: url), timeline: plan)
        let duration = try await composition.load(.duration)
        XCTAssertEqual(duration.seconds, 3.2, accuracy: 0.001)
        let tracks = try await composition.loadTracks(withMediaType: .audio)
        let segments = try await XCTUnwrap(tracks.first).load(.segments)
        let audio = segments.filter { !$0.isEmpty && ($0 as? AVCompositionTrackSegment)?.sourceURL?.standardizedFileURL == url.standardizedFileURL }
        XCTAssertEqual(audio.count, 2)
        XCTAssertTrue(audio.allSatisfy { $0.timeMapping.source.end.seconds <= 7 })
        XCTAssertEqual(tracks.count, 2, "Silent PCM must not share the recitation's track")
        let tailSegments = try await XCTUnwrap(tracks.last).load(.segments)
        let tail = try XCTUnwrap(tailSegments.last as? AVCompositionTrackSegment)
        XCTAssertFalse(tail.isEmpty, "Final padding must contain silent media, not a discarded empty range")
        XCTAssertNotEqual(tail.sourceURL?.standardizedFileURL, url.standardizedFileURL)
        XCTAssertEqual(tail.timeMapping.target.duration.seconds, 0.1, accuracy: 0.001)
    }

    func testCompositionPadsOverrunOfRealMP3Source() async throws {
        // 7 seconds of silent MPEG-1 Layer III frames (128 kbps, 44.1 kHz),
        // the format of the real recordings, built here rather than checked in.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hifz-\(UUID().uuidString).mp3")
        defer { try? FileManager.default.removeItem(at: url) }
        var frame = Data([0xFF, 0xFB, 0x90, 0x00])
        frame.append(Data(count: 413))
        var file = Data()
        for _ in 0..<268 { file.append(frame) }
        try file.write(to: url)
        var recording = recitation
        recording.audioUrl = url.absoluteString
        recording.verses = [RecitationVerse(ayah: 1, fromMs: 6000, toMs: 7100, words: [])]
        let plan = try HifzPlaybackTimeline(recitation: recording, range: 1...1, repeats: 2, pauseSeconds: 1)
        let source = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let composition = try await HifzComposition.make(asset: source, timeline: plan)
        let duration = try await composition.load(.duration)
        XCTAssertEqual(duration.seconds, 3.2, accuracy: 0.01)
    }

    func testResumeAndJumpRestorePlaybackSessionAfterRecording() throws {
        let player = HifzPlayer()
        defer { player.stop() }
        let session = AVAudioSession.sharedInstance()
        player.start(recitation: recitation, range: 1...7, repeats: 3, pauseSeconds: 1.5)
        player.pause()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        player.resume()
        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.mode, .spokenAudio)
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        player.practise(ayah: 2)
        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.mode, .spokenAudio)
    }

    func testResumeRetiresRecorderBeforeReferenceAudioPlays() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = try RecitationPracticeRecorder(cacheDirectory: root, audioReserved: { false })
        defer { recorder.close() }
        let player = HifzPlayer()
        defer { player.stop() }
        player.start(recitation: recitation, range: 1...7, repeats: 3, pauseSeconds: 1.5)
        player.pause()
        recorder.start(permission: { _ in }, prepareAudio: { _ in }, allowedNow: { true })
        XCTAssertEqual(recorder.phase, .preparing)
        player.resume()
        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertTrue(player.isPlaying)
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

    func testQueuedBayanNotificationCannotStopReplacementPractice() async throws {
        let (recording, url) = try localAudio()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = HifzPlayer()
        defer { player.stop() }
        player.start(recitation: recording, range: 1...7, repeats: 3, pauseSeconds: 1, startingAyah: 2)
        NotificationCenter.default.post(name: .bayanAudioWillStart, object: nil)
        player.start(recitation: recording, range: 1...7, repeats: 3, pauseSeconds: 1, startingAyah: 5)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(HifzPlayer.active === player)
        XCTAssertEqual(player.currentAyah, 5)
        XCTAssertFalse(player.playbackFailed)
    }

}
