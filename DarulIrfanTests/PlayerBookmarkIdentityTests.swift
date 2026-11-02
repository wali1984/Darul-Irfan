import Foundation
import XCTest
@testable import DarulIrfan

final class PlayerBookmarkIdentityTests: XCTestCase {
    @MainActor
    func testQueueAdvanceWhileTypingKeepsOriginalRecordingAndPosition() async {
        let repository = BookmarkTestRepository()
        let player = BookmarkTestPlayer()
        player.nowPlaying = AudioPlayableItem(id: "first", title: "First", url: URL(fileURLWithPath: "/first.m4a"), mediaItemID: "first")
        player.currentTime = 42
        let model = PlayerSheetViewModel(audioPlayer: player, mediaRepository: repository)
        model.beginAddBookmark()
        model.noteDraft = "  Return here  "
        player.nowPlaying = AudioPlayableItem(id: "second", title: "Second", url: URL(fileURLWithPath: "/second.m4a"), mediaItemID: "second")
        player.currentTime = 7
        await model.confirmAddBookmark()
        let saved = await repository.saved
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.mediaItemID, "first")
        XCTAssertEqual(saved.first?.positionSeconds, 42)
        XCTAssertEqual(saved.first?.note, "Return here")
    }

    @MainActor
    func testUnsupportedStreamCannotStartBookmarkPrompt() {
        let model = PlayerSheetViewModel(audioPlayer: BookmarkTestPlayer(), mediaRepository: BookmarkTestRepository())
        model.beginAddBookmark()
        XCTAssertFalse(model.showsAddBookmarkPrompt)
    }
}

private actor BookmarkTestRepository: MediaRepositoryProtocol {
    func recentlyPlayed(limit: Int) async throws -> [(item: MediaItem, progress: PlaybackProgress)] { [] }
    func items(category: MediaCategory?, year: Int?, month: Int?, limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem? { nil }
    func availableYears(category: MediaCategory?) async throws -> [Int] { [] }
    func playbackProgress(mediaItemID: String) async throws -> PlaybackProgress? { nil }
    func savePlaybackProgress(_ progress: PlaybackProgress) async throws {}
    func mediaBookmarks(mediaItemID: String?) async throws -> [MediaBookmark] { [] }
    private(set) var saved: [MediaBookmark] = []
    func addMediaBookmark(_ bookmark: MediaBookmark) async throws { saved.append(bookmark) }
    func removeMediaBookmark(id: UUID) async throws {}
    func playlists() async throws -> [Playlist] { [] }
    func savePlaylist(_ playlist: Playlist) async throws {}
    func deletePlaylist(id: UUID) async throws {}
    func upsertItems(_ items: [MediaItem]) async throws {}
}

@MainActor
private final class BookmarkTestPlayer: AudioPlayerServicing {
    var nowPlaying: AudioPlayableItem?
    var isPlaying: Bool { false }
    var isBuffering: Bool { false }
    var playbackError: String? { nil }
    var currentTime: Double = 0
    var duration: Double { 0 }
    var playbackSpeed: PlaybackSpeed = .normal
    var queue: [AudioPlayableItem] { [] }
    func play(_ item: AudioPlayableItem, queue: [AudioPlayableItem]) { XCTFail("Bookmark editing must not start playback") }
    func togglePlayPause() {}
    func seek(to seconds: Double) {}
    func skipForward(_ seconds: Double) {}
    func skipBackward(_ seconds: Double) {}
    func playNext() {}
    func playPrevious() {}
    func stop() {}
    func snapshotProgress() -> PlaybackProgress? { nil }
}
