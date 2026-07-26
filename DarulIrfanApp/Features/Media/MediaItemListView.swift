import Foundation
import Observation
import SwiftUI

// MARK: - Filter

/// Which slice of the media catalog a list shows.
enum MediaListFilter: Equatable {
    case category(MediaCategory)
    case year(category: MediaCategory?, year: Int)
    case month(category: MediaCategory?, year: Int, month: Int)
}

// MARK: - List view model

/// Loads one filtered slice of the media catalog and exposes the row actions:
/// play (with the list as the queue), download for offline, and lookups for
/// offline/downloading state.
@Observable
@MainActor
final class MediaListViewModel {
    let filter: MediaListFilter

    private let mediaRepository: any MediaRepositoryProtocol
    private let downloadsRepository: any DownloadsRepositoryProtocol
    private let downloadManager: any DownloadManaging
    private let audioPlayer: any AudioPlayerServicing

    private(set) var items: [MediaItem] = []
    private(set) var assetsByMediaItemID: [String: DownloadedAsset] = [:]
    private(set) var isLoading = false
    private(set) var loadErrorMessage: String?

    /// Set when a download fails; bound to an alert.
    var downloadErrorMessage: String?

    private var inFlightDownloadIDs: Set<String> = []
    private var hasLoadedOnce = false

    init(
        filter: MediaListFilter,
        mediaRepository: any MediaRepositoryProtocol,
        downloadsRepository: any DownloadsRepositoryProtocol,
        downloadManager: any DownloadManaging,
        audioPlayer: any AudioPlayerServicing
    ) {
        self.filter = filter
        self.mediaRepository = mediaRepository
        self.downloadsRepository = downloadsRepository
        self.downloadManager = downloadManager
        self.audioPlayer = audioPlayer
    }

    func load() async {
        if !hasLoadedOnce {
            isLoading = true
        }
        loadErrorMessage = nil
        do {
            let fetched: [MediaItem]
            switch filter {
            case .category(let category):
                fetched = try await mediaRepository.items(
                    category: category, year: nil, month: nil, limit: 500
                )
            case .year(let category, let year):
                fetched = try await mediaRepository.items(
                    category: category, year: year, month: nil, limit: 1000
                )
            case .month(let category, let year, let month):
                fetched = try await mediaRepository.items(
                    category: category, year: year, month: month, limit: 500
                )
            }
            // Newest first; undated items last.
            items = fetched.sorted { lhs, rhs in
                switch (lhs.date, rhs.date) {
                case (nil, nil): return lhs.title < rhs.title
                case (nil, _): return false
                case (_, nil): return true
                case (let l?, let r?): return l > r
                }
            }

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
            loadErrorMessage = "These items could not be loaded right now. Please try again in a moment."
        }
        isLoading = false
    }

    // MARK: State lookups

    func isDownloaded(_ item: MediaItem) -> Bool {
        assetsByMediaItemID[item.id] != nil
    }

    func isDownloading(_ item: MediaItem) -> Bool {
        if inFlightDownloadIDs.contains(item.id) { return true }
        guard let urlString = item.downloadUrl else { return false }
        return downloadManager.activeDownloads[urlString] != nil
    }

    func downloadProgress(for item: MediaItem) -> Double? {
        guard let urlString = item.downloadUrl else { return nil }
        return downloadManager.activeDownloads[urlString]
    }

    func canPlay(_ item: MediaItem) -> Bool {
        guard item.mediaType == .audio, !MediaPlayback.isWMAOnly(item) else { return false }
        return item.streamUrl != nil || isDownloaded(item)
    }

    // MARK: Actions

    /// Plays the item, queuing every natively playable item in this list so
    /// "next"/"previous" moves through what the user is browsing. If the item
    /// is already the current one, toggles play/pause instead of restarting.
    func play(_ item: MediaItem) {
        if audioPlayer.nowPlaying?.mediaItemID == item.id {
            audioPlayer.togglePlayPause()
            return
        }
        let queue: [AudioPlayableItem] = items.compactMap { listItem in
            MediaPlayback.playableItem(
                for: listItem,
                asset: assetsByMediaItemID[listItem.id],
                downloadManager: downloadManager
            )
        }
        guard let target = queue.first(where: { $0.mediaItemID == item.id }) else { return }
        audioPlayer.play(target, queue: queue)
    }

    /// Starts an offline download when the item has a direct download URL.
    func download(_ item: MediaItem) {
        guard let urlString = item.downloadUrl, let url = URL(string: urlString) else { return }
        guard !isDownloaded(item), !inFlightDownloadIDs.contains(item.id) else { return }
        inFlightDownloadIDs.insert(item.id)
        Task { [weak self] in
            guard let self else { return }
            do {
                let asset = try await self.downloadManager.download(
                    url: url, forContentItem: nil, mediaItemID: item.id
                )
                self.assetsByMediaItemID[item.id] = asset
            } catch {
                self.downloadErrorMessage = "The download could not be completed. Please check your connection and try again."
            }
            self.inFlightDownloadIDs.remove(item.id)
        }
    }
}

// MARK: - List view

/// A filtered list of media items (category, year, or month slice).
struct MediaItemListView: View {
    private let dependencies: AppDependencies
    @State private var viewModel: MediaListViewModel

    init(filter: MediaListFilter, dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: MediaListViewModel(
            filter: filter,
            mediaRepository: dependencies.mediaRepository,
            downloadsRepository: dependencies.downloadsRepository,
            downloadManager: dependencies.downloadManager,
            audioPlayer: dependencies.audioPlayer
        ))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.loadErrorMessage {
                DIEmptyState(
                    systemImage: "wifi.exclamationmark",
                    titleKey: "Something went wrong",
                    messageKey: LocalizedStringKey(message)
                )
                .diOctagramWatermark(size: 260, opacity: 0.05)
            } else if viewModel.items.isEmpty {
                DIEmptyState(
                    systemImage: "waveform",
                    titleKey: "Nothing here yet",
                    messageKey: "Items will appear here after the next library sync. Pull down to refresh."
                )
                .diOctagramWatermark(size: 260, opacity: 0.05)
            } else {
                itemList
            }
        }
        .diScreenBackground()
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
        .alert(
            "Download Failed",
            isPresented: Binding(
                get: { viewModel.downloadErrorMessage != nil },
                set: { if !$0 { viewModel.downloadErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(viewModel.downloadErrorMessage ?? ""))
        }
    }

    private var itemList: some View {
        List {
            ForEach(viewModel.items) { item in
                MediaItemRow(
                    item: item,
                    isDownloaded: viewModel.isDownloaded(item),
                    isDownloading: viewModel.isDownloading(item),
                    downloadProgress: viewModel.downloadProgress(for: item),
                    canPlay: viewModel.canPlay(item),
                    onPlay: { viewModel.play(item) },
                    onDownload: { viewModel.download(item) }
                )
                .listRowBackground(DIColor.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var titleText: Text {
        switch viewModel.filter {
        case .category(let category):
            return Text(LocalizedStringKey(category.englishName))
        case .year(_, let year):
            return Text(verbatim: String(year))
        case .month(_, let year, let month):
            return Text(verbatim: "\(MediaTimeFormat.monthName(month)) \(String(year))")
        }
    }
}

// MARK: - Row

/// One media item row: title (Urdu-aware), date, duration, speaker line,
/// offline badge, and the play/download/share/YouTube actions.
struct MediaItemRow: View {
    let item: MediaItem
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double?
    let canPlay: Bool
    let onPlay: () -> Void
    let onDownload: () -> Void
    @State private var presentedVideo: MediaPresentedVideo?

    private var isWMAOnly: Bool { MediaPlayback.isWMAOnly(item) }
    private var youtubeVideoID: String? { item.youtubeId }

    var body: some View {
        HStack(alignment: .center, spacing: DISpacing.sm) {
            leadingAction
            VStack(alignment: .leading, spacing: DISpacing.xs) {
                MediaTitleText(item: item, latinFont: .headline, lineLimit: 2)
                metadataLine
                if let speaker = item.speaker {
                    Text(speaker)
                        .font(.caption2)
                        .foregroundStyle(DIColor.textMuted)
                        .lineLimit(1)
                }
                badgeLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailingControls
        }
        .padding(.vertical, DISpacing.xs)
        .sheet(item: $presentedVideo) { video in
            YouTubePlayerSheet(videoID: video.id, title: video.title)
        }
    }

    // MARK: Leading action

    @ViewBuilder
    private var leadingAction: some View {
        if isWMAOnly {
            mutedMedallion("exclamationmark")
        } else if canPlay {
            Button {
                DIHaptics.soft()
                onPlay()
            } label: {
                gradientMedallion("play.fill")
            }
            .buttonStyle(DIPressableStyle())
            .accessibilityLabel(Text("Play \(item.title)"))
        } else if let youtubeVideoID {
            Button {
                presentedVideo = MediaPresentedVideo(id: youtubeVideoID, title: item.title)
            } label: {
                crimsonMedallion("play.rectangle.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Play \(item.title) in Darul Irfan"))
        } else {
            mutedMedallion("waveform")
        }
    }

    /// The category-tinted gradient disc used for the primary row affordance.
    private func gradientMedallion(_ glyph: String) -> some View {
        ZStack {
            Circle().fill(MediaStyle.iconGradient(item.category))
            Image(systemName: glyph)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 40, height: 40)
        .shadow(color: MediaStyle.accent(item.category).opacity(0.3), radius: 5, y: 2)
    }

    private func crimsonMedallion(_ glyph: String) -> some View {
        ZStack {
            Circle().fill(MediaStyle.crimson)
            Image(systemName: glyph)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 40, height: 40)
        .shadow(color: DIColor.crimson.opacity(0.3), radius: 5, y: 2)
    }

    private func mutedMedallion(_ glyph: String) -> some View {
        ZStack {
            Circle().fill(DIColor.sandstone)
            Image(systemName: glyph)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DIColor.textMuted)
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }

    // MARK: Metadata

    @ViewBuilder
    private var metadataLine: some View {
        HStack(spacing: DISpacing.xs) {
            if let date = item.date {
                Text(date, format: Date.FormatStyle(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
            if let duration = item.durationSeconds, duration > 0 {
                if item.date != nil {
                    Text(verbatim: "·")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                        .accessibilityHidden(true)
                }
                Text(verbatim: MediaTimeFormat.duration(duration))
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityLabel(Text("Duration \(MediaTimeFormat.duration(duration))"))
            }
        }
    }

    @ViewBuilder
    private var badgeLine: some View {
        if isWMAOnly {
            VStack(alignment: .leading, spacing: DISpacing.xs) {
                Text("This archived audio format is not supported on iOS yet.")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack(spacing: DISpacing.xs) {
                if isDownloaded {
                    DIPillBadge(text: "Offline", color: MediaStyle.accent(item.category))
                }
                if item.mediaType == .youtube {
                    Text("Plays in Darul Irfan")
                        .font(.caption2)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
        }
    }

    // MARK: Trailing controls

    @ViewBuilder
    private var trailingControls: some View {
        if isDownloading {
            HStack(spacing: DISpacing.xs) {
                ProgressView()
                    .controlSize(.small)
                if let downloadProgress {
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(DIColor.textMuted)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Downloading"))
        } else {
            actionsMenu
        }
    }

    private var actionsMenu: some View {
        Menu {
            if canPlay {
                Button {
                    onPlay()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
            }
            if item.downloadUrl != nil, !isDownloaded, !isWMAOnly {
                Button {
                    onDownload()
                } label: {
                    Label("Download for offline", systemImage: "arrow.down.circle")
                }
            }
            if let youtubeVideoID {
                Button {
                    presentedVideo = MediaPresentedVideo(id: youtubeVideoID, title: item.title)
                } label: {
                    Label("Play video", systemImage: "play.rectangle.fill")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(DIColor.textMuted)
        }
        .accessibilityLabel(Text("More actions for \(item.title)"))
    }
}

private struct MediaPresentedVideo: Identifiable {
    let id: String
    let title: String
}
