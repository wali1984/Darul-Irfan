import XCTest
@testable import DarulIrfan

final class PersonalZikrTests: XCTestCase {
    private let plan = [PersonalZikrStep(stage: .latifa1), PersonalZikrStep(stage: .latifa2, minutes: 2), PersonalZikrStep(stage: .aqrabiyyat)]

    func testStageChangesAtExactBoundaryAndFinishesAfterLast() {
        XCTAssertEqual(PersonalZikrMath.position(plan, elapsed: 59.999)?.step.stage, .latifa1)
        XCTAssertEqual(PersonalZikrMath.position(plan, elapsed: 60)?.step.stage, .latifa2)
        XCTAssertEqual(PersonalZikrMath.position(plan, elapsed: 60)?.remaining, 120)
        XCTAssertNil(PersonalZikrMath.position(plan, elapsed: 240))
    }
    func testCustomMuraqabasFollowBuiltinsWithoutSharingTheirIdentity() {
        let custom = PersonalZikrStep(stage: .aqrabiyyat, minutes: 60, customID: "own", customTitle: "My Muraqaba")
        XCTAssertTrue(PersonalZikrMath.valid(plan + [custom]))
        XCTAssertFalse(PersonalZikrMath.valid([custom] + plan))
        XCTAssertFalse(PersonalZikrMath.valid(plan + [custom, custom]))
        XCTAssertEqual(PersonalZikrMath.position(plan + [custom], elapsed: 240)?.step.id, "own")
    }
    func testInvalidDurationAndReorderedStagesAreRejected() {
        XCTAssertFalse(PersonalZikrMath.valid([PersonalZikrStep(stage: .latifa1, minutes: 0)]))
        XCTAssertFalse(PersonalZikrMath.valid([PersonalZikrStep(stage: .latifa1, minutes: 61)]))
        XCTAssertFalse(PersonalZikrMath.valid(Array(plan.reversed())))
    }
    func testRestoredRunCatchesUpAndPausedTimeDoesNotCount() throws {
        let start = Date(timeIntervalSince1970: 1000)
        var run = PersonalZikrRun(plan: plan, firstStartedAt: start, startedAt: start)
        let restored = try JSONDecoder().decode(PersonalZikrRun.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(restored.elapsed(at: start.addingTimeInterval(190)), 190)
        run.elapsedBeforeRun = run.elapsed(at: start.addingTimeInterval(75))
        run.startedAt = nil
        XCTAssertEqual(run.elapsed(at: start.addingTimeInterval(900)), 75)
        run.startedAt = start.addingTimeInterval(900)
        XCTAssertEqual(run.elapsed(at: start.addingTimeInterval(901)), 76)
    }
    func testHistoryRetainsExactlyThreeCalendarMonthsAndDeduplicates() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12))!
        let cutoff = calendar.date(byAdding: .month, value: -3, to: now)!
        let kept = PersonalZikrEntry(id: "kept", startedAt: cutoff.addingTimeInterval(-60), endedAt: cutoff, duration: 60)
        let old = PersonalZikrEntry(id: "old", startedAt: cutoff.addingTimeInterval(-120), endedAt: cutoff.addingTimeInterval(-1), duration: 60)
        XCTAssertEqual(PersonalZikrHistory.retained([old, kept, kept], now: now, calendar: calendar), [kept])
    }
    func testUpcomingBannerHasNoGapOrOverlapAtStart() {
        let start = Date(timeIntervalSince1970: 10000), end = start.addingTimeInterval(1800)
        XCTAssertNil(DailyZikrBanner.phase(start: start, end: end, now: start.addingTimeInterval(-1800.001)))
        XCTAssertEqual(DailyZikrBanner.phase(start: start, end: end, now: start.addingTimeInterval(-1800)), .upcoming)
        XCTAssertEqual(DailyZikrBanner.phase(start: start, end: end, now: start.addingTimeInterval(-0.001)), .upcoming)
        XCTAssertEqual(DailyZikrBanner.phase(start: start, end: end, now: start), .live)
        XCTAssertNil(DailyZikrBanner.phase(start: start, end: end, now: end))
    }
    func testEnglishHijriUsesFullMonthName() {
        let service = HijriCalendarService()
        let date = ISO8601DateFormatter().date(from: "2026-10-30T12:00:00Z")!
        let text = service.hijriDateText(for: date, offsetDays: 0, locale: Locale(identifier: "en"), timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertTrue(text.contains("Jumada al-Awwal"), text)
    }
    func testReminderPickerKeepsSevenAMWhenDaylightSavingEnds() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let day = ISO8601DateFormatter().date(from: "2026-11-01T12:00:00Z")!
        let reminder = PersonalZikrReminder(minuteOfDay: 420)
        XCTAssertEqual(reminder.date(on: day, calendar: calendar), day)
        XCTAssertEqual(calendar.component(.hour, from: reminder.date(on: day, calendar: calendar)), 7)
    }
}
