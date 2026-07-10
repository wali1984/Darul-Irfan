import Foundation
import Observation
import SwiftUI

// MARK: - Continue Listening entry

/// One "Continue Listening" entry: a media item plus its saved position.
struct MediaResumeEntry: Identifiable, Equatable {
    let item: MediaItem
    let progress: PlaybackProgress

    var id: String { item.id }
}

// MARK: - Shared playback helpers

/// Small, stateless helpers shared by the Media screens for turning catalog
/// items into playable queue entries and classifying items that cannot be
/// played natively on iOS.
enum MediaPlayback {
    /// Queue ID for the AlMurshid TV live stream (not a catalog item).
    static let liveStreamID = "live-almurshid-tv"

    /// Default AlMurshid TV live audio URL. Treated as a remote-config
    /// default carried over from the prototype; the stream may be off air.
    static let liveStreamURLString = "https://stream.darulirfan.org/almurshid-tv.mp3"

    /// Builds the playable representation of a catalog item, preferring the
    /// downloaded local file over the remote stream URL. Returns nil when the
    /// item cannot be played natively (video, YouTube-only, WMA-only, or no
    /// usable URL).
    @MainActor
    static func playableItem(
        for item: MediaItem,
        asset: DownloadedAsset?,
        downloadManager: any DownloadManaging
    ) -> AudioPlayableItem? {
        guard item.mediaType == .audio, !isWMAOnly(item) else { return nil }

        var resolvedURL: URL?
        if let asset, let localURL = downloadManager.localURL(for: asset) {
            resolvedURL = localURL
        } else if let stream = item.streamUrl, let remoteURL = URL(string: stream) {
            resolvedURL = remoteURL
        }
        guard let url = resolvedURL else { return nil }

        return AudioPlayableItem(
            id: item.id,
            title: item.title,
            subtitle: item.speaker,
            url: url,
            mediaItemID: item.id
        )
    }

    /// True when the item has at least one direct URL and every direct URL
    /// points at a `.wma` file, which iOS cannot play. Should not occur in
    /// seed data (WMA is excluded at ingest) but guarded anyway.
    static func isWMAOnly(_ item: MediaItem) -> Bool {
        let urls: [String] = [item.streamUrl, item.downloadUrl].compactMap { $0 }
        guard !urls.isEmpty else { return false }
        return urls.allSatisfy { $0.lowercased().hasSuffix(".wma") }
    }

    /// External YouTube watch URL when the item carries a YouTube ID.
    static func youtubeURL(for item: MediaItem) -> URL? {
        guard let youtubeId = item.youtubeId, !youtubeId.isEmpty else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(youtubeId)")
    }

    /// The item's source page on naqshbandiaowaisiah.org, when parseable.
    static func sourceURL(for item: MediaItem) -> URL? {
        URL(string: item.sourceUrl)
    }
}

// MARK: - Time / month formatting

enum MediaTimeFormat {
    /// "m:ss" or "h:mm:ss" for a duration/position in seconds.
    static func duration(_ seconds: Double) -> String {
        let safeSeconds = seconds.isFinite ? max(0, seconds) : 0
        let total = Int(safeSeconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Localized month name for a 1-based month number.
    static func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        let symbols: [String] = formatter.monthSymbols ?? []
        guard month >= 1, month <= symbols.count else { return String(month) }
        return symbols[month - 1]
    }
}

// MARK: - Shared title view

/// Renders a media item's title with the correct script treatment: Urdu
/// titles use the Nastaliq face inside a right-to-left environment; other
/// languages use the given system font.
struct MediaTitleText: View {
    let item: MediaItem
    var latinFont: Font = .headline
    var lineLimit: Int = 2

    var body: some View {
        if item.language == "ur" {
            Text(item.title)
                .font(DIFont.urduBody())
                .foregroundStyle(DIColor.textPrimary)
                .lineLimit(lineLimit)
                .environment(\.layoutDirection, .rightToLeft)
        } else {
            Text(item.title)
                .font(latinFont)
                .foregroundStyle(DIColor.textPrimary)
                .lineLimit(lineLimit)
        }
    }
}

// MARK: - Home view model

/// State for the Media tab home: Continue Listening, category counts, and the
/// AlMurshid TV live stream entry point.
@Observable
@MainActor
final class MediaViewModel {
    private let mediaRepository: any MediaRepositoryProtocol
    private let downloadsRepository: any DownloadsRepositoryProtocol
    private let downloadManager: any DownloadManaging
    private let audioPlayer: any AudioPlayerServicing

    private(set) var isLoading = false
    private(set) var loadErrorMessage: String?
    private(set) var resumeEntries: [MediaResumeEntry] = []
    private(set) var categoryCounts: [MediaCategory: Int] = [:]
    private(set) var totalItemCount = 0
    private(set) var assetsByMediaItemID: [String: DownloadedAsset] = [:]

    /// Shown when the live stream appears to have failed shortly after start.
    var showsStreamUnavailableAlert = false

    private var liveCheckTask: Task<Void, Never>?
    private var hasLoadedOnce = false

    init(
        mediaRepository: any MediaRepositoryProtocol,
        downloadsRepository: any DownloadsRepositoryProtocol,
        downloadManager: any DownloadManaging,
        audioPlayer: any AudioPlayerServicing
    ) {
        self.mediaRepository = mediaRepository
        self.downloadsRepository = downloadsRepository
        self.downloadManager = downloadManager
        self.audioPlayer = audioPlayer
    }

    var isEmpty: Bool {
        totalItemCount == 0 && resumeEntries.isEmpty
    }

    func load() async {
        if !hasLoadedOnce {
            isLoading = true
        }
        loadErrorMessage = nil
        do {
            let recent = try await mediaRepository.recentlyPlayed(limit: 10)
            resumeEntries = recent.map { MediaResumeEntry(item: $0.item, progress: $0.progress) }

            let allItems = try await mediaRepository.items(
                category: nil, year: nil, month: nil, limit: 10_000
            )
            totalItemCount = allItems.count
            var counts: [MediaCategory: Int] = [:]
            for item in allItems {
                counts[item.category, default: 0] += 1
            }
            categoryCounts = counts

            let assets = try await downloadsRepository.allAssets()
            var byMediaID: [String: DownloadedAsset] = [:]
            for asset in assets {
                if let mediaID = asset.mediaItemID {
                    byMediaID[mediaID] = asset
                }
            }
            assetsByMediaItemID = byMediaID
            hasLoadedOnce = true
        } catch {
            loadErrorMessage = "The media library could not be loaded right now. Please try again in a moment."
        }
        isLoading = false
    }

    /// Resumes a "Continue Listening" entry from its saved position.
    func resume(_ entry: MediaResumeEntry) {
        let asset = assetsByMediaItemID[entry.item.id]
        guard let playable = MediaPlayback.playableItem(
            for: entry.item, asset: asset, downloadManager: downloadManager
        ) else { return }
        audioPlayer.play(playable, queue: [playable])
        if entry.progress.positionSeconds > 5 {
            audioPlayer.seek(to: entry.progress.positionSeconds)
        }
    }

    /// Starts the AlMurshid TV live audio stream and schedules a best-effort
    /// check: if the player has stopped (or never started) a few seconds
    /// later, the stream is likely off air and a gentle alert is shown.
    func playLiveStream() {
        guard let url = URL(string: MediaPlayback.liveStreamURLString) else { return }
        let liveItem = AudioPlayableItem(
            id: MediaPlayback.liveStreamID,
            title: "AlMurshid TV",
            subtitle: "Live audio stream",
            url: url,
            mediaItemID: nil
        )
        audioPlayer.play(liveItem, queue: [liveItem])

        liveCheckTask?.cancel()
        liveCheckTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !Task.isCancelled else { return }
            let player = self.audioPlayer
            let stoppedEntirely = player.nowPlaying == nil
            let stalledAtStart = player.nowPlaying?.id == MediaPlayback.liveStreamID
                && !player.isPlaying
                && player.currentTime < 1
            if stoppedEntirely || stalledAtStart {
                self.showsStreamUnavailableAlert = true
            }
        }
    }

    func cancelLiveStreamCheck() {
        liveCheckTask?.cancel()
        liveCheckTask = nil
    }
}
