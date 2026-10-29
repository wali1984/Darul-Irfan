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

    /// Decodes the timings (7 MB) away from the main thread, so the first
    /// surah opened after launch does not freeze while they load.
    static func warmUp() async {
        await Task.detached(priority: .utility) { _ = RecitationProvider.shared }.value
    }

    var reciterName: String { data?.reciter ?? "" }

    func recitation(forSurah surah: Int) -> SurahRecitation? {
        data?.surahs[String(surah)]
    }
}

// MARK: - Mushaf word positions

/// Where each recited word sits in the mushaf text of one ayah.
///
/// The reader always draws the ayah from quran_ayahs.json. The reciter's word
/// list is not the mushaf: it follows what was recited, so a phrase the
/// reciter repeats is listed again, and in some ayat a word is missing or
/// spelt differently. Its text is therefore never shown. Only its positions
/// are used, to tint the mushaf word that is sounding.
///
/// A map exists only for an ayah whose words, taken once per position (the
/// repeats collapsed), spell the mushaf text exactly apart from spacing and
/// invisible formatting. Any other ayah gets no map, and nothing is tinted
/// there rather than the wrong word.
struct MushafWordMap: Sendable, Equatable {
    /// Unicode-scalar offsets into the ayah's text, per word position.
    let ranges: [Int: Range<Int>]

    init?(text: String, words: [RecitationWord]) {
        // One text per position: when the reciter repeats a phrase its words
        // come round again with the same positions.
        var wordByPosition: [Int: String] = [:]
        for word in words where wordByPosition[word.position] == nil {
            wordByPosition[word.position] = word.text
        }
        guard !wordByPosition.isEmpty,
              wordByPosition.keys.sorted() == Array(1...wordByPosition.count) else { return nil }

        let scalars = Array(text.unicodeScalars)
        var cursor = 0
        var found: [Int: Range<Int>] = [:]
        for position in 1...wordByPosition.count {
            guard let word = wordByPosition[position] else { return nil }
            let significant = word.unicodeScalars.filter { !Self.isIgnorable($0) }
            guard !significant.isEmpty else { return nil }
            var start: Int?
            for scalar in significant {
                while cursor < scalars.count, Self.isIgnorable(scalars[cursor]) { cursor += 1 }
                guard cursor < scalars.count, scalars[cursor] == scalar else { return nil }
                if start == nil { start = cursor }
                cursor += 1
            }
            guard let start else { return nil }
            found[position] = Self.widened(start..<cursor, in: scalars)
        }
        // Every letter of the mushaf must belong to a recited word.
        while cursor < scalars.count, Self.isIgnorable(scalars[cursor]) { cursor += 1 }
        guard cursor == scalars.count else { return nil }
        ranges = found
    }

    /// The ayah's own text cut around the word at `position`: before, the
    /// word, after. Joined, the three are exactly `text`.
    func pieces(of text: String, position: Int) -> (before: String, word: String, after: String)? {
        guard let range = ranges[position] else { return nil }
        let scalars = Array(text.unicodeScalars)
        guard range.upperBound <= scalars.count else { return nil }
        return (
            Self.string(scalars[..<range.lowerBound]),
            Self.string(scalars[range]),
            Self.string(scalars[range.upperBound...])
        )
    }

    private static func string(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    /// Spacing and invisible formatting (zero-width spaces, direction marks,
    /// byte-order marks), and the rub-el-hizb sign, which the two sources
    /// place differently.
    private static func isIgnorable(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace
            || scalar.properties.generalCategory == .format
            || scalar.value == 0x06DE
    }

    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    /// The tint changes the text's attributes at the word's edges. The mushaf
    /// text runs a few words together with no space; where the letter before
    /// such an edge joins the next one, the tint widens to the next safe
    /// break so no letter loses its joined shape.
    private static func widened(_ range: Range<Int>, in scalars: [Unicode.Scalar]) -> Range<Int> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower > 0, !isSafeBreak(at: lower, in: scalars) { lower -= 1 }
        while upper < scalars.count, !isSafeBreak(at: upper, in: scalars) { upper += 1 }
        return lower..<upper
    }

    /// Whether attributes may change between `scalars[index - 1]` and
    /// `scalars[index]` without changing how either side is drawn.
    private static func isSafeBreak(at index: Int, in scalars: [Unicode.Scalar]) -> Bool {
        guard index > 0, index < scalars.count else { return true }
        let next = scalars[index]
        if isIgnorable(next) { return true }
        // A mark belongs to the letter before it.
        if isMark(next) { return false }
        var previousIndex = index - 1
        while previousIndex >= 0, isMark(scalars[previousIndex]) { previousIndex -= 1 }
        guard previousIndex >= 0 else { return true }
        let previous = scalars[previousIndex]
        let previousJoins = previous.properties.generalCategory == .otherLetter || previous.value == 0x0640
        let nextJoins = next.properties.generalCategory == .otherLetter || next.value == 0x0640
        guard previousJoins, nextJoins else { return true }
        // Two letters with nothing between them: safe only when the first
        // never connects to the letter after it.
        return rightJoiningOnly.contains(previous.value)
    }

    /// Arabic and Urdu letters that connect only to the letter before them
    /// (alef, dal, reh, waw and their forms, teh marbuta, yeh barree), plus
    /// the hamza, which connects to neither side.
    private static let rightJoiningOnly: Set<UInt32> = Set(
        [0x0621, 0x0622, 0x0623, 0x0624, 0x0625, 0x0627, 0x0629, 0x062F, 0x0630, 0x0631,
         0x0632, 0x0648, 0x0671, 0x0672, 0x0673, 0x0674, 0x0675, 0x0676, 0x0677,
         0x06C0, 0x06C3, 0x06C4, 0x06C5, 0x06C6, 0x06C7, 0x06C8, 0x06C9, 0x06CA, 0x06CB,
         0x06CD, 0x06CF, 0x06D2, 0x06D3, 0x06D5, 0x06EE, 0x06EF]
        + Array(UInt32(0x0688)...UInt32(0x0699))
    )
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

    /// Plays a single per-ayah clip (a translation recitation) with no word
    /// tracking. The ayah still gets its verse-rail highlight.
    func playClip(surah: Int, ayah: Int, url: URL) {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        currentSurah = surah
        currentAyah = ayah
        currentWordPosition = nil

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
