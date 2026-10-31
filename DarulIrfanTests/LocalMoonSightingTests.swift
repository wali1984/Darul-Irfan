import XCTest
@testable import DarulIrfan

final class LocalMoonSightingTests: XCTestCase {
    func testCorrectionCrossesAHijriYearBoundary() {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let first = calendar.date(from: DateComponents(year: 1448, month: 1, day: 1, hour: 12))!
        let service = HijriCalendarService()
        let previous = service.hijriComponents(for: first, offsetDays: -1, timeZone: calendar.timeZone)
        XCTAssertEqual(previous.year, 1447)
        XCTAssertEqual(previous.month, 12)
        XCTAssertTrue([29, 30].contains(previous.day!))
        let later = service.hijriComponents(for: first, offsetDays: 2, timeZone: calendar.timeZone)
        XCTAssertEqual(later.year, 1448); XCTAssertEqual(later.month, 1); XCTAssertEqual(later.day, 3)
    }
    func testCorrectionUsesTheSelectedLocationsCivilDay() {
        let now = ISO8601DateFormatter().date(from: "2026-10-30T22:00:00Z")!
        let service = HijriCalendarService()
        let newYork = service.hijriComponents(for: now, offsetDays: 1, timeZone: TimeZone(identifier: "America/New_York")!)
        let pakistan = service.hijriComponents(for: now, offsetDays: 0, timeZone: TimeZone(identifier: "Asia/Karachi")!)
        XCTAssertEqual(newYork.year, pakistan.year); XCTAssertEqual(newYork.month, pakistan.month); XCTAssertEqual(newYork.day, pakistan.day)
    }
}
