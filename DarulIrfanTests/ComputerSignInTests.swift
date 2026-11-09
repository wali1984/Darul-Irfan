import XCTest
@testable import DarulIrfan

/// "Approve a computer" (the desktop app's sign-in): the code however it is
/// typed or scanned, the QR's link, and the server's answers
/// (Server/src/computerLinks.ts).
final class ComputerSignInTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.darulIrfanServer().decode(type, from: Data(json.utf8))
    }

    func testCodeIsReadHoweverItIsTyped() {
        XCTAssertEqual(ComputerLinkCode.shown("k7q29mxd"), "K7Q2-9MXD")
        XCTAssertEqual(ComputerLinkCode.shown("k7q2 9mxd"), "K7Q2-9MXD")
        XCTAssertEqual(ComputerLinkCode.shown("K7Q2-9MXD-EXTRA"), "K7Q2-9MXD")
        XCTAssertEqual(ComputerLinkCode.shown("k7q"), "K7Q")
        XCTAssertEqual(ComputerLinkCode.letters(of: " k7-q2 9m-xd "), "K7Q29MXD")
        // Only Latin letters and digits: an Urdu keyboard's characters are dropped.
        XCTAssertEqual(ComputerLinkCode.letters(of: "K7Q2۹MXD"), "K7Q2MXD")
    }

    func testCodeIsFoundInWhatWasScannedOrPasted() {
        XCTAssertEqual(ComputerLinkCode.code(in: "darulirfan://approve-computer?code=K7Q2-9MXD"), "K7Q2-9MXD")
        XCTAssertEqual(ComputerLinkCode.code(in: "darulirfan://approve-computer?v=1&code=k7q29mxd"), "K7Q2-9MXD")
        XCTAssertEqual(ComputerLinkCode.code(in: "darulirfan://approve-computer?code=K7Q2%2D9MXD"), "K7Q2-9MXD")
        XCTAssertEqual(ComputerLinkCode.code(in: " k7q2-9mxd\n"), "K7Q2-9MXD")
        XCTAssertNil(ComputerLinkCode.code(in: "darulirfan://approve-computer?code=K7Q2"))
        XCTAssertNil(ComputerLinkCode.code(in: "darulirfan://approve-computer?other=K7Q29MXD"))
        // A malformed query must not trap.
        XCTAssertNil(ComputerLinkCode.code(in: "darulirfan://approve-computer?code=%%%&="))
        XCTAssertNil(ComputerLinkCode.code(in: "this is a sentence, not a code at all"))
    }

    func testTheQRLinkOpensApproveAComputer() {
        XCTAssertEqual(AppRoute(path: "darulirfan://approve-computer?code=k7q2-9mxd"), .approveComputer(code: "K7Q2-9MXD"))
        XCTAssertEqual(AppRoute(path: "approve-computer"), .approveComputer(code: nil))
        XCTAssertEqual(AppRoute(path: "darulirfan://approve-computer?code=nope"), .approveComputer(code: nil))
        XCTAssertEqual(AppRoute(url: URL(string: "darulirfan://approve-computer?code=K7Q2-9MXD")!), .approveComputer(code: "K7Q2-9MXD"))
        XCTAssertNil(AppRoute(url: URL(string: "https://example.com/approve-computer?code=K7Q2-9MXD")!))
        // Other routes still ignore their query.
        XCTAssertEqual(AppRoute(path: "darulirfan://groups/usa?from=push"), .group(id: "usa"))
    }

    func testPreviewAndListDecodeTheContract() throws {
        let preview = try decode(ComputerLinkPreview.self, #"{ "deviceName": "Ali's laptop", "platform": "windows", "expiresAt": "2026-11-09T18:30:00Z" }"#)
        XCTAssertEqual(preview.deviceName, "Ali's laptop")
        XCTAssertEqual(preview.platform, "windows")
        XCTAssertNotNil(preview.expiresAt)

        let list = try decode(SignedInComputerList.self, """
        { "computers": [
            { "id": "abc123def456", "name": "Ali's Mac", "platform": "macos", "createdAt": "2026-11-09T10:00:00Z",
              "lastSeenAt": "2026-11-09T11:00:00Z", "expiresAt": "2026-12-09T11:00:00Z", "current": false },
            { "name": "No id, left out" },
            { "id": "0123456789ab", "platform": "windows" }
        ] }
        """)
        XCTAssertEqual(list.computers.map(\.id), ["abc123def456", "0123456789ab"])
        XCTAssertEqual(list.computers.first?.name, "Ali's Mac")
        XCTAssertNotNil(list.computers.first?.lastSeenAt)
        XCTAssertFalse(list.computers[1].current)
        XCTAssertNil(list.computers[1].createdAt)
        XCTAssertTrue(try decode(SignedInComputerList.self, "{}").computers.isEmpty)
    }

    func testPlatformNamesAndSymbols() {
        XCTAssertEqual(ComputerPlatform.name("windows"), "Windows")
        XCTAssertEqual(ComputerPlatform.name("macos"), "macOS")
        XCTAssertEqual(ComputerPlatform.symbol("macos"), "laptopcomputer")
        XCTAssertEqual(ComputerPlatform.symbol("windows"), "desktopcomputer")
    }

    func testRefusalsAreOneMessageAndLimitsAreSaid() {
        let refused = ComputerSignInService.failureText(for: MemberGroupError.server("That code is not valid or has expired."))
        XCTAssertEqual(refused, ComputerSignInService.failureText(for: MemberGroupError.server("Type the 8 characters shown on the computer.")))
        XCTAssertEqual(ComputerSignInService.failureText(for: MemberGroupError.server("Too many requests")),
                       MemberGroupError.tooManyAttempts.localizedDescription)
        XCTAssertEqual(ComputerSignInService.failureText(for: URLError(.notConnectedToInternet)),
                       MemberGroupError.actionDescription(for: URLError(.notConnectedToInternet)))
        XCTAssertNotEqual(ComputerSignInService.failureText(for: MemberGroupError.notSignedIn), refused)
    }
}
