import XCTest
@testable import DarulIrfan

final class GroupRoomPassTests: XCTestCase {
    func testOlderServerPassStillDecodesWithoutNativeIdentity() throws {
        let data = Data(#"{"authToken":"token","pageURL":"https://example.invalid/v1/meet"}"#.utf8)
        let pass = try JSONDecoder().decode(GroupRoomPass.self, from: data)
        XCTAssertNil(pass.roomID)
    }

    func testRoomIdentitySurvivesTokenRotation() throws {
        func decode(_ token: String) throws -> GroupRoomPass {
            let data = try JSONSerialization.data(withJSONObject: [
                "authToken": token, "pageURL": "https://example.invalid/v1/meet", "roomID": "room-1",
            ])
            return try JSONDecoder().decode(GroupRoomPass.self, from: data)
        }
        let first = try decode("first-token")
        let returning = try decode("new-token")
        XCTAssertNotEqual(first.authToken, returning.authToken)
        XCTAssertEqual(first.roomID, returning.roomID)
        XCTAssertEqual(first.roomID, "room-1")
    }
}
