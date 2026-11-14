import XCTest
import WebKit
@testable import DarulIrfan

@MainActor
final class WebRendererRecoveryTests: XCTestCase {
    func testLiveNavigationFailureStopsStatusPollingAndReportsOnce() {
        var failures = 0
        let coordinator = LiveAudioWebView.Coordinator(allowsMicrophone: false, onFailure: { failures += 1 })
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in }
        coordinator.statusTimer = timer
        coordinator.navigationFailed(URLError(.notConnectedToInternet))
        coordinator.navigationFailed(URLError(.timedOut))
        XCTAssertEqual(failures, 1)
        XCTAssertFalse(coordinator.active)
        XCTAssertFalse(timer.isValid)
        XCTAssertNil(coordinator.statusTimer)
    }

    func testLivePageCancellationAndDisposedCallbacksAreIgnored() {
        var failures = 0
        let coordinator = LiveAudioWebView.Coordinator(allowsMicrophone: false, onFailure: { failures += 1 })
        coordinator.navigationFailed(URLError(.cancelled))
        XCTAssertTrue(coordinator.active)
        coordinator.active = false
        coordinator.navigationFailed(URLError(.notConnectedToInternet))
        coordinator.webViewWebContentProcessDidTerminate(WKWebView())
        XCTAssertEqual(failures, 0)
    }

    func testVideoTerminationReportsOnceAndDisablesFurtherUpdates() {
        var failures = 0
        let coordinator = YouTubeWebView.Coordinator { failures += 1 }
        let web = WKWebView()
        coordinator.webViewWebContentProcessDidTerminate(web)
        coordinator.webViewWebContentProcessDidTerminate(web)
        XCTAssertEqual(failures, 1)
        XCTAssertFalse(coordinator.active)
    }

    func testRoomTerminationDoesNotLeaveOrRejoinAutomatically() {
        var failures = 0
        var leaves = 0
        let coordinator = MeetingWebView.Coordinator(onLeave: { leaves += 1 }, onFailure: { failures += 1 })
        let web = WKWebView()
        coordinator.webViewWebContentProcessDidTerminate(web)
        coordinator.webViewWebContentProcessDidTerminate(web)
        XCTAssertEqual(failures, 1)
        XCTAssertEqual(leaves, 0)
        XCTAssertFalse(coordinator.active)
    }

    func testDisposedPlayersIgnoreLateTermination() {
        var failures = 0
        let video = YouTubeWebView.Coordinator { failures += 1 }
        let room = MeetingWebView.Coordinator(onLeave: {}, onFailure: { failures += 1 })
        video.active = false
        room.active = false
        let web = WKWebView()
        video.webViewWebContentProcessDidTerminate(web)
        room.webViewWebContentProcessDidTerminate(web)
        XCTAssertEqual(failures, 0)
    }
}
