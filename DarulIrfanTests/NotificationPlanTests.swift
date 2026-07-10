import Foundation
import XCTest
@testable import DarulIrfan

/// Tests for the pure `PrayerNotificationPlan.build` planner — no
/// UserNotifications involved. Fixtures use fixed times in Asia/Karachi so
/// every expectation is deterministic; `now` is always passed explicitly.
final class NotificationPlanTests: XCTestCase {

    // MARK: - Fixtures

    /// Fixed per-day fixture times (Asia/Karachi wall clock).
    private static let fixtureTimes: [(prayer: Prayer, hour: Int, minute: Int)] = [
        (.fajr, 5, 0),
        (.sunrise, 6, 30),
        (.dhuhr, 12, 30),
        (.asr, 16, 0),
        (.maghrib, 18, 0),
        (.isha, 19, 30),
    ]

    /// One day's schedule for 2026-01-(15+dayOffset) in Karachi.
    private func makeSchedule(dayOffset: Int) -> PrayerDaySchedule {
        let day = 15 + dayOffset
        var times: [Prayer: Date] = [:]
        for entry in Self.fixtureTimes {
            times[entry.prayer] = TestDates.make(
                year: 2026, month: 1, day: day,
                hour: entry.hour, minute: entry.minute,
                timeZone: TestDates.karachi
            )
        }
        return PrayerDaySchedule(
            date: DateComponents(year: 2026, month: 1, day: day),
            location: TestPlaces.karachi,
            times: times
        )
    }

    private func makeSchedules(days: Int) -> [PrayerDaySchedule] {
        (0..<days).map { makeSchedule(dayOffset: $0) }
    }

    /// A reference instant strictly before every fixture fire date.
    private let now = TestDates.make(
        year: 2026, month: 1, day: 14, hour: 0,
        timeZone: TestDates.karachi
    )

    /// Explicit styles for all six prayers (avoids the preference type's
    /// non-off fallback for missing keys).
    private func styles(
        _ value: PrayerAlertStyle,
        overriding overrides: [Prayer: PrayerAlertStyle] = [:]
    ) -> [Prayer: PrayerAlertStyle] {
        var map: [Prayer: PrayerAlertStyle] = [:]
        for prayer in Prayer.allCases {
            map[prayer] = overrides[prayer] ?? value
        }
        return map
    }

    // MARK: - Style filtering

    func testOffStylesAreExcluded() {
        let preferences = PrayerNotificationPreferences(
            styles: styles(.off, overriding: [.dhuhr: .defaultSound]),
            preReminders: [:]
        )
        let plan = PrayerNotificationPlan.build(
            schedules: makeSchedules(days: 1),
            preferences: preferences,
            now: now
        )

        // Only dhuhr fires, plus the single trailing refresh reminder.
        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan.first?.identifier, "prayer|2026-01-15|dhuhr")
        XCTAssertEqual(plan.last?.identifier, PrayerNotificationPlan.refreshReminderIdentifier)
        XCTAssertFalse(plan.contains { $0.identifier.contains("|fajr") })
        XCTAssertFalse(plan.contains { $0.identifier.contains("|isha") })
    }

    func testSunriseIsExcludedByDefaultPreferences() {
        let plan = PrayerNotificationPlan.build(
            schedules: makeSchedules(days: 1),
            preferences: .default,
            now: now
        )

        XCTAssertFalse(plan.contains { $0.identifier.contains("|sunrise") })
        // Defaults: five obligatory prayers on, no pre-reminders → 5 + refresh.
        XCTAssertEqual(plan.count, 6)
    }

    func testSunriseIsIncludedWhenUserEnablesIt() {
        var stylesMap = PrayerNotificationPreferences.default.styles
        stylesMap[.sunrise] = .defaultSound
        let preferences = PrayerNotificationPreferences(styles: stylesMap, preReminders: [:])

        let plan = PrayerNotificationPlan.build(
            schedules: makeSchedules(days: 1),
            preferences: preferences,
            now: now
        )
        XCTAssertTrue(plan.contains { $0.identifier == "prayer|2026-01-15|sunrise" })
    }

    // MARK: - Pre-reminders

    func testPreReminderIsIncludedTenMinutesBeforePrayer() throws {
        let preferences = PrayerNotificationPreferences(
            styles: styles(.off, overriding: [.fajr: .azanClip]),
            preReminders: [.fajr: .tenMinutes]
        )
        let plan = PrayerNotificationPlan.build(
            schedules: makeSchedules(days: 1),
            preferences: preferences,
            now: now
        )

        let atTime = try XCTUnwrap(
            plan.first { $0.identifier == "prayer|2026-01-15|fajr" }
        )
        let preReminder = try XCTUnwrap(
            plan.first { $0.identifier == "prayer-pre|2026-01-15|fajr" }
        )
        XCTAssertEqual(
            atTime.fireDate.timeIntervalSince(preReminder.fireDate), 600,
            accuracy: 0.001,
            "Pre-reminder must fire exactly 10 minutes before the prayer"
        )
    }

    func testPreReminderAlreadyInThePastIsDropped() {
        // now = 04:55 on the 15th: the 10-minute fajr pre-reminder (04:50) is
        // in the past, but fajr itself (05:00) is still upcoming.
        let lateNow = TestDates.make(
            year: 2026, month: 1, day: 15, hour: 4, minute: 55,
            timeZone: TestDates.karachi
        )
        let preferences = PrayerNotificationPreferences(
            styles: styles(.off, overriding: [.fajr: .defaultSound]),
            preReminders: [.fajr: .tenMinutes]
        )
        let plan = PrayerNotificationPlan.build(
            schedules: makeSchedules(days: 1),
            preferences: preferences,
            now: lateNow
        )

        XCTAssertTrue(plan.contains { $0.identifier == "prayer|2026-01-15|fajr" })
        XCTAssertFalse(plan.contains { $0.identifier == "prayer-pre|2026-01-15|fajr" })
    }

    // MARK: - Sound mapping

    func testSilentStyleProducesSilentNotificationAndSilentPreReminder() throws {
        let preferences = PrayerNotificationPreferences(
            styles: styles(.off, overriding: [.dhuhr: .silent]),
            preReminders: [.dhuhr: .fiveMinutes]
        )
        let plan = PrayerNotificationPlan.build(
            schedules: makeSchedules(days: 1),
            preferences: preferences,
            now: now
        )

        let atTime = try XCTUnwrap(plan.first { $0.identifier == "prayer|2026-01-15|dhuhr" })
        XCTAssertEqual(atTime.soundKind, .silent)
        let preReminder = try XCTUnwrap(plan.first { $0.identifier == "prayer-pre|2026-01-15|dhuhr" })
        XCTAssertEqual(preReminder.soundKind, .silent)
    }

    func testAzanClipStyleIsCarriedOnPlannedNotification() throws {
        let plan = PrayerNotificationPlan.build(
            schedules: makeSchedules(days: 1),
            preferences: .default, // all five obligatory prayers use .azanClip
            now: now
        )
        let fajr = try XCTUnwrap(plan.first { $0.identifier == "prayer|2026-01-15|fajr" })
        XCTAssertEqual(fajr.soundKind, .azanClip)
        XCTAssertEqual(fajr.title, PrayerNotificationPlan.title(for: .fajr))
        XCTAssertEqual(fajr.body, PrayerNotificationPlan.body(for: .fajr))
    }

    // MARK: - Ordering

    func testPlanIsChronologicalWithPastTimesDropped() {
        // now = 13:00 on day one: fajr/sunrise/dhuhr of day one are past.
        let middayNow = TestDates.make(
            year: 2026, month: 1, day: 15, hour: 13,
            timeZone: TestDates.karachi
        )
        let plan = PrayerNotificationPlan.build(
            schedules: makeSchedules(days: 3),
            preferences: .default,
            now: middayNow
        )

        XCTAssertFalse(plan.isEmpty)
        XCTAssertFalse(plan.contains { $0.identifier == "prayer|2026-01-15|fajr" })
        XCTAssertFalse(plan.contains { $0.identifier == "prayer|2026-01-15|dhuhr" })
        XCTAssertEqual(plan.first?.identifier, "prayer|2026-01-15|asr")

        for index in plan.indices.dropFirst() {
            XCTAssertLessThanOrEqual(
                plan[index - 1].fireDate, plan[index].fireDate,
                "Plan must be sorted chronologically"
            )
        }
        // Day one remainder (asr, maghrib, isha) + 2 full days + refresh.
        XCTAssertEqual(plan.count, 3 + 5 + 5 + 1)
    }

    // MARK: - 64-request cap and trailing refresh reminder

    func testCapIsRespectedWithTrailingRefreshReminder() throws {
        // 14 days × (5 at-time + 5 pre-reminders) = 140 candidates → far over
        // the limit. The plan must keep the soonest 63 and append the refresh
        // reminder, totalling exactly 64.
        var preReminders: [Prayer: PrePrayerReminder] = [:]
        for prayer in Prayer.obligatory {
            preReminders[prayer] = .tenMinutes
        }
        let preferences = PrayerNotificationPreferences(
            styles: PrayerNotificationPreferences.default.styles,
            preReminders: preReminders
        )

        let plan = PrayerNotificationPlan.build(
            schedules: makeSchedules(days: 14),
            preferences: preferences,
            now: now,
            limit: 64
        )

        XCTAssertEqual(plan.count, 64)

        let last = try XCTUnwrap(plan.last)
        XCTAssertEqual(last.identifier, PrayerNotificationPlan.refreshReminderIdentifier)

        // The refresh reminder fires a fixed delay after the last real one.
        let lastReal = try XCTUnwrap(plan.dropLast().last)
        let expectedDelay = TimeInterval(PrayerNotificationPlan.refreshReminderDelayMinutes * 60)
        XCTAssertEqual(
            last.fireDate.timeIntervalSince(lastReal.fireDate),
            expectedDelay,
            accuracy: 0.001
        )

        // Everything before the refresh reminder is a prayer/pre identifier,
        // in chronological order (soonest kept, furthest dropped).
        let realNotifications = Array(plan.dropLast())
        for (index, notification) in realNotifications.enumerated() {
            XCTAssertTrue(
                PrayerNotificationPlan.isPrayerIdentifier(notification.identifier)
            )
            if index > 0 {
                XCTAssertLessThanOrEqual(
                    realNotifications[index - 1].fireDate,
                    notification.fireDate
                )
            }
        }
        // The very first candidate chronologically is the fajr pre-reminder
        // of the first day (04:50 < 05:00 fajr).
        XCTAssertEqual(plan.first?.identifier, "prayer-pre|2026-01-15|fajr")
    }

    func testEmptySchedulesProduceEmptyPlanWithoutRefreshReminder() {
        let plan = PrayerNotificationPlan.build(
            schedules: [],
            preferences: .default,
            now: now
        )
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: - Identifier stability

    func testIdentifiersAreStableAcrossBuilds() {
        let schedules = makeSchedules(days: 3)
        let first = PrayerNotificationPlan.build(
            schedules: schedules, preferences: .default, now: now
        )
        let second = PrayerNotificationPlan.build(
            schedules: schedules, preferences: .default, now: now
        )
        XCTAssertEqual(
            first.map { $0.identifier },
            second.map { $0.identifier },
            "Identical inputs must yield identical identifiers (needed for reschedule cleanup)"
        )
        // Format contract: "prayer|<yyyy-MM-dd>|<prayerRaw>".
        XCTAssertTrue(first.contains { $0.identifier == "prayer|2026-01-16|maghrib" })
    }

    func testIsPrayerIdentifierRecognizesOwnedIdentifiersOnly() {
        XCTAssertTrue(PrayerNotificationPlan.isPrayerIdentifier("prayer|2026-01-15|fajr"))
        XCTAssertTrue(PrayerNotificationPlan.isPrayerIdentifier("prayer-pre|2026-01-15|isha"))
        XCTAssertTrue(PrayerNotificationPlan.isPrayerIdentifier(
            PrayerNotificationPlan.refreshReminderIdentifier
        ))
        // One-off zikr/event reminders must never be swept by a reschedule.
        XCTAssertFalse(PrayerNotificationPlan.isPrayerIdentifier("reminder|zikr-evening"))
        XCTAssertFalse(PrayerNotificationPlan.isPrayerIdentifier("some-other-id"))
    }

    // MARK: - Trigger components

    func testTriggerComponentsCarryFullDateAndTimezone() throws {
        let fireDate = TestDates.make(
            year: 2026, month: 1, day: 15, hour: 5, minute: 0,
            timeZone: TestDates.karachi
        )
        let components = PrayerNotificationPlan.triggerComponents(
            for: fireDate,
            timeZone: TestDates.karachi
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 5)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.timeZone, TestDates.karachi)
    }
}
