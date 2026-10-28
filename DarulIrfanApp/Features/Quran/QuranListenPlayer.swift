import AVFoundation
import Foundation
import Observation

// MARK: - What to play

/// What is heard: the recitation, the Silsila's translation, or each ayah's
/// recitation followed by its translation.
enum QuranListenContent: String, CaseIterable, Identifiable, Sendable {
    case arabic
    case translation
    case both

    var id: String { rawValue }
}

/// How far playback runs from the ayah it starts at.
enum QuranListenScope: String, CaseIterable, Identifiable, Sendable {
    case ayah
    case ruku
    case surah
    case juz

    var id: String { rawValue }
}

struct AyahRef: Hashable, Comparable, Sendable {
    var surah: Int
    var ayah: Int

    static func < (lhs: AyahRef, rhs: AyahRef) -> Bool {
        (lhs.surah, lhs.ayah) < (rhs.surah, rhs.ayah)
    }
}

enum QuranListenRange {
    /// Every ayah from `start` to the end of its ayah, ruku, surah or juz.
    static func ayahs(from start: AyahRef, scope: QuranListenScope) -> [AyahRef] {
        let end: AyahRef
        switch scope {
        case .ayah:
            return [start]
        case .surah:
            end = AyahRef(surah: start.surah, ayah: ayahCount(start.surah))
        case .ruku:
            end = before(next(after: start, in: QuranDivisions.rukuStarts))
        case .juz:
            end = before(next(after: start, in: QuranDivisions.juzStarts))
        }
        var result: [AyahRef] = []
        var current = start
        while current <= end {
            result.append(current)
            current = current.ayah < ayahCount(current.surah)
                ? AyahRef(surah: current.surah, ayah: current.ayah + 1)
                : AyahRef(surah: current.surah + 1, ayah: 1)
            if current.surah > 114 { break }
        }
        return result
    }

    static func ayahCount(_ surah: Int) -> Int {
        (1...114).contains(surah) ? QuranDivisions.ayahCounts[surah - 1] : 0
    }

    /// The first division start after `ayah` (or the end of the Qur'an).
    private static func next(after ayah: AyahRef, in starts: [[Int]]) -> AyahRef? {
        starts.map { AyahRef(surah: $0[0], ayah: $0[1]) }.first { $0 > ayah }
    }

    private static func before(_ ref: AyahRef?) -> AyahRef {
        guard let ref else { return AyahRef(surah: 114, ayah: ayahCount(114)) }
        return ref.ayah > 1 ? AyahRef(surah: ref.surah, ayah: ref.ayah - 1)
            : AyahRef(surah: ref.surah - 1, ayah: ayahCount(ref.surah - 1))
    }
}

// MARK: - Player

/// Plays the Qur'an reader's audio: the reciter's surah recording (cut at the
/// ayah timings), the narrated translation, or both ayah by ayah, over an
/// ayah, ruku, surah or juz. Translations play from a queue that loads the
/// next ayah while the current one sounds, so one runs into the next without
/// a gap. One shared instance, so a juz carries on into the next surah.
@Observable
@MainActor
final class QuranListenPlayer {
    static let shared = QuranListenPlayer()

    enum Part: Sendable { case arabic, translation }

    private(set) var isPlaying = false
    private(set) var current: AyahRef?
    private(set) var part: Part?
    private(set) var currentWordPosition: Int?
    private(set) var content: QuranListenContent = .arabic
    private(set) var scope: QuranListenScope = .surah

    @ObservationIgnored private var steps: [AyahRef] = []
    @ObservationIgnored private var index = 0
    @ObservationIgnored private var translationEdition: String?
    @ObservationIgnored private var session = 0

    @ObservationIgnored private var reciter: AVPlayer?
    @ObservationIgnored private var reciterSurah: Int?
    @ObservationIgnored private var recitation: SurahRecitation?
    @ObservationIgnored private var tick: Any?
    @ObservationIgnored private var boundary: Any?
    @ObservationIgnored private var reciterEnd: NSObjectProtocol?

    @ObservationIgnored private let narrator = AVQueuePlayer()
    @ObservationIgnored private var narrated: [ObjectIdentifier: AyahRef] = [:]
    @ObservationIgnored private var narratorEnd: NSObjectProtocol?
    @ObservationIgnored private var narratorItemWatch: NSKeyValueObservation?

    private init() {
        narrator.actionAtItemEnd = .advance
    }

    /// Whether the translation in `edition` can be played for any ayah.
    static func hasTranslation(edition: String?) -> Bool {
        guard let edition else { return false }
        return NarrationCatalog.shared.manifest?.editions[edition]?["translation"]?.isEmpty == false
    }

    func start(from ayah: AyahRef, content: QuranListenContent, scope: QuranListenScope, translationEdition: String?) {
        stop()
        session += 1
        self.content = content
        self.scope = scope
        self.translationEdition = translationEdition
        steps = QuranListenRange.ayahs(from: ayah, scope: scope)
        if content == .translation {
            steps = steps.filter(hasNarration)
        }
        index = 0
        guard !steps.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        isPlaying = true
        playStep()
    }

    func pause() {
        reciter?.pause()
        narrator.pause()
        isPlaying = false
    }

    func resume() {
        guard current != nil else { return }
        if part == .translation { narrator.play() } else { reciter?.play() }
        isPlaying = true
    }

    func stop() {
        session += 1
        clearReciterObservers()
        reciter?.pause()
        reciter = nil
        reciterSurah = nil
        recitation = nil
        narrator.pause()
        narrator.removeAllItems()
        narrated = [:]
        if let narratorEnd { NotificationCenter.default.removeObserver(narratorEnd) }
        narratorEnd = nil
        narratorItemWatch = nil
        steps = []
        index = 0
        isPlaying = false
        current = nil
        part = nil
        currentWordPosition = nil
    }

    func isSounding(surah: Int, ayah: Int) -> Bool {
        isPlaying && current == AyahRef(surah: surah, ayah: ayah)
    }

    func isActive(inSurah surah: Int) -> Bool {
        current?.surah == surah
    }

    // MARK: Steps

    private func playStep() {
        guard index < steps.count else { finish(); return }
        let step = steps[index]
        switch content {
        case .arabic:
            // Straight through to the last ayah of this surah in the range.
            let last = steps[index...].prefix { $0.surah == step.surah }.last ?? step
            playRecitation(from: step, to: last) { [weak self] in
                guard let self else { return }
                self.index += self.steps[self.index...].prefix { $0.surah == step.surah }.count
                self.playStep()
            }
        case .translation:
            playTranslations()
        case .both:
            playRecitation(from: step, to: step) { [weak self] in
                self?.playTranslation(of: step) { [weak self] in
                    self?.index += 1
                    self?.playStep()
                }
            }
        }
    }

    private func finish() {
        stop()
    }

    // MARK: Recitation

    private func playRecitation(from first: AyahRef, to last: AyahRef, then: @escaping () -> Void) {
        guard let surahRecitation = RecitationProvider.shared.recitation(forSurah: first.surah),
              let start = surahRecitation.verse(first.ayah), let end = surahRecitation.verse(last.ayah),
              let url = URL(string: surahRecitation.audioUrl) else {
            then()
            return
        }
        part = .arabic
        current = first
        if reciterSurah != first.surah || reciter == nil {
            clearReciterObservers()
            reciter?.pause()
            let player = AVPlayer(url: url)
            player.automaticallyWaitsToMinimizeStalling = true
            reciter = player
            reciterSurah = first.surah
            recitation = surahRecitation
            tick = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] time in
                let ms = Int(time.seconds * 1000)
                MainActor.assumeIsolated { self?.follow(ms: ms) }
            }
        }
        guard let reciter else { return }
        if let boundary { reciter.removeTimeObserver(boundary); self.boundary = nil }
        if let reciterEnd { NotificationCenter.default.removeObserver(reciterEnd); self.reciterEnd = nil }
        let mySession = session
        var done = false
        let finishPart: () -> Void = { [weak self] in
            guard let self, !done, self.session == mySession else { return }
            done = true
            self.reciter?.pause()
            then()
        }
        // The last ayah of a recording runs to its end; any other stops at its timing.
        if end.toMs < surahRecitation.durationMs - 300 {
            boundary = reciter.addBoundaryTimeObserver(
                forTimes: [NSValue(time: CMTime(value: CMTimeValue(end.toMs), timescale: 1000))], queue: .main
            ) { MainActor.assumeIsolated { finishPart() } }
        }
        reciterEnd = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: reciter.currentItem, queue: .main
        ) { _ in MainActor.assumeIsolated { finishPart() } }
        reciter.seek(to: CMTime(value: CMTimeValue(start.fromMs), timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.session == mySession, self.isPlaying else { return }
                self.reciter?.play()
            }
        }
    }

    private func follow(ms: Int) {
        guard part == .arabic, let recitation, let surah = reciterSurah else { return }
        guard let verse = recitation.verses.first(where: { ms >= $0.fromMs && ms < $0.toMs }) else { return }
        let ref = AyahRef(surah: surah, ayah: verse.ayah)
        if current != ref { current = ref }
        currentWordPosition = verse.words.first(where: { ms >= $0.startMs && ms < $0.endMs })?.position
    }

    private func clearReciterObservers() {
        if let tick { reciter?.removeTimeObserver(tick) }
        if let boundary { reciter?.removeTimeObserver(boundary) }
        if let reciterEnd { NotificationCenter.default.removeObserver(reciterEnd) }
        tick = nil
        boundary = nil
        reciterEnd = nil
    }

    // MARK: Translation

    private func hasNarration(_ ref: AyahRef) -> Bool {
        guard let edition = translationEdition else { return false }
        return NarrationCatalog.shared.has(edition: edition, kind: "translation", surah: ref.surah, start: ref.ayah, end: ref.ayah)
    }

    private func item(for ref: AyahRef) -> AVPlayerItem? {
        guard let edition = translationEdition, hasNarration(ref) else { return nil }
        let name = NarrationCatalog.name(surah: ref.surah, start: ref.ayah, end: ref.ayah)
        let local = NarrationCatalog.localURL(edition: edition, kind: "translation", name: name)
        let remote = NarrationCatalog.shared.remoteURL(edition: edition, kind: "translation", name: name)
        let exists = FileManager.default.fileExists(atPath: local.path)
        if !exists { TranslationSpeaker.keepForOffline(remote, at: local) }
        let item = AVPlayerItem(url: exists ? local : remote)
        narrated[ObjectIdentifier(item)] = ref
        return item
    }

    /// One ayah's translation, then `then` (recitation + translation mode).
    private func playTranslation(of ref: AyahRef, then: @escaping () -> Void) {
        guard let item = item(for: ref) else { then(); return }
        part = .translation
        current = ref
        currentWordPosition = nil
        narrator.removeAllItems()
        narrator.insert(item, after: nil)
        if let narratorEnd { NotificationCenter.default.removeObserver(narratorEnd) }
        let mySession = session
        narratorEnd = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.session == mySession else { return }
                then()
            }
        }
        if isPlaying { narrator.play() }
    }

    /// The whole range's translations as one gapless queue, kept three ayat
    /// ahead of what is sounding.
    private func playTranslations() {
        part = .translation
        currentWordPosition = nil
        narrator.removeAllItems()
        enqueueAhead()
        let mySession = session
        narratorItemWatch = narrator.observe(\.currentItem, options: [.new]) { [weak self] player, _ in
            let id = player.currentItem.map(ObjectIdentifier.init)
            Task { @MainActor in
                guard let self, self.session == mySession else { return }
                guard let id, let ref = self.narrated[id] else {
                    if self.isPlaying && self.narrator.items().isEmpty { self.finish() }
                    return
                }
                self.current = ref
                if let position = self.steps.firstIndex(of: ref) { self.index = position }
                self.enqueueAhead()
            }
        }
        if isPlaying { narrator.play() }
    }

    private func enqueueAhead() {
        let queued = narrator.items().compactMap { narrated[ObjectIdentifier($0)] }
        var nextIndex = queued.last.flatMap { steps.firstIndex(of: $0) }.map { $0 + 1 } ?? index
        var count = queued.count
        while count < 3 && nextIndex < steps.count {
            if let item = item(for: steps[nextIndex]) {
                narrator.insert(item, after: narrator.items().last)
                count += 1
            }
            nextIndex += 1
        }
    }
}
