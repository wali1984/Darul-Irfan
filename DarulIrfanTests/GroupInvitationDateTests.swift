import XCTest
@testable import DarulIrfan

final class GroupInvitationDateTests: XCTestCase {
    func testInvitationDatesOverrideNonWesternNumbering() {
        let date = Date(timeIntervalSince1970: 1794744000)
        let zone = TimeZone(secondsFromGMT: 0)!
        for locale in [Locale(identifier: "ur_PK@numbers=arabext"), Locale(identifier: "en_US@numbers=arab")] {
            let clock = GroupInvitationDate.clock(date, locale: locale, timeZone: zone)
            XCTAssertTrue(clock.contains { $0.isNumber })
            XCTAssertFalse(clock.contains { $0.isNumber && !("0"..."9").contains(String($0)) })
            for includesTime in [false, true] {
                let value = GroupInvitationDate.text(date, locale: locale, includesTime: includesTime, timeZone: zone)
                XCTAssertTrue(value.contains("2026"))
                XCTAssertEqual(value.contains("\u{2066}"), includesTime)
                XCTAssertFalse(value.contains { $0.isNumber && !("0"..."9").contains(String($0)) })
                XCTAssertTrue(value.hasPrefix("\u{2068}") && value.hasSuffix("\u{2069}"))
            }
        }
    }

    func testInvitationDatesUseSelectedLanguageAndOptionalTime() {
        let date = Date(timeIntervalSince1970: 1794744000)
        let zone = TimeZone(secondsFromGMT: 0)!
        let english = GroupInvitationDate.text(date, locale: Locale(identifier: "en"), timeZone: zone)
        let urdu = GroupInvitationDate.text(date, locale: Locale(identifier: "ur"), timeZone: zone)
        XCTAssertNotEqual(english, urdu)
        XCTAssertNotEqual(urdu, GroupInvitationDate.text(date, locale: Locale(identifier: "ur"), includesTime: true, timeZone: zone))
    }
}
