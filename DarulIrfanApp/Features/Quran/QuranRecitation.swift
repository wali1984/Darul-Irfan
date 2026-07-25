import Foundation
import AVFoundation
import Observation

// MARK: - Recitation data (bundled word-by-word timings)

/// One word within an ayah, with its audio time window (milliseconds) so the
/// reader can highlight it in sync with a reciter.
struct RecitationWord: Codable, Sendable, Equatable {
    var position: Int
    var text: String
    var startMs: Int
    var endMs: Int
}

struct RecitationVerse: Codable, Sendable, Equatable {
    var ayah: Int
    var fromMs: Int
    var toMs: Int
    var words: [RecitationWord]
}

/// A famous reciter's recitation of one surah: a single continuous audio file
/// plus per-verse and per-word timings.
struct SurahRecitation: Codable, Sendable, Equatable {
    var audioUrl: String
    var durationMs: Int
    var verses: [RecitationVerse]

    func verse(_ ayah: Int) -> RecitationVerse? { verses.first { $0.ayah == ayah } }
}

struct RecitationData: Codable, Sendable {
    var reciter: String
    var reciterId: Int
    var surahs: [String: SurahRecitation]
}

/// Loads the bundled `quran_word_timings.json`. Reader-only data, so it is read
/// straight from the app bundle rather than the content database.
final class RecitationProvider: @unchecked Sendable {
    static let shared = RecitationProvider()
    private let data: RecitationData?

    private init() {
        if let url = Bundle.main.url(forResource: "quran_word_timings", withExtension: "json"),
           let raw = try? Data(contentsOf: url) {
            data = try? JSONDecoder().decode(RecitationData.self, from: raw)
        } else {
            data = nil
        }
    }

    var reciterName: String { data?.reciter ?? "" }

    func recitation(forSurah surah: Int) -> SurahRecitation? {
        data?.surahs[String(surah)]
    }
}

// MARK: - Recitation player

/// Streams a surah's recitation and publishes the currently-sounding ayah and
/// word so the reader can highlight along. One shared instance drives the whole
/// Quran tab.
@Observable
@MainActor
final class RecitationPlayer {
    private(set) var isPlaying = false
    private(set) var currentSurah: Int?
    private(set) var currentAyah: Int?
    private(set) var currentWordPosition: Int?

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var recitation: SurahRecitation?

    func toggle(surah: Int, recitation: SurahRecitation, fromAyah: Int?) {
        if isPlaying && currentSurah == surah {
            pause()
        } else if currentSurah == surah && player != nil {
            resume()
        } else {
            start(surah: surah, recitation: recitation, fromAyah: fromAyah)
        }
    }

    func start(surah: Int, recitation: SurahRecitation, fromAyah: Int?) {
        stop()
        guard let url = URL(string: recitation.audioUrl) else { return }
        self.recitation = recitation
        currentSurah = surah

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer

        if let fromAyah, let verse = recitation.verse(fromAyah) {
            newPlayer.seek(to: CMTime(value: CMTimeValue(verse.fromMs), timescale: 1000))
        }

        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 20), queue: .main
        ) { [weak self] time in
            let ms = Int(time.seconds * 1000)
            Task { @MainActor in self?.updateHighlight(ms: ms) }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }

        newPlayer.play()
        isPlaying = true
    }

    private func updateHighlight(ms: Int) {
        guard let recitation else { return }
        guard let verse = recitation.verses.first(where: { ms >= $0.fromMs && ms < $0.toMs }) else { return }
        currentAyah = verse.ayah
        currentWordPosition = verse.words.first(where: { ms >= $0.startMs && ms < $0.endMs })?.position
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        guard player != nil else { return }
        player?.play()
        isPlaying = true
    }

    func stop() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
        recitation = nil
        isPlaying = false
        currentSurah = nil
        currentAyah = nil
        currentWordPosition = nil
    }

    /// True while this exact ayah is the one currently sounding.
    func isSounding(surah: Int, ayah: Int) -> Bool {
        isPlaying && currentSurah == surah && currentAyah == ayah
    }
}
