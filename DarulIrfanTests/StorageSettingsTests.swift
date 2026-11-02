import Foundation
import XCTest
@testable import DarulIrfan

@MainActor
final class StorageSettingsTests: XCTestCase {
    private func asset(_ id: String) -> DownloadedAsset {
        DownloadedAsset(id: id, remoteUrl: "https://example.invalid/\(id)",
                        relativeFilePath: UUID().uuidString + ".mp3", byteSize: 10,
                        contentItemID: nil, mediaItemID: nil, downloadedAt: Date())
    }

    func testFailedClearRemainsVisibleAfterSuccessfulRefreshAndRetry() async {
        let repository = StorageTestRepository([asset("one")])
        let manager = StorageTestManager(repository)
        let model = StorageSettingsViewModel(downloadManager: manager, downloadsRepository: repository)
        await model.load()
        await repository.failNextRead()
        await model.clearAllDownloads()
        XCTAssertEqual(model.failedDeletions, 1)
        XCTAssertFalse(model.loadFailed, "Refresh succeeds but must not erase the clear failure")
        XCTAssertEqual(model.assetCount, 1)
        await model.clearAllDownloads()
        XCTAssertEqual(model.failedDeletions, 0)
        XCTAssertEqual(model.assetCount, 0)
    }

    func testPerFileFailureRetainsAssetAndOtherFilesContinue() async {
        let repository = StorageTestRepository([asset("keep"), asset("remove")])
        let manager = StorageTestManager(repository)
        manager.failureID = "keep"
        let model = StorageSettingsViewModel(downloadManager: manager, downloadsRepository: repository)
        await model.clearAllDownloads()
        XCTAssertEqual(model.failedDeletions, 1)
        let remaining = try? await repository.allAssets()
        XCTAssertEqual(remaining?.map(\.id), ["keep"])
        manager.failureID = nil
        await model.clearAllDownloads()
        XCTAssertEqual(model.assetCount, 0)
    }

    func testStorageReadBlocksDuplicateRefreshAndClearUntilItFinishes() async throws {
        let repository = StorageTestRepository([asset("keep")])
        let manager = StorageTestManager(repository)
        let entered = expectation(description: "Storage read suspended")
        var resumeRead: CheckedContinuation<Void, Never>?
        manager.beforeRead = {
            await withCheckedContinuation { continuation in
                resumeRead = continuation
                entered.fulfill()
            }
        }
        let model = StorageSettingsViewModel(downloadManager: manager, downloadsRepository: repository)
        let pending = Task { await model.load() }
        await fulfillment(of: [entered], timeout: 5)
        XCTAssertTrue(model.isLoading)
        await model.load()
        await model.clearAllDownloads()
        XCTAssertEqual(manager.readCalls, 1)
        let retained = try await repository.allAssets()
        XCTAssertEqual(retained.count, 1, "Clear must not race an outstanding summary read")
        resumeRead?.resume()
        await pending.value
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertEqual(model.assetCount, 1)
        manager.beforeRead = nil
        await model.clearAllDownloads()
        XCTAssertFalse(model.isClearing)
        XCTAssertEqual(model.assetCount, 0)
    }

    func testReadFailureCanBeRetried() async {
        let repository = StorageTestRepository([asset("one")])
        await repository.failNextRead()
        let model = StorageSettingsViewModel(downloadManager: StorageTestManager(repository), downloadsRepository: repository)
        await model.load()
        XCTAssertTrue(model.loadFailed)
        await model.load()
        XCTAssertFalse(model.loadFailed)
        XCTAssertEqual(model.assetCount, 1)
    }

    func testManagerPreservesRecordWhenFileRemovalThrows() async throws {
        let item = asset("keep")
        let repository = StorageTestRepository([item])
        let manager = DownloadManager(downloadsRepository: repository, removeFile: { _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        do { try await manager.deleteAsset(item); XCTFail("Deletion must propagate the failure") }
        catch { }
        let remaining = try await repository.allAssets()
        XCTAssertEqual(remaining, [item])
        let missingManager = DownloadManager(downloadsRepository: repository, removeFile: { _ in
            throw CocoaError(.fileNoSuchFile)
        })
        try await missingManager.deleteAsset(item)
        let after = try await repository.allAssets()
        XCTAssertTrue(after.isEmpty, "Missing files should permit stale-record cleanup")
    }

    func testCanceledDownloadFinishingAfterRetryDoesNotClearReplacement() async throws {
        let firstStarted = expectation(description: "First transfer started")
        let retryStarted = expectation(description: "Replacement transfer started")
        let transport = DelayedCancellationDownloadFetcher(started: [firstStarted, retryStarted])
        let manager = DownloadManager(downloadsRepository: StorageTestRepository([]), fetcher: transport)
        let url = try XCTUnwrap(URL(string: "https://example.invalid/cancel-retry.mp3"))
        let first = Task { try await manager.download(url: url, forContentItem: nil, mediaItemID: nil) }
        await fulfillment(of: [firstStarted], timeout: 5)
        manager.cancelDownload(url: url)
        XCTAssertNil(manager.activeDownloads[url.absoluteString])
        let retry = Task { try await manager.download(url: url, forContentItem: nil, mediaItemID: nil) }
        await fulfillment(of: [retryStarted], timeout: 5)
        XCTAssertEqual(manager.activeDownloads[url.absoluteString], 0)

        // Deliberately finish the canceled network request after the retry started.
        await transport.failAttempt(0)
        if case .success = await first.result { XCTFail("Canceled transfer must fail") }
        XCTAssertEqual(manager.activeDownloads[url.absoluteString], 0,
                       "Late cleanup from the canceled attempt must not hide the replacement")

        manager.cancelDownload(url: url)
        XCTAssertNil(manager.activeDownloads[url.absoluteString])
        await transport.failAttempt(1)
        if case .success = await retry.result { XCTFail("Canceled retry must fail") }
        let attempts = await transport.attemptCount
        XCTAssertEqual(attempts, 2)
    }

    func testInvalidStoredPathsCannotResolveOutsideDownloads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("downloads", isDirectory: true)
        for directoryHint in [true, false] {
            let root = URL(fileURLWithPath: directory.path, isDirectory: directoryHint)
            XCTAssertEqual(try DownloadFileAccess.resolve(directory: root, name: "valid.mp3").lastPathComponent, "valid.mp3")
        }
        for name in ["../personal.json", "/tmp/personal.json", "nested/file", "nested\\file", ".", "..", ""] {
            XCTAssertThrowsError(try DownloadFileAccess.resolve(directory: directory, name: name), name)
        }
    }
}

private actor StorageTestRepository: DownloadsRepositoryProtocol {
    private var assets: [DownloadedAsset]
    private var failRead = false
    init(_ assets: [DownloadedAsset]) { self.assets = assets }
    func failNextRead() { failRead = true }
    func allAssets() throws -> [DownloadedAsset] {
        if failRead { failRead = false; throw CocoaError(.fileReadNoPermission) }
        return assets
    }
    func asset(remoteUrl: String) -> DownloadedAsset? { assets.first { $0.remoteUrl == remoteUrl } }
    func saveAsset(_ asset: DownloadedAsset) { assets.append(asset) }
    func deleteAsset(id: String) { assets.removeAll { $0.id == id } }
}

@MainActor
private final class StorageTestManager: DownloadManaging {
    let repository: StorageTestRepository
    var failureID: String?
    var beforeRead: (() async -> Void)?
    var readCalls = 0
    var activeDownloads: [String: Double] = [:]
    init(_ repository: StorageTestRepository) { self.repository = repository }
    func download(url: URL, forContentItem contentItemID: String?, mediaItemID: String?) async throws -> DownloadedAsset { throw URLError(.unsupportedURL) }
    func cancelDownload(url: URL) {}
    func localURL(for asset: DownloadedAsset) -> URL? { nil }
    func totalBytesUsed() async -> Int64 {
        readCalls += 1
        await beforeRead?()
        return 10
    }
    func deleteAsset(_ asset: DownloadedAsset) async throws {
        if asset.id == failureID { throw CocoaError(.fileWriteNoPermission) }
        await repository.deleteAsset(id: asset.id)
    }
}

/// Holds cancellation completion until the test explicitly releases each attempt.
private actor DelayedCancellationDownloadFetcher: DownloadFetching {
    let started: [XCTestExpectation]
    private var pending: [Int: CheckedContinuation<(URL, URLResponse), Error>] = [:]
    private(set) var attemptCount = 0
    init(started: [XCTestExpectation]) { self.started = started }
    func fetch(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> (URL, URLResponse) {
        let attempt = attemptCount
        attemptCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[attempt] = continuation
            if attempt < started.count { started[attempt].fulfill() }
        }
    }
    func failAttempt(_ attempt: Int) {
        pending.removeValue(forKey: attempt)?.resume(throwing: URLError(.cancelled))
    }
}
