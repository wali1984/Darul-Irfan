import XCTest
@testable import DarulIrfan

final class HalqaTransportOperationGateTests: XCTestCase {
    @MainActor
    func testLeaveDuringJoinDefersReleaseAndRejectsLateSuccess() {
        let gate = HalqaTransportOperationGate()
        var releases = 0
        XCTAssertTrue(gate.begin())
        gate.close { releases += 1 }
        XCTAssertEqual(releases, 0)
        XCTAssertFalse(gate.begin())
        XCTAssertFalse(gate.finish())
        XCTAssertEqual(releases, 1)
        XCTAssertFalse(gate.begin())
    }

    @MainActor
    func testNormalInitializationThenJoinAndReleaseRetry() {
        let gate = HalqaTransportOperationGate()
        var releases = 0
        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.begin())
        XCTAssertTrue(gate.finish())
        XCTAssertTrue(gate.begin())
        XCTAssertTrue(gate.finish())
        gate.close { releases += 1 }
        gate.close { releases += 1 }
        XCTAssertEqual(releases, 2)
        XCTAssertFalse(gate.begin())
    }
}
