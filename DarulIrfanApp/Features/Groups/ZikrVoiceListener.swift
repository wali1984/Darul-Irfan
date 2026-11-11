import AVFoundation
import Speech
import UIKit

/// Listens to Hazrat ji on the leading admin's phone and names the stage he
/// is on: the Method of Zikr's opening recitations (heard in Arabic) and the
/// stages he calls out ("pehla latifa", "rabita", "muraqaba ahadiyat"), heard
/// as Urdu where the phone has an Urdu recognizer and otherwise as Hindi,
/// which writes the same spoken words in Devanagari.
///
/// The owner chose (2026-11-03) that a heard stage shows at once and an admin
/// can undo it; a tap always works too. Nothing leaves the phone except the
/// stage announcement itself: recognition runs on the device where it can.
///
/// One "Go Live" tap must carry a whole session hands-free (owner,
/// 2026-11-04): the screen stays awake, recognition starts again whenever it
/// ends or fails, and the microphone comes back after a call, Siri, another
/// app's audio, a headset change or a return to the app.
@MainActor
final class ZikrVoiceListener {
    enum State: Equatable { case off, asking, listening, unavailable(String) }
    private(set) var state: State = .off { didSet { onState?(state) } }
    var onState: ((State) -> Void)?
    /// A stage id the speech matched ("tasbih", "latifa-1", "raabta").
    var onHeard: ((String) -> Void)?
    /// The latest few words heard, for the admin's small live indicator.
    var onWords: ((String) -> Void)?
    /// The stage on the screen now, whoever set it (heard, tapped, typed):
    /// the Zikr's order and timing start from it (ZikrStageRules).
    var currentStage: (() -> String?)?

    private let engine = AVAudioEngine()
    private var tasks: [SFSpeechRecognitionTask] = []
    /// Read on the audio thread: each buffer goes straight to the live requests.
    private let feed = RequestFeed()
    private var requests: [SFSpeechAudioBufferRecognitionRequest] = [] { didSet { feed.set(requests) } }
    private var recognizers: [SFSpeechRecognizer] = []
    private var watchdog: Task<Void, Never>?
    private var pendingRestart: Task<Void, Never>?
    private var pendingRecovery: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    /// Bumped by every fresh start of recognition; a task that ends with an
    /// older number was replaced on purpose and is not restarted.
    private var generation = 0
    private var begunAt = Date()
    /// Recognition that ended without hearing anything, in a row: backs off.
    private var quietEnds = 0
    /// A phone call or Siri has the microphone; resumed when it ends.
    private var interrupted = false
    /// The screen-lock setting before listening began, put back on stop.
    private var idleTimerBefore: Bool?
    /// Whether a heard stage becomes the stage, and the recent words it reads.
    private var rules = ZikrStageRules()
    private var heardWords = ZikrRecentWords()
    /// The recognizer that reads the call-outs (Urdu, or Hindi): talk is judged on it.
    private var calloutSource = 0

    func start() async {
        guard state == .off || state.isUnavailable else { return }
        state = .asking
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard state == .asking else { return }
        guard speech == .authorized, microphone else {
            state = .unavailable(String(localized: "Allow Speech Recognition and the Microphone for Darul Irfan in Settings."))
            return
        }
        let callout = ["ur-PK", "ur-IN", "hi-IN"].lazy.compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
            .first { $0.isAvailable }
        recognizers = [SFSpeechRecognizer(locale: Locale(identifier: "ar-SA")), callout].compactMap { $0 }.filter(\.isAvailable)
        calloutSource = recognizers.lastIndex { !$0.locale.identifier.hasPrefix("ar") } ?? 0
        rules = ZikrStageRules()
        heardWords = ZikrRecentWords()
        lastHeard = nil
        guard !recognizers.isEmpty else {
            state = .unavailable(String(localized: "Speech recognition is not available on this phone right now."))
            return
        }
        guard startAudio() else {
            state = .unavailable(String(localized: "The microphone could not be started."))
            return
        }
        state = .listening
        keepScreenAwake(true)
        observeAudioSession()
        quietEnds = 0
        begin()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled, self.state == .listening else { return }
                self.checkHealth()
                // A stage tapped or typed while nothing was heard still starts the gap.
                self.rules.observe(self.currentStage?(), at: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    func stop() {
        watchdog?.cancel(); watchdog = nil
        pendingRestart?.cancel(); pendingRestart = nil
        pendingRecovery?.cancel(); pendingRecovery = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        generation += 1
        tasks.forEach { $0.cancel() }; tasks = []
        requests.forEach { $0.endAudio() }; requests = []
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        interrupted = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        keepScreenAwake(false)
        state = .off
    }

    /// Back in the app: the microphone may have been taken while away.
    func resumeIfNeeded() {
        guard state == .listening else { return }
        interrupted = false
        if !engine.isRunning { scheduleRecovery(after: .milliseconds(300)) }
    }

    // MARK: Audio

    private func startAudio() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            let format = input.outputFormat(forBus: 0)
            // No input yet (a route is still changing): the watchdog tries again.
            guard format.sampleRate > 0, format.channelCount > 0 else { return false }
            let feed = self.feed
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                feed.append(buffer)
            }
            engine.prepare()
            try engine.start()
            feed.markStarted()
            return true
        } catch {
            return false
        }
    }

    /// Starts the microphone afresh (a new route, a reset, an interruption over).
    private func recoverAudio() {
        guard state == .listening, !interrupted else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        guard startAudio() else { return }
        quietEnds = 0
        begin()
    }

    /// Notifications come in bursts; one recovery a moment later serves them all.
    private func scheduleRecovery(after delay: Duration = .milliseconds(600)) {
        pendingRecovery?.cancel()
        pendingRecovery = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.recoverAudio()
        }
    }

    private func checkHealth() {
        switch Self.watchdogAction(engineRunning: engine.isRunning, secondsSinceAudio: feed.secondsSinceLastBuffer(),
                                   secondsSinceBegin: Date().timeIntervalSince(begunAt), interrupted: interrupted) {
        case .none: break
        case .refreshRecognition: begin()
        case .restartAudio: recoverAudio()
        }
    }

    private func observeAudioSession() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let action = ZikrVoiceListener.interruptionAction(note.userInfo)
            MainActor.assumeIsolated {
                guard let self, self.state == .listening else { return }
                switch action {
                case .pause:
                    self.interrupted = true
                case .resume:
                    self.interrupted = false
                    self.scheduleRecovery()
                case .ignore:
                    break
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let recover = ZikrVoiceListener.recoversAfterRouteChange(note.userInfo)
            MainActor.assumeIsolated {
                guard recover, let self, self.state == .listening else { return }
                self.scheduleRecovery()
            }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state == .listening else { return }
                self.scheduleRecovery()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state == .listening else { return }
                self.interrupted = false
                self.scheduleRecovery(after: .seconds(1))
            }
        })
    }

    private func keepScreenAwake(_ awake: Bool) {
        if awake {
            if idleTimerBefore == nil { idleTimerBefore = UIApplication.shared.isIdleTimerDisabled }
            UIApplication.shared.isIdleTimerDisabled = true
        } else if let before = idleTimerBefore {
            UIApplication.shared.isIdleTimerDisabled = before
            idleTimerBefore = nil
        }
    }

    // MARK: Recognition

    private func begin() {
        generation += 1
        let current = generation
        pendingRestart?.cancel(); pendingRestart = nil
        tasks.forEach { $0.finish() }
        requests.forEach { $0.endAudio() }
        tasks = []; requests = []
        begunAt = Date()
        // A fresh transcript per recognizer: the last one's words still count for a few seconds.
        heardWords.endAll(at: ProcessInfo.processInfo.systemUptime)
        for (source, recognizer) in recognizers.enumerated() where recognizer.isAvailable {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            request.addsPunctuation = false
            requests.append(request)
            tasks.append(recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let ended = error != nil || result?.isFinal == true
                Task { @MainActor in
                    guard let self else { return }
                    if let text, !text.isEmpty { self.heard(text, source: source) }
                    if ended { self.recognitionEnded(generation: current) }
                }
            })
        }
        // A recognizer can be briefly unavailable; try again shortly.
        if requests.isEmpty { recognitionEnded(generation: current) }
    }

    /// A recognition task finished or failed by itself: start again, sooner
    /// after speech, later after repeated silent failures.
    private func recognitionEnded(generation ended: Int) {
        guard Self.restartsRecognition(endedGeneration: ended, currentGeneration: generation, isListening: state == .listening) else { return }
        let delay = Self.restartDelay(quietEnds: quietEnds)
        quietEnds += 1
        pendingRestart?.cancel()
        pendingRestart = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, self.state == .listening, self.generation == ended else { return }
            if self.interrupted || !self.engine.isRunning { self.recoverAudio() } else { self.begin() }
        }
    }

    private var lastHeard: (stage: String, at: Date)?
    private var lastWords = ""

    private func heard(_ transcript: String, source: Int) {
        quietEnds = 0
        let words = Self.recentWords(transcript)
        if words != lastWords { lastWords = words; onWords?(words) }
        // Only the last few seconds' words: a partial result repeats everything said so far.
        let now = ProcessInfo.processInfo.systemUptime
        heardWords.update(source, transcript: transcript, at: now)
        let callout = heardWords.reading(calloutSource, at: now)
        let arabic = recognizers.indices.filter { $0 != calloutSource }.map { heardWords.reading($0, at: now) }.joined(separator: " ")
        // The Zikr's order and timing decide whether the words heard move the stage.
        guard let stage = rules.decide(current: currentStage?(), callout: callout, arabic: arabic, at: now) else { return }
        if Self.isRepeat(stage, last: lastHeard, now: Date()) { return }
        lastHeard = (stage, Date())
        rules.took(stage, at: now)
        onHeard?(stage)
    }

    // MARK: Decisions (tested without a microphone)

    enum WatchdogAction: Equatable { case none, refreshRecognition, restartAudio }
    enum InterruptionAction: Equatable { case pause, resume, ignore }

    /// Every few seconds: the microphone silent or stopped is started again;
    /// recognition is renewed before the recognizer's one-minute limit.
    nonisolated static func watchdogAction(engineRunning: Bool, secondsSinceAudio: TimeInterval?,
                                           secondsSinceBegin: TimeInterval, interrupted: Bool) -> WatchdogAction {
        if interrupted { return .none }
        if !engineRunning { return .restartAudio }
        if let secondsSinceAudio, secondsSinceAudio > 6 { return .restartAudio }
        return secondsSinceBegin >= 50 ? .refreshRecognition : .none
    }

    /// Only the live recognition, ending by itself while listening, restarts.
    nonisolated static func restartsRecognition(endedGeneration: Int, currentGeneration: Int, isListening: Bool) -> Bool {
        isListening && endedGeneration == currentGeneration
    }

    /// Half a second after speech; doubling after each silent end, up to 30 seconds.
    nonisolated static func restartDelay(quietEnds: Int) -> Duration {
        let steps = min(max(quietEnds, 0), 6)
        return .milliseconds(min(30_000, 500 * (1 << steps)))
    }

    nonisolated static func interruptionAction(_ userInfo: [AnyHashable: Any]?) -> InterruptionAction {
        guard let raw = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return .ignore }
        switch type {
        case .began:
            return .pause
        case .ended:
            return .resume
        @unknown default:
            return .ignore
        }
    }

    /// A headset or microphone coming or going changes the input; our own
    /// category setting (and other apps') does not need a restart here.
    nonisolated static func recoversAfterRouteChange(_ userInfo: [AnyHashable: Any]?) -> Bool {
        guard let raw = userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return false }
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .routeConfigurationChange, .wakeFromSleep: return true
        default: return false
        }
    }

    /// The same stage heard again within two minutes is the same call-out.
    nonisolated static func isRepeat(_ stage: String, last: (stage: String, at: Date)?, now: Date) -> Bool {
        guard let last else { return false }
        return last.stage == stage && now.timeIntervalSince(last.at) < 120
    }

    /// The last few words of a transcript, for the live indicator.
    nonisolated static func recentWords(_ transcript: String, count: Int = 6) -> String {
        transcript.split(whereSeparator: \.isWhitespace).suffix(count).joined(separator: " ")
    }
}

/// The recognition requests the audio thread feeds, behind a lock.
private final class RequestFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [SFSpeechAudioBufferRecognitionRequest] = []
    private var lastBuffer: Date?
    func set(_ value: [SFSpeechAudioBufferRecognitionRequest]) { lock.withLock { requests = value } }
    func append(_ buffer: AVAudioPCMBuffer) {
        let live = lock.withLock { () -> [SFSpeechAudioBufferRecognitionRequest] in
            lastBuffer = Date()
            return requests
        }
        live.forEach { $0.append(buffer) }
    }
    /// A fresh start counts as audio, so the watchdog waits for the first buffer.
    func markStarted() { lock.withLock { lastBuffer = Date() } }
    func secondsSinceLastBuffer() -> TimeInterval? { lock.withLock { lastBuffer.map { Date().timeIntervalSince($0) } } }
}

private extension ZikrVoiceListener.State {
    var isUnavailable: Bool { if case .unavailable = self { true } else { false } }
}

/// The words that name each stage, as each recognizer writes them. Kept apart
/// from the listener so it can be tested without a microphone.
enum ZikrSpeechMatcher {
    /// Arabic marks, tatweel, Devanagari nukta and nasal marks go; letters the
    /// phones' recognisers mix up in Hazrat ji's call-outs fold together (heard in
    /// the Daily Zikr of 2 and 3 Nov 2026): ٹ/ت, a final ں, ۂ/ہ; द/त, थ/त, ठ/ट.
    static func normalized(_ text: String) -> String {
        let dropped: (Unicode.Scalar) -> Bool = {
            (0x064B...0x065F).contains($0.value) || [0x0670, 0x0640, 0x093C, 0x0901, 0x0902, 0x06BA].contains($0.value)
        }
        let map: [Unicode.Scalar: Unicode.Scalar] = ["أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ى": "ی", "ي": "ی",
                                                     "ك": "ک", "ة": "ہ", "ه": "ہ", "ھ": "ہ", "ۂ": "ہ", "ٹ": "ت",
                                                     "द": "त", "थ": "त", "ठ": "ट"]
        var scalars = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars where !dropped(scalar) { scalars.append(map[scalar] ?? scalar) }
        return String(scalars)
    }

    /// Each Latifa as Hazrat ji calls it, "<number> latifa", in every form the
    /// recognisers wrote it (Urdu, and Hindi in Devanagari).
    private static let ordinals: [[String]] = [
        ["پہلا", "پہلے", "اہلا", "पहला", "पहले"],
        ["دوسرا", "دوسرے", "दूसरा", "दूसरे"],
        ["تیسرا", "تیسرے", "तीसरा", "तीसरे"],
        ["چوتھا", "چوتھے", "चौथा", "चौथे"],
        ["پانچواں", "پانچویں", "پانچو", "पांचवां", "पांचवें", "पांच"],
        ["چھٹا", "چھٹے", "छठा", "छठे", "छटने", "छट्टे"],
        ["ساتواں", "ساتویں", "ساتھو", "ساتوے", "सातवां", "सातवें", "सात"],
    ]
    private static let latifaWords = ["لطیفہ", "لطیفے", "लतीफा", "लतीफे"]

    static let phrases: [(stage: String, words: [String])] = makePhrases()

    private static func makePhrases() -> [(stage: String, words: [String])] {
        var list: [(stage: String, words: [String])] = [
            // The Tasbihat are the third Kalima ("سبحان اللہ والحمد للہ ولا الہ الا اللہ واللہ اکبر ولا حول
            // ولا قوۃ الا باللہ العلی العظیم"): "سبحان اللہ" names it, and before any stage
            // ZikrStageRules wants its next words too (a bayan says "سبحان اللہ").
            (stage: "tasbih", words: ["سبحان اللہ والحمد", "سبحان اللہ و الحمد", "سبحان اللہ",
                                      "सुब्हान अल्लाह", "सुबहान अल्लाह", "सुभान अल्लाह"]),
            (stage: "istighfar", words: ["استغفر اللہ ربی", "استغفر اللہ"]),
            (stage: "shahadah", words: ["اشہد ان لا الہ", "اشہد ان"]),
            (stage: "taawwudh", words: ["اعوذ باللہ", "اعوذ"]),
            (stage: "basmalah", words: ["بسم اللہ الرحمن", "بسم اللہ"]),
        ]
        for (index, numbers) in ordinals.enumerated() {
            var words: [String] = []
            for number in numbers {
                for latifa in latifaWords { words.append(number + " " + latifa) }
            }
            if index == 0 { words.append("لطیفہ قلب") }
            if index == 1 { words.append("लतीफा रूह") }
            list.append((stage: "latifa-" + String(index + 1), words: words))
        }
        list += [
            (stage: "ahadiyat", words: ["احدیت", "عادیت", "अहदियत", "आधियत", "अहदीयत"]),
            (stage: "maiyyat", words: ["معیت", "मइय्यत", "मैयत", "मायियत", "माईयत"]),
            (stage: "aqrabiyyat", words: ["اقربیت", "अकरबियत", "अक्रबियत"]),
            (stage: "sair-kaaba", words: ["سیر کعبہ", "سہر کعبہ", "سیرِ کعبہ", "सैर काबा", "सहर काबा", "सैरे काबा"]),
            (stage: "rauza-athar", words: ["روضہ اطہر", "روضۂ اطہر", "روز اثر", "روزہ اثر", "रोज अथर", "रोजा अथर", "रौजा अतहर", "रोजा अतहर"]),
            (stage: "masjid-nabawi", words: ["مسجد نبوی", "مسجد نبی", "मस्जिद नबवी", "मस्जिदे नबवी", "मस्च नवी", "मस्चे नवी"]),
            (stage: "raabta", words: ["رابطہ", "राबिता", "राब्ता", "राबता"]),
        ]
        return list
    }

    /// The stage whose words were said last in the transcript, if any.
    static func stage(in transcript: String) -> String? {
        match(in: transcript)?.stage
    }

    /// The stage whose words were said last in the transcript, and those
    /// words (normalized), if any.
    static func match(in transcript: String) -> (stage: String, phrase: String)? {
        var best: (stage: String, phrase: String, at: String.Index)?
        for (stage, words) in phrases {
            for word in words {
                let phrase = normalized(word)
                guard let range = transcript.range(of: phrase, options: .backwards) else { continue }
                if best == nil || range.lowerBound > best!.at { best = (stage, phrase, range.lowerBound) }
            }
        }
        return best.map { (stage: $0.stage, phrase: $0.phrase) }
    }
}

/// Whether a stage heard becomes the stage: the live Zikr's own order and
/// timing, as proven on Our Sheikh's relay (Tools/LiveRelay audio_picker,
/// 10 November 2026), so every Halqah's "Go Live" follows the leader the same
/// way. Only the decision lives here; the words that name a stage are
/// ZikrSpeechMatcher's (the relay's Whisper spellings do not carry over).
/// Times are seconds on one steady clock. Android: ZikrStageRules in
/// ZikrVoiceListener.kt, the same rules.
///
/// - The stages only go forward in `order`. The opening recitations come
///   first, in their order (any may be skipped). After the 7th Latifa the
///   Zikr returns to the 1st for a moment, then Raabta, then the Muraqabat:
///   a Latifa called then is that return and moves nothing.
/// - A Latifa's number may jump at most two past the next one (a call was
///   missed), a Muraqaba's name at most two ahead; never backwards. A custom
///   stage or the dua: no moves by voice.
/// - No new Latifa, Raabta or Muraqaba within `stageGap` of the last stage
///   change, whoever made it (heard, tapped, typed). The opening and the 1st
///   Latifa after it are exempt.
/// - Never in the middle of talk: a bayan says "پہلا لطیفہ" and "بسم اللہ".
///   The Zikr's own sound reads as nothing, or one or two words over and over.
/// - Before any stage only the Zikr's own opening starts it.
/// - A Latifa's call is a word or two: never from a long reading.
struct ZikrStageRules {
    static let order = ["tasbih", "latifa-1", "latifa-2", "latifa-3", "latifa-4", "latifa-5", "latifa-6", "latifa-7",
                        "raabta", "ahadiyat", "maiyyat", "aqrabiyyat", "sair-kaaba", "rauza-athar", "masjid-nabawi", "shajra"]
    static let opening = ["tasbih", "istighfar", "shahadah", "taawwudh", "basmalah"]
    /// A Latifa or Muraqaba lasts minutes: no new one this soon after the last stage.
    static let stageGap: TimeInterval = 40
    /// The opening recitations follow each other within seconds.
    static let openingWindow: TimeInterval = 45
    static let runWindow: TimeInterval = 60
    /// Three different opening recitations heard close together are the
    /// Zikr's opening even in "talk" (recitation reads as talk); a bayan quotes one at a time.
    static let openingRunSize = 3
    /// A stage heard is refused when the readings from `talkBefore` to
    /// `talkSkip` seconds before it (the call itself is talk) were mostly talk.
    static let talkBefore: TimeInterval = 30
    static let talkSkip: TimeInterval = 6
    static let talkMost = 0.4
    /// A reading is the words heard in the last few seconds.
    static let readingSeconds: TimeInterval = 5
    /// The Tasbih's next words: before any stage "سبحان اللہ" alone (a bayan
    /// says it) does not start the Zikr.
    static let tasbihMore: [String] = ["الحمد", "اکبر", "لا الہ", "لا حول", "قوۃ", "قوت", "قوہ", "العظیم",
                                       "हम्द", "अकबर", "ला इलाह", "ला हौल", "कुव्वत", "अजीम"].map(ZikrSpeechMatcher.normalized)
    private static let seventh = order.firstIndex(of: "latifa-7") ?? 7

    /// The stage as last seen, and since when.
    private(set) var seenStage: String?
    private(set) var stageAt: TimeInterval = -1e9
    /// The 7th Latifa (or later) was on the stage: the 1st again is the return to it.
    private var passedSeventh = false
    /// Whether each reading of the call-outs was talk, about one a second.
    private var talk: [(at: TimeInterval, isTalk: Bool)] = []
    /// Opening recitations heard before any stage: (when, index in `opening`).
    private var recited: [(at: TimeInterval, index: Int)] = []

    init() {}

    /// The stage on the screen now, whoever set it: a change starts the gap.
    mutating func observe(_ stage: String?, at: TimeInterval) {
        guard stage != seenStage else { return }
        seenStage = stage
        stageAt = at
        guard let stage else { passedSeventh = false; return }
        if let index = Self.order.firstIndex(of: stage), index >= Self.seventh { passedSeventh = true }
    }

    /// The listener announced `stage`: it is the stage from now.
    mutating func took(_ stage: String, at: TimeInterval) {
        observe(stage, at: at)
    }

    /// The stage the latest readings move to, if any. `callout` is the last
    /// few seconds' words from the Urdu (or Hindi) recognizer, `arabic` from
    /// the Arabic one; `current` the stage on the screen.
    mutating func decide(current: String?, callout: String, arabic: String = "", at: TimeInterval) -> String? {
        observe(current, at: at)
        let callout = ZikrSpeechMatcher.normalized(callout)
        let arabic = ZikrSpeechMatcher.normalized(arabic)
        if talk.last.map({ at - $0.at >= 1 }) ?? true {
            talk.append((at: at, isTalk: Self.isTalk(callout)))
            talk.removeAll { at - $0.at > Self.talkBefore + 5 }
        }
        guard let heard = ZikrSpeechMatcher.match(in: callout) ?? ZikrSpeechMatcher.match(in: arabic),
              let stage = listened(heard.stage, phrase: heard.phrase, current: current, callout: callout, arabic: arabic, at: at)
        else { return nil }
        // The opening's next recitation, or its 1st Latifa, is taken in talk:
        // recitation reads as talk.
        let inOpening = current.map { Self.opening.contains($0) } ?? openingRun(at: at, window: Self.runWindow)
        let exempt = (Self.opening.contains(stage) || stage == "latifa-1") && inOpening
        if !exempt && talkShare(before: at) >= Self.talkMost { return nil }
        return stage
    }

    /// The stage the words name, by the order and the gap (talk aside).
    private mutating func listened(_ heard: String, phrase: String, current: String?, callout: String, arabic: String,
                                   at: TimeInterval) -> String? {
        let latifa = Self.latifa(heard)
        let reading = callout.contains(phrase) ? callout : arabic
        // Before any stage (-1) or during the opening: its recitations in their order, then the 1st Latifa.
        var after: Int?
        if let current { after = Self.opening.firstIndex(of: current) } else { after = -1 }
        if let after {
            if let index = Self.opening.firstIndex(of: heard) {
                guard index > after else { return nil }
                if current == nil {
                    // Only the Zikr's own opening starts it: the Tasbih with its next
                    // words, or the Istighfar or Shahadah right after a Tasbih heard,
                    // or three recitations in a row. A bayan opens with "اعوذ باللہ ...
                    // بسم اللہ" and says "سبحان اللہ".
                    let tasbihBefore = recited.contains { $0.index == 0 && at - $0.at <= Self.openingWindow }
                    recited = recited.filter { at - $0.at <= Self.runWindow } + [(at: at, index: index)]
                    if openingRun(at: at) { return heard }
                    if index == 0 && !Self.tasbihMore.contains(where: { callout.contains($0) || arabic.contains($0) }) { return nil }
                    if index > 0 && !(index <= 2 && tasbihBefore) { return nil }
                }
                return heard
            }
            // The 1st Latifa's call ends the opening (the 2nd or 3rd if a call was
            // missed). Before any stage only after an opening recitation in the
            // minute before it.
            guard let latifa, latifa <= 3, !Self.isLong(reading, without: phrase) else { return nil }
            if current == nil && !recited.contains(where: { at - $0.at <= Self.runWindow }) { return nil }
            return heard
        }
        guard let current, at - stageAt >= Self.stageGap else { return nil }
        // The 1st Latifa after the 7th is the return to it: Raabta and the Muraqabat follow.
        let now = current == "latifa-1" && passedSeventh ? "latifa-7" : current
        guard let position = Self.order.firstIndex(of: now) else { return nil }  // a custom stage, the dua
        if let number = Self.latifa(now), number < 7 {
            guard let latifa, latifa > number, latifa <= number + 3, !Self.isLong(reading, without: phrase) else { return nil }
            return heard
        }
        guard position >= Self.seventh, latifa == nil, let named = Self.order.firstIndex(of: heard),
              named > position, named <= position + 2 else { return nil }
        return heard
    }

    func openingRun(at: TimeInterval, window: TimeInterval = ZikrStageRules.openingWindow) -> Bool {
        let heard = Set(recited.filter { at - $0.at <= window }.map { $0.index })
        return heard.count >= Self.openingRunSize && (heard.min() ?? Int.max) <= 2
    }

    /// The share of the readings from `talkBefore` to `talkSkip` seconds before
    /// `at` that were talk (0 when nothing was heard: quiet is not a bayan).
    func talkShare(before at: TimeInterval) -> Double {
        let window = talk.filter { $0.at >= at - Self.talkBefore && $0.at <= at - Self.talkSkip }
        guard !window.isEmpty else { return 0 }
        return Double(window.filter { $0.isTalk }.count) / Double(window.count)
    }

    /// Speech (a bayan, a call, a recitation) rather than the Zikr's sound,
    /// which reads as nothing or one or two words over and over.
    static func isTalk(_ reading: String) -> Bool {
        let words = reading.split(whereSeparator: \.isWhitespace)
        return words.count >= 3 && Set(words).count >= 3
    }

    /// A reading that is talk even without the call's own words.
    static func isLong(_ reading: String, without phrase: String) -> Bool {
        let own = Set(phrase.split(whereSeparator: \.isWhitespace))
        return isTalk(reading.split(whereSeparator: \.isWhitespace).filter { !own.contains($0) }.joined(separator: " "))
    }

    static func latifa(_ stage: String) -> Int? {
        stage.hasPrefix("latifa-") ? Int(stage.dropFirst(7)) : nil
    }
}

/// When each word of the recognizers' running transcripts was first heard in
/// its present form, so a reading is the last few seconds' words (the relay
/// reads a five-second window every second; a partial result repeats
/// everything said since recognition began).
struct ZikrRecentWords {
    typealias Word = (word: String, at: TimeInterval)
    private var live: [Int: [Word]] = [:]
    private var ended: [Int: [Word]] = [:]

    init() {}

    /// A recognizer's whole transcript so far: the words that changed are new.
    mutating func update(_ source: Int, transcript: String, at: TimeInterval) {
        let words = ZikrSpeechMatcher.normalized(transcript).split(whereSeparator: \.isWhitespace).map(String.init)
        let old = live[source] ?? []
        var kept = 0
        while kept < old.count, kept < words.count, old[kept].word == words[kept] { kept += 1 }
        let added: [Word] = words.dropFirst(kept).map { (word: $0, at: at) }
        live[source] = Array(old.prefix(kept)) + added
    }

    /// Recognition starts afresh: the transcripts so far still count for a reading.
    mutating func endAll(at: TimeInterval) {
        for (source, words) in live { ended[source, default: []] += words }
        live = [:]
        for source in Array(ended.keys) {
            ended[source]?.removeAll { at - $0.at > ZikrStageRules.readingSeconds }
        }
    }

    /// The words a recognizer heard in the last few seconds.
    func reading(_ source: Int, at: TimeInterval, seconds: TimeInterval = ZikrStageRules.readingSeconds) -> String {
        ((ended[source] ?? []) + (live[source] ?? [])).filter { at - $0.at <= seconds }.map { $0.word }.joined(separator: " ")
    }
}
