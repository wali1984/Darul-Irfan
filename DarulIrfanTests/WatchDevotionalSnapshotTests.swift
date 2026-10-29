import XCTest
@testable import DarulIrfan

final class WatchDevotionalSnapshotTests: XCTestCase {
    func testLegacyPrayerSnapshotDecodesWithoutZikrSessions() throws {
        let json = """
        {
          "version": 1,
          "generatedAt": "2026-07-30T10:00:00Z",
          "placeName": "Test City",
          "upcomingTimes": [],
          "hijriDateText": "15 Safar 1448"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(PrayerWidgetSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.zikrSessions)
        XCTAssertNil(snapshot.devotionalMetrics)
    }

    func testDevotionalMetricsRoundTripForWidgetsAndWatch() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let metrics = WidgetDevotionalMetrics(
            prayersCompleted: 4,
            prayerGoal: 5,
            prayerStreakDays: 9,
            prayerCompletionRate: 0.84,
            quranSurahNumber: 36,
            quranAyahNumber: 12,
            tasbihTitle: "Darood Sharif",
            tasbihCount: 72,
            tasbihTarget: 100,
            zikrCompletionsToday: 1,
            updatedAt: now
        )
        let snapshot = PrayerWidgetSnapshot(
            generatedAt: now,
            placeName: "Test City",
            upcomingTimes: [],
            hijriDateText: "15 Safar 1448",
            suhoorEndsAt: nil,
            iftarAt: nil,
            devotionalMetrics: metrics
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PrayerWidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded.devotionalMetrics, metrics)
    }

    func testCurrentZikrWinsOverLaterOccurrence() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let active = WidgetZikrSession(
            id: "active",
            title: "Active Zikr",
            startsAt: now.addingTimeInterval(-300),
            endsAt: now.addingTimeInterval(1_500)
        )
        let later = WidgetZikrSession(
            id: "later",
            title: "Later Zikr",
            startsAt: now.addingTimeInterval(3_600),
            endsAt: now.addingTimeInterval(5_400)
        )
        let snapshot = PrayerWidgetSnapshot(
            generatedAt: now,
            placeName: "Test City",
            upcomingTimes: [],
            hijriDateText: "15 Safar 1448",
            suhoorEndsAt: nil,
            iftarAt: nil,
            zikrSessions: [later, active]
        )

        XCTAssertEqual(snapshot.currentOrNextZikr(at: now)?.id, "active")
    }

    func testZikrMathReturnsActiveOccurrenceThenTomorrow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 30, hour: 10, minute: 0
        )))
        let session = ZikrSession(
            id: "daily",
            title: "Daily Zikr",
            weekdays: Array(1...7),
            startHour: 10,
            startMinute: 0,
            durationMinutes: 30,
            timeZoneIdentifier: "UTC",
            joinUrl: nil,
            instructions: nil,
            availabilityNote: nil,
            sourceUrl: nil
        )

        let during = day.addingTimeInterval(15 * 60)
        XCTAssertEqual(ZikrScheduleMath.currentOrNextOccurrence(of: session, at: during), day)

        let after = day.addingTimeInterval(31 * 60)
        let next = try XCTUnwrap(ZikrScheduleMath.currentOrNextOccurrence(of: session, at: after))
        XCTAssertEqual(next, calendar.date(byAdding: .day, value: 1, to: day))
    }
    // MARK: - After midnight, and away from the place

    /// The widgets turn the Hijri date over at midnight without the app.
    func testHijriTextFollowsTheEntrysDay() {
        let karachi = "Asia/Karachi"
        let day = TestDates.make(year: 2026, month: 2, day: 17, hour: 23, minute: 30, timeZone: TestDates.karachi)
        let nextDay = day.addingTimeInterval(60 * 60)
        let snapshot = PrayerWidgetSnapshot(
            generatedAt: day,
            placeName: "Karachi",
            upcomingTimes: [],
            hijriDateText: "29 Sha'ban 1447",
            suhoorEndsAt: nil,
            iftarAt: nil,
            timeZoneIdentifier: karachi,
            hijriDates: ["2026-02-17": "29 Sha'ban 1447", "2026-02-18": "1 Ramadan 1447"]
        )
        XCTAssertEqual(snapshot.hijriText(on: day), "29 Sha'ban 1447")
        XCTAssertEqual(snapshot.hijriText(on: nextDay), "1 Ramadan 1447")
        XCTAssertEqual(snapshot.hijriText(on: nextDay.addingTimeInterval(30 * 86_400)), "29 Sha'ban 1447", "Falls back to the text it was written with")
    }

    /// Yesterday's "5 of 5" must not greet the morning.
    func testTodaysCountsStartFromNothingOnANewDay() {
        let refreshed = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TestDates.karachi
        let metrics = WidgetDevotionalMetrics(
            prayersCompleted: 5,
            prayerGoal: 5,
            prayerStreakDays: 9,
            prayerCompletionRate: 0.9,
            quranSurahNumber: nil,
            quranAyahNumber: nil,
            tasbihTitle: nil,
            tasbihCount: 0,
            tasbihTarget: nil,
            zikrCompletionsToday: 2,
            updatedAt: refreshed
        )
        XCTAssertEqual(metrics.completedPrayers(on: refreshed, calendar: calendar), 5)
        XCTAssertEqual(metrics.zikrCompletions(on: refreshed, calendar: calendar), 2)
        let tomorrow = refreshed.addingTimeInterval(86_400)
        XCTAssertEqual(metrics.completedPrayers(on: tomorrow, calendar: calendar), 0)
        XCTAssertEqual(metrics.zikrCompletions(on: tomorrow, calendar: calendar), 0)
    }

    /// "Today's times" are the place's day, as in the app, not the phone's.
    func testTodaysTimesAreThePlacesDay() {
        // 23:30 in Karachi on the 15th is 13:30 in New York on the 15th, and
        // 01:30 Karachi on the 16th is 15:30 New York on the 15th.
        let lateKarachi = TestDates.make(year: 2026, month: 1, day: 15, hour: 23, minute: 30, timeZone: TestDates.karachi)
        let earlyNextKarachi = TestDates.make(year: 2026, month: 1, day: 16, hour: 1, minute: 30, timeZone: TestDates.karachi)
        let snapshot = PrayerWidgetSnapshot(
            generatedAt: lateKarachi,
            placeName: "Karachi",
            upcomingTimes: [
                WidgetPrayerTime(prayerKey: "isha", displayName: "Isha", time: lateKarachi, isObligatory: true),
                WidgetPrayerTime(prayerKey: "fajr", displayName: "Fajr", time: earlyNextKarachi, isObligatory: true),
            ],
            hijriDateText: "",
            suhoorEndsAt: nil,
            iftarAt: nil,
            timeZoneIdentifier: "Asia/Karachi"
        )
        XCTAssertEqual(snapshot.times(onSameDayAs: lateKarachi).map(\.prayerKey), ["isha"])
        XCTAssertEqual(snapshot.times(onSameDayAs: earlyNextKarachi).map(\.prayerKey), ["fajr"])
        XCTAssertEqual(snapshot.startOfNextDay(after: lateKarachi), TestDates.make(year: 2026, month: 1, day: 16, hour: 0, minute: 0, timeZone: TestDates.karachi))
    }
}
