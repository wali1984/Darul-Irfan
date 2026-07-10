import Foundation
import XCTest
@testable import DarulIrfan

/// Tests for the `DayKey` helper used by every tracker: keys must reflect the
/// civil day in the *given* timezone, and `trailing()` must produce
/// consecutive keys oldest-first, including across month boundaries.
final class DayKeyTests: XCTestCase {

    // MARK: - Timezone sensitivity

    func testSameInstantYieldsDifferentKeysAcrossTimezones() {
        // 2026-01-14 22:00 UTC is already 03:00 on the 15th in Karachi (UTC+5).
        let instant = TestDates.make(
            year: 2026, month: 1, day: 14, hour: 22,
            timeZone: TestDates.utc
        )
        XCTAssertEqual(DayKey.make(from: instant, timeZone: TestDates.utc), "2026-01-14")
        XCTAssertEqual(DayKey.make(from: instant, timeZone: TestDates.karachi), "2026-01-15")
    }

    func testMidnightBoundaryInOneZone() {
        // One second before and after Karachi midnight land on different keys
        // in Karachi but the same key in UTC (where it is still 18:59/19:00).
        let beforeMidnight = TestDates.make(
            year: 2026, month: 1, day: 14, hour: 23, minute: 59, second: 59,
            timeZone: TestDates.karachi
        )
        let afterMidnight = beforeMidnight.addingTimeInterval(2)

        XCTAssertEqual(DayKey.make(from: beforeMidnight, timeZone: TestDates.karachi), "2026-01-14")
        XCTAssertEqual(DayKey.make(from: afterMidnight, timeZone: TestDates.karachi), "2026-01-15")
        XCTAssertEqual(
            DayKey.make(from: beforeMidnight, timeZone: TestDates.utc),
            DayKey.make(from: afterMidnight, timeZone: TestDates.utc)
        )
    }

    func testKeyIsZeroPadded() {
        let date = TestDates.make(year: 2026, month: 3, day: 5, timeZone: TestDates.utc)
        XCTAssertEqual(DayKey.make(from: date, timeZone: TestDates.utc), "2026-03-05")
    }

    // MARK: - Trailing windows

    func testTrailingReturnsOldestFirstAcrossMonthBoundary() {
        // 2026 is not a leap year, so February has 28 days.
        let end = TestDates.make(year: 2026, month: 3, day: 1, timeZone: TestDates.utc)
        let keys = DayKey.trailing(3, endingAt: end, timeZone: TestDates.utc)
        XCTAssertEqual(keys, ["2026-02-27", "2026-02-28", "2026-03-01"])
    }

    func testTrailingSingleDayIsJustTheEndKey() {
        let end = TestDates.make(year: 2026, month: 7, day: 9, timeZone: TestDates.karachi)
        let keys = DayKey.trailing(1, endingAt: end, timeZone: TestDates.karachi)
        XCTAssertEqual(keys, [DayKey.make(from: end, timeZone: TestDates.karachi)])
    }

    func testTrailingKeysAreConsecutiveAndUnique() {
        let end = TestDates.make(year: 2026, month: 1, day: 10, timeZone: TestDates.karachi)
        let keys = DayKey.trailing(30, endingAt: end, timeZone: TestDates.karachi)

        XCTAssertEqual(keys.count, 30)
        XCTAssertEqual(Set(keys).count, 30, "Keys must be unique")
        XCTAssertEqual(keys.last, "2026-01-10")
        XCTAssertEqual(keys.first, "2025-12-12")
        // Lexicographic order of yyyy-MM-dd keys equals chronological order.
        XCTAssertEqual(keys, keys.sorted())
    }
}
