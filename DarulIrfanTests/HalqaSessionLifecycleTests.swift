import XCTest
import RealtimeKit
@testable import DarulIrfan

final class HalqaSessionLifecycleTests: XCTestCase {
    @MainActor
    func testMembershipRemovalReleasesOnceAndCannotCompletePendingJoin() async {
        let model = HalqaSessionLifecycle()
        let transport = FakeHalqaTransport()
        model.start(sessionID: "one") { transport }
        let events = NativeMeetingMembershipEvents()
        let terminalEvents = expectation(description: "Removal and rejection delivered")
        terminalEvents.expectedFulfillmentCount = 2
        terminalEvents.assertForOverFulfill = true
        events.ended = { transport.onEnded?(); terminalEvents.fulfill() }
        events.onWaitListStatusUpdate(waitListStatus: .none)
        events.onWaitListStatusUpdate(waitListStatus: .waiting)
        events.onWaitListStatusUpdate(waitListStatus: .accepted)
        events.onRemovedFromMeeting()
        events.onWaitListStatusUpdate(waitListStatus: .rejected)
        await fulfillment(of: [terminalEvents], timeout: 2)
        XCTAssertEqual(transport.releaseCalls, 1)
        transport.initialized?(true)
        XCTAssertEqual(transport.joinCalls, 0)
        transport.released?(true)
        XCTAssertNil(model.transport)
        XCTAssertEqual(model.phase, .idle)
    }

    @MainActor
    func testReconnectKeepsSessionAndLateNetworkEventsCannotChangeReplacement() {
        let model = HalqaSessionLifecycle()
        let first = FakeHalqaTransport()
        model.start(sessionID: "one") { first }
        first.initialized?(true)
        first.joined?(true)
        let late = first.onConnectionChanged
        first.onConnectionChanged?(.reconnecting)
        XCTAssertEqual(model.connectionStatus, .reconnecting)
        XCTAssertEqual(model.phase, .joined)
        XCTAssertTrue(model.start(sessionID: "one") { XCTFail("Must reuse transport"); return first })
        XCTAssertEqual(first.joinCalls, 1)
        first.onConnectionChanged?(.connected)
        XCTAssertEqual(model.connectionStatus, .connected)
        model.leave()
        late?(.unavailable)
        XCTAssertEqual(model.connectionStatus, .connected)
        first.released?(true)
        XCTAssertNil(first.onConnectionChanged)
        model.start(sessionID: "two") { FakeHalqaTransport() }
        late?(.unavailable)
        XCTAssertEqual(model.connectionStatus, .unknown)
        XCTAssertEqual(model.sessionID, "two")
    }

    @MainActor
    func testHostEndReleasesRoomAndLateEventCannotEndReplacement() {
        let model = HalqaSessionLifecycle()
        let first = FakeHalqaTransport()
        model.start(sessionID: "one") { first }
        first.initialized?(true)
        first.joined?(true)
        let lateEnd = first.onEnded
        first.onEnded?()
        XCTAssertEqual(model.phase, .leaving)
        first.released?(true)
        XCTAssertNil(first.onEnded)
        let second = FakeHalqaTransport()
        model.start(sessionID: "two") { second }
        second.initialized?(true)
        second.joined?(true)
        lateEnd?()
        XCTAssertEqual(model.phase, .joined)
        XCTAssertEqual(model.sessionID, "two")
    }

    @MainActor
    func testReopenReusesConnectionAndOtherRoomWaitsForLeave() {
        let model = HalqaSessionLifecycle()
        let transport = FakeHalqaTransport()
        XCTAssertTrue(model.start(sessionID: "one") { transport })
        transport.initialized?(true)
        transport.joined?(true)
        XCTAssertEqual(model.phase, .joined)
        XCTAssertTrue(model.start(sessionID: "one") { XCTFail("Must reuse connection"); return transport })
        XCTAssertFalse(model.start(sessionID: "two") { XCTFail("Must leave first"); return transport })
        model.leave()
        XCTAssertFalse(model.start(sessionID: "two") { transport })
        transport.released?(true)
        XCTAssertTrue(model.start(sessionID: "two") { FakeHalqaTransport() })
    }

    @MainActor
    func testLeaveDuringInitializationRejectsLateJoin() {
        let model = HalqaSessionLifecycle()
        let transport = FakeHalqaTransport()
        model.start(sessionID: "one") { transport }
        model.leave()
        transport.initialized?(true)
        XCTAssertEqual(transport.joinCalls, 0)
        transport.released?(true)
        XCTAssertEqual(model.phase, .idle)
    }

    @MainActor
    func testFailedReleaseKeepsOwnershipUntilRetrySucceeds() {
        let model = HalqaSessionLifecycle()
        let transport = FakeHalqaTransport()
        model.start(sessionID: "one") { transport }
        transport.initialized?(true)
        model.leave()
        transport.joined?(true)
        transport.released?(false)
        XCTAssertEqual(model.phase, .failed)
        XCTAssertFalse(model.start(sessionID: "two") { transport })
        model.leave()
        transport.released?(true)
        XCTAssertNil(model.sessionID)
        XCTAssertEqual(model.phase, .idle)
    }
}

@MainActor
private final class FakeHalqaTransport: HalqaSessionTransport {
    var onEnded: (() -> Void)?
    var onConnectionChanged: ((HalqaConnectionStatus) -> Void)?
    var initialized: ((Bool) -> Void)?
    var joined: ((Bool) -> Void)?
    var released: ((Bool) -> Void)?
    var joinCalls = 0
    var releaseCalls = 0
    func initialize(completion: @escaping (Bool) -> Void) { initialized = completion }
    func join(completion: @escaping (Bool) -> Void) { joinCalls += 1; joined = completion }
    func release(completion: @escaping (Bool) -> Void) { releaseCalls += 1; released = completion }
}
