import AVFoundation
import Foundation
import Observation

/// Drives memorisation practice: one ayah at a time, repeated a chosen number
/// of times with a pause between repetitions.
///
/// Deliberately separate from `RecitationPlayer` rather than an extension of it.
/// That player streams a whole surah and reports where it has reached; this one
/// holds a single verse's window and replays it. Keeping them apart means the
/// reader's playback cannot regress because practice changed, and the two never
/// fight over one AVPlayer.
///
/// The verse windows come from the bundled word timings, so practice needs no
/// network beyond the surah's audio file and no new data of its own.
@Observable
@MainActor
final class HifzPlayer {
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

    var isPlaying: Bool { phase == .reciting || phase == .pausing }

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var recitation: SurahRecitation?
    @ObservationIgnored private var pauseTask: Task<Void, Never>?
    @ObservationIgnored private var bayanObserver: NSObjectProtocol?
    /// Bumped by each seek, so only the latest one starts playback.
    @ObservationIgnored private var seekToken = 0
    /// While a seek is under way the player still reports the old position;
    /// the end-of-verse check ignores it until the seek lands.
    @ObservationIgnored private var isSeeking = false

    @ObservationIgnored private var range: ClosedRange<Int> = 1...1
    @ObservationIgnored private var repeats = 3
    @ObservationIgnored private var pauseSeconds: Double = 1.5

    /// Starts practice. `recitation` is the surah's bundled timing set; without
    /// one there is nothing to loop, so the caller should not offer practice.
    func start(
        recitation: SurahRecitation,
        range: ClosedRange<Int>,
        repeats: Int,
        pauseSeconds: Double
    ) {
        stop()
        guard let url = URL(string: recitation.audioUrl) else { return }
        self.recitation = recitation
        self.range = range
        self.repeats = max(1, repeats)
        self.pauseSeconds = max(0, pauseSeconds)

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        // One recording at a time: the reader's recitation stops and the
        // bayan player pauses; a bayan started later ends the practice.
        QuranListenPlayer.shared.stop()
        NotificationCenter.default.post(name: .quranAudioWillStart, object: nil)
        bayanObserver = NotificationCenter.default.addObserver(
            forName: .bayanAudioWillStart, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }

        // The reader's exactly-timed item, with its offline copy: the file is
        // variable bitrate, and a seek timed by estimate lands inside the
        // ayah before or cuts the one being memorised.
        let newPlayer = AVPlayer(playerItem: QuranListenPlayer.recitationItem(url, durationMs: recitation.durationMs))
        player = newPlayer
        // 20 Hz is enough to stop within a fiftieth of a second of a verse end,
        // which is below what a listener notices, and cheap.
        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 20), queue: .main
        ) { [weak self] time in
            let ms = Int(time.seconds * 1000)
            Task { @MainActor in self?.observe(ms: ms) }
        }

        currentAyah = range.lowerBound
        repetition = 1
        recite(ayah: range.lowerBound)
    }

    func pause() {
        pauseTask?.cancel()
        pauseTask = nil
        player?.pause()
        phase = .idle
    }

    func resume() {
        guard let ayah = currentAyah else { return }
        // Restart the verse rather than resuming mid-word: a half-verse is not
        // useful for memorising.
        recite(ayah: ayah)
    }

    func stop() {
        pauseTask?.cancel()
        pauseTask = nil
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let bayanObserver { NotificationCenter.default.removeObserver(bayanObserver) }
        bayanObserver = nil
        seekToken += 1
        isSeeking = false
        player?.pause()
        player = nil
        recitation = nil
        phase = .idle
        currentAyah = nil
        repetition = 1
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
        guard let player, let verse = recitation?.verse(ayah) else { return }
        phase = .reciting
        player.pause()
        seekToken += 1
        let token = seekToken
        isSeeking = true
        player.seek(
            to: CMTime(value: CMTimeValue(verse.fromMs), timescale: 1000),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            Task { @MainActor in
                guard let self, token == self.seekToken else { return }
                self.isSeeking = false
                guard finished, self.phase == .reciting else { return }
                self.player?.play()
            }
        }
    }

    private func observe(ms: Int) {
        guard phase == .reciting, !isSeeking, let ayah = currentAyah,
              let verse = recitation?.verse(ayah), ms >= verse.toMs else { return }
        player?.pause()
        if repetition < repeats {
            repetition += 1
            waitThenContinue { [weak self] in
                guard let self, let ayah = self.currentAyah else { return }
                self.recite(ayah: ayah)
            }
        } else if ayah < range.upperBound {
            repetition = 1
            currentAyah = ayah + 1
            waitThenContinue { [weak self] in
                guard let self, let next = self.currentAyah else { return }
                self.recite(ayah: next)
            }
        } else {
            phase = .finished
        }
    }

    /// The silence between repetitions. Cancellable, so pausing or leaving the
    /// screen during the gap does not start the next repetition afterwards.
    private func waitThenContinue(_ next: @escaping @MainActor () -> Void) {
        phase = .pausing
        pauseTask?.cancel()
        let seconds = pauseSeconds
        pauseTask = Task { @MainActor [weak self] in
            if seconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            guard !Task.isCancelled, self?.phase == .pausing else { return }
            next()
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
