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
    /// Stable ID used by the official owned-stream player and its Lock Screen
    /// / mini-player live treatment. No URL is bundled with this identifier.
    static let liveStreamID = "official-live"

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

/// Renders a media item's title with the correct script treatment: a title
/// written in Arabic script uses the Nastaliq face inside a right-to-left
/// environment; any other uses the given system font. Judged by the title's
/// own letters, not the item's language: the bayans are all in Urdu, but
/// some 330 carry English titles ("Al-Murshid TV Program (Episode - 212)"),
/// which were set in Nastaliq, right to left.
struct MediaTitleText: View {
    let item: MediaItem
    var latinFont: Font = .headline
    var lineLimit: Int = 2
    /// The text colour: white on an emerald hero card.
    var color: Color = DIColor.textPrimary

    private var isArabicScript: Bool {
        item.title.unicodeScalars.contains { scalar in
            (0x0600...0x06FF).contains(scalar.value) || (0x0750...0x077F).contains(scalar.value)
                || (0xFB50...0xFDFF).contains(scalar.value) || (0xFE70...0xFEFF).contains(scalar.value)
        }
    }

    var body: some View {
        if isArabicScript {
            Text(item.title)
                .font(DIFont.urduBody())
                .foregroundStyle(color)
                .lineLimit(lineLimit)
                .environment(\.layoutDirection, .rightToLeft)
        } else {
            Text(item.title)
                .font(latinFont)
                .foregroundStyle(color)
                .lineLimit(lineLimit)
        }
    }
}

// MARK: - Home view model

/// State for the Media tab home: Continue Listening, category counts, and the
/// catalog browsing and playback progress.
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

    /// The catalogue has been read once.
    private(set) var hasLoadedOnce = false

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

    /// Reads the catalogue the first time. Afterwards only Continue
    /// Listening is read again, which changes as bayans are played.
    func loadIfNeeded() async {
        guard hasLoadedOnce else {
            await load()
            return
        }
        if let recent = try? await mediaRepository.recentlyPlayed(limit: 10) {
            resumeEntries = recent.map { MediaResumeEntry(item: $0.item, progress: $0.progress) }
        }
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
            // As each list shows them: an audio lecture with its video counts
            // under Video Lectures too.
            var counts: [MediaCategory: Int] = [:]
            for category in MediaCategory.allCases {
                counts[category] = allItems.filter { category.contains($0) }.count
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

}
