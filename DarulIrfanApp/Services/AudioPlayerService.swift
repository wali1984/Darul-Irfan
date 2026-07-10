import Foundation
import AVFoundation
import MediaPlayer
import Observation

/// Live audio player for lectures and recitations. Wraps a single AVPlayer,
/// keeps the shared queue, publishes playback state for the mini player and
/// the full player screen, mirrors state to the Lock Screen / Control Center
/// (MPNowPlayingInfoCenter + MPRemoteCommandCenter), and persists
/// "continue listening" progress through `MediaRepositoryProtocol`.
///
/// Owned by `AppDependencies` for the app's lifetime; all mutable state is
/// MainActor-isolated. System callbacks (periodic time observer, notification
/// center, remote commands) hop back onto the main actor before touching state.
@Observable
@MainActor
final class AudioPlayerService: AudioPlayerServicing {

    // MARK: - Observable state

    private(set) var nowPlaying: AudioPlayableItem?
    private(set) var isPlaying: Bool = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var queue: [AudioPlayableItem] = []

    var playbackSpeed: PlaybackSpeed = .normal {
        didSet {
            guard playbackSpeed != oldValue else { return }
            let rate = Float(playbackSpeed.rawValue)
            player?.defaultRate = rate
            if isPlaying {
                // Setting rate while playing applies the new speed immediately;
                // defaultRate preserves it across pause/resume.
                player?.rate = rate
            }
            updateNowPlayingInfo()
        }
    }

    // MARK: - Private state (not observed)

    private let mediaRepository: any MediaRepositoryProtocol

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserverToken: Any?
    @ObservationIgnored private var itemEndObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var routeChangeObserver: NSObjectProtocol?
    @ObservationIgnored private var resumeTask: Task<Void, Never>?
    @ObservationIgnored private var lastProgressSaveDate: Date = .distantPast
    @ObservationIgnored private var wasPlayingBeforeInterruption: Bool = false

    /// Seconds of playback between periodic progress saves.
    private static let progressSaveInterval: TimeInterval = 10
    /// Saved positions shorter than this restart from the beginning.
    private static let minimumResumePosition: Double = 10
    /// Items at or past this completed fraction restart from the beginning.
    private static let maximumResumeFraction: Double = 0.9

    // MARK: - Init

    init(mediaRepository: any MediaRepositoryProtocol) {
        self.mediaRepository = mediaRepository
        configureAudioSessionCategory()
        configureRemoteCommands()
        installInterruptionObserver()
        installRouteChangeObserver()
    }

    // MARK: - AudioPlayerServicing

    func play(_ item: AudioPlayableItem, queue newQueue: [AudioPlayableItem]) {
        let resolvedQueue: [AudioPlayableItem]
        if newQueue.contains(item) {
            resolvedQueue = newQueue
        } else if newQueue.isEmpty {
            resolvedQueue = [item]
        } else {
            resolvedQueue = [item] + newQueue
        }

        // Tapping the item that is already loaded just updates the queue and
        // resumes if paused, instead of restarting from the top.
        if let current = nowPlaying, current.id == item.id, player != nil {
            queue = resolvedQueue
            if !isPlaying {
                resumePlayback()
            }
            return
        }

        // Persist the outgoing item's position before switching.
        persistProgressNow()
        resumeTask?.cancel()
        resumeTask = nil
        teardownPlayer()

        nowPlaying = item
        queue = resolvedQueue
        currentTime = 0
        duration = 0

        activateAudioSession()

        let playerItem = AVPlayerItem(url: item.url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.defaultRate = Float(playbackSpeed.rawValue)
        player = newPlayer

        installTimeObserver(on: newPlayer)
        installItemEndObserver(for: playerItem)

        newPlayer.play()
        newPlayer.rate = Float(playbackSpeed.rawValue)
        isPlaying = true
        lastProgressSaveDate = Date()

        updateNowPlayingInfo()
        restoreSavedProgressIfNeeded(for: item)
    }

    func togglePlayPause() {
        guard nowPlaying != nil else { return }
        if isPlaying {
            pausePlayback()
        } else {
            resumePlayback()
        }
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        var target = seconds.isFinite ? seconds : 0
        target = max(0, target)
        if duration > 0 {
            target = min(target, duration)
        }
        currentTime = target
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlayingInfo()
    }

    func skipForward(_ seconds: Double) {
        let amount = (seconds.isFinite && seconds > 0) ? seconds : 0
        guard amount > 0 else { return }
        seek(to: currentTime + amount)
    }

    func skipBackward(_ seconds: Double) {
        let amount = (seconds.isFinite && seconds > 0) ? seconds : 0
        guard amount > 0 else { return }
        seek(to: currentTime - amount)
    }

    func playNext() {
        guard let current = nowPlaying else { return }
        guard let index = queue.firstIndex(where: { $0.id == current.id }),
              index + 1 < queue.count else {
            // End of the queue: stop rather than loop.
            stop()
            return
        }
        play(queue[index + 1], queue: queue)
    }

    func playPrevious() {
        guard let current = nowPlaying else { return }
        // A few seconds in, "previous" means "restart this one" — matches
        // system player behavior.
        if currentTime > 5 {
            seek(to: 0)
            return
        }
        guard let index = queue.firstIndex(where: { $0.id == current.id }),
              index > 0 else {
            seek(to: 0)
            return
        }
        play(queue[index - 1], queue: queue)
    }

    func stop() {
        persistProgressNow()
        resumeTask?.cancel()
        resumeTask = nil
        teardownPlayer()

        nowPlaying = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        queue = []
        wasPlayingBeforeInterruption = false

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    func snapshotProgress() -> PlaybackProgress? {
        guard let item = nowPlaying, let mediaItemID = item.mediaItemID else {
            return nil
        }
        let safePosition = (currentTime.isFinite && currentTime >= 0) ? currentTime : 0
        let safeDuration = (duration.isFinite && duration > 0) ? duration : 0
        return PlaybackProgress(
            mediaItemID: mediaItemID,
            positionSeconds: safePosition,
            durationSeconds: safeDuration,
            updatedAt: Date()
        )
    }

    // MARK: - Playback core

    private func pausePlayback() {
        player?.pause()
        isPlaying = false
        persistProgressNow()
        updateNowPlayingInfo()
    }

    private func resumePlayback() {
        guard nowPlaying != nil, let player else { return }
        activateAudioSession()
        player.play()
        player.rate = Float(playbackSpeed.rawValue)
        isPlaying = true
        lastProgressSaveDate = Date()
        updateNowPlayingInfo()
    }

    private func handlePeriodicTick(playheadSeconds: Double) {
        guard let player else { return }

        if playheadSeconds.isFinite && playheadSeconds >= 0 {
            currentTime = playheadSeconds
        }

        if let itemDuration = player.currentItem?.duration, itemDuration.isNumeric {
            let seconds = itemDuration.seconds
            if seconds.isFinite && seconds > 0 {
                duration = seconds
            }
        }

        guard isPlaying else { return }
        if Date().timeIntervalSince(lastProgressSaveDate) >= Self.progressSaveInterval {
            lastProgressSaveDate = Date()
            persistProgressNow()
            updateNowPlayingInfo()
        }
    }

    private func handleItemDidEnd() {
        if duration > 0 {
            currentTime = duration
        }
        isPlaying = false
        // Record completion so "continue listening" treats it as finished.
        persistProgressNow()
        playNext()
    }

    // MARK: - Progress persistence

    private func persistProgressNow() {
        guard let progress = snapshotProgress() else { return }
        // Skip meaningless zero-position writes so a fresh load never
        // clobbers a previously saved position.
        guard progress.positionSeconds > 0.5 else { return }
        let repository = mediaRepository
        Task {
            try? await repository.savePlaybackProgress(progress)
        }
    }

    private func restoreSavedProgressIfNeeded(for item: AudioPlayableItem) {
        guard let mediaItemID = item.mediaItemID else { return }
        let repository = mediaRepository
        resumeTask = Task { [weak self] in
            let saved = try? await repository.playbackProgress(mediaItemID: mediaItemID)
            guard !Task.isCancelled, let saved else { return }
            guard let self else { return }
            // The user may have moved on while we were loading.
            guard self.nowPlaying?.id == item.id else { return }

            if self.duration <= 0 && saved.durationSeconds > 0 {
                self.duration = saved.durationSeconds
            }
            if saved.positionSeconds > Self.minimumResumePosition
                && saved.fractionCompleted < Self.maximumResumeFraction {
                self.seek(to: saved.positionSeconds)
            }
        }
    }

    // MARK: - Player wiring

    private func installTimeObserver(on player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in
                self?.handlePeriodicTick(playheadSeconds: seconds)
            }
        }
    }

    private func installItemEndObserver(for item: AVPlayerItem) {
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleItemDidEnd()
            }
        }
    }

    private func teardownPlayer() {
        if let token = timeObserverToken, let player {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil

        if let observer = itemEndObserver {
            NotificationCenter.default.removeObserver(observer)
            itemEndObserver = nil
        }

        player?.pause()
        player = nil
    }

    // MARK: - Audio session

    private func configureAudioSessionCategory() {
        // .playback keeps audio audible with the silent switch on and enables
        // background playback (with the audio background mode entitlement).
        // .spokenAudio suits lecture content.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        } catch {
            // The system default category still allows foreground playback;
            // nothing actionable for the user here.
        }
    }

    private func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Activation can fail during a phone call; playback will simply
            // not start and the user can retry.
        }
    }

    private func installInterruptionObserver() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeRaw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt else {
                return
            }
            let optionsRaw = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                self?.handleInterruption(typeRawValue: typeRaw, optionsRawValue: optionsRaw)
            }
        }
    }

    private func handleInterruption(typeRawValue: UInt, optionsRawValue: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: typeRawValue) else {
            return
        }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying {
                pausePlayback()
            }
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRawValue)
            if options.contains(.shouldResume) && wasPlayingBeforeInterruption {
                resumePlayback()
            }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    private func installRouteChangeObserver() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let reasonRaw = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw),
                  reason == .oldDeviceUnavailable else {
                return
            }
            // Headphones unplugged: pause instead of blasting the speaker.
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.pausePlayback()
            }
        }
    }

    // MARK: - Now Playing / remote commands

    private func updateNowPlayingInfo() {
        guard let item = nowPlaying else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackSpeed.rawValue : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: playbackSpeed.rawValue,
        ]
        if let subtitle = item.subtitle, !subtitle.isEmpty {
            info[MPMediaItemPropertyArtist] = subtitle
        }
        if duration.isFinite && duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.nowPlaying != nil, !self.isPlaying else { return }
                self.resumePlayback()
            }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.pausePlayback()
            }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 30
            Task { @MainActor in
                self?.skipForward(interval)
            }
            return .success
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor in
                self?.skipBackward(interval)
            }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = positionEvent.positionTime
            Task { @MainActor in
                self?.seek(to: position)
            }
            return .success
        }

        // Skip-interval commands replace track skipping for lecture content.
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }
}
