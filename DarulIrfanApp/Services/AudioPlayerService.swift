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
    private(set) var isBuffering: Bool = false
    private(set) var playbackError: String?
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
    @ObservationIgnored private var quranAudioObserver: NSObjectProtocol?
    /// The lock screen shows the Qur'an reader's recitation, not this player.
    @ObservationIgnored private var showsRecitation = false
    @ObservationIgnored private var recitationTracked = false
    @ObservationIgnored private var resumeTask: Task<Void, Never>?
    @ObservationIgnored private var playerStateObserver: NSKeyValueObservation?
    @ObservationIgnored private var itemStateObserver: NSKeyValueObservation?
    @ObservationIgnored private var lastProgressSaveDate: Date = .distantPast
    @ObservationIgnored private var wasPlayingBeforeInterruption: Bool = false
    /// A seek asked for before the item could take one - a saved place, or
    /// Continue Listening - made once the item is ready. AVPlayerItem cancels
    /// a seek outside its seekable ranges, which stay empty until then.
    @ObservationIgnored private var pendingSeek: Double?
    /// Whether the current item has opened; a failure before that may be the
    /// file's format, after it the connection.
    @ObservationIgnored private var itemBecameReady = false
    /// The item tried again as MPEG-4 audio after failing to open as MP3.
    @ObservationIgnored private var retriedAsMPEG4ID: String?
    /// Streams that opened only as MPEG-4 audio, opened that way at once.
    @ObservationIgnored private var mpeg4URLs: Set<URL> = []
    /// Lectures the catalogue marks as MPEG-4 audio (mimeType "audio/mp4"),
    /// read once from the bundled catalogue the first time a lecture plays.
    @ObservationIgnored private var mpeg4MediaIDs: Set<String> = []
    @ObservationIgnored private var mpeg4MediaIDsRequested = false

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
        installQuranAudioObserver()
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
        if let current = nowPlaying, current.id == item.id, player != nil, playbackError == nil {
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
        playbackError = nil
        isPlaying = false
        isBuffering = false

        guard activateAudioSession() else { return }

        pendingSeek = nil
        loadCatalogueContainersIfNeeded()
        let asMPEG4 = opensAsMPEG4(item)
        // Opened as MPEG-4 from the start, a failure is not the format's.
        retriedAsMPEG4ID = asMPEG4 ? item.id : nil
        startPlayer(for: item, asMPEG4: asMPEG4)

        updateNowPlayingInfo()
        restoreSavedProgressIfNeeded(for: item)
    }

    /// Opens `item` in a new AVPlayer and starts it.
    private func startPlayer(for item: AudioPlayableItem, asMPEG4: Bool) {
        let playerItem: AVPlayerItem
        if asMPEG4 {
            let asset = AVURLAsset(url: item.url, options: [AVURLAssetOverrideMIMETypeKey: "audio/mp4"])
            playerItem = AVPlayerItem(asset: asset)
        } else {
            playerItem = AVPlayerItem(url: item.url)
        }
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.defaultRate = Float(playbackSpeed.rawValue)
        player = newPlayer
        itemBecameReady = false
        installStateObservers(on: newPlayer, item: playerItem)

        installTimeObserver(on: newPlayer)
        installItemEndObserver(for: playerItem)

        // One recording at a time: the Qur'an reader's audio stops.
        NotificationCenter.default.post(name: .bayanAudioWillStart, object: nil)
        newPlayer.play()
        newPlayer.rate = Float(playbackSpeed.rawValue)
        isBuffering = true
        lastProgressSaveDate = Date()
    }

    /// Whether `item` is known to be MPEG-4 audio: the catalogue says so, or
    /// it opened only that way before.
    private func opensAsMPEG4(_ item: AudioPlayableItem) -> Bool {
        mpeg4URLs.contains(item.url) || item.mediaItemID.map { mpeg4MediaIDs.contains($0) } == true
    }

    /// Reads which lectures are MPEG-4 audio from the bundled catalogue, off
    /// the main thread. A lecture played before the answer arrives still
    /// opens, by the retry below.
    private func loadCatalogueContainersIfNeeded() {
        guard !mpeg4MediaIDsRequested else { return }
        mpeg4MediaIDsRequested = true
        Task.detached(priority: .utility) { [weak self] in
            let ids = Set(SeedBundle.mediaItems().filter { $0.mimeType == "audio/mp4" }.map(\.id))
            await MainActor.run { self?.mpeg4MediaIDs = ids }
        }
    }

    /// Some lectures named .mp3 hold MPEG-4 audio (nine of the 2025
    /// Siraj-e-Moneera conference tour do) and are served as audio/mpeg, so
    /// AVPlayer opens them as MP3 and fails. Such a file is opened once more
    /// as what it is, at the place it was to start from.
    private func retryAsMPEG4(_ item: AudioPlayableItem) {
        retriedAsMPEG4ID = item.id
        let resumeAt = pendingSeek ?? (currentTime > 0 ? currentTime : nil)
        teardownPlayer()
        pendingSeek = resumeAt
        startPlayer(for: item, asMPEG4: true)
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        guard let item = nowPlaying else { return }
        if playbackError != nil {
            play(item, queue: queue)
        } else if isPlaying || isBuffering {
            pausePlayback()
        } else {
            resumePlayback()
        }
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        resumeTask?.cancel()
        resumeTask = nil
        var target = seconds.isFinite ? seconds : 0
        target = max(0, target)
        if duration > 0 {
            target = min(target, duration)
        }
        currentTime = target
        if player.currentItem?.status == .readyToPlay {
            pendingSeek = nil
            let time = CMTime(seconds: target, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            // Made once the item is ready: see `pendingSeek`. Resuming a
            // lecture used to start it from the beginning instead.
            pendingSeek = target
        }
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
        isBuffering = false
        playbackError = nil
        currentTime = 0
        duration = 0
        queue = []
        wasPlayingBeforeInterruption = false
        pendingSeek = nil

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
        isBuffering = false
        persistProgressNow()
        updateNowPlayingInfo()
    }

    private func resumePlayback() {
        guard nowPlaying != nil, let player else { return }
        guard activateAudioSession() else { return }
        NotificationCenter.default.post(name: .bayanAudioWillStart, object: nil)
        player.play()
        player.rate = Float(playbackSpeed.rawValue)
        isBuffering = true
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
        let identity = ObjectIdentifier(player)
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in
                guard let active = self?.player, ObjectIdentifier(active) == identity else { return }
                self?.handlePeriodicTick(playheadSeconds: seconds)
            }
        }
    }

    private func installItemEndObserver(for item: AVPlayerItem) {
        let identity = ObjectIdentifier(item)
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let active = self?.player?.currentItem, ObjectIdentifier(active) == identity else { return }
                self?.handleItemDidEnd()
            }
        }
    }

    private func teardownPlayer() {
        playerStateObserver?.invalidate()
        itemStateObserver?.invalidate()
        playerStateObserver = nil
        itemStateObserver = nil
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

    private func installStateObservers(on player: AVPlayer, item: AVPlayerItem) {
        let identity = ObjectIdentifier(player)
        playerStateObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.synchronizePlaybackState(identity: identity) }
        }
        itemStateObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.synchronizePlaybackState(identity: identity) }
        }
    }

    private func synchronizePlaybackState(identity: ObjectIdentifier) {
        guard let player, ObjectIdentifier(player) == identity else { return }
        if player.currentItem?.status == .failed {
            // A file that never opened may be MPEG-4 audio named .mp3.
            if let item = nowPlaying, !itemBecameReady, retriedAsMPEG4ID != item.id,
               item.url.pathExtension.lowercased() == "mp3" {
                retryAsMPEG4(item)
                return
            }
            isPlaying = false
            isBuffering = false
            playbackError = "Audio could not be loaded. Check your connection and tap Retry."
            persistProgressNow()
        } else {
            if player.currentItem?.status == .readyToPlay, !itemBecameReady {
                itemBecameReady = true
                if let item = nowPlaying, retriedAsMPEG4ID == item.id { mpeg4URLs.insert(item.url) }
                if let target = pendingSeek {
                    pendingSeek = nil
                    player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
            isPlaying = player.timeControlStatus == .playing
            isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        }
        updateNowPlayingInfo()
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

    private func activateAudioSession() -> Bool {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            playbackError = nil
            return true
        } catch {
            isPlaying = false
            isBuffering = false
            playbackError = "Audio is unavailable right now. Finish your call or other audio session, then tap Retry."
            return false
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
            wasPlayingBeforeInterruption = isPlaying || isBuffering
            if isPlaying || isBuffering {
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
                guard let self, self.isPlaying || self.isBuffering else { return }
                self.pausePlayback()
            }
        }
    }

    // MARK: - One recording at a time

    /// The Qur'an reader's audio (its recitation, translation, tafsir or
    /// memorising) pauses a bayan rather than playing over it. The bayan stays
    /// loaded, so the mini player can resume it, which stops the Qur'an audio.
    private func installQuranAudioObserver() {
        quranAudioObserver = NotificationCenter.default.addObserver(
            forName: .quranAudioWillStart,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isPlaying || self.isBuffering { self.pausePlayback() }
                self.followRecitation()
            }
        }
    }

    /// The recitation under way, playing or paused, if there is one.
    private var recitation: QuranListenPlayer? {
        QuranListenPlayer.shared.current != nil ? QuranListenPlayer.shared : nil
    }

    /// While the reader recites, the lock screen shows the recitation, not a
    /// paused bayan; followed until it ends, when this player's own details
    /// come back.
    private func followRecitation() {
        let listen = QuranListenPlayer.shared
        if let ayah = listen.current {
            showsRecitation = true
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPMediaItemPropertyTitle: String(localized: "Quran"),
                MPMediaItemPropertyArtist: "\(ayah.surah):\(ayah.ayah)",
                MPNowPlayingInfoPropertyPlaybackRate: listen.isPlaying ? 1.0 : 0.0,
            ]
        } else if showsRecitation {
            showsRecitation = false
            updateNowPlayingInfo()
            return
        }
        guard !recitationTracked else { return }
        recitationTracked = true
        withObservationTracking {
            _ = listen.current
            _ = listen.isPlaying
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.recitationTracked = false
                self?.followRecitation()
            }
        }
    }

    // MARK: - Now Playing / remote commands

    private func updateNowPlayingInfo() {
        // The recitation has the lock screen while it is under way.
        guard !showsRecitation else { return }
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

        // While the reader recites, play and pause from the lock screen or
        // AirPods are the recitation's: they used to resume a paused bayan
        // over it.
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if let recitation = self?.recitation {
                    recitation.resume()
                    return
                }
                guard let self, let item = self.nowPlaying, !self.isPlaying else { return }
                if self.playbackError != nil { self.play(item, queue: self.queue) }
                else { self.resumePlayback() }
            }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if let recitation = self?.recitation {
                    recitation.pause()
                    return
                }
                guard let self, self.isPlaying || self.isBuffering else { return }
                self.pausePlayback()
            }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if let recitation = self?.recitation {
                    if recitation.isPlaying { recitation.pause() } else { recitation.resume() }
                    return
                }
                self?.togglePlayPause()
            }
            return .success
        }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 30
            Task { @MainActor in
                // Not the paused bayan under a recitation.
                guard self?.recitation == nil else { return }
                self?.skipForward(interval)
            }
            return .success
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor in
                guard self?.recitation == nil else { return }
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
                guard self?.recitation == nil else { return }
                self?.seek(to: position)
            }
            return .success
        }

        // Skip-interval commands replace track skipping for lecture content.
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }
}
