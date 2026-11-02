import AVFoundation
import Observation
import UIKit

/// Foreground-only local capture. The screen supplies an awaited audio handoff
/// and permission request; neither a delayed permission nor a delayed handoff
/// may start capture after suspend/close. No network or shared media library.
@Observable
@MainActor
final class RecitationPracticeRecorder: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    private static weak var active: RecitationPracticeRecorder?

    /// Called synchronously before a new Halqah constructs its transport.
    /// Also invalidates a microphone request still awaiting permission.
    static func yieldToHalqah() {
        active?.suspend()
        active = nil
    }

    enum Phase { case idle, preparing, recording, replaying }
    enum Failure { case permission, audio, recording, playback, storage }
    private(set) var phase = Phase.idle
    private(set) var failure: Failure?
    private(set) var hasClip = false
    private(set) var clipReference: String?
    @ObservationIgnored private var recordingReference: String?
    @ObservationIgnored private let files: RecitationPracticeFiles
    @ObservationIgnored private let audioReserved: @MainActor () -> Bool
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var replay: AVAudioPlayer?
    @ObservationIgnored private var ticket = UUID()
    @ObservationIgnored private var closed = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(cacheDirectory: URL, audioReserved: @escaping @MainActor () -> Bool = {
        NativeHalqaSession.shared.lifecycle.transport != nil
    }) throws {
        self.audioReserved = audioReserved
        files = try RecitationPracticeFiles(cacheDirectory: cacheDirectory)
        super.init()
        for name in [UIApplication.didEnterBackgroundNotification, AVAudioSession.interruptionNotification,
                     AVAudioSession.routeChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                if name == AVAudioSession.interruptionNotification,
                   (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) != AVAudioSession.InterruptionType.began.rawValue { return }
                if name == AVAudioSession.routeChangeNotification,
                   (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) != AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { return }
                Task { @MainActor in self?.suspend() }
            })
        }
        for name in [Notification.Name.quranAudioWillStart, .bayanAudioWillStart] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.phase == .recording || self.phase == .replaying else { return }
                    // A different player is taking the session. Stop this
                    // recorder without deactivating that new owner's session.
                    self.suspend(deactivateSession: false)
                }
            })
        }
    }

    func start(reference: String? = nil, permission: (@escaping @MainActor (Bool) -> Void) -> Void,
               prepareAudio: @escaping (@escaping @MainActor (Bool) -> Void) -> Void,
               allowedNow: @escaping () -> Bool) {
        guard !closed, phase == .idle else { return }
        guard !audioReserved(), allowedNow() else { failure = .audio; return }
        claimPractice()
        failure = nil
        phase = .preparing
        ticket = UUID()
        let request = ticket
        permission { [weak self] granted in
            guard let self, self.isCurrent(request) else { return }
            guard !self.audioReserved(), allowedNow() else { self.phase = .idle; self.failure = .audio; return }
            guard granted else { self.phase = .idle; self.failure = .permission; return }
            prepareAudio { [weak self] ready in
                guard let self, self.isCurrent(request) else { return }
                guard ready, !self.audioReserved(), allowedNow(), UIApplication.shared.applicationState == .active else {
                    self.phase = .idle; self.failure = .audio; return
                }
                self.beginCapture(reference: reference)
            }
        }
    }

    private func isCurrent(_ request: UUID) -> Bool { !closed && ticket == request && phase == .preparing }

    private func beginCapture(reference: String?) {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            phase = .idle; failure = .permission; return
        }
        do {
            let file = try files.begin()
            recordingReference = reference
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let recording = try AVAudioRecorder(url: file, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000
            ])
            recorder = recording
            recording.delegate = self
            guard recording.prepareToRecord(), recording.record(forDuration: RecitationPracticeFiles.maximumDuration) else {
                throw CaptureError.cannotStart
            }
            phase = .recording
        } catch {
            recorder?.delegate = nil
            recorder?.stop()
            recorder = nil
            phase = .idle
            failure = .recording
            discardPending()
            deactivate()
        }
    }

    func stopRecording(deactivateSession: Bool = true) {
        guard let recording = recorder else { return }
        recorder = nil
        recording.delegate = nil
        recording.stop()
        phase = .idle
        do {
            let decoded = try AVAudioPlayer(contentsOf: recording.url)
            try files.accept(recording.url, decodedDuration: decoded.duration)
            clipReference = recordingReference
            hasClip = true
        } catch { failure = .recording; discardPending() }
        if deactivateSession { deactivate() }
    }

    /// The same audio handoff is required for replay as for capture. It must not
    /// interrupt a retained Halqah or race a preparing reference player.
    func play(prepareAudio: (@escaping @MainActor (Bool) -> Void) -> Void, allowedNow: @escaping () -> Bool) {
        guard !closed, phase == .idle, let file = files.current else { return }
        guard !audioReserved(), allowedNow() else { failure = .audio; return }
        claimPractice()
        failure = nil
        phase = .preparing
        ticket = UUID()
        let request = ticket
        prepareAudio { [weak self] ready in
            guard let self, self.isCurrent(request) else { return }
            guard ready, !self.audioReserved(), allowedNow(), UIApplication.shared.applicationState == .active else {
                self.phase = .idle; self.failure = .audio; return
            }
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
                let audio = try AVAudioPlayer(contentsOf: file)
                self.replay = audio
                audio.delegate = self
                guard audio.play() else { throw CaptureError.cannotStart }
                self.phase = .replaying
            } catch { self.stopReplay(); self.failure = .playback }
        }
    }

    func stopReplay(deactivateSession: Bool = true) {
        replay?.delegate = nil
        replay?.stop()
        replay = nil
        phase = .idle
        if deactivateSession { deactivate() }
    }

    func suspend(deactivateSession: Bool = true) {
        ticket = UUID()
        if recorder != nil { stopRecording(deactivateSession: deactivateSession) }
        else if replay != nil { stopReplay(deactivateSession: deactivateSession) }
        phase = .idle
        if Self.active === self { Self.active = nil }
    }

    private func claimPractice() {
        if let previous = Self.active, previous !== self { previous.suspend() }
        Self.active = self
    }

    func deleteClip() {
        guard phase == .idle else { return }
        do { try files.deleteCurrent(); hasClip = false; clipReference = nil; failure = nil }
        catch { failure = .storage }
    }

    func close() {
        suspend()
        closed = true
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        do { try files.close(); hasClip = false; clipReference = nil }
        catch { failure = .storage }
    }

    private func discardPending() {
        do { try files.discardPending() } catch { failure = .storage }
    }
    private func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    private enum CaptureError: Error { case cannotStart }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let identity = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, let active = self.recorder, ObjectIdentifier(active) == identity else { return }
            if flag { self.stopRecording() }
            else {
                active.delegate = nil; active.stop(); self.recorder = nil
                self.phase = .idle; self.failure = .recording
                self.discardPending(); self.deactivate()
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let active = self.replay, ObjectIdentifier(active) == identity else { return }
            self.stopReplay()
            if !flag { self.failure = .playback }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        audioRecorderDidFinishRecording(recorder, successfully: false)
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        audioPlayerDidFinishPlaying(player, successfully: false)
    }
}
