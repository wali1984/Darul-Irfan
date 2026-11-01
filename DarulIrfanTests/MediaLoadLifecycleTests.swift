import Foundation
import XCTest
@testable import DarulIrfan

final class MediaLoadLifecycleTests: XCTestCase {
    @MainActor
    func testCancellationClearsSpinnerWithoutErrorAndAllowsRetry() async {
        let repository = LifecycleMediaRepository(mode: .cancelled)
        let model = makeModel(repository)
        await model.load()
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.loadErrorMessage)
        XCTAssertFalse(model.hasLoadedOnce)

        await repository.setMode(.failed)
        await model.load()
        XCTAssertFalse(model.isLoading)
        XCTAssertNotNil(model.loadErrorMessage)

        await repository.setMode(.success)
        await model.load()
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.loadErrorMessage)
        XCTAssertTrue(model.hasLoadedOnce)
    }

    @MainActor
    func testOverlappingReloadDoesNotStartASecondRepositoryRead() async {
        let repository = LifecycleMediaRepository(mode: .blocked)
        let model = makeModel(repository)
        let first = Task { await model.load() }
        await repository.waitForRead()
        XCTAssertTrue(model.isLoading)
        await model.load()
        let reads = await repository.readCount
        XCTAssertEqual(reads, 1)
        await repository.releaseRead()
        await first.value
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.hasLoadedOnce)
    }

    @MainActor
    func testMediaListCancellationFailureAndRetryClearLoadingState() async {
        let repository = LifecycleMediaRepository(mode: .cancelled, exerciseItems: true)
        let model = makeListModel(repository)
        await model.load()
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.loadErrorMessage)
        await repository.setMode(.failed)
        await model.load()
        XCTAssertFalse(model.isLoading)
        XCTAssertNotNil(model.loadErrorMessage)
        await repository.setMode(.success)
        await model.load()
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.loadErrorMessage)
        XCTAssertTrue(model.items.isEmpty)
    }

    @MainActor
    func testMediaListIgnoresOverlappingReload() async {
        let repository = LifecycleMediaRepository(mode: .blocked, exerciseItems: true)
        let model = makeListModel(repository)
        let first = Task { await model.load() }
        await repository.waitForRead()
        XCTAssertTrue(model.isLoading)
        await model.load()
        let reads = await repository.readCount
        XCTAssertEqual(reads, 1)
        await repository.releaseRead()
        await first.value
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testArchiveCancellationRetryAndFailedRefreshPreserveYears() async {
        let repository = LifecycleMediaRepository(mode: .cancelled, exerciseYears: true)
        let model = ArchiveBrowserViewModel(category: nil, mediaRepository: repository)
        await model.load()
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.loadErrorMessage)
        await repository.setMode(.success)
        await model.load()
        XCTAssertEqual(model.years, [2026])
        await repository.setMode(.failed)
        await model.load()
        XCTAssertEqual(model.years, [2026])
        XCTAssertNotNil(model.loadErrorMessage)
        XCTAssertFalse(model.isLoading)
        await repository.setMode(.success)
        await model.load()
        XCTAssertNil(model.loadErrorMessage)
    }

    @MainActor
    func testArchiveYearCancellationFailureAndRetry() async {
        let repository = LifecycleMediaRepository(mode: .cancelled, exerciseItems: true)
        let model = ArchiveYearViewModel(category: nil, year: 2026, mediaRepository: repository)
        await model.load()
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.loadErrorMessage)
        await repository.setMode(.failed)
        await model.load()
        XCTAssertNotNil(model.loadErrorMessage)
        await repository.setMode(.success)
        await model.load()
        XCTAssertNil(model.loadErrorMessage)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.totalCount, 0)
    }

    @MainActor
    func testArchiveModelsIgnoreOverlappingLoads() async {
        let yearsRepository = LifecycleMediaRepository(mode: .blocked, exerciseYears: true)
        let years = ArchiveBrowserViewModel(category: nil, mediaRepository: yearsRepository)
        let first = Task { await years.load() }
        await yearsRepository.waitForRead()
        await years.load()
        let yearReads = await yearsRepository.readCount
        XCTAssertEqual(yearReads, 1)
        await yearsRepository.releaseRead()
        await first.value
        XCTAssertFalse(years.isLoading)
        let monthRepository = LifecycleMediaRepository(mode: .blocked, exerciseItems: true)
        let months = ArchiveYearViewModel(category: nil, year: 2026, mediaRepository: monthRepository)
        let second = Task { await months.load() }
        await monthRepository.waitForRead()
        await months.load()
        let monthReads = await monthRepository.readCount
        XCTAssertEqual(monthReads, 1)
        await monthRepository.releaseRead()
        await second.value
        XCTAssertFalse(months.isLoading)
    }

    @MainActor
    private func makeListModel(_ repository: LifecycleMediaRepository) -> MediaListViewModel {
        MediaListViewModel(filter: .category(.audioLectures), mediaRepository: repository,
                           downloadsRepository: LifecycleDownloads(), downloadManager: LifecycleDownloadManager(),
                           audioPlayer: LifecycleAudioPlayer())
    }

    @MainActor
    private func makeModel(_ repository: LifecycleMediaRepository) -> MediaViewModel {
        MediaViewModel(mediaRepository: repository, downloadsRepository: LifecycleDownloads(),
                       downloadManager: LifecycleDownloadManager(), audioPlayer: LifecycleAudioPlayer())
    }
}

private actor LifecycleMediaRepository: MediaRepositoryProtocol {
    enum Mode { case cancelled, failed, blocked, success }
    private var mode: Mode
    private(set) var readCount = 0
    private var readGate: CheckedContinuation<Void, Never>?
    private var startedGate: CheckedContinuation<Void, Never>?
    private let exerciseItems: Bool
    private let exerciseYears: Bool
    init(mode: Mode, exerciseItems: Bool = false, exerciseYears: Bool = false) {
        self.mode = mode; self.exerciseItems = exerciseItems; self.exerciseYears = exerciseYears
    }
    func setMode(_ value: Mode) { mode = value }
    func waitForRead() async {
        if readCount > 0 { return }
        await withCheckedContinuation { startedGate = $0 }
    }
    func releaseRead() { readGate?.resume(); readGate = nil }
    func recentlyPlayed(limit: Int) async throws -> [(item: MediaItem, progress: PlaybackProgress)] {
        readCount += 1
        startedGate?.resume()
        startedGate = nil
        switch mode {
        case .cancelled: throw CancellationError()
        case .failed: throw CocoaError(.fileReadCorruptFile)
        case .blocked:
            if readCount == 1 { await withCheckedContinuation { readGate = $0 } }
        case .success: break
        }
        return []
    }
    func items(category: MediaCategory?, year: Int?, month: Int?, limit: Int) async throws -> [MediaItem] {
        if exerciseItems { _ = try await recentlyPlayed(limit: limit) }
        return []
    }
    func item(id: String) async throws -> MediaItem? { nil }
    func availableYears(category: MediaCategory?) async throws -> [Int] {
        if exerciseYears { _ = try await recentlyPlayed(limit: 1); return [2026] }
        return []
    }
    func playbackProgress(mediaItemID: String) async throws -> PlaybackProgress? { nil }
    func savePlaybackProgress(_ progress: PlaybackProgress) async throws {}
    func mediaBookmarks(mediaItemID: String?) async throws -> [MediaBookmark] { [] }
    func addMediaBookmark(_ bookmark: MediaBookmark) async throws {}
    func removeMediaBookmark(id: UUID) async throws {}
    func playlists() async throws -> [Playlist] { [] }
    func savePlaylist(_ playlist: Playlist) async throws {}
    func deletePlaylist(id: UUID) async throws {}
    func upsertItems(_ items: [MediaItem]) async throws {}
}

private struct LifecycleDownloads: DownloadsRepositoryProtocol {
    func allAssets() async throws -> [DownloadedAsset] { [] }
    func asset(remoteUrl: String) async throws -> DownloadedAsset? { nil }
    func saveAsset(_ asset: DownloadedAsset) async throws {}
    func deleteAsset(id: String) async throws {}
}

@MainActor
private final class LifecycleDownloadManager: DownloadManaging {
    var activeDownloads: [String: Double] { [:] }
    func download(url: URL, forContentItem contentItemID: String?, mediaItemID: String?) async throws -> DownloadedAsset {
        XCTFail("Loading the catalogue must not start downloads")
        throw CocoaError(.featureUnsupported)
    }
    func cancelDownload(url: URL) {}
    func deleteAsset(_ asset: DownloadedAsset) async throws {}
    func localURL(for asset: DownloadedAsset) -> URL? { nil }
    func totalBytesUsed() async -> Int64 { 0 }
}

@MainActor
private final class LifecycleAudioPlayer: AudioPlayerServicing {
    var nowPlaying: AudioPlayableItem? { nil }
    var isPlaying: Bool { false }
    var isBuffering: Bool { false }
    var playbackError: String? { nil }
    var currentTime: Double { 0 }
    var duration: Double { 0 }
    var playbackSpeed: PlaybackSpeed = .normal
    var queue: [AudioPlayableItem] { [] }
    func play(_ item: AudioPlayableItem, queue: [AudioPlayableItem]) { XCTFail("Loading the catalogue must not play media") }
    func togglePlayPause() {}
    func seek(to seconds: Double) {}
    func skipForward(_ seconds: Double) {}
    func skipBackward(_ seconds: Double) {}
    func playNext() {}
    func playPrevious() {}
    func stop() {}
    func snapshotProgress() -> PlaybackProgress? { nil }
}
