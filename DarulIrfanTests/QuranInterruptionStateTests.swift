import XCTest
@testable import DarulIrfan

final class QuranInterruptionStateTests: XCTestCase {
    func testOnlyInterruptedPlayingSessionResumesOnce() {
        var state = QuranInterruptionState()
        state.begin(session: 4, wasPlaying: true)
        XCTAssertTrue(state.end(session: 4, shouldResume: true))
        XCTAssertFalse(state.end(session: 4, shouldResume: true))
    }

    func testPausedPlaybackAndDeniedResumeStayPaused() {
        var state = QuranInterruptionState()
        state.begin(session: 4, wasPlaying: false)
        XCTAssertFalse(state.end(session: 4, shouldResume: true))
        state.begin(session: 4, wasPlaying: true)
        XCTAssertFalse(state.end(session: 4, shouldResume: false))
        XCTAssertFalse(state.end(session: 4, shouldResume: true))
    }

    func testNewRecordingCannotConsumeOldResumeIntent() {
        var state = QuranInterruptionState()
        state.begin(session: 4, wasPlaying: true)
        XCTAssertFalse(state.end(session: 5, shouldResume: true))
    }

    func testUserPauseStopOrDisconnectedHeadphonesCancelResume() {
        var state = QuranInterruptionState()
        state.begin(session: 4, wasPlaying: true)
        state.cancel()
        XCTAssertFalse(state.end(session: 4, shouldResume: true))
    }
}
