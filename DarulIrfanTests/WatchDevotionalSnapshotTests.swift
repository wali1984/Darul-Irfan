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
}
