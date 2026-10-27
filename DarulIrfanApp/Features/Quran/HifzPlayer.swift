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

        let newPlayer = AVPlayer(playerItem: AVPlayerItem(url: url))
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

    private func recite(ayah: Int) {
        guard let player, let verse = recitation?.verse(ayah) else { return }
        phase = .reciting
        player.seek(
            to: CMTime(value: CMTimeValue(verse.fromMs), timescale: 1000),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        player.play()
    }

    private func observe(ms: Int) {
        guard phase == .reciting, let ayah = currentAyah,
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
