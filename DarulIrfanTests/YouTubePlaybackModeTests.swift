import XCTest
@testable import DarulIrfan

final class YouTubePlaybackModeTests: XCTestCase {
    @MainActor
    func testModeChangesReloadButGroupUpdatesPreservePlayback() {
        let playing = YouTubeSync(position: 120, paused: false, at: .distantPast)
        let paused = YouTubeSync(position: 125, paused: true, at: .distantPast)
        XCTAssertTrue(YouTubePlayerView.needsReload(loadedID: nil, previousSync: nil, videoID: "video", sync: nil))
        XCTAssertTrue(YouTubePlayerView.needsReload(loadedID: "video", previousSync: nil, videoID: "video", sync: playing))
        XCTAssertTrue(YouTubePlayerView.needsReload(loadedID: "video", previousSync: playing, videoID: "video", sync: nil))
        XCTAssertTrue(YouTubePlayerView.needsReload(loadedID: "video", previousSync: playing, videoID: "other", sync: playing))
        XCTAssertFalse(YouTubePlayerView.needsReload(loadedID: "video", previousSync: nil, videoID: "video", sync: nil))
        XCTAssertFalse(YouTubePlayerView.needsReload(loadedID: "video", previousSync: playing, videoID: "video", sync: paused))
        XCTAssertFalse(YouTubePlayerView.needsReload(loadedID: "video", previousSync: paused, videoID: "video", sync: playing))
    }
}
