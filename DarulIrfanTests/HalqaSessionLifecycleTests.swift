import XCTest
@testable import DarulIrfan

final class HalqaSessionLifecycleTests: XCTestCase {
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
    var initialized: ((Bool) -> Void)?
    var joined: ((Bool) -> Void)?
    var released: ((Bool) -> Void)?
    var joinCalls = 0
    func initialize(completion: @escaping (Bool) -> Void) { initialized = completion }
    func join(completion: @escaping (Bool) -> Void) { joinCalls += 1; joined = completion }
    func release(completion: @escaping (Bool) -> Void) { released = completion }
}
