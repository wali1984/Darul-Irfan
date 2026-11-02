import Foundation
import XCTest
@testable import DarulIrfan

final class MediaPlaybackResolutionTests: XCTestCase {
    @MainActor
    func testSavedAudioWinsAndMissingFileFallsBackToStream() throws {
        var item = try XCTUnwrap(SeedBundle.mediaItems().first { $0.mediaType == .audio })
        let manager = PlaybackResolutionDownloads()
        let remote = try XCTUnwrap(item.streamUrl)
        let asset = DownloadedAsset(id: "saved", remoteUrl: remote,
            relativeFilePath: "lecture.mp3", byteSize: 10, contentItemID: nil,
            mediaItemID: item.id, downloadedAt: .now)
        manager.savedURL = URL(fileURLWithPath: "/offline/lecture.mp3")
        let saved = MediaPlayback.playableItem(for: item, asset: asset, downloadManager: manager)
        XCTAssertEqual(saved?.url, manager.savedURL)
        XCTAssertEqual(saved?.mediaItemID, item.id)
        let stream = item.streamUrl
        item.streamUrl = nil
        XCTAssertEqual(MediaPlayback.playableItem(for: item, asset: asset, downloadManager: manager)?.url, manager.savedURL)
        manager.savedURL = nil
        XCTAssertNil(MediaPlayback.playableItem(for: item, asset: asset, downloadManager: manager))
        item.streamUrl = stream
        XCTAssertEqual(MediaPlayback.playableItem(for: item, asset: asset, downloadManager: manager)?.url,
                       stream.flatMap { URL(string: $0) })
    }

    @MainActor
    func testVideoAndUnsupportedAudioCannotBecomeNativeAudio() throws {
        var item = try XCTUnwrap(SeedBundle.mediaItems().first { $0.mediaType == .audio })
        let manager = PlaybackResolutionDownloads()
        item.streamUrl = "https://example.invalid/audio.wma"
        item.downloadUrl = nil
        XCTAssertNil(MediaPlayback.playableItem(for: item, asset: nil, downloadManager: manager))
        let video = try XCTUnwrap(SeedBundle.mediaItems().first { $0.mediaType != .audio })
        XCTAssertNil(MediaPlayback.playableItem(for: video, asset: nil, downloadManager: manager))
    }
}

@MainActor
private final class PlaybackResolutionDownloads: DownloadManaging {
    var savedURL: URL?
    var activeDownloads: [String: Double] = [:]
    func localURL(for asset: DownloadedAsset) -> URL? { savedURL }
    func totalBytesUsed() async -> Int64 { 0 }
    func download(url: URL, forContentItem contentItemID: String?, mediaItemID: String?) async throws -> DownloadedAsset {
        throw URLError(.unsupportedURL)
    }
    func cancelDownload(url: URL) {}
    func deleteAsset(_ asset: DownloadedAsset) async throws {}
}
