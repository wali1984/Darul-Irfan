import Foundation
import XCTest
@testable import DarulIrfan

/// My Day planning and the personal iqamah reminder.
final class MyDayTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TestDates.karachi
        return calendar
    }

    private func schedule(on day: Date) -> PrayerDaySchedule {
        PrayerCalculationService().schedule(
            for: calendar.dateComponents([.year, .month, .day], from: day),
            at: TestPlaces.karachi,
            preferences: PrayerCalculationPreferences()
        )!
    }

    func testRepeatRules() {
        let monday = TestDates.make(year: 2026, month: 10, day: 26, timeZone: TestDates.karachi)
        let saturday = TestDates.make(year: 2026, month: 10, day: 31, timeZone: TestDates.karachi)
        let nextMonday = TestDates.make(year: 2026, month: 11, day: 2, timeZone: TestDates.karachi)
        var task = DayTask(title: "Read", startDay: monday)
        XCTAssertTrue(task.occurs(on: monday, calendar: calendar))
        XCTAssertFalse(task.occurs(on: nextMonday, calendar: calendar))
        task.repeatRule = .weekdays
        XCTAssertFalse(task.occurs(on: saturday, calendar: calendar))
        XCTAssertTrue(task.occurs(on: nextMonday, calendar: calendar))
        task.repeatRule = .weekly
        XCTAssertTrue(task.occurs(on: nextMonday, calendar: calendar))
        XCTAssertFalse(task.occurs(on: saturday, calendar: calendar))
        // Never before its start day.
        task.repeatRule = .daily
        XCTAssertFalse(task.occurs(on: monday.addingTimeInterval(-86_400), calendar: calendar))
    }

    /// "After Fajr" is that day's Fajr, not a fixed clock time.
    func testPrayerRelativeTimeFollowsThePrayer() throws {
        let day = TestDates.make(year: 2026, month: 1, day: 15, timeZone: TestDates.karachi)
        let daySchedule = schedule(on: day)
        var task = DayTask(title: "Quran", startDay: day)
        task.timing = .afterPrayer(.fajr, minutes: 15)
        let fajr = try XCTUnwrap(daySchedule.time(for: .fajr))
        XCTAssertEqual(MyDayPlanner.time(of: task, on: day, schedule: daySchedule, calendar: calendar), fajr.addingTimeInterval(900))
        task.timing = .beforePrayer(.maghrib, minutes: 10)
        let maghrib = try XCTUnwrap(daySchedule.time(for: .maghrib))
        XCTAssertEqual(MyDayPlanner.time(of: task, on: day, schedule: daySchedule, calendar: calendar), maghrib.addingTimeInterval(-600))
    }

    func testTimedTasksComeFirstInTimeOrder() {
        let day = TestDates.make(year: 2026, month: 1, day: 15, timeZone: TestDates.karachi)
        var late = DayTask(title: "Late", startDay: day); late.timing = .clock(hour: 20, minute: 0)
        var early = DayTask(title: "Early", startDay: day); early.timing = .clock(hour: 7, minute: 0)
        let whenever = DayTask(title: "Whenever", startDay: day)
        let ordered = MyDayPlanner.ordered([whenever, late, early], on: day, schedule: nil, calendar: calendar)
        XCTAssertEqual(ordered.map(\.task.title), ["Early", "Late", "Whenever"])
    }

    /// A task done today is next reminded on its next day, not later today.
    func testDoneTaskSkipsToNextDay() throws {
        let now = TestDates.make(year: 2026, month: 1, day: 15, hour: 6, minute: 0, timeZone: TestDates.karachi)
        var task = DayTask(title: "Walk", startDay: now)
        task.timing = .clock(hour: 18, minute: 0)
        task.repeatRule = .daily
        task.completedDays = [DayKey.make(from: now, timeZone: TestDates.karachi)]
        let next = try XCTUnwrap(MyDayPlanner.nextOccurrence(of: task, after: now, schedules: [], calendar: calendar))
        let tomorrowEvening = TestDates.make(year: 2026, month: 1, day: 16, hour: 18, minute: 0, timeZone: TestDates.karachi)
        XCTAssertEqual(next, tomorrowEvening)
    }

    /// A repeating task keeps reminding without the app being opened: the
    /// planner hands out its next several times, not just the first.
    func testRepeatingTaskYieldsSeveralUpcomingTimes() {
        let now = TestDates.make(year: 2026, month: 1, day: 15, hour: 6, minute: 0, timeZone: TestDates.karachi)
        var task = DayTask(title: "Walk", startDay: now)
        task.timing = .clock(hour: 18, minute: 0)
        task.repeatRule = .daily
        task.completedDays = [DayKey.make(from: now.addingTimeInterval(86_400), timeZone: TestDates.karachi)]

        let times = MyDayPlanner.occurrences(of: task, after: now, schedules: [], limit: 3, calendar: calendar)

        XCTAssertEqual(times, [
            TestDates.make(year: 2026, month: 1, day: 15, hour: 18, minute: 0, timeZone: TestDates.karachi),
            // The 16th is already done.
            TestDates.make(year: 2026, month: 1, day: 17, hour: 18, minute: 0, timeZone: TestDates.karachi),
            TestDates.make(year: 2026, month: 1, day: 18, hour: 18, minute: 0, timeZone: TestDates.karachi),
        ])
    }

    /// One entry this build cannot read costs that entry, never the whole
    /// document (every save rewrites it).
    func testDocumentDecodingSkipsAnUnreadableEntryAndFillsMissingFields() throws {
        let json = """
        {
          "tasks": [
            {"title": "Read", "startDay": "2026-01-15T00:00:00Z"},
            {"title": 42},
            {"id": "6F1C1C55-2C85-4B4E-9C8C-2B1B8E5B3D11", "title": "Walk", "startDay": "2026-01-16T00:00:00Z", "remind": true}
          ],
          "notes": [{"text": "Reflection"}, {"nope": true}],
          "fasts": {"2026-01-15": "voluntary", "2026-01-16": "unknownKind"}
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(MyDayDocument.self, from: Data(json.utf8))

        XCTAssertEqual(document.tasks.map(\.title), ["Read", "Walk"])
        XCTAssertEqual(document.tasks.first?.repeatRule, .never)
        XCTAssertEqual(document.tasks.last?.remind, true)
        XCTAssertEqual(document.notes.map(\.text), ["Reflection"])
        XCTAssertEqual(document.fasts, ["2026-01-15": .voluntary])
        XCTAssertEqual(document.version, 1)
    }

    /// A file that does not decode is set aside, not saved over.
    @MainActor
    func testUnreadableFileIsKeptAsideRatherThanOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("my_day.json")
        try Data("not json".utf8).write(to: url)

        let store = MyDayStore(fileURL: url)
        store.upsert(DayTask(title: "New", startDay: Date()))

        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("my_day.unreadable-") }, "The old file is kept")
        let reopened = MyDayStore(fileURL: url)
        reopened.loadIfNeeded()
        XCTAssertEqual(reopened.document.tasks.map(\.title), ["New"])
        try FileManager.default.removeItem(at: folder)
    }

    @MainActor
    func testStoreRoundTripsOnDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("my_day.json")
        let task = DayTask(title: "Tasbih", startDay: Date())
        let note = DayNote(text: "Reflection", reference: NoteReference(kind: .ayah, itemID: "2:255", label: "Al-Baqarah 2:255"))
        let store = MyDayStore(fileURL: url)
        store.loadIfNeeded()
        store.upsert(task)
        store.upsert(note)
        store.setFast(.voluntary, on: Date())
        let reopened = MyDayStore(fileURL: url)
        reopened.loadIfNeeded()
        XCTAssertEqual(reopened.document.tasks.map(\.title), ["Tasbih"])
        XCTAssertEqual(reopened.notes(about: try XCTUnwrap(note.reference)).count, 1)
        XCTAssertEqual(reopened.fast(on: Date()), .voluntary)
        try FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: Iqamah

    func testIqamahReminderFiresFiveMinutesBeforeIqamah() throws {
        let day = TestDates.make(year: 2026, month: 1, day: 15, hour: 0, minute: 0, timeZone: TestDates.karachi)
        let daySchedule = schedule(on: day)
        var preferences = PrayerNotificationPreferences.default
        preferences.iqamahGaps = [.asr: 15]
        let plan = PrayerNotificationPlan.build(schedules: [daySchedule], preferences: preferences, now: day)
        let iqamah = try XCTUnwrap(plan.first { $0.identifier.hasPrefix(PrayerNotificationPlan.iqamahIdentifierPrefix) })
        let asr = try XCTUnwrap(daySchedule.time(for: .asr))
        XCTAssertEqual(iqamah.fireDate, asr.addingTimeInterval(10 * 60))
        XCTAssertTrue(PrayerNotificationPlan.isPrayerIdentifier(iqamah.identifier))
        XCTAssertEqual(plan.filter { $0.identifier.hasPrefix(PrayerNotificationPlan.iqamahIdentifierPrefix) }.count, 1)
    }

    /// Settings saved before iqamah gaps existed still decode.
    func testNotificationPreferencesDecodeWithoutIqamahGaps() throws {
        let data = try JSONEncoder().encode(PrayerNotificationPreferences.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "iqamahGaps")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(PrayerNotificationPreferences.self, from: legacy)
        XCTAssertEqual(decoded.iqamahGap(for: .asr), 0)
    }
}
