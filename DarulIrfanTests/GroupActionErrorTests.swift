import Foundation
import XCTest
@testable import DarulIrfan

final class GroupActionErrorTests: XCTestCase {
    func testMutationFailuresDoNotDescribeLoading() {
        let expected = String(localized: "The action could not be completed. Check your connection and try again.")
        XCTAssertEqual(MemberGroupError.actionDescription(for: MemberGroupError.requestFailed), expected)
        XCTAssertEqual(MemberGroupError.actionDescription(for: URLError(.notConnectedToInternet)), expected)
    }

    func testActionableServiceGuidanceIsPreserved() {
        for error in [MemberGroupError.notSignedIn, .tooManyAttempts, .server("Only admins can delete this session.")] {
            XCTAssertEqual(MemberGroupError.actionDescription(for: error), error.localizedDescription)
        }
    }
}
