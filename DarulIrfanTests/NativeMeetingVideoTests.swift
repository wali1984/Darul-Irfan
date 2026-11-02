import XCTest
import UIKit
@testable import DarulIrfan

final class NativeMeetingVideoTests: XCTestCase {
    @MainActor
    func testOldScreenCleanupCannotDetachRendererAfterNavigationHandoff() {
        let renderer = UIView()
        let oldScreen = NativeMeetingVideoContainer()
        let returnedScreen = NativeMeetingVideoContainer()
        oldScreen.display(renderer)
        XCTAssertTrue(renderer.superview === oldScreen)
        returnedScreen.display(renderer)
        XCTAssertTrue(renderer.superview === returnedScreen)
        oldScreen.display(nil)
        XCTAssertTrue(renderer.superview === returnedScreen)
        returnedScreen.display(nil)
        XCTAssertNil(renderer.superview)
    }
}
