import AVFoundation
import Foundation
import Observation

/// Drives memorisation practice: one ayah at a time, repeated a chosen number
/// of times with a pause between repetitions.
///
/// Deliberately separate from `RecitationPlayer` rather than an extension of it.
/// That player streams a whole surah and reports where it has reached; this one
/// assembles repeated verse windows and recall intervals. Keeping them apart means the
/// reader's playback cannot regress because practice changed, and the two never
/// fight over one AVPlayer.
///
/// The verse windows come from the bundled word timings, so practice needs no
/// network beyond the surah's audio file and no new data of its own.
@Observable
@MainActor
final class HifzPlayer {
    /// One retained session owns practice until Stop or replacement. Views
    /// reattach without restarting the current verse or recall interval.
    private(set) static var active: HifzPlayer?
    static func forSurah(_ surah: Int) -> HifzPlayer {
        if let active, active.surahNumber == surah { return active }
        return HifzPlayer()
    }
    struct Settings {
        let range: ClosedRange<Int>
        let repeats: Int
        let pauseSeconds: Double
    }
    private(set) var settings: Settings?
    private(set) var surahNumber: Int?
    var ownsRemoteControls: Bool { currentAyah != nil && !playbackFailed && phase != .finished }
    enum Phase: Equatable {
        case idle
        case reciting
        /// Between repetitions: silence the listener uses to recall the verse.
        case pausing
        case finished
    }

    private(set) var phase: Phase = .idle
    private(set) var currentAyah: Int?
    /// Which repetition of the current ayah is sounding, 1-based.
    private(set) var repetition = 1
    private(set) var playbackFailed = false

    var isPlaying: Bool { phase == .reciting || phase == .pausing }

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var itemStatusObserver: NSKeyValueObservation?
    @ObservationIgnored private var failureObserver: NSObjectProtocol?
    @ObservationIgnored private var preparationTask: Task<Void, Never>?
    @ObservationIgnored private var timeline: HifzPlaybackTimeline?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var bayanObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var routeObserver: NSObjectProtocol?
    @ObservationIgnored private var audioSessionID = UUID()
    /// Bumped by each seek, so only the latest one starts playback.
    @ObservationIgnored private var seekToken = 0
    /// While a seek is under way the player still reports the old position;
    /// the end-of-verse check ignores it until the seek lands.
    @ObservationIgnored private var isSeeking = false

    @ObservationIgnored private var range: ClosedRange<Int> = 1...1

    /// Starts practice. `recitation` is the surah's bundled timing set; without
    /// one there is nothing to loop, so the caller should not offer practice.
    func start(
        recitation: SurahRecitation,
        range: ClosedRange<Int>,
        repeats: Int,
        pauseSeconds: Double,
        startingAyah: Int? = nil,
        surahNumber: Int? = nil
    ) {
        if let previous = Self.active, previous !== self { previous.stop() }
        stop()
        Self.active = self
        self.surahNumber = surahNumber
        settings = Settings(range: range, repeats: repeats, pauseSeconds: pauseSeconds)
        guard let url = URL(string: recitation.audioUrl) else {
            currentAyah = min(max(startingAyah ?? range.lowerBound, range.lowerBound), range.upperBound)
            playbackFailed = true
            return
        }
        installAudioSessionObservers()
        self.range = range
        do {
            timeline = try HifzPlaybackTimeline(recitation: recitation, range: range,
                repeats: repeats, pauseSeconds: pauseSeconds)
        } catch { failPlayback(); return }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        // One recording at a time: the reader's recitation stops and the
        // bayan player pauses; a bayan started later ends the practice.
        QuranListenPlayer.shared.stop()
        NotificationCenter.default.post(name: .quranAudioWillStart, object: nil)
        let observerSessionID = audioSessionID
        bayanObserver = NotificationCenter.default.addObserver(
            forName: .bayanAudioWillStart, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.audioSessionID == observerSessionID else { return }
                self.stop()
            }
        }

        let newPlayer = AVPlayer()
        player = newPlayer
        let sessionID = audioSessionID
        preparationTask = Task { @MainActor [weak self, weak newPlayer] in
            guard let self, let newPlayer, let timeline = self.timeline else { return }
            do {
                try HifzComposition.requireReadableLocalAudio(url)
                let source = QuranListenPlayer.recitationItem(url, durationMs: recitation.durationMs).asset
                let composition = try await HifzComposition.make(asset: source, timeline: timeline)
                guard !Task.isCancelled, self.audioSessionID == sessionID, self.player === newPlayer else { return }
                newPlayer.replaceCurrentItem(with: AVPlayerItem(asset: composition))
                self.installItemObservers(newPlayer)
                if self.isPlaying, let ayah = self.currentAyah { self.recite(ayah: ayah) }
            } catch is CancellationError { return }
            catch {
                guard self.audioSessionID == sessionID, self.player === newPlayer else { return }
                self.failPlayback()
            }
        }
        // Observation updates the visible ayah; playback boundaries and recall
        // intervals are now driven by the composition, independent of this timer.
        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 20), queue: .main
        ) { [weak self, weak newPlayer] time in
            guard time.seconds.isFinite else { return }
            let ms = Int(time.seconds * 1000)
            Task { @MainActor in
                guard let self, let newPlayer, self.player === newPlayer else { return }
                self.observe(ms: ms)
            }
        }

        let first = min(max(startingAyah ?? range.lowerBound, range.lowerBound), range.upperBound)
        currentAyah = first
        repetition = 1
        recite(ayah: first)
    }

    func pause() {
        player?.pause()
        phase = .idle
    }

    func resume() {
        guard let ayah = currentAyah else { return }
        do { try AVAudioSession.sharedInstance().setActive(true) }
        catch { return }
        // Restart the verse rather than resuming mid-word: a half-verse is not
        // useful for memorising.
        recite(ayah: ayah)
    }

    func stop() {
        if Self.active === self { Self.active = nil }
        surahNumber = nil
        settings = nil
        audioSessionID = UUID()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        routeObserver = nil
        preparationTask?.cancel()
        preparationTask = nil
        timeline = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
        if let bayanObserver { NotificationCenter.default.removeObserver(bayanObserver) }
        bayanObserver = nil
        seekToken += 1
        isSeeking = false
        player?.pause()
        player = nil
        playbackFailed = false
        phase = .idle
        currentAyah = nil
        repetition = 1
    }

    // Practice pauses on an interruption or disconnected headphones. It keeps
    // the verse/repetition for an explicit Resume, including during a recall gap.
    // Queued notifications from a stopped/replaced session cannot pause a new one.
    private func installAudioSessionObservers() {
        let sessionID = audioSessionID
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in
                guard let self, self.audioSessionID == sessionID else { return }
                self.pause()
            }
        }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            Task { @MainActor in
                guard let self, self.audioSessionID == sessionID else { return }
                self.pause()
            }
        }
    }

    private func failPlayback() {
        let interruptedAyah = currentAyah
        stop()
        currentAyah = interruptedAyah
        playbackFailed = true
    }

    /// Jumps straight to an ayah, resetting its repetition count.
    func practise(ayah: Int) {
        guard range.contains(ayah) else { return }
        currentAyah = ayah
        repetition = 1
        recite(ayah: ayah)
    }

    /// Plays the verse's window from its first word. Playback starts only once
    /// the seek has landed; started at once, the end-of-verse check could act
    /// on the position before the seek and cut the repetition short.
    private func recite(ayah: Int) {
        guard let player, let segment = timeline?.segments.first(where: {
            $0.ayah == ayah && $0.repetition == repetition && $0.sourceStartMs != nil
        }) else { return }
        phase = .reciting
        guard player.currentItem != nil else { return } // preparation retains intent
        player.pause()
        seekToken += 1
        let token = seekToken
        isSeeking = true
        player.seek(to: CMTime(value: segment.startMs, timescale: 1000),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, token == self.seekToken else { return }
                self.isSeeking = false
                guard self.phase == .reciting else { return }
                guard finished else { self.failPlayback(); return }
                self.player?.play()
            }
        }
    }

    private func observe(ms: Int) {
        guard player?.currentItem != nil, isPlaying, !isSeeking,
              let segment = timeline?.segment(at: Int64(ms)) else { return }
        currentAyah = segment.ayah
        repetition = segment.repetition
        phase = segment.sourceStartMs == nil ? .pausing : .reciting
    }

    private func installItemObservers(_ newPlayer: AVPlayer) {
        if let item = newPlayer.currentItem {
            itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self, weak newPlayer] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor in
                    guard let self, let newPlayer, self.player === newPlayer else { return }
                    self.failPlayback()
                }
            }
            failureObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
            ) { [weak self, weak newPlayer] _ in
                Task { @MainActor in
                    guard let self, let newPlayer, self.player === newPlayer else { return }
                    self.failPlayback()
                }
            }
        }
        if let item = newPlayer.currentItem {
            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
            ) { [weak self, weak newPlayer] _ in
                Task { @MainActor in
                    guard let self, let newPlayer, self.player === newPlayer else { return }
                    self.phase = .finished
                }
            }
        }
    }

}

/// Where practice was left off, per surah, so returning resumes rather than
/// restarting. Small enough for user defaults, and private to the device.
enum HifzProgress {
    private static func key(_ surah: Int) -> String { "hifz.surah.\(surah)" }

    static func save(surah: Int, ayah: Int, repeats: Int, pauseSeconds: Double, start: Int, end: Int) {
        UserDefaults.standard.set(
            ["ayah": ayah, "repeats": repeats, "pause": pauseSeconds, "start": start, "end": end],
            forKey: key(surah)
        )
    }

    static func load(surah: Int) -> (ayah: Int, repeats: Int, pauseSeconds: Double, start: Int, end: Int)? {
        guard let stored = UserDefaults.standard.dictionary(forKey: key(surah)) else { return nil }
        guard let ayah = stored["ayah"] as? Int,
              let start = stored["start"] as? Int,
              let end = stored["end"] as? Int else { return nil }
        return (
            ayah: ayah,
            repeats: stored["repeats"] as? Int ?? 3,
            pauseSeconds: stored["pause"] as? Double ?? 1.5,
            start: start,
            end: end
        )
    }
}
