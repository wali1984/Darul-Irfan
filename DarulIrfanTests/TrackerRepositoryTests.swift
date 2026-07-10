import Foundation
import XCTest
@testable import DarulIrfan

/// Tests for `TrackerRepository`: prayer log upserts and the streak summary
/// math (current streak, best streak, completion rate) plus the other
/// tracker tables, against an in-memory store.
final class TrackerRepositoryTests: XCTestCase {

    private var database: AppDatabase!
    private var repository: TrackerRepository!

    override func setUp() async throws {
        database = try await AppDatabase.inMemory()
        repository = TrackerRepository(database: database)
    }

    override func tearDown() {
        repository = nil
        database = nil
    }

    // MARK: - Helpers

    /// Marks every obligatory prayer of `dayKey` as fulfilled, mixing
    /// individual and congregation marks (both count toward completion).
    private func markDayComplete(_ dayKey: String) async throws {
        for (index, prayer) in Prayer.obligatory.enumerated() {
            let completion: PrayerCompletion = index % 2 == 0 ? .prayed : .jamaat
            try await repository.savePrayerLog(PrayerLogEntry(
                dayKey: dayKey,
                prayer: prayer,
                completion: completion,
                updatedAt: Date()
            ))
        }
    }

    // MARK: - Prayer log upsert

    func testSavePrayerLogUpsertsPerDayAndPrayer() async throws {
        let dayKey = "2026-01-15"
        try await repository.savePrayerLog(PrayerLogEntry(
            dayKey: dayKey,
            prayer: .fajr,
            completion: .prayed,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        // Correcting the mark for the same day+prayer replaces the row.
        try await repository.savePrayerLog(PrayerLogEntry(
            dayKey: dayKey,
            prayer: .fajr,
            completion: .qaza,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        ))

        let entries = try await repository.prayerLog(dayKeys: [dayKey])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.completion, .qaza)

        // Unknown day keys simply return nothing; empty input short-circuits.
        let other = try await repository.prayerLog(dayKeys: ["2026-01-16"])
        XCTAssertTrue(other.isEmpty)
        let empty = try await repository.prayerLog(dayKeys: [])
        XCTAssertTrue(empty.isEmpty)
    }

    // MARK: - Streak summary

    /// Window layout (oldest → newest over 7 days ending today):
    ///   day0 ✓ complete, day1 ✓ complete, day2 — nothing (gap),
    ///   day3 partial (1 fulfilled + 1 qaza), day4 ✓, day5 ✓, day6 (today) ✓
    /// Expectations:
    ///   currentStreak = 3 (day4..day6), bestStreak = 3,
    ///   completionRate = fulfilled 26 of 35 slots.
    func testStreakSummaryWithThreeCompleteDaysAndAGap() async throws {
        let now = Date()
        let keys = DayKey.trailing(7, endingAt: now)
        XCTAssertEqual(keys.count, 7)

        try await markDayComplete(keys[0])
        try await markDayComplete(keys[1])
        // keys[2]: gap — no marks at all.
        // keys[3]: partial — one fulfilled, one qaza (qaza must not count).
        try await repository.savePrayerLog(PrayerLogEntry(
            dayKey: keys[3], prayer: .fajr, completion: .prayed, updatedAt: now
        ))
        try await repository.savePrayerLog(PrayerLogEntry(
            dayKey: keys[3], prayer: .asr, completion: .qaza, updatedAt: now
        ))
        try await markDayComplete(keys[4])
        try await markDayComplete(keys[5])
        try await markDayComplete(keys[6])

        let summary = try await repository.streakSummary(
            endingAt: keys[6],
            windowDays: 7
        )

        XCTAssertEqual(summary.windowDays, 7)
        XCTAssertEqual(summary.currentStreakDays, 3, "Streak runs day4..day6 and stops at the partial day")
        XCTAssertEqual(summary.bestStreakDays, 3, "Best run in the window is also 3 (the current one)")
        // Fulfilled: 5×5 complete days + 1 on the partial day = 26 of 7×5 = 35.
        XCTAssertEqual(summary.completionRate, 26.0 / 35.0, accuracy: 0.0001)
    }

    func testStreakSummaryEmptyWindowIsAllZeros() async throws {
        let todayKey = DayKey.make(from: Date())
        let summary = try await repository.streakSummary(endingAt: todayKey, windowDays: 7)
        XCTAssertEqual(summary.currentStreakDays, 0)
        XCTAssertEqual(summary.bestStreakDays, 0)
        XCTAssertEqual(summary.completionRate, 0, accuracy: 0.0001)
    }

    /// An in-progress today must not reset the streak: with yesterday and the
    /// day before fully complete and today unmarked, the current streak is
    /// still 2 (today is a grace day until it is over).
    func testStreakSummaryInProgressTodayDoesNotResetCurrentStreak() async throws {
        let now = Date()
        let keys = DayKey.trailing(7, endingAt: now)
        try await markDayComplete(keys[4])
        try await markDayComplete(keys[5])
        // keys[6] is today: no marks yet.

        let summary = try await repository.streakSummary(endingAt: keys[6], windowDays: 7)
        XCTAssertEqual(summary.currentStreakDays, 2, "Unmarked today gets grace; streak counts from yesterday")
        XCTAssertEqual(summary.bestStreakDays, 2)

        // A partially marked today also keeps the grace.
        try await repository.savePrayerLog(PrayerLogEntry(
            dayKey: keys[6], prayer: .fajr, completion: .prayed, updatedAt: now
        ))
        let partial = try await repository.streakSummary(endingAt: keys[6], windowDays: 7)
        XCTAssertEqual(partial.currentStreakDays, 2)
    }

    func testStreakSummaryBestRunEarlierThanCurrentRun() async throws {
        // Window of 10: a 4-day run early on, then a gap, then 2 days at the
        // end → best 4, current 2.
        let now = Date()
        let keys = DayKey.trailing(10, endingAt: now)
        for index in [0, 1, 2, 3] {
            try await markDayComplete(keys[index])
        }
        try await markDayComplete(keys[8])
        try await markDayComplete(keys[9])

        let summary = try await repository.streakSummary(endingAt: keys[9], windowDays: 10)
        XCTAssertEqual(summary.currentStreakDays, 2)
        XCTAssertEqual(summary.bestStreakDays, 4)
    }

    // MARK: - Fasting log

    func testFastingLogRoundtripAndOverwrite() async throws {
        let dayKey = "2026-03-01"
        try await repository.saveFastingLog(FastingLogEntry(
            dayKey: dayKey, fasted: true,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        try await repository.saveFastingLog(FastingLogEntry(
            dayKey: dayKey, fasted: false,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        ))

        let entries = try await repository.fastingLog(dayKeys: [dayKey])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.fasted, false)
    }

    // MARK: - Tasbih counters

    func testTasbihCounterSaveUpdateAndDelete() async throws {
        let counter = TasbihCounter(
            id: UUID(),
            title: "Astaghfirullah",
            target: 100,
            count: 33,
            lifetimeCount: 500,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await repository.saveTasbihCounter(counter)
        let counters = try await repository.tasbihCounters()
        XCTAssertEqual(counters, [counter])

        var advanced = counter
        advanced.count = 34
        advanced.lifetimeCount = 501
        advanced.updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        try await repository.saveTasbihCounter(advanced)
        let updated = try await repository.tasbihCounters()
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated.first?.count, 34)
        XCTAssertEqual(updated.first?.lifetimeCount, 501)

        try await repository.deleteTasbihCounter(id: counter.id)
        let empty = try await repository.tasbihCounters()
        XCTAssertTrue(empty.isEmpty)
    }

    // MARK: - Zikr habit

    func testZikrHabitRoundtrip() async throws {
        let dayKey = "2026-01-15"
        try await repository.saveZikrHabit(ZikrHabitEntry(
            dayKey: dayKey, completedCount: 1,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        try await repository.saveZikrHabit(ZikrHabitEntry(
            dayKey: dayKey, completedCount: 2,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        ))

        let entries = try await repository.zikrHabit(dayKeys: [dayKey])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.completedCount, 2)
    }
}
