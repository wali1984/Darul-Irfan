import Foundation
import XCTest
@testable import DarulIrfan

/// Zikr reminders keep a week of sessions scheduled (they used to fire once),
/// and say how each session is joined.
final class ZikrRemindersTests: XCTestCase {

    private func session(
        id: String,
        title: String,
        hour: Int,
        minute: Int,
        anchor: String? = nil
    ) -> ZikrSession {
        ZikrSession(
            id: id,
            title: title,
            weekdays: Array(1...7),
            startHour: hour,
            startMinute: minute,
            durationMinutes: 30,
            timeZoneIdentifier: "Asia/Karachi",
            joinUrl: nil,
            instructions: nil,
            availabilityNote: nil,
            sourceUrl: nil,
            anchor: anchor,
            anchorOffsetMinutes: anchor == nil ? nil : 60
        )
    }

    func testADailySessionKeepsAWeekOfStartsAhead() throws {
        let daily = session(id: "zikr-after-isha", title: "Daily Zikr", hour: 21, minute: 15)
        let now = TestDates.make(year: 2026, month: 1, day: 15, hour: 22, minute: 0, timeZone: TestDates.karachi)

        let starts = ZikrOccurrences.starts(of: daily, after: now, count: ZikrReminders.occurrencesPerSession, calculator: nil)

        XCTAssertEqual(starts.count, 7)
        XCTAssertEqual(starts.first, TestDates.make(year: 2026, month: 1, day: 16, hour: 21, minute: 15, timeZone: TestDates.karachi))
        for (earlier, later) in zip(starts, starts.dropFirst()) {
            XCTAssertEqual(later.timeIntervalSince(earlier), 86_400, accuracy: 1)
        }
    }

    /// The Tahajjud start follows Fajr at Dar-ul-Irfan each day.
    func testATahajjudSessionIsResolvedForEachDay() throws {
        let tahajjud = session(id: "zikr-tahajjud", title: "Tahajjud Zikr", hour: 4, minute: 0, anchor: "beforeFajr")
        let calculator = PrayerCalculationService()
        let now = TestDates.make(year: 2026, month: 1, day: 15, hour: 12, minute: 0, timeZone: TestDates.karachi)

        let starts = ZikrOccurrences.starts(of: tahajjud, after: now, count: 3, calculator: calculator)

        XCTAssertEqual(starts.count, 3)
        for start in starts {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TestDates.karachi
            let day = calendar.dateComponents([.year, .month, .day], from: start)
            let fajr = try XCTUnwrap(calculator.schedule(
                for: day,
                at: ZikrAnchorResolver.darulIrfan,
                preferences: PrayerCalculationPreferences()
            )?.time(for: .fajr))
            XCTAssertEqual(start, fajr.addingTimeInterval(-3_600), "An hour before that day's Fajr")
        }
    }

    func testRemindersComeTenMinutesEarlyOrAtTheStart() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let soon = now.addingTimeInterval(5 * 60)
        let later = now.addingTimeInterval(3_600)
        let past = now.addingTimeInterval(-60)

        let fires = ZikrReminders.fireDates(forStarts: [past, soon, later], now: now)

        XCTAssertEqual(fires, [soon, later.addingTimeInterval(-600)])
    }

    /// Tahajjud is joined on Paltalk; the reminder must not call it Daily Zikr.
    func testEachSessionsReminderNamesItsOwnZikr() {
        let tahajjud = session(id: "zikr-tahajjud", title: "Tahajjud Zikr", hour: 4, minute: 0, anchor: "beforeFajr")
        let daily = session(id: "zikr-after-isha", title: "Daily Zikr", hour: 21, minute: 15)

        let tahajjudBody = ZikrReminders.body(for: tahajjud)
        XCTAssertTrue(ZikrReminders.isTahajjud(tahajjud))
        XCTAssertFalse(ZikrReminders.isTahajjud(daily))
        XCTAssertNotEqual(tahajjudBody, ZikrReminders.body(for: daily))
        XCTAssertEqual(
            tahajjudBody,
            String(localized: "Tahajjud Zikr begins soon. Join it on Paltalk from Darul Irfan.")
        )
    }

    /// The widgets and the Watch see a session that is under way, then the next ones.
    func testWidgetOccurrencesIncludeTheSessionInProgress() {
        let daily = session(id: "zikr-after-isha", title: "Daily Zikr", hour: 21, minute: 15)
        let duringSession = TestDates.make(year: 2026, month: 1, day: 15, hour: 21, minute: 30, timeZone: TestDates.karachi)

        let occurrences = ZikrOccurrences.widgetSessions(for: [daily], reference: duringSession, perSession: 3, calculator: nil)

        XCTAssertEqual(occurrences.first?.startsAt, TestDates.make(year: 2026, month: 1, day: 15, hour: 21, minute: 15, timeZone: TestDates.karachi))
        XCTAssertTrue(occurrences.first?.isActive(at: duringSession) ?? false)
        XCTAssertEqual(occurrences.count, 3)
    }
}
