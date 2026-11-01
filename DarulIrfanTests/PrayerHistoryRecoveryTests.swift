import XCTest
@testable import DarulIrfan

private actor HistoryRepository: TrackerRepositoryProtocol {
    var failSummary = false
    var delayWeek = false
    private var pending: CheckedContinuation<[PrayerLogEntry], Error>?
    private var started: CheckedContinuation<Void, Never>?
    func setFailure(_ value: Bool) { failSummary = value }
    func delayNextWeek() { delayWeek = true }
    func prayerLog(dayKeys: [String]) async throws -> [PrayerLogEntry] {
        if delayWeek && dayKeys.count == 7 {
            delayWeek = false
            return try await withCheckedThrowingContinuation {
                pending = $0; started?.resume(); started = nil
            }
        }
        return []
    }
    func waitForWeek() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finishWeek() { pending?.resume(returning: []); pending = nil }
    func streakSummary(endingAt endDayKey: String, windowDays: Int) async throws -> PrayerStreakSummary {
        if failSummary { throw URLError(.cannotLoadFromNetwork) }
        return PrayerStreakSummary(currentStreakDays: 0, bestStreakDays: 0, completionRate: 0, windowDays: windowDays)
    }
    func savePrayerLog(_ entry: PrayerLogEntry) async throws { }
    func fastingLog(dayKeys: [String]) async throws -> [FastingLogEntry] { [] }
    func saveFastingLog(_ entry: FastingLogEntry) async throws { }
    func tasbihCounters() async throws -> [TasbihCounter] { [] }
    func saveTasbihCounter(_ counter: TasbihCounter) async throws { }
    func saveTasbihProgress(_ counter: TasbihCounter, completions: [String: Int]) async throws { }
    func deleteTasbihCounter(id: UUID) async throws { }
    func zikrHabit(dayKeys: [String]) async throws -> [ZikrHabitEntry] { [] }
    func saveZikrHabit(_ entry: ZikrHabitEntry) async throws { }
}

@MainActor
final class PrayerHistoryRecoveryTests: XCTestCase {
    func testFailureIsNotEmptyHistoryAndRetryPublishesCompleteSnapshot() async {
        let repo = HistoryRepository()
        let model = PrayerTrackerDetailViewModel(trackerRepository: repo)
        await repo.setFailure(true)
        await model.reload()
        XCTAssertTrue(model.failed)
        XCTAssertNil(model.loadedWindow)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertFalse(model.isLoading)
        await repo.setFailure(false)
        await model.reload()
        XCTAssertEqual(model.rows.count, 7)
        XCTAssertEqual(model.summary?.windowDays, 7)
        XCTAssertFalse(model.failed)
        model.window = .month
        await repo.setFailure(true)
        await model.reload()
        XCTAssertEqual(model.loadedWindow, .week)
        XCTAssertEqual(model.rows.count, 7)
        XCTAssertEqual(model.summary?.windowDays, 7)
        XCTAssertTrue(model.failed)
    }

    func testLateWeekCannotOverwriteMonth() async {
        let repo = HistoryRepository()
        let model = PrayerTrackerDetailViewModel(trackerRepository: repo)
        await repo.delayNextWeek()
        let first = Task { await model.reload() }
        await repo.waitForWeek()
        model.window = .month
        await model.reload()
        await repo.finishWeek()
        await first.value
        XCTAssertEqual(model.rows.count, 30)
        XCTAssertEqual(model.summary?.windowDays, 30)
        XCTAssertEqual(model.loadedWindow, .month)
        XCTAssertFalse(model.isLoading)
    }

    func testCancellationDoesNotPublishOrReportFailure() async {
        let repo = HistoryRepository()
        let model = PrayerTrackerDetailViewModel(trackerRepository: repo)
        await repo.delayNextWeek()
        let task = Task { await model.reload() }
        await repo.waitForWeek()
        task.cancel()
        await repo.finishWeek()
        await task.value
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.loadedWindow)
        XCTAssertFalse(model.failed)
        XCTAssertFalse(model.isLoading)
    }
}
