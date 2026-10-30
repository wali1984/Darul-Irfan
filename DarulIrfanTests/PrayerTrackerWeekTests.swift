import Foundation
import XCTest
@testable import DarulIrfan

/// The prayer tracker on the Prayer times page: Saturday-to-Friday weeks
/// paged back from today and never past it, the day key each mark is saved
/// under, the order the four marks cycle in, and the lock on days after
/// today. Then Today's two other pure pieces: the prayer ring and the live
/// strip.
final class PrayerTrackerWeekTests: XCTestCase {

    private let utc = PrayerTrackerCalendar.calendar(timeZone: TestDates.utc)

    private func keys(_ days: [Date], in timeZone: TimeZone = TestDates.utc) -> [String] {
        days.map { DayKey.make(from: $0, timeZone: timeZone) }
    }

    private func key(_ day: Date) -> String {
        DayKey.make(from: day, timeZone: TestDates.utc)
    }

    // MARK: - Mark cycling

    func testMarksCycleInTheTrackersOrder() {
        XCTAssertEqual(PrayerTrackerCalendar.nextMark(after: .unmarked), .prayed)
        XCTAssertEqual(PrayerTrackerCalendar.nextMark(after: .prayed), .jamaat)
        XCTAssertEqual(PrayerTrackerCalendar.nextMark(after: .jamaat), .qaza)
        XCTAssertEqual(PrayerTrackerCalendar.nextMark(after: .qaza), .unmarked)

        // Four taps bring a prayer back to where it started.
        var mark = PrayerCompletion.unmarked
        for _ in 0..<4 {
            mark = PrayerTrackerCalendar.nextMark(after: mark)
        }
        XCTAssertEqual(mark, .unmarked)
    }

    // MARK: - Week paging

    func testCurrentWeekRunsSaturdayToFridayAndHoldsToday() {
        // Friday 30 October 2026 closes its week.
        let today = TestDates.make(year: 2026, month: 10, day: 30, hour: 15, timeZone: TestDates.utc)
        let days = PrayerTrackerCalendar.days(weekOffset: 0, today: today, calendar: utc)
        XCTAssertEqual(keys(days), [
            "2026-10-24", "2026-10-25", "2026-10-26", "2026-10-27", "2026-10-28", "2026-10-29", "2026-10-30",
        ])
        // Saturday first (Gregorian weekday 7), Friday last (6).
        XCTAssertEqual(days.first.map { utc.component(.weekday, from: $0) }, 7)
        XCTAssertEqual(days.last.map { utc.component(.weekday, from: $0) }, 6)
        // Each day is the start of its day.
        for day in days {
            XCTAssertEqual(utc.startOfDay(for: day), day)
        }
    }

    func testSaturdayBeginsANewWeek() {
        let saturday = TestDates.make(year: 2026, month: 10, day: 31, hour: 0, minute: 5, timeZone: TestDates.utc)
        let days = keys(PrayerTrackerCalendar.days(weekOffset: 0, today: saturday, calendar: utc))
        XCTAssertEqual(days.first, "2026-10-31")
        XCTAssertEqual(days.last, "2026-11-06")
    }

    func testPagingGoesBackAWeekAtATime() {
        let today = TestDates.make(year: 2026, month: 10, day: 30, timeZone: TestDates.utc)
        XCTAssertEqual(keys(PrayerTrackerCalendar.days(weekOffset: -1, today: today, calendar: utc)), [
            "2026-10-17", "2026-10-18", "2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23",
        ])
        let fourBack = keys(PrayerTrackerCalendar.days(weekOffset: -4, today: today, calendar: utc))
        XCTAssertEqual(fourBack.first, "2026-09-26")
        XCTAssertEqual(fourBack.last, "2026-10-02")
    }

    func testPagingNeverPassesTheCurrentWeek() {
        let today = TestDates.make(year: 2026, month: 10, day: 30, timeZone: TestDates.utc)
        XCTAssertEqual(PrayerTrackerCalendar.clampedWeekOffset(1), 0)
        XCTAssertEqual(PrayerTrackerCalendar.clampedWeekOffset(0), 0)
        XCTAssertEqual(PrayerTrackerCalendar.clampedWeekOffset(-3), -3)
        XCTAssertEqual(
            PrayerTrackerCalendar.days(weekOffset: 2, today: today, calendar: utc),
            PrayerTrackerCalendar.days(weekOffset: 0, today: today, calendar: utc)
        )
        // Next week is off on the current week, on from any earlier one.
        XCTAssertFalse(PrayerTrackerCalendar.canShowNextWeek(from: 0))
        XCTAssertFalse(PrayerTrackerCalendar.canShowNextWeek(from: 1))
        XCTAssertTrue(PrayerTrackerCalendar.canShowNextWeek(from: -1))
    }

    // MARK: - Day keys

    func testDayKeysCrossAMonthBoundary() {
        // Sunday 1 November 2026: its week began on Saturday 31 October.
        let today = TestDates.make(year: 2026, month: 11, day: 1, timeZone: TestDates.utc)
        XCTAssertEqual(PrayerTrackerCalendar.dayKeys(weekOffset: 0, today: today, calendar: utc), [
            "2026-10-31", "2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06",
        ])
        XCTAssertEqual(PrayerTrackerCalendar.dayKeys(weekOffset: -1, today: today, calendar: utc).last, "2026-10-30")
    }

    func testDayKeysCrossAYearBoundary() {
        // Friday 1 January 2027 closes a week that began in 2026.
        let today = TestDates.make(year: 2027, month: 1, day: 1, timeZone: TestDates.utc)
        XCTAssertEqual(PrayerTrackerCalendar.dayKeys(weekOffset: 0, today: today, calendar: utc), [
            "2026-12-26", "2026-12-27", "2026-12-28", "2026-12-29", "2026-12-30", "2026-12-31", "2027-01-01",
        ])
    }

    func testDayKeysFollowThePhonesTimeZone() {
        // 22:00 UTC on Friday 30 October is already 03:00 on Saturday in
        // Karachi, where a new week has begun.
        let instant = TestDates.make(year: 2026, month: 10, day: 30, hour: 22, timeZone: TestDates.utc)
        let karachi = PrayerTrackerCalendar.calendar(timeZone: TestDates.karachi)
        XCTAssertEqual(PrayerTrackerCalendar.dayKeys(weekOffset: 0, today: instant, calendar: utc).last, "2026-10-30")
        XCTAssertEqual(PrayerTrackerCalendar.dayKeys(weekOffset: 0, today: instant, calendar: karachi).first, "2026-10-31")
    }

    // MARK: - Days after today are locked

    func testDaysAfterTodayAreLocked() {
        // Wednesday 28 October: Thursday and Friday have not come.
        let today = TestDates.make(year: 2026, month: 10, day: 28, hour: 9, timeZone: TestDates.utc)
        let days = PrayerTrackerCalendar.days(weekOffset: 0, today: today, calendar: utc)
        let markable = days.map { PrayerTrackerCalendar.isMarkable($0, today: today, calendar: utc) }
        XCTAssertEqual(markable, [true, true, true, true, true, false, false])
        // Late tonight is still today.
        let lateToday = TestDates.make(year: 2026, month: 10, day: 28, hour: 23, minute: 59, timeZone: TestDates.utc)
        XCTAssertTrue(PrayerTrackerCalendar.isMarkable(lateToday, today: today, calendar: utc))
        // Every day of an earlier week can be marked.
        let lastWeek = PrayerTrackerCalendar.days(weekOffset: -1, today: today, calendar: utc)
        XCTAssertTrue(lastWeek.allSatisfy { PrayerTrackerCalendar.isMarkable($0, today: today, calendar: utc) })
    }

    func testNoEntryIsMadeForADayAfterToday() {
        let now = TestDates.make(year: 2026, month: 10, day: 28, hour: 9, timeZone: TestDates.utc)
        let tomorrow = TestDates.make(year: 2026, month: 10, day: 29, hour: 1, timeZone: TestDates.utc)
        XCTAssertNil(PrayerTrackerCalendar.entry(cycling: .unmarked, for: .fajr, on: tomorrow, now: now, timeZone: TestDates.utc))
        XCTAssertNil(PrayerTrackerCalendar.entry(cycling: .qaza, for: .isha, on: tomorrow, now: now, timeZone: TestDates.utc))
    }

    func testAnEarlierDaysEntryCarriesThatDaysKeyAndTheNextMark() throws {
        let now = TestDates.make(year: 2026, month: 10, day: 30, hour: 9, timeZone: TestDates.utc)
        let tuesday = TestDates.make(year: 2026, month: 10, day: 27, timeZone: TestDates.utc)
        let entry = try XCTUnwrap(
            PrayerTrackerCalendar.entry(cycling: .prayed, for: .asr, on: tuesday, now: now, timeZone: TestDates.utc)
        )
        XCTAssertEqual(entry.dayKey, "2026-10-27")
        XCTAssertEqual(entry.prayer, .asr)
        XCTAssertEqual(entry.completion, .jamaat)
        XCTAssertEqual(entry.updatedAt, now)
        XCTAssertEqual(entry.id, "2026-10-27|asr")

        // Today's mark is made exactly as it always was.
        let todays = try XCTUnwrap(
            PrayerTrackerCalendar.entry(cycling: .unmarked, for: .fajr, on: now, now: now, timeZone: TestDates.utc)
        )
        XCTAssertEqual(todays.dayKey, "2026-10-30")
        XCTAssertEqual(todays.completion, .prayed)
    }

    // MARK: - The day shown

    func testTheShownDayFollowsTheWeek() {
        let today = TestDates.make(year: 2026, month: 10, day: 28, hour: 9, timeZone: TestDates.utc)
        // Nothing chosen: today in this week, Friday in an earlier one.
        XCTAssertEqual(key(PrayerTrackerCalendar.shownDay(selected: nil, weekOffset: 0, today: today, calendar: utc)), "2026-10-28")
        XCTAssertEqual(key(PrayerTrackerCalendar.shownDay(selected: nil, weekOffset: -1, today: today, calendar: utc)), "2026-10-23")
        // A chosen day in the week is kept, whatever its time of day.
        let monday = TestDates.make(year: 2026, month: 10, day: 26, hour: 18, timeZone: TestDates.utc)
        XCTAssertEqual(key(PrayerTrackerCalendar.shownDay(selected: monday, weekOffset: 0, today: today, calendar: utc)), "2026-10-26")
        // A day after today, or a day of another week, gives way.
        let friday = TestDates.make(year: 2026, month: 10, day: 30, timeZone: TestDates.utc)
        XCTAssertEqual(key(PrayerTrackerCalendar.shownDay(selected: friday, weekOffset: 0, today: today, calendar: utc)), "2026-10-28")
        XCTAssertEqual(key(PrayerTrackerCalendar.shownDay(selected: monday, weekOffset: -1, today: today, calendar: utc)), "2026-10-23")
    }

    // MARK: - Reading a week while marking

    /// A week read from the tracker never puts an older mark back over one
    /// made while the read was in flight, and leaves other weeks alone.
    func testAWeeksReadKeepsMarksMadeWhileItWasInFlight() {
        let stored = [
            PrayerLogEntry(dayKey: "2026-10-27", prayer: .fajr, completion: .prayed, updatedAt: Date(timeIntervalSince1970: 0)),
            PrayerLogEntry(dayKey: "2026-10-28", prayer: .asr, completion: .qaza, updatedAt: Date(timeIntervalSince1970: 0)),
        ]
        // Tuesday's Fajr was marked in congregation during the read.
        let onScreen: [String: [Prayer: PrayerCompletion]] = [
            "2026-10-27": [.fajr: .jamaat],
            "2026-10-20": [.isha: .prayed],
        ]
        let merged = PrayerTrackerCalendar.merge(
            read: stored,
            keys: ["2026-10-26", "2026-10-27", "2026-10-28"],
            into: onScreen,
            changedDuringRead: ["2026-10-27"]
        )
        XCTAssertEqual(merged["2026-10-27"], [.fajr: .jamaat], "The newer mark stays")
        XCTAssertEqual(merged["2026-10-28"], [.asr: .qaza], "Stored marks arrive")
        XCTAssertEqual(merged["2026-10-26"], [:], "A day with nothing stored has no marks")
        XCTAssertEqual(merged["2026-10-20"], [.isha: .prayed], "A day outside the read is untouched")

        // Nothing marked meanwhile: the stored marks win everywhere read.
        let plain = PrayerTrackerCalendar.merge(read: stored, keys: ["2026-10-27"], into: onScreen, changedDuringRead: [])
        XCTAssertEqual(plain["2026-10-27"], [.fajr: .prayed])
    }

    // MARK: - Saving an earlier day

    /// A past day's mark goes through the same repository write as today's,
    /// under that day's key, and never disturbs today's row.
    func testAnEarlierDaysMarkIsSavedBesideTodaysThroughTheTrackerRepository() async throws {
        let database = try await AppDatabase.inMemory()
        let repository = TrackerRepository(database: database)
        let now = Date()
        let calendar = PrayerTrackerCalendar.calendar()
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let todayKey = DayKey.make(from: now)
        let yesterdayKey = DayKey.make(from: yesterday)

        let todays = try XCTUnwrap(PrayerTrackerCalendar.entry(cycling: .unmarked, for: .fajr, on: now, now: now))
        let earlier = try XCTUnwrap(PrayerTrackerCalendar.entry(cycling: .prayed, for: .fajr, on: yesterday, now: now))
        XCTAssertEqual(todays.dayKey, todayKey)
        XCTAssertEqual(earlier.dayKey, yesterdayKey)
        try await repository.savePrayerLog(todays)
        try await repository.savePrayerLog(earlier)

        let readToday = try await repository.prayerLog(dayKeys: [todayKey])
        let readYesterday = try await repository.prayerLog(dayKeys: [yesterdayKey])
        XCTAssertEqual(readToday.map(\.completion), [.prayed])
        XCTAssertEqual(readYesterday.map(\.completion), [.jamaat])

        // Cycling the earlier day again replaces its row and leaves today's.
        let again = try XCTUnwrap(PrayerTrackerCalendar.entry(cycling: .jamaat, for: .fajr, on: yesterday, now: now))
        try await repository.savePrayerLog(again)
        let rereadYesterday = try await repository.prayerLog(dayKeys: [yesterdayKey])
        let rereadToday = try await repository.prayerLog(dayKeys: [todayKey])
        XCTAssertEqual(rereadYesterday.map(\.completion), [.qaza])
        XCTAssertEqual(rereadToday.map(\.completion), [.prayed])
    }

    // MARK: - Today's prayer ring

    func testRingRunsFromTheLastTimeToTheNextPrayer() {
        let dayStart = TestDates.make(year: 2026, month: 10, day: 30, hour: 0, timeZone: TestDates.utc)
        let fajr = TestDates.make(year: 2026, month: 10, day: 30, hour: 5, timeZone: TestDates.utc)
        let sunrise = TestDates.make(year: 2026, month: 10, day: 30, hour: 6, timeZone: TestDates.utc)
        let dhuhr = TestDates.make(year: 2026, month: 10, day: 30, hour: 12, timeZone: TestDates.utc)
        let times = [fajr, sunrise, dhuhr]

        // Halfway from sunrise (6:00) to Dhuhr (12:00).
        let nine = TestDates.make(year: 2026, month: 10, day: 30, hour: 9, timeZone: TestDates.utc)
        XCTAssertEqual(
            TodayHeroMath.ringProgress(now: nine, next: dhuhr, earlierTimes: times, dayStart: dayStart),
            0.5,
            accuracy: 0.0001
        )
        // Before Fajr it runs from the start of the day.
        let early = TestDates.make(year: 2026, month: 10, day: 30, hour: 2, minute: 30, timeZone: TestDates.utc)
        XCTAssertEqual(
            TodayHeroMath.ringProgress(now: early, next: fajr, earlierTimes: times, dayStart: dayStart),
            0.5,
            accuracy: 0.0001
        )
        // Never outside 0...1.
        XCTAssertEqual(
            TodayHeroMath.ringProgress(now: dhuhr, next: dhuhr, earlierTimes: times, dayStart: dayStart),
            0,
            accuracy: 0.0001
        )
    }

    // MARK: - Today's live strip

    func testLiveStripShowsDailyZikrOnlyWithSomethingToPlay() {
        let evening = TestDates.make(year: 2026, month: 10, day: 30, hour: 21, timeZone: TestDates.karachi)
        var live = LiveBroadcast.offline
        XCTAssertNil(TodayLiveStrip.strip(for: live, at: evening))

        live.state = .live
        XCTAssertNil(TodayLiveStrip.strip(for: live, at: evening), "Live with nothing the app can play shows no strip")

        let url = URL(string: "https://www.youtube.com/watch?v=abc123") ?? URL(fileURLWithPath: "/")
        let video = LiveSource(kind: .youtube, url: url, videoID: "abc123", supportsBackgroundAudio: false)
        live.sources = [video]
        XCTAssertEqual(TodayLiveStrip.strip(for: live, at: evening), .dailyZikr(title: live.title, source: video))

        live.state = .ended
        XCTAssertNil(TodayLiveStrip.strip(for: live, at: evening))
    }

    func testLiveStripShowsTheTahajjudRoomOnlyBeforeDawnInPakistan() {
        let room = URL(string: "https://paltalk.im/egnMPD3Y") ?? URL(fileURLWithPath: "/")
        var live = LiveBroadcast.offline
        live.room = LiveRoom(platform: "paltalk", listeners: 12, since: nil, url: room)
        let beforeDawn = TestDates.make(year: 2026, month: 10, day: 30, hour: 4, timeZone: TestDates.karachi)
        let evening = TestDates.make(year: 2026, month: 10, day: 30, hour: 20, timeZone: TestDates.karachi)
        XCTAssertEqual(TodayLiveStrip.strip(for: live, at: beforeDawn), .tahajjud(room: room))
        // The same room carries Daily Zikr in the evening; that is not the
        // Tahajjud zikr.
        XCTAssertNil(TodayLiveStrip.strip(for: live, at: evening))
    }
}
