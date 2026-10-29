import AVFoundation
import Foundation
import Observation

// MARK: - One recording at a time

extension Notification.Name {
    /// Posted when the Qur'an reader's own audio starts - the recitation, its
    /// translation, a tafsir narration or memorisation practice - so the
    /// bayan player pauses instead of playing over it.
    static let quranAudioWillStart = Notification.Name("DarulIrfan.quranAudioWillStart")
    /// Posted by the bayan player when it starts, so the Qur'an players stop.
    static let bayanAudioWillStart = Notification.Name("DarulIrfan.bayanAudioWillStart")
}

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

struct ListenAyah: Hashable, Comparable, Sendable {
    var surah: Int
    var ayah: Int

    static func < (lhs: ListenAyah, rhs: ListenAyah) -> Bool {
        (lhs.surah, lhs.ayah) < (rhs.surah, rhs.ayah)
    }
}

enum QuranListenRange {
    /// Every ayah from `start` to the end of its ayah, ruku, surah or juz.
    static func ayahs(from start: ListenAyah, scope: QuranListenScope) -> [ListenAyah] {
        let end: ListenAyah
        switch scope {
        case .ayah:
            return [start]
        case .surah:
            end = ListenAyah(surah: start.surah, ayah: ayahCount(start.surah))
        case .ruku:
            end = before(next(after: start, in: QuranDivisions.rukuStarts))
        case .juz:
            end = before(next(after: start, in: QuranDivisions.juzStarts))
        }
        var result: [ListenAyah] = []
        var current = start
        while current <= end {
            result.append(current)
            current = current.ayah < ayahCount(current.surah)
                ? ListenAyah(surah: current.surah, ayah: current.ayah + 1)
                : ListenAyah(surah: current.surah + 1, ayah: 1)
            if current.surah > 114 { break }
        }
        return result
    }

    static func ayahCount(_ surah: Int) -> Int {
        (1...114).contains(surah) ? QuranDivisions.ayahCounts[surah - 1] : 0
    }

    /// The first division start after `ayah` (or the end of the Qur'an).
    private static func next(after ayah: ListenAyah, in starts: [[Int]]) -> ListenAyah? {
        starts.map { ListenAyah(surah: $0[0], ayah: $0[1]) }.first { $0 > ayah }
    }

    private static func before(_ ref: ListenAyah?) -> ListenAyah {
        guard let ref else { return ListenAyah(surah: 114, ayah: ayahCount(114)) }
        return ref.ayah > 1 ? ListenAyah(surah: ref.surah, ayah: ref.ayah - 1)
            : ListenAyah(surah: ref.surah - 1, ayah: ayahCount(ref.surah - 1))
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
    private(set) var current: ListenAyah?
    private(set) var part: Part?
    private(set) var currentWordPosition: Int?
    private(set) var content: QuranListenContent = .arabic
    private(set) var scope: QuranListenScope = .surah

    @ObservationIgnored private var steps: [ListenAyah] = []
    @ObservationIgnored private var index = 0
    @ObservationIgnored private var translationEdition: String?
    @ObservationIgnored private var session = 0
    /// Bumped each time a recitation part starts, so its end is handled once.
    @ObservationIgnored private var partToken = 0
    @ObservationIgnored private var afterPart: (() -> Void)?

    @ObservationIgnored private var reciter: AVPlayer?
    @ObservationIgnored private var reciterSurah: Int?
    @ObservationIgnored private var recitation: SurahRecitation?
    @ObservationIgnored private var tick: Any?
    @ObservationIgnored private var boundary: Any?
    @ObservationIgnored private var reciterEnd: NSObjectProtocol?

    @ObservationIgnored private let narrator = AVQueuePlayer()
    @ObservationIgnored private var narrated: [ObjectIdentifier: ListenAyah] = [:]
    @ObservationIgnored private var narratorEnd: NSObjectProtocol?
    @ObservationIgnored private var narratorItemWatch: NSKeyValueObservation?
    @ObservationIgnored private var bayanObserver: NSObjectProtocol?

    private init() {
        narrator.actionAtItemEnd = .advance
        // A bayan started anywhere in the app ends the recitation, rather
        // than the two playing at once.
        bayanObserver = NotificationCenter.default.addObserver(
            forName: .bayanAudioWillStart, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    /// Whether the translation in `edition` can be played for any ayah.
    static func hasTranslation(edition: String?) -> Bool {
        guard let edition else { return false }
        return NarrationCatalog.shared.manifest?.editions[edition]?["translation"]?.isEmpty == false
    }

    func start(from ayah: ListenAyah, content: QuranListenContent, scope: QuranListenScope, translationEdition: String?) {
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
        NotificationCenter.default.post(name: .quranAudioWillStart, object: nil)
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
        NotificationCenter.default.post(name: .quranAudioWillStart, object: nil)
        if part == .translation { narrator.play() } else { reciter?.play() }
        isPlaying = true
    }

    func stop() {
        session += 1
        partToken += 1
        afterPart = nil
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
        isPlaying && current == ListenAyah(surah: surah, ayah: ayah)
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

    private func playRecitation(from first: ListenAyah, to last: ListenAyah, then: @escaping () -> Void) {
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
            let player = AVPlayer(playerItem: Self.recitationItem(url, durationMs: surahRecitation.durationMs))
            player.automaticallyWaitsToMinimizeStalling = true
            reciter = player
            reciterSurah = first.surah
            recitation = surahRecitation
            tick = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] time in
                let ms = Int(time.seconds * 1000)
                Task { @MainActor in self?.follow(ms: ms) }
            }
        }
        guard let reciter else { return }
        if let boundary { reciter.removeTimeObserver(boundary); self.boundary = nil }
        if let reciterEnd { NotificationCenter.default.removeObserver(reciterEnd); self.reciterEnd = nil }
        let mySession = session
        partToken += 1
        let token = partToken
        afterPart = then
        // The last ayah of a recording runs to its end; any other stops at its timing.
        if end.toMs < surahRecitation.durationMs - 300 {
            boundary = reciter.addBoundaryTimeObserver(
                forTimes: [NSValue(time: CMTime(value: CMTimeValue(end.toMs), timescale: 1000))], queue: .main
            ) { [weak self] in Task { @MainActor in self?.endPart(token) } }
        }
        reciterEnd = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: reciter.currentItem, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.endPart(token) } }
        // The next ayah begins where the last one stopped (recitation with
        // translation): play on from there rather than seek to it again.
        let here = reciter.currentTime().seconds
        if here.isFinite, abs(Int(here * 1000) - start.fromMs) < 400 {
            if isPlaying { reciter.play() }
            return
        }
        reciter.seek(to: CMTime(value: CMTimeValue(start.fromMs), timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.session == mySession, self.isPlaying else { return }
                self.reciter?.play()
            }
        }
    }

    /// The surah's recording, timed exactly. The reciters' files are variable
    /// bitrate: timed by estimate, a seek lands away from the ayah, so the
    /// ayah was cut short and the one before heard again. A copy is kept on
    /// the phone (surahs up to half an hour) so later seeks are exact and fast.
    /// Memorisation practice plays the same item for the same reason.
    static func recitationItem(_ remote: URL, durationMs: Int) -> AVPlayerItem {
        let local = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("recitation" + remote.path)
        let exists = FileManager.default.fileExists(atPath: local.path)
        if !exists && durationMs <= 30 * 60_000 { TranslationSpeaker.keepForOffline(remote, at: local) }
        let asset = AVURLAsset(url: exists ? local : remote, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        return AVPlayerItem(asset: asset)
    }

    /// A recitation part has reached its last ayah's end (once per part).
    private func endPart(_ token: Int) {
        guard token == partToken, let then = afterPart else { return }
        afterPart = nil
        reciter?.pause()
        then()
    }

    private func follow(ms: Int) {
        guard part == .arabic, let recitation, let surah = reciterSurah else { return }
        guard let verse = recitation.verses.first(where: { ms >= $0.fromMs && ms < $0.toMs }) else { return }
        let ref = ListenAyah(surah: surah, ayah: verse.ayah)
        if current != ref { current = ref }
        // Assigned only on change: this runs twenty times a second, and every
        // assignment redraws the sounding ayah's card.
        let position = verse.words.first(where: { ms >= $0.startMs && ms < $0.endMs })?.position
        if currentWordPosition != position { currentWordPosition = position }
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

    private func hasNarration(_ ref: ListenAyah) -> Bool {
        guard let edition = translationEdition else { return false }
        return NarrationCatalog.shared.has(edition: edition, kind: "translation", surah: ref.surah, start: ref.ayah, end: ref.ayah)
    }

    private func item(for ref: ListenAyah) -> AVPlayerItem? {
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
    private func playTranslation(of ref: ListenAyah, then: @escaping () -> Void) {
        guard let item = item(for: ref) else { then(); return }
        part = .translation
        current = ref
        currentWordPosition = nil
        narrator.removeAllItems()
        narrator.insert(item, after: nil)
        if let narratorEnd { NotificationCenter.default.removeObserver(narratorEnd) }
        let mySession = session
        narratorEnd = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
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
