import AVFoundation
import Speech

/// Listens to Hazrat ji on the leading admin's phone and names the stage he
/// is on: the Method of Zikr's opening recitations (heard in Arabic) and the
/// stages he calls out ("pehla latifa", "rabita", "muraqaba ahadiyat"), heard
/// as Urdu where the phone has an Urdu recognizer and otherwise as Hindi,
/// which writes the same spoken words in Devanagari.
///
/// The owner chose (2026-11-03) that a heard stage shows at once and an admin
/// can undo it; a tap always works too. Nothing leaves the phone except the
/// stage announcement itself: recognition runs on the device where it can.
@MainActor
final class ZikrVoiceListener {
    enum State: Equatable { case off, asking, listening, unavailable(String) }
    private(set) var state: State = .off { didSet { onState?(state) } }
    var onState: ((State) -> Void)?
    /// A stage id the speech matched ("tasbih", "latifa-1", "raabta").
    var onHeard: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var tasks: [SFSpeechRecognitionTask] = []
    /// Read on the audio thread: each buffer goes straight to the live requests.
    private let feed = RequestFeed()
    private var requests: [SFSpeechAudioBufferRecognitionRequest] = [] { didSet { feed.set(requests) } }
    private var recognizers: [SFSpeechRecognizer] = []
    private var restart: Task<Void, Never>?

    func start() async {
        guard state == .off || state.isUnavailable else { return }
        state = .asking
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard speech == .authorized, microphone else {
            state = .unavailable(String(localized: "Allow Speech Recognition and the Microphone for Darul Irfan in Settings."))
            return
        }
        let callout = ["ur-PK", "ur-IN", "hi-IN"].lazy.compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
            .first { $0.isAvailable }
        recognizers = [SFSpeechRecognizer(locale: Locale(identifier: "ar-SA")), callout].compactMap { $0 }.filter(\.isAvailable)
        guard !recognizers.isEmpty else {
            state = .unavailable(String(localized: "Speech recognition is not available on this phone right now."))
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            let feed = self.feed
            input.installTap(onBus: 0, bufferSize: 2048, format: input.outputFormat(forBus: 0)) { buffer, _ in
                feed.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            state = .unavailable(String(localized: "The microphone could not be started."))
            return
        }
        state = .listening
        begin()
        // Server recognition stops after about a minute; start afresh before then.
        restart = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(50))
                guard let self, !Task.isCancelled, self.state == .listening else { return }
                self.begin()
            }
        }
    }

    func stop() {
        restart?.cancel(); restart = nil
        tasks.forEach { $0.cancel() }; tasks = []
        requests.forEach { $0.endAudio() }; requests = []
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = .off
    }

    private func begin() {
        tasks.forEach { $0.finish() }
        requests.forEach { $0.endAudio() }
        tasks = []; requests = []
        for recognizer in recognizers {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            request.addsPunctuation = false
            requests.append(request)
            tasks.append(recognizer.recognitionTask(with: request) { [weak self] result, _ in
                guard let text = result?.bestTranscription.formattedString else { return }
                Task { @MainActor in self?.heard(text) }
            })
        }
    }

    private var lastHeard: (stage: String, at: Date)?

    private func heard(_ transcript: String) {
        // Only the latest words: a partial result repeats everything said so far.
        let recent = String(ZikrSpeechMatcher.normalized(transcript).suffix(80))
        guard let stage = ZikrSpeechMatcher.stage(in: recent) else { return }
        if let lastHeard, lastHeard.stage == stage, Date().timeIntervalSince(lastHeard.at) < 120 { return }
        lastHeard = (stage, Date())
        onHeard?(stage)
    }
}

/// The recognition requests the audio thread feeds, behind a lock.
private final class RequestFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [SFSpeechAudioBufferRecognitionRequest] = []
    func set(_ value: [SFSpeechAudioBufferRecognitionRequest]) { lock.withLock { requests = value } }
    func append(_ buffer: AVAudioPCMBuffer) { lock.withLock { requests }.forEach { $0.append(buffer) } }
}

private extension ZikrVoiceListener.State {
    var isUnavailable: Bool { if case .unavailable = self { true } else { false } }
}

/// The words that name each stage, as each recognizer writes them. Kept apart
/// from the listener so it can be tested without a microphone.
enum ZikrSpeechMatcher {
    /// Arabic marks and tatweel go; alef forms and ya/kaf/ha fold together.
    static func normalized(_ text: String) -> String {
        let dropped: (Unicode.Scalar) -> Bool = {
            (0x064B...0x065F).contains($0.value) || [0x0670, 0x0640, 0x093C].contains($0.value)
        }
        let map: [Unicode.Scalar: Unicode.Scalar] = ["أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ى": "ی", "ي": "ی",
                                                     "ك": "ک", "ة": "ہ", "ه": "ہ", "ھ": "ہ"]
        var scalars = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars where !dropped(scalar) { scalars.append(map[scalar] ?? scalar) }
        return String(scalars)
    }

    /// Listed most specific first: "latifa" with its number before the plain word.
    static let phrases: [(stage: String, words: [String])] = [
        ("tasbih", ["سبحان اللہ والحمد", "سبحان اللہ و الحمد"]),
        ("istighfar", ["استغفر اللہ ربی", "استغفر اللہ"]),
        ("shahadah", ["اشہد ان لا الہ", "اشہد ان"]),
        ("taawwudh", ["اعوذ باللہ", "اعوذ"]),
        ("basmalah", ["بسم اللہ الرحمن", "بسم اللہ"]),
        ("latifa-1", ["پہلا لطیفہ", "پہلے لطیفے", "لطیفہ قلب", "पहला लतीफ़ा", "पहला लतीफा", "पहले लतीफ़े", "पहले लतीफे"]),
        ("latifa-2", ["دوسرا لطیفہ", "دوسرے لطیفے", "लतीफ़ा रूह", "दूसरा लतीफ़ा", "दूसरा लतीफा", "दूसरे लतीफ़े", "दूसरे लतीफे"]),
        ("latifa-3", ["تیسرا لطیفہ", "تیسرے لطیفے", "तीसरा लतीफ़ा", "तीसरा लतीफा", "तीसरे लतीफ़े", "तीसरे लतीफे"]),
        ("latifa-4", ["چوتھا لطیفہ", "چوتھے لطیفے", "चौथा लतीफ़ा", "चौथा लतीफा", "चौथे लतीफ़े", "चौथे लतीफे"]),
        ("latifa-5", ["پانچواں لطیفہ", "پانچویں لطیفے", "पांचवां लतीफ़ा", "पाँचवाँ लतीफ़ा", "पांचवां लतीफा", "पांचवें लतीफ़े", "पांचवें लतीफे"]),
        ("latifa-6", ["چھٹا لطیفہ", "چھٹے لطیفے", "छठा लतीफ़ा", "छठा लतीफा", "छठे लतीफ़े", "छठे लतीफे"]),
        ("latifa-7", ["ساتواں لطیفہ", "ساتویں لطیفے", "सातवां लतीफ़ा", "सातवाँ लतीफ़ा", "सातवां लतीफा", "सातवें लतीफ़े", "सातवें लतीफे"]),
        ("ahadiyat", ["مراقبہ احدیت", "احدیت", "मुराक़बा अहदियत", "अहदियत"]),
        ("maiyyat", ["مراقبہ معیت", "معیت", "मुराक़बा मइय्यत", "मइय्यत", "मैयत"]),
        ("aqrabiyyat", ["مراقبہ اقربیت", "اقربیت", "मुराक़बा अक़रबियत", "अक़रबियत", "अकरबियत"]),
        ("raabta", ["رابطہ", "राबिता", "राब्ता", "राबता"]),
    ]

    /// The stage whose words were said last in the transcript, if any.
    static func stage(in transcript: String) -> String? {
        var best: (stage: String, at: String.Index)?
        for (stage, words) in phrases {
            for word in words {
                guard let range = transcript.range(of: normalized(word), options: .backwards) else { continue }
                if best == nil || range.lowerBound > best!.at { best = (stage, range.lowerBound) }
                break
            }
        }
        return best?.stage
    }
}
