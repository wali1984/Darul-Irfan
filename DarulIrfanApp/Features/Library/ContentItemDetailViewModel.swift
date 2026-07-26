import Foundation
import Observation

/// State for one content item's detail screen: the loaded item, its
/// rights-aware body paragraphs, per-file download states, and throttled
/// reading-progress persistence.
@Observable
@MainActor
final class ContentItemDetailViewModel {
    enum DownloadRowState: Equatable {
        case notDownloaded
        case downloading
        case downloaded(asset: DownloadedAsset, localURL: URL)
        case failed
    }

    let itemID: String

    private let contentRepository: any ContentRepositoryProtocol
    private let downloadsRepository: any DownloadsRepositoryProtocol
    private let downloadManager: any DownloadManaging

    private(set) var item: ContentItem?
    private(set) var isLoading = true
    /// Plain-text paragraphs of the body; empty when native text is unavailable.
    private(set) var bodyParagraphs: [String] = []
    /// Saved scroll fraction from a previous reading session (0...1).
    private(set) var initialReadingFraction: Double = 0
    /// Download state per remote URL string.
    private(set) var downloadStates: [String: DownloadRowState] = [:]

    // Reading-progress throttling
    private var latestFraction: Double = 0
    private var lastSavedFraction: Double?
    private var lastSaveDate: Date = .distantPast

    init(
        itemID: String,
        contentRepository: any ContentRepositoryProtocol,
        downloadsRepository: any DownloadsRepositoryProtocol,
        downloadManager: any DownloadManaging
    ) {
        self.itemID = itemID
        self.contentRepository = contentRepository
        self.downloadsRepository = downloadsRepository
        self.downloadManager = downloadManager
    }

    // MARK: - Derived state

    /// Whether the native reader may show the body. Items without distribution
    /// permission remain represented by their native metadata and placeholder.
    var showsBody: Bool {
        guard let item else { return false }
        return item.rightsStatus != .linkOnly && !bodyParagraphs.isEmpty
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        do {
            item = try await contentRepository.item(id: itemID)
        } catch {
            item = nil
        }
        if let item {
            if item.rightsStatus != .linkOnly {
                let plain: String
                if let bodyPlainText = item.bodyPlainText, !bodyPlainText.isEmpty {
                    plain = bodyPlainText
                } else if let bodyHtml = item.bodyHtml, !bodyHtml.isEmpty {
                    plain = LibraryHTMLText.plainText(fromHTML: bodyHtml)
                } else {
                    plain = ""
                }
                bodyParagraphs = LibraryHTMLText.paragraphs(from: plain)
            } else {
                bodyParagraphs = []
            }
            if let progress = try? await contentRepository.readingProgress(contentItemID: item.id) {
                initialReadingFraction = min(max(progress.fraction, 0), 1)
            }
            await refreshDownloadStates()
        }
        isLoading = false
    }

    // MARK: - Downloads

    func refreshDownloadStates() async {
        guard let item else { return }
        var states: [String: DownloadRowState] = [:]
        for urlString in item.downloadUrls {
            if let asset = try? await downloadsRepository.asset(remoteUrl: urlString),
               let localURL = downloadManager.localURL(for: asset) {
                states[urlString] = .downloaded(asset: asset, localURL: localURL)
            } else if downloadManager.activeDownloads[urlString] != nil {
                states[urlString] = .downloading
            } else {
                states[urlString] = .notDownloaded
            }
        }
        downloadStates = states
    }

    func download(urlString: String) async {
        guard let item, let url = URL(string: urlString) else { return }
        downloadStates[urlString] = .downloading
        do {
            let asset = try await downloadManager.download(
                url: url,
                forContentItem: item.id,
                mediaItemID: nil
            )
            if let localURL = downloadManager.localURL(for: asset) {
                downloadStates[urlString] = .downloaded(asset: asset, localURL: localURL)
            } else {
                downloadStates[urlString] = .failed
            }
        } catch {
            // A user-cancelled download was already reset to .notDownloaded.
            if downloadStates[urlString] == .downloading {
                downloadStates[urlString] = .failed
            }
        }
    }

    func cancelDownload(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        downloadManager.cancelDownload(url: url)
        downloadStates[urlString] = .notDownloaded
    }

    func deleteDownload(urlString: String) async {
        guard case .downloaded(let asset, _)? = downloadStates[urlString] else { return }
        do {
            try await downloadManager.deleteAsset(asset)
            downloadStates[urlString] = .notDownloaded
        } catch {
            await refreshDownloadStates()
        }
    }

    /// Live progress fraction from the download manager, if it reports one.
    func progressFraction(for urlString: String) -> Double? {
        guard let fraction = downloadManager.activeDownloads[urlString] else { return nil }
        return min(max(fraction, 0), 1)
    }

    // MARK: - Reading progress (throttled)

    /// Called continuously while the reader scrolls; persists at most once
    /// every 2 seconds and only for meaningful movement.
    func scrollFractionChanged(_ fraction: Double) {
        latestFraction = min(max(fraction, 0), 1)
        guard let item, item.rightsStatus != .linkOnly, !bodyParagraphs.isEmpty else { return }
        let movedMeaningfully = abs((lastSavedFraction ?? -1) - latestFraction) >= 0.02
        guard movedMeaningfully, Date().timeIntervalSince(lastSaveDate) >= 2 else { return }
        persistProgress()
    }

    /// Final save when leaving the screen.
    func flushReadingProgress() {
        guard let item, item.rightsStatus != .linkOnly, !bodyParagraphs.isEmpty else { return }
        guard latestFraction != (lastSavedFraction ?? -1) else { return }
        persistProgress()
    }

    private func persistProgress() {
        guard let item else { return }
        lastSavedFraction = latestFraction
        lastSaveDate = Date()
        let progress = ContentReadingProgress(
            contentItemID: item.id,
            fraction: latestFraction,
            updatedAt: Date()
        )
        let repository = contentRepository
        Task {
            try? await repository.saveReadingProgress(progress)
        }
    }
}
