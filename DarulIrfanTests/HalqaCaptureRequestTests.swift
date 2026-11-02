import XCTest
@testable import DarulIrfan

final class HalqaCaptureRequestTests: XCTestCase {
    @MainActor
    func testMuteCancelsPendingEnableButLaterExplicitUnmuteStillWorks() {
        let gate = HalqaCaptureRequest()
        var firstEnable: ((Bool) -> Void)?
        var cleanup: ((Bool) -> Void)?
        var mute: ((Bool) -> Void)?
        var stopped = 0
        gate.request(permission: { $0(true) }, allowedNow: { true }, enable: { firstEnable = $0 },
                     disableLateCapture: { done in stopped += 1; cleanup = done }, completion: { XCTAssertFalse($0) })
        gate.stop(disable: { mute = $0 }, completion: { XCTAssertTrue($0) })
        // Do not admit a new request until the old SDK operation settles.
        gate.request(permission: { _ in XCTFail() }, allowedNow: { true }, enable: { _ in XCTFail() },
                     disableLateCapture: { _ in XCTFail() }, completion: { XCTAssertFalse($0) })
        firstEnable?(true)
        XCTAssertEqual(stopped, 1)
        XCTAssertTrue(gate.pending)
        cleanup?(true)
        XCTAssertTrue(gate.pending, "The original mute is still in flight")
        mute?(true)
        XCTAssertFalse(gate.pending)
        gate.request(permission: { $0(true) }, allowedNow: { true }, enable: { $0(true) },
                     disableLateCapture: { _ in XCTFail() }, completion: { XCTAssertTrue($0) })
        XCTAssertFalse(gate.pending)
    }

    @MainActor
    func testPermissionReturningAfterLeaveNeverEnablesCapture() {
        let gate = HalqaCaptureRequest()
        var permission: ((Bool) -> Void)?
        var enabled = false
        var result: Bool?
        gate.request(permission: { permission = $0 }, allowedNow: { true },
                     enable: { _ in enabled = true }, disableLateCapture: { _ in XCTFail() }, completion: { result = $0 })
        gate.close()
        permission?(true)
        XCTAssertFalse(enabled)
        XCTAssertEqual(result, false)
        XCTAssertFalse(gate.pending)
    }

    @MainActor
    func testLateCaptureSuccessIsDisabledAndDuplicateTapDoesNotPrompt() {
        let gate = HalqaCaptureRequest()
        var enabled: ((Bool) -> Void)?
        var stopped = 0
        var prompts = 0
        let permission: (@escaping (Bool) -> Void) -> Void = { prompts += 1; $0(true) }
        gate.request(permission: permission, allowedNow: { true }, enable: { enabled = $0 },
                     disableLateCapture: { done in stopped += 1; done(true) }, completion: { XCTAssertFalse($0) })
        gate.request(permission: permission, allowedNow: { true }, enable: { _ in XCTFail() },
                     disableLateCapture: { _ in XCTFail() }, completion: { XCTAssertFalse($0) })
        XCTAssertEqual(prompts, 1)
        gate.close()
        enabled?(true)
        XCTAssertEqual(stopped, 1)
        XCTAssertFalse(gate.pending)
    }

    @MainActor
    func testForegroundOrRoleLossDuringPermissionDialogPreventsEnable() {
        let gate = HalqaCaptureRequest()
        var allowed = true
        var permission: ((Bool) -> Void)?
        gate.request(permission: { permission = $0 }, allowedNow: { allowed },
                     enable: { _ in XCTFail() }, disableLateCapture: { _ in XCTFail() }, completion: { XCTAssertFalse($0) })
        allowed = false
        permission?(true)
        XCTAssertFalse(gate.pending)
    }
}
