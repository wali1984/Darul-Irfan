import Foundation
import XCTest
@testable import DarulIrfan

/// Tests for the live Adhan wrapper. Expected absolute times were derived
/// with an independent implementation of the PrayTimes.org astronomical
/// algorithm (NOAA solar position + equation of time; the same family of
/// equations adhan-swift implements via Meeus's "Astronomical Algorithms"),
/// evaluated for Karachi (24.8607 N, 67.0011 E, UTC+5) on 2026-01-15 with the
/// University of Islamic Sciences Karachi parameters (Fajr 18°, Isha 18°,
/// Hanafi asr). The two implementations agree to well under a minute, so the
/// ±4-minute tolerance comfortably absorbs both engine differences and the
/// rounding adhan applies.
final class PrayerCalculationServiceTests: XCTestCase {

    private let service = PrayerCalculationService()

    /// Karachi-method preferences, Hanafi asr, no manual offsets.
    private func karachiPreferences() -> PrayerCalculationPreferences {
        var preferences = PrayerCalculationPreferences()
        preferences.method = .karachi
        preferences.asrMethod = .hanafi
        return preferences
    }

    private func components(year: Int, month: Int, day: Int) -> DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    /// An expected instant on 2026-01-15 in Karachi, from hour + decimal minutes.
    private func karachiExpected(hour: Int, minutes: Double) -> Date {
        let midnight = TestDates.make(
            year: 2026, month: 1, day: 15, hour: 0, minute: 0,
            timeZone: TestDates.karachi
        )
        return midnight.addingTimeInterval(Double(hour) * 3600.0 + minutes * 60.0)
    }

    // MARK: - Karachi, fixed date, absolute values

    func testKarachiJanuary15TimesMatchKarachiMethodWithinFourMinutes() throws {
        let schedule = try XCTUnwrap(service.schedule(
            for: components(year: 2026, month: 1, day: 15),
            at: TestPlaces.karachi,
            preferences: karachiPreferences()
        ))

        // Reference values from the independent PrayTimes computation
        // (hour, decimal minutes, local Karachi time):
        let expected: [(prayer: Prayer, hour: Int, minutes: Double)] = [
            (.fajr, 5, 58.38),
            (.sunrise, 7, 18.55),
            (.dhuhr, 12, 41.34),
            (.asr, 16, 28.38),      // Hanafi (shadow factor 2)
            (.maghrib, 18, 4.31),
            (.isha, 19, 24.46),
        ]

        let tolerance: TimeInterval = 240 // ±4 minutes

        for entry in expected {
            let actual = try XCTUnwrap(
                schedule.time(for: entry.prayer),
                "\(entry.prayer.rawValue) missing from schedule"
            )
            let reference = karachiExpected(hour: entry.hour, minutes: entry.minutes)
            let delta = abs(actual.timeIntervalSince(reference))
            XCTAssertLessThanOrEqual(
                delta, tolerance,
                "\(entry.prayer.rawValue) off by \(Int(delta))s from reference"
            )
        }
    }

    // MARK: - New York DST boundaries

    /// US DST starts 2026-03-08: the wall clock jumps from UTC-5 to UTC-4, so
    /// the local clock time of solar events shifts about +60 minutes between
    /// 03-07 and 03-08 while the absolute interval between consecutive noons
    /// stays ~24 h (solar noon drifts well under a minute per day).
    func testNewYorkSpringForwardShiftsLocalTimesByOneHour() throws {
        let preferences = karachiPreferences()

        let before = try XCTUnwrap(service.schedule(
            for: components(year: 2026, month: 3, day: 7),
            at: TestPlaces.newYork,
            preferences: preferences
        ))
        let after = try XCTUnwrap(service.schedule(
            for: components(year: 2026, month: 3, day: 8),
            at: TestPlaces.newYork,
            preferences: preferences
        ))

        let dhuhrBefore = try XCTUnwrap(before.time(for: .dhuhr))
        let dhuhrAfter = try XCTUnwrap(after.time(for: .dhuhr))

        // Absolute spacing stays one civil day (±3 min covers solar drift
        // plus minute rounding); a DST bug would show up as ±1 h here.
        let interval = dhuhrAfter.timeIntervalSince(dhuhrBefore)
        XCTAssertLessThanOrEqual(
            abs(interval - 86_400), 180,
            "Consecutive solar noons should be ~24h apart in absolute time"
        )

        // Wall-clock shift: +60 minutes across the spring-forward boundary.
        let minutesBefore = TestDates.minutesIntoDay(of: dhuhrBefore, timeZone: TestDates.newYork)
        let minutesAfter = TestDates.minutesIntoDay(of: dhuhrAfter, timeZone: TestDates.newYork)
        XCTAssertLessThanOrEqual(
            abs((minutesAfter - minutesBefore) - 60), 5,
            "Local dhuhr time should move ~1 hour later when DST starts"
        )
    }

    /// US DST ends 2026-11-01 (UTC-4 back to UTC-5): local clock times of
    /// solar events shift about -60 minutes between 10-31 and 11-01.
    func testNewYorkFallBackShiftsLocalTimesBackOneHour() throws {
        let preferences = karachiPreferences()

        let before = try XCTUnwrap(service.schedule(
            for: components(year: 2026, month: 10, day: 31),
            at: TestPlaces.newYork,
            preferences: preferences
        ))
        let after = try XCTUnwrap(service.schedule(
            for: components(year: 2026, month: 11, day: 1),
            at: TestPlaces.newYork,
            preferences: preferences
        ))

        let dhuhrBefore = try XCTUnwrap(before.time(for: .dhuhr))
        let dhuhrAfter = try XCTUnwrap(after.time(for: .dhuhr))

        let interval = dhuhrAfter.timeIntervalSince(dhuhrBefore)
        XCTAssertLessThanOrEqual(
            abs(interval - 86_400), 180,
            "Consecutive solar noons should be ~24h apart in absolute time"
        )

        let minutesBefore = TestDates.minutesIntoDay(of: dhuhrBefore, timeZone: TestDates.newYork)
        let minutesAfter = TestDates.minutesIntoDay(of: dhuhrAfter, timeZone: TestDates.newYork)
        XCTAssertLessThanOrEqual(
            abs((minutesAfter - minutesBefore) + 60), 5,
            "Local dhuhr time should move ~1 hour earlier when DST ends"
        )
    }

    // MARK: - Asr juristic method

    /// The Hanafi asr (shadow factor 2) is always later than the Shafi asr
    /// (factor 1) because the sun needs longer to lengthen shadows further.
    func testHanafiAsrIsStrictlyLaterThanShafiAsr() throws {
        var shafi = karachiPreferences()
        shafi.asrMethod = .shafi
        var hanafi = karachiPreferences()
        hanafi.asrMethod = .hanafi

        let day = components(year: 2026, month: 1, day: 15)
        let shafiAsr = try XCTUnwrap(
            service.schedule(for: day, at: TestPlaces.karachi, preferences: shafi)?
                .time(for: .asr)
        )
        let hanafiAsr = try XCTUnwrap(
            service.schedule(for: day, at: TestPlaces.karachi, preferences: hanafi)?
                .time(for: .asr)
        )

        XCTAssertGreaterThan(hanafiAsr, shafiAsr, "Hanafi asr must be strictly later")
        // On this date the reference gap is ~45 minutes; ≥5 minutes is a
        // safe lower bound that still proves the madhab was actually applied.
        XCTAssertGreaterThanOrEqual(hanafiAsr.timeIntervalSince(shafiAsr), 300)
    }

    // MARK: - Manual offsets

    /// A +10-minute fajr adjustment must shift fajr by exactly 600 s: the
    /// engine adds whole minutes before its minute rounding, so the rounded
    /// results differ by precisely the offset.
    func testManualFajrOffsetShiftsFajrByExactlyTenMinutes() throws {
        let base = karachiPreferences()
        var adjusted = karachiPreferences()
        adjusted.adjustments.fajr = 10

        let day = components(year: 2026, month: 1, day: 15)
        let baseSchedule = try XCTUnwrap(
            service.schedule(for: day, at: TestPlaces.karachi, preferences: base)
        )
        let adjustedSchedule = try XCTUnwrap(
            service.schedule(for: day, at: TestPlaces.karachi, preferences: adjusted)
        )

        let baseFajr = try XCTUnwrap(baseSchedule.time(for: .fajr))
        let adjustedFajr = try XCTUnwrap(adjustedSchedule.time(for: .fajr))
        XCTAssertEqual(adjustedFajr.timeIntervalSince(baseFajr), 600, accuracy: 0.001)

        // Other prayers are untouched by a fajr-only offset.
        let baseDhuhr = try XCTUnwrap(baseSchedule.time(for: .dhuhr))
        let adjustedDhuhr = try XCTUnwrap(adjustedSchedule.time(for: .dhuhr))
        XCTAssertEqual(adjustedDhuhr, baseDhuhr)
    }

    // MARK: - Custom method angles

    /// With the custom method, a shallower fajr angle (12°) is reached later
    /// in the morning than a deeper one (18°), so fajr must move later.
    func testCustomFajrAngleChangesFajrTime() throws {
        var deepAngle = PrayerCalculationPreferences()
        deepAngle.method = .custom
        deepAngle.customAngles.fajrAngle = 18.0
        deepAngle.customAngles.ishaAngle = 17.0

        var shallowAngle = PrayerCalculationPreferences()
        shallowAngle.method = .custom
        shallowAngle.customAngles.fajrAngle = 12.0
        shallowAngle.customAngles.ishaAngle = 17.0

        let day = components(year: 2026, month: 1, day: 15)
        let fajr18 = try XCTUnwrap(
            service.schedule(for: day, at: TestPlaces.karachi, preferences: deepAngle)?
                .time(for: .fajr)
        )
        let fajr12 = try XCTUnwrap(
            service.schedule(for: day, at: TestPlaces.karachi, preferences: shallowAngle)?
                .time(for: .fajr)
        )

        XCTAssertGreaterThan(fajr12, fajr18, "12° fajr must be later than 18° fajr")
        // At Karachi's latitude 6° of solar depression is well over 5 minutes
        // of clock time, so this floor cannot produce a false negative.
        XCTAssertGreaterThanOrEqual(fajr12.timeIntervalSince(fajr18), 300)
    }

    // MARK: - Multi-day schedules

    func testSchedulesForThreeDaysReturnsThreeConsecutiveDayComponents() {
        let start = TestDates.make(
            year: 2026, month: 1, day: 15, hour: 12,
            timeZone: TestDates.karachi
        )
        let schedules = service.schedules(
            forDaysStarting: start,
            days: 3,
            at: TestPlaces.karachi,
            preferences: karachiPreferences()
        )

        XCTAssertEqual(schedules.count, 3)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TestDates.karachi
        for (offset, schedule) in schedules.enumerated() {
            guard let expectedDay = calendar.date(byAdding: .day, value: offset, to: start) else {
                XCTFail("Could not derive expected day for offset \(offset)")
                continue
            }
            let expected = calendar.dateComponents([.year, .month, .day], from: expectedDay)
            XCTAssertEqual(schedule.date.year, expected.year)
            XCTAssertEqual(schedule.date.month, expected.month)
            XCTAssertEqual(schedule.date.day, expected.day)
            // Every day of the window carries all six times.
            for prayer in Prayer.allCases {
                XCTAssertNotNil(schedule.time(for: prayer), "\(prayer.rawValue) missing on day \(offset)")
            }
        }
    }

    // MARK: - Next prayer

    func testNextPrayerAfterIshaRollsToTomorrowsFajr() throws {
        let preferences = karachiPreferences()
        let today = try XCTUnwrap(service.schedule(
            for: components(year: 2026, month: 1, day: 15),
            at: TestPlaces.karachi,
            preferences: preferences
        ))
        let tomorrow = try XCTUnwrap(service.schedule(
            for: components(year: 2026, month: 1, day: 16),
            at: TestPlaces.karachi,
            preferences: preferences
        ))

        let isha = try XCTUnwrap(today.time(for: .isha))
        let next = try XCTUnwrap(service.nextPrayer(
            after: isha.addingTimeInterval(60),
            at: TestPlaces.karachi,
            preferences: preferences
        ))

        XCTAssertEqual(next.prayer, .fajr)
        XCTAssertEqual(next.time, try XCTUnwrap(tomorrow.time(for: .fajr)))
        XCTAssertEqual(next.scheduleDate.day, 16)
        XCTAssertEqual(next.scheduleDate.month, 1)
        XCTAssertEqual(next.scheduleDate.year, 2026)
    }

    func testNextPrayerBeforeFajrIsTodaysFajr() throws {
        let preferences = karachiPreferences()
        let today = try XCTUnwrap(service.schedule(
            for: components(year: 2026, month: 1, day: 15),
            at: TestPlaces.karachi,
            preferences: preferences
        ))
        let fajr = try XCTUnwrap(today.time(for: .fajr))

        let next = try XCTUnwrap(service.nextPrayer(
            after: fajr.addingTimeInterval(-1800),
            at: TestPlaces.karachi,
            preferences: preferences
        ))
        XCTAssertEqual(next.prayer, .fajr)
        XCTAssertEqual(next.time, fajr)
        XCTAssertEqual(next.scheduleDate.day, 15)
    }

    /// Sunrise is never returned as a "next prayer" — only obligatory prayers.
    func testNextPrayerSkipsSunrise() throws {
        let preferences = karachiPreferences()
        let today = try XCTUnwrap(service.schedule(
            for: components(year: 2026, month: 1, day: 15),
            at: TestPlaces.karachi,
            preferences: preferences
        ))
        let fajr = try XCTUnwrap(today.time(for: .fajr))

        // Just after fajr, the next event on the clock is sunrise, but the
        // next *prayer* must be dhuhr.
        let next = try XCTUnwrap(service.nextPrayer(
            after: fajr.addingTimeInterval(60),
            at: TestPlaces.karachi,
            preferences: preferences
        ))
        XCTAssertEqual(next.prayer, .dhuhr)
    }
}
