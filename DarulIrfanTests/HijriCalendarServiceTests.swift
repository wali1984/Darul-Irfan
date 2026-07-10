import Foundation
import XCTest
@testable import DarulIrfan

/// Tests for `HijriCalendarService`. All expectations are self-consistent:
/// they are computed inside the test with the same Umm al-Qura calendar the
/// service uses (`Calendar(identifier: .islamicUmmAlQura)`), so they hold on
/// any OS release regardless of table updates. What the tests actually pin
/// down is the service's contract: the ±day offset is applied to the *Date*
/// before extracting Hijri components (never to the day component), which is
/// exactly what makes month boundaries behave.
final class HijriCalendarServiceTests: XCTestCase {

    private let service = HijriCalendarService()

    /// The same calendar the service builds internally (current timezone).
    private func ummAlQura() -> Calendar {
        Calendar(identifier: .islamicUmmAlQura)
    }

    private func gregorian() -> Calendar {
        Calendar(identifier: .gregorian)
    }

    /// A fixed noon-anchored base date (noon avoids DST edges in any zone).
    private func baseDate() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 9
        components.hour = 12
        // Built in the current timezone deliberately: the service extracts
        // Hijri components in the current timezone too, so both sides of
        // every comparison see the same civil day.
        return gregorian().date(from: components) ?? Date()
    }

    // MARK: - Offset semantics

    func testOffsetMatchesShiftingTheDateItself() throws {
        let calendar = ummAlQura()
        let base = baseDate()

        for offset in [-2, -1, 0, 1, 2] {
            let shifted = try XCTUnwrap(
                gregorian().date(byAdding: .day, value: offset, to: base)
            )
            let expected = calendar.dateComponents([.year, .month, .day], from: shifted)
            let actual = service.hijriComponents(for: base, offsetDays: offset)
            XCTAssertEqual(actual.year, expected.year, "year mismatch at offset \(offset)")
            XCTAssertEqual(actual.month, expected.month, "month mismatch at offset \(offset)")
            XCTAssertEqual(actual.day, expected.day, "day mismatch at offset \(offset)")
        }
    }

    func testOffsetCrossesHijriMonthBoundaryCorrectly() throws {
        let calendar = ummAlQura()
        let base = baseDate()

        // Find the next Gregorian day whose Hijri day-of-month is 1. Hijri
        // months are 29 or 30 days, so one must occur within 31 days.
        var boundary: Date?
        for dayOffset in 0..<32 {
            guard let candidate = gregorian().date(byAdding: .day, value: dayOffset, to: base) else {
                continue
            }
            if calendar.dateComponents([.day], from: candidate).day == 1 {
                boundary = candidate
                break
            }
        }
        let firstOfMonth = try XCTUnwrap(boundary, "No Hijri month start found in a 32-day scan")
        let firstComponents = calendar.dateComponents([.year, .month, .day], from: firstOfMonth)

        // Offset -1 from the 1st must land on the last day (29 or 30) of the
        // previous Hijri month — exactly what the previous calendar day shows.
        let minusOne = service.hijriComponents(for: firstOfMonth, offsetDays: -1)
        let previousDay = try XCTUnwrap(
            gregorian().date(byAdding: .day, value: -1, to: firstOfMonth)
        )
        let expectedPrevious = calendar.dateComponents([.year, .month, .day], from: previousDay)

        XCTAssertEqual(minusOne.year, expectedPrevious.year)
        XCTAssertEqual(minusOne.month, expectedPrevious.month)
        XCTAssertEqual(minusOne.day, expectedPrevious.day)
        let minusOneDay = try XCTUnwrap(minusOne.day)
        XCTAssertGreaterThanOrEqual(minusOneDay, 29, "Last day of a Hijri month is 29 or 30")
        XCTAssertNotEqual(minusOne.month, firstComponents.month, "Offset -1 must leave the month")

        // And offset +1 from the day before the boundary lands on day 1.
        let plusOne = service.hijriComponents(for: previousDay, offsetDays: 1)
        XCTAssertEqual(plusOne.day, 1)
        XCTAssertEqual(plusOne.month, firstComponents.month)
    }

    // MARK: - Ramadan

    func testIsRamadanIsSelfConsistentWithUmmAlQura() throws {
        let calendar = ummAlQura()
        let base = baseDate()

        // A Hijri year is ~354 days, so scanning 400 days always finds both
        // a Ramadan day and a non-Ramadan day.
        var ramadanDate: Date?
        var otherDate: Date?
        for dayOffset in 0..<400 {
            guard let candidate = gregorian().date(byAdding: .day, value: dayOffset, to: base) else {
                continue
            }
            let month = calendar.dateComponents([.month], from: candidate).month
            if month == 9 && ramadanDate == nil {
                ramadanDate = candidate
            } else if month != 9 && otherDate == nil {
                otherDate = candidate
            }
            if ramadanDate != nil && otherDate != nil { break }
        }

        let inRamadan = try XCTUnwrap(ramadanDate, "No Ramadan day found in a 400-day scan")
        let outsideRamadan = try XCTUnwrap(otherDate, "No non-Ramadan day found in a 400-day scan")

        XCTAssertTrue(service.isRamadan(inRamadan, offsetDays: 0))
        XCTAssertFalse(service.isRamadan(outsideRamadan, offsetDays: 0))
    }

    func testIsRamadanRespectsOffsetAcrossTheMonthStart() throws {
        let calendar = ummAlQura()
        let base = baseDate()

        // Find 1 Ramadan, then look at the civil day just before it.
        var firstOfRamadan: Date?
        for dayOffset in 0..<400 {
            guard let candidate = gregorian().date(byAdding: .day, value: dayOffset, to: base) else {
                continue
            }
            let parts = calendar.dateComponents([.month, .day], from: candidate)
            if parts.month == 9 && parts.day == 1 {
                firstOfRamadan = candidate
                break
            }
        }
        let ramadanStart = try XCTUnwrap(firstOfRamadan, "No 1 Ramadan found in a 400-day scan")
        let dayBefore = try XCTUnwrap(
            gregorian().date(byAdding: .day, value: -1, to: ramadanStart)
        )

        // The eve of Ramadan is Sha'ban with no offset, Ramadan with +1.
        XCTAssertFalse(service.isRamadan(dayBefore, offsetDays: 0))
        XCTAssertTrue(service.isRamadan(dayBefore, offsetDays: 1))
        // And the first day with -1 steps back out of Ramadan.
        XCTAssertFalse(service.isRamadan(ramadanStart, offsetDays: -1))
    }

    // MARK: - Display text

    func testHijriDateTextContainsDayAndYearForEnglishLocale() throws {
        let base = baseDate()
        let locale = Locale(identifier: "en_US")
        let components = service.hijriComponents(for: base, offsetDays: 0)
        let day = try XCTUnwrap(components.day)
        let year = try XCTUnwrap(components.year)

        let text = service.hijriDateText(for: base, offsetDays: 0, locale: locale)
        XCTAssertFalse(text.isEmpty)
        // Format is "d MMMM yyyy": the Hijri day and year must both appear
        // verbatim when rendered with Western digits.
        XCTAssertTrue(text.contains(String(day)), "Expected day \(day) in '\(text)'")
        XCTAssertTrue(text.contains(String(year)), "Expected year \(year) in '\(text)'")
    }
}
