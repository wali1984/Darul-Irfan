import XCTest
@testable import DarulIrfan

final class MeetingOriginTests: XCTestCase {
    private let trusted = URL(string: "https://rooms.example.test")!

    func testTrustedPathsAndDefaultPort() {
        for value in ["https://rooms.example.test", "https://rooms.example.test/v1/meet#token=fixture", "https://ROOMS.example.test:443/room"] {
            XCTAssertTrue(MeetingOrigin.allows(URL(string: value), trusted: trusted), value)
        }
    }

    func testForeignOrAmbiguousOriginsCannotReceivePermission() {
        XCTAssertFalse(MeetingOrigin.allows(nil, trusted: trusted))
        for value in ["", "http://rooms.example.test", "https://rooms.example.test:444",
                      "https://evil.example.test", "https://rooms.example.test.evil.test",
                      "https://user@rooms.example.test", "https://rooms.example.test@evil.test",
                      "javascript:alert(1)", "file:///v1/meet", "//rooms.example.test"] {
            XCTAssertFalse(MeetingOrigin.allows(URL(string: value), trusted: trusted), value)
        }
    }

    func testWebKitOriginPortAndSecureScheme() {
        XCTAssertTrue(MeetingOrigin.allows(scheme: "https", host: "rooms.example.test", port: 0, trusted: trusted))
        XCTAssertTrue(MeetingOrigin.allows(scheme: "https", host: "rooms.example.test", port: 443, trusted: trusted))
        XCTAssertFalse(MeetingOrigin.allows(scheme: "http", host: "rooms.example.test", port: 443, trusted: trusted))
        XCTAssertFalse(MeetingOrigin.allows(scheme: "https", host: "rooms.example.test", port: 8443, trusted: trusted))
        let custom = URL(string: "https://rooms.example.test:8443")!
        XCTAssertTrue(MeetingOrigin.allows(URL(string: "https://rooms.example.test:8443/room"), trusted: custom))
        XCTAssertFalse(MeetingOrigin.allows(trusted, trusted: custom))
    }
}
