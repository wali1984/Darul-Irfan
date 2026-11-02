import XCTest
@testable import DarulIrfan

final class ReaderVisibleFramesTests: XCTestCase {
    func testOnlyVisibleEndAllowsAdvance() {
        let viewport = CGRect(x: 0, y: 100, width: 390, height: 600)
        XCTAssertFalse(ReaderVisibleFrames.endIsVisible(CGRect(x: 16, y: 3000, width: 358, height: 48), in: viewport))
        XCTAssertFalse(ReaderVisibleFrames.endIsVisible(CGRect(x: 16, y: 690, width: 358, height: 48), in: viewport))
        XCTAssertTrue(ReaderVisibleFrames.endIsVisible(CGRect(x: 16, y: 650, width: 358, height: 48), in: viewport))
        XCTAssertFalse(ReaderVisibleFrames.endIsVisible(.zero, in: viewport))
    }
}
