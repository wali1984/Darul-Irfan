import XCTest
@testable import DarulIrfan

final class HalqaCaptureRequestTests: XCTestCase {
    @MainActor
    func testPermissionReturningAfterLeaveNeverEnablesCapture() {
        let gate = HalqaCaptureRequest()
        var permission: ((Bool) -> Void)?
        var enabled = false
        var result: Bool?
        gate.request(permission: { permission = $0 }, allowedNow: { true },
                     enable: { _ in enabled = true }, disableLateCapture: {}, completion: { result = $0 })
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
                     disableLateCapture: { stopped += 1 }, completion: { XCTAssertFalse($0) })
        gate.request(permission: permission, allowedNow: { true }, enable: { _ in XCTFail() },
                     disableLateCapture: {}, completion: { XCTAssertFalse($0) })
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
                     enable: { _ in XCTFail() }, disableLateCapture: {}, completion: { XCTAssertFalse($0) })
        allowed = false
        permission?(true)
        XCTAssertFalse(gate.pending)
    }
}
