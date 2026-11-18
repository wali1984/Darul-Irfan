import XCTest
@testable import DarulIrfan

/// Owner 2026-11-18 (Halqah tester feedback): the stage opened over the page
/// and the session's video never played; the phone slept and the member fell
/// out of the session.
@MainActor
final class HalqahSessionAwakeTests: XCTestCase {
    private var switched: [Bool] = []
    private var system = false

    override func setUp() {
        super.setUp()
        ScreenAwake.reset()
        switched = []
        system = false
        ScreenAwake.setIdleTimerDisabled = { [unowned self] in self.system = $0; self.switched.append($0) }
        ScreenAwake.idleTimerDisabled = { [unowned self] in self.system }
    }

    override func tearDown() {
        ScreenAwake.reset()
        ScreenAwake.setIdleTimerDisabled = { UIApplication.shared.isIdleTimerDisabled = $0 }
        ScreenAwake.idleTimerDisabled = { UIApplication.shared.isIdleTimerDisabled }
        super.tearDown()
    }

    func testClosingTheStageKeepsThePhoneOnWhileTheSessionIsLive() {
        ScreenAwake.hold("halqah-page:g")
        ScreenAwake.hold("halqah-stage:g")
        ScreenAwake.release("halqah-stage:g")
        XCTAssertTrue(system, "the page still holds it while the session is live")
        ScreenAwake.set("halqah-page:g", awake: false)
        XCTAssertFalse(system)
        XCTAssertFalse(ScreenAwake.isHeld)
    }

    func testHoldersInAnyOrderGiveBackWhatTheAppHad() {
        system = true
        ScreenAwake.hold("zikr-voice")
        ScreenAwake.hold("live-audio")
        ScreenAwake.release("zikr-voice")
        ScreenAwake.release("live-audio")
        XCTAssertTrue(system, "the app's own setting comes back")
        // A release nobody held changes nothing.
        switched = []
        ScreenAwake.release("live-audio")
        XCTAssertEqual(switched, [])
    }

    private func live(videoID: String? = nil, recorded: Bool = false, finished: Bool = false) -> GroupLive {
        GroupLive(kind: "zikr", title: "Zikr", videoID: videoID, hasRoom: false, startedAt: Date(), sessionID: "s",
                  recorded: recorded,
                  queue: recorded ? [GroupQueueItem(kind: "video", id: "q1", title: "Zikr", durationSeconds: 1800, url: nil, contentType: nil, videoID: "yuQSH_D2iMo")] : nil,
                  playback: recorded ? GroupPlayback(index: 0, positionSeconds: 10, paused: false, finished: finished, at: Date()) : nil)
    }

    func testTheStageShowsTheSessionsVideoOrRecording() {
        XCTAssertTrue(GroupSessionMedia.shows(live(recorded: true), groupID: "north-america"))
        XCTAssertTrue(GroupSessionMedia.shows(live(videoID: "abc"), groupID: "north-america"))
        XCTAssertFalse(GroupSessionMedia.shows(live(recorded: true, finished: true), groupID: "north-america"))
        XCTAssertFalse(GroupSessionMedia.shows(live(), groupID: "north-america"), "a led Zikr keeps the picture")
        XCTAssertFalse(GroupSessionMedia.shows(nil, groupID: "north-america"))
        XCTAssertFalse(GroupSessionMedia.shows(live(videoID: "abc"), groupID: "our-sheikh"), "Our Sheikh's stage has its live sound")
    }
}
