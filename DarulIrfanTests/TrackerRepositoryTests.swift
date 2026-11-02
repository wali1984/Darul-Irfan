import Foundation
import XCTest
@testable import DarulIrfan

/// Tests for `TrackerRepository`: prayer log upserts and the streak summary
/// math (current streak, best streak, completion rate) plus the other
/// tracker tables, against an in-memory store.
final class TrackerRepositoryTests: XCTestCase {

    @MainActor
    func testReturningTasbihScreenAdoptsOtherTabProgressWithoutOverwritingIt() async throws {
        let initial = TasbihCounter(id: UUID(), title: "Shared counter", target: 100, count: 3, lifetimeCount: 20, updatedAt: Date())
        try await repository.saveTasbihCounter(initial)
        let metrics = DevotionalMetricsSyncService(quranRepository: QuranRepository(database: database),
                                                  trackerRepository: repository, watchSync: WatchSyncService())
        let today = TasbihCounterViewModel(counter: initial, trackerRepository: repository, devotionalMetrics: metrics)
        let zikr = TasbihCounterViewModel(counter: initial, trackerRepository: repository, devotionalMetrics: metrics)
        zikr.increment()
        await zikr.persistOnExit().value
        // Merely leaving an unchanged stale screen must not write its old 3.
        await today.persistOnExit().value
        var saved = try await repository.tasbihCounters()
        XCTAssertEqual(saved.first?.count, 4)
        await today.refresh()
        XCTAssertEqual(today.counter.count, 4)
        today.increment()
        await today.persistOnExit().value
        saved = try await repository.tasbihCounters()
        XCTAssertEqual(saved.first?.count, 5)
        XCTAssertEqual(saved.first?.lifetimeCount, 20)
        XCTAssertEqual(saved.count, 1)
    }

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

    @MainActor
    func testContextualTasbihReusesMatchingProgressAndKeepsDifferentTargetsSeparate() async throws {
        let title = "Preset \(UUID().uuidString)"
        let existing = TasbihCounter(id: UUID(), title: title, target: 100, count: 23, lifetimeCount: 200, updatedAt: Date())
        try await repository.saveTasbihCounter(existing)
        let reopened = try await TasbihPresetResolver.resolve(title: title, target: 100, repository: repository)
        XCTAssertEqual(reopened, existing)
        let otherTarget = try await TasbihPresetResolver.resolve(title: title, target: 33, repository: repository)
        XCTAssertNotEqual(otherTarget.id, existing.id)
        XCTAssertEqual(otherTarget.target, 33)
        let saved = try await repository.tasbihCounters()
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.first(where: { $0.id == existing.id }), existing)
    }

    @MainActor
    func testConcurrentContextualTasbihLinksCreateOnlyOneCounter() async throws {
        let title = "Concurrent preset \(UUID().uuidString)"
        let store = try XCTUnwrap(repository)
        async let first = TasbihPresetResolver.resolve(title: title, target: 100, repository: store)
        async let second = TasbihPresetResolver.resolve(title: title, target: 100, repository: store)
        let pair = try await (first, second)
        XCTAssertEqual(pair.0.id, pair.1.id)
        let saved = try await store.tasbihCounters()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.title, title)
        XCTAssertEqual(saved.first?.target, 100)
        XCTAssertEqual(saved.first?.count, 0)
    }

    @MainActor
    func testTasbihShortcutCountsVisibleCounterAndStopsAfterLeaving() async throws {
        let initial = TasbihCounter(id: UUID(), title: "Shortcut", target: 1, count: 0, lifetimeCount: 0, updatedAt: Date())
        try await repository.saveTasbihCounter(initial)
        let metrics = DevotionalMetricsSyncService(quranRepository: QuranRepository(database: database),
                                                  trackerRepository: repository, watchSync: WatchSyncService())
        let model = TasbihCounterViewModel(counter: initial, trackerRepository: repository, devotionalMetrics: metrics)
        TasbihShortcutTarget.install(model)
        defer { TasbihShortcutTarget.remove(model) }
        try await TasbihShortcutTarget.increment()
        XCTAssertEqual(model.counter.count, 1)
        let counters = try await repository.tasbihCounters()
        let habits = try await repository.zikrHabit(dayKeys: [DayKey.make(from: Date())])
        XCTAssertEqual(counters.first?.count, 1)
        XCTAssertEqual(habits.first?.completedCount, 1)
        TasbihShortcutTarget.remove(model)
        do {
            try await TasbihShortcutTarget.increment()
            XCTFail("A shortcut must not count after leaving the counter")
        } catch { }
        XCTAssertEqual(model.counter.count, 1)
    }

    @MainActor
    func testTasbihHabitFailureRollsBackCounterAndRetryCommitsOnce() async throws {
        let day = DayKey.make(from: Date())
        let initial = TasbihCounter(id: UUID(), title: "Target", target: 8, count: 7, lifetimeCount: 9, updatedAt: Date())
        try await repository.saveTasbihCounter(initial)
        try await repository.saveZikrHabit(ZikrHabitEntry(dayKey: day, completedCount: 2, updatedAt: Date()))
        let metrics = DevotionalMetricsSyncService(quranRepository: QuranRepository(database: database),
                                                  trackerRepository: repository, watchSync: WatchSyncService())
        let model = TasbihCounterViewModel(counter: initial, trackerRepository: repository, devotionalMetrics: metrics)
        try await database.connection.executeScript("CREATE TRIGGER reject_habit BEFORE UPDATE ON zikr_habit BEGIN SELECT RAISE(ABORT, 'habit failure'); END;")
        model.increment()
        await model.persistOnExit().value
        XCTAssertTrue(model.saveFailed)
        XCTAssertEqual(model.counter.count, 8)
        let failedCounters = try await repository.tasbihCounters()
        let failedHabits = try await repository.zikrHabit(dayKeys: [day])
        XCTAssertEqual(failedCounters.first?.count, 7)
        XCTAssertEqual(failedHabits.first?.completedCount, 2)
        try await database.connection.executeScript("DROP TRIGGER reject_habit;")
        await model.retrySave()
        await model.retrySave()
        XCTAssertFalse(model.saveFailed)
        let counters = try await repository.tasbihCounters()
        let habits = try await repository.zikrHabit(dayKeys: [day])
        XCTAssertEqual(counters.first?.count, 8)
        XCTAssertEqual(counters.first?.lifetimeCount, 9)
        XCTAssertEqual(habits.first?.completedCount, 3)
    }

    @MainActor
    func testTasbihTargetResetBeforeDebounceKeepsBothCompletions() async throws {
        let initial = TasbihCounter(id: UUID(), title: "Target", target: 1, count: 0, lifetimeCount: 0, updatedAt: Date())
        try await repository.saveTasbihCounter(initial)
        let metrics = DevotionalMetricsSyncService(quranRepository: QuranRepository(database: database),
                                                  trackerRepository: repository, watchSync: WatchSyncService())
        let model = TasbihCounterViewModel(counter: initial, trackerRepository: repository, devotionalMetrics: metrics)
        model.increment()
        await model.reset()
        model.increment()
        await model.persistOnExit().value
        await model.retrySave()
        let counters = try await repository.tasbihCounters()
        let habits = try await repository.zikrHabit(dayKeys: [DayKey.make(from: Date())])
        XCTAssertEqual(counters.first?.count, 1)
        XCTAssertEqual(counters.first?.lifetimeCount, 1)
        XCTAssertEqual(habits.first?.completedCount, 2)
        XCTAssertFalse(model.saveFailed)
    }

    func testTasbihNewHabitFailureRollsBackCounter() async throws {
        let initial = TasbihCounter(id: UUID(), title: "Target", target: 1, count: 0, lifetimeCount: 0, updatedAt: Date())
        try await repository.saveTasbihCounter(initial)
        var reached = initial
        reached.count = 1
        try await database.connection.executeScript("CREATE TRIGGER reject_habit BEFORE INSERT ON zikr_habit BEGIN SELECT RAISE(ABORT, 'habit failure'); END;")
        do {
            try await repository.saveTasbihProgress(reached, completions: ["2026-11-01": 1])
            XCTFail("Both writes must roll back")
        } catch { }
        let counters = try await repository.tasbihCounters()
        let habits = try await repository.zikrHabit(dayKeys: ["2026-11-01"])
        XCTAssertEqual(counters.first?.count, 0)
        XCTAssertTrue(habits.isEmpty)
    }

    func testConcurrentTasbihTargetsAddRatherThanOverwriteDailyTotal() async throws {
        let repo = repository!
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    let counter = TasbihCounter(id: UUID(), title: "Target", target: 1, count: 1, lifetimeCount: 0, updatedAt: Date())
                    try await repo.saveTasbihProgress(counter, completions: ["2026-11-01": 1])
                }
            }
            try await group.waitForAll()
        }
        let habits = try await repository.zikrHabit(dayKeys: ["2026-11-01"])
        let counters = try await repository.tasbihCounters()
        XCTAssertEqual(habits.first?.completedCount, 12)
        XCTAssertEqual(counters.count, 12)
    }

    @MainActor
    func testTasbihBackgroundFlushFailureRemainsRetryable() async throws {
        let initial = TasbihCounter(id: UUID(), title: "Counter", target: nil, count: 7, lifetimeCount: 9, updatedAt: Date())
        try await repository.saveTasbihCounter(initial)
        let metrics = DevotionalMetricsSyncService(quranRepository: QuranRepository(database: database),
                                                  trackerRepository: repository, watchSync: WatchSyncService())
        let model = TasbihCounterViewModel(counter: initial, trackerRepository: repository, devotionalMetrics: metrics)
        try await database.connection.executeScript("CREATE TRIGGER reject_tasbih BEFORE INSERT ON tasbih_counters BEGIN SELECT RAISE(ABORT, 'test write failure'); END;")
        model.increment()
        await model.persistOnExit().value
        XCTAssertTrue(model.saveFailed)
        XCTAssertFalse(model.isRetryingSave)
        XCTAssertEqual(model.counter.count, 8)
        let beforeRetry = try await repository.tasbihCounters()
        XCTAssertEqual(beforeRetry.first?.count, 7)
        try await database.connection.executeScript("DROP TRIGGER reject_tasbih;")
        await model.retrySave()
        await model.retrySave()
        XCTAssertFalse(model.saveFailed)
        XCTAssertFalse(model.isRetryingSave)
        let saved = try await repository.tasbihCounters()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.count, 8)
        XCTAssertEqual(saved.first?.lifetimeCount, 9)
    }

    @MainActor
    func testTasbihCountSaveFailureRetainsCountAndRetryPersistsOnce() async throws {
        let initial = TasbihCounter(id: UUID(), title: "Counter", target: nil, count: 7, lifetimeCount: 9, updatedAt: Date())
        try await repository.saveTasbihCounter(initial)
        let metrics = DevotionalMetricsSyncService(quranRepository: QuranRepository(database: database),
                                                  trackerRepository: repository, watchSync: WatchSyncService())
        let model = TasbihCounterViewModel(counter: initial, trackerRepository: repository, devotionalMetrics: metrics)
        try await database.connection.executeScript("CREATE TRIGGER reject_tasbih BEFORE INSERT ON tasbih_counters BEGIN SELECT RAISE(ABORT, 'test write failure'); END;")
        model.increment()
        await model.retrySave()
        XCTAssertTrue(model.saveFailed)
        XCTAssertFalse(model.isRetryingSave)
        XCTAssertEqual(model.counter.count, 8)
        let beforeRetry = try await repository.tasbihCounters()
        XCTAssertEqual(beforeRetry.first?.count, 7)
        try await database.connection.executeScript("DROP TRIGGER reject_tasbih;")
        await model.retrySave()
        await model.retrySave()
        XCTAssertFalse(model.saveFailed)
        XCTAssertFalse(model.isRetryingSave)
        let saved = try await repository.tasbihCounters()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.count, 8)
        XCTAssertEqual(saved.first?.lifetimeCount, 9)
    }

    @MainActor
    func testTasbihEditorSaveFailurePropagatesAndRetryKeepsOneCounter() async throws {
        let metrics = DevotionalMetricsSyncService(quranRepository: QuranRepository(database: database),
                                                  trackerRepository: repository, watchSync: WatchSyncService())
        let model = TasbihListViewModel(trackerRepository: repository, devotionalMetrics: metrics)
        let draft = TasbihCounter(id: UUID(), title: "Draft", target: 100, count: 0, lifetimeCount: 0, updatedAt: Date())
        try await database.connection.executeScript("CREATE TRIGGER reject_tasbih BEFORE INSERT ON tasbih_counters BEGIN SELECT RAISE(ABORT, 'test write failure'); END;")
        do {
            try await model.save(draft)
            XCTFail("A failed write must reach the editor, not close it as successful")
        } catch { }
        let failedRows = try await repository.tasbihCounters()
        XCTAssertTrue(failedRows.isEmpty)
        try await database.connection.executeScript("DROP TRIGGER reject_tasbih;")
        try await model.save(draft)
        try await model.save(draft)
        let saved = try await repository.tasbihCounters()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.id, draft.id)
    }

    @MainActor
    func testTasbihCounterEditCommitsOnlyAfterSaveAndPreservesCounts() async throws {
        let initial = TasbihCounter(id: UUID(), title: "Original", target: 100, count: 7, lifetimeCount: 21, updatedAt: Date())
        try await repository.saveTasbihCounter(initial)
        let metrics = DevotionalMetricsSyncService(quranRepository: QuranRepository(database: database),
                                                  trackerRepository: repository, watchSync: WatchSyncService())
        let model = TasbihCounterViewModel(counter: initial, trackerRepository: repository, devotionalMetrics: metrics)
        var draft = initial
        draft.title = "Edited"
        draft.target = 200
        draft.count = 999
        draft.lifetimeCount = 999
        try await database.connection.executeScript("CREATE TRIGGER reject_tasbih BEFORE INSERT ON tasbih_counters BEGIN SELECT RAISE(ABORT, 'test write failure'); END;")
        do {
            try await model.apply(draft)
            XCTFail("A failed edit must not be accepted")
        } catch { }
        XCTAssertEqual(model.counter.title, initial.title)
        XCTAssertEqual(model.counter.count, 7)
        try await database.connection.executeScript("DROP TRIGGER reject_tasbih;")
        try await model.apply(draft)
        let saved = try await repository.tasbihCounters()
        XCTAssertEqual(saved.first?.title, "Edited")
        XCTAssertEqual(saved.first?.target, 200)
        XCTAssertEqual(saved.first?.count, 7)
        XCTAssertEqual(saved.first?.lifetimeCount, 21)
    }

    // MARK: - Helpers

    @MainActor
    func testTasbihListLoadFailureKeepsLastKnownCountersAndCanRetry() async throws {
        let draft = TasbihCounter(id: UUID(), title: "Saved", target: 100, count: 7, lifetimeCount: 21, updatedAt: Date())
        try await repository.saveTasbihCounter(draft)
        let metrics = DevotionalMetricsSyncService(quranRepository: QuranRepository(database: database),
                                                  trackerRepository: repository, watchSync: WatchSyncService())
        let model = TasbihListViewModel(trackerRepository: repository, devotionalMetrics: metrics)
        await model.load()
        XCTAssertFalse(model.loadFailed)
        try await database.connection.executeScript("ALTER TABLE tasbih_counters RENAME TO unavailable_tasbih;")
        await model.load()
        XCTAssertTrue(model.loadFailed)
        XCTAssertEqual(model.counters.first?.id, draft.id)
        try await database.connection.executeScript("ALTER TABLE unavailable_tasbih RENAME TO tasbih_counters;")
        await model.load()
        XCTAssertFalse(model.loadFailed)
        XCTAssertEqual(model.counters.first?.count, 7)
    }

    @MainActor
    func testTasbihDeleteFailurePropagatesWithoutRemovingCounter() async throws {
        let draft = TasbihCounter(id: UUID(), title: "Saved", target: 100, count: 7, lifetimeCount: 21, updatedAt: Date())
        try await repository.saveTasbihCounter(draft)
        let metrics = DevotionalMetricsSyncService(quranRepository: QuranRepository(database: database),
                                                  trackerRepository: repository, watchSync: WatchSyncService())
        let model = TasbihListViewModel(trackerRepository: repository, devotionalMetrics: metrics)
        await model.load()
        try await database.connection.executeScript("CREATE TRIGGER reject_tasbih_delete BEFORE DELETE ON tasbih_counters BEGIN SELECT RAISE(ABORT, 'test delete failure'); END;")
        do {
            try await model.delete(draft)
            XCTFail("A failed delete must be reported")
        } catch { }
        XCTAssertEqual(model.counters.first?.id, draft.id)
        let saved = try await repository.tasbihCounters()
        XCTAssertEqual(saved.count, 1)
        try await database.connection.executeScript("DROP TRIGGER reject_tasbih_delete;")
        try await model.delete(draft)
        XCTAssertTrue(model.counters.isEmpty)
    }

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
