import Foundation
import Observation
import UIKit

// MARK: - Habit strip item

/// One day in the trailing-week zikr habit strip.
struct ZikrHabitDayItem: Identifiable, Equatable {
    let dayKey: String
    let date: Date
    let completedCount: Int
    var id: String { dayKey }
}

// MARK: - Counter list

/// State for the tasbih counter list plus the daily habit strip.
@Observable
@MainActor
final class TasbihListViewModel {
    private let trackerRepository: any TrackerRepositoryProtocol
    private let devotionalMetrics: DevotionalMetricsSyncService

    private(set) var counters: [TasbihCounter] = []
    private(set) var habitDays: [ZikrHabitDayItem] = []
    private(set) var isLoaded = false
    private(set) var loadFailed = false

    init(
        trackerRepository: any TrackerRepositoryProtocol,
        devotionalMetrics: DevotionalMetricsSyncService
    ) {
        self.trackerRepository = trackerRepository
        self.devotionalMetrics = devotionalMetrics
    }

    func load() async {
        do {
            counters = try await trackerRepository.tasbihCounters()
            loadFailed = false
        } catch {
            loadFailed = true
        }
        await loadHabitStrip()
        await devotionalMetrics.refresh()
        isLoaded = true
    }

    func save(_ counter: TasbihCounter) async throws {
        try await trackerRepository.saveTasbihCounter(counter)
        await load()
    }

    func delete(_ counter: TasbihCounter) async throws {
        try await trackerRepository.deleteTasbihCounter(id: counter.id)
        await load()
    }

    private func loadHabitStrip() async {
        let calendar = Calendar.current
        let today = Date()
        let dayKeys = DayKey.trailing(7, endingAt: today)
        var entriesByKey: [String: ZikrHabitEntry] = [:]
        if let entries = try? await trackerRepository.zikrHabit(dayKeys: dayKeys) {
            for entry in entries {
                entriesByKey[entry.dayKey] = entry
            }
        }

        var items: [ZikrHabitDayItem] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = DayKey.make(from: date)
            items.append(ZikrHabitDayItem(
                dayKey: key,
                date: date,
                completedCount: entriesByKey[key]?.completedCount ?? 0
            ))
        }
        habitDays = items
    }
}

// MARK: - Single counter

/// State for one open tasbih counter: tap counting with haptics, progress
/// toward the optional target, reset into the lifetime total, and the daily
/// habit record when the target is reached.
@Observable
@MainActor
final class TasbihCounterViewModel {
    private let trackerRepository: any TrackerRepositoryProtocol
    private let devotionalMetrics: DevotionalMetricsSyncService

    private(set) var counter: TasbihCounter
    private(set) var saveFailed = false
    private(set) var isRetryingSave = false

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var pendingCompletions: [String: Int] = [:]
    @ObservationIgnored private var hasRecordedTargetThisSession = false
    @ObservationIgnored private let tapFeedback = UIImpactFeedbackGenerator(style: .light)
    @ObservationIgnored private let targetFeedback = UINotificationFeedbackGenerator()

    init(
        counter: TasbihCounter,
        trackerRepository: any TrackerRepositoryProtocol,
        devotionalMetrics: DevotionalMetricsSyncService
    ) {
        self.counter = counter
        self.trackerRepository = trackerRepository
        self.devotionalMetrics = devotionalMetrics
        // Counts at/above target on arrival should not re-record the habit.
        if let target = counter.target, target > 0, counter.count >= target {
            hasRecordedTargetThisSession = true
        }
    }

    var progress: Double {
        guard let target = counter.target, target > 0 else { return 0 }
        return min(1.0, Double(counter.count) / Double(target))
    }

    var lifetimeTotal: Int {
        counter.lifetimeCount + counter.count
    }

    var hasReachedTarget: Bool {
        guard let target = counter.target, target > 0 else { return false }
        return counter.count >= target
    }

    func increment() {
        counter.count += 1
        counter.updatedAt = Date()
        tapFeedback.impactOccurred()

        if let target = counter.target, target > 0,
           counter.count >= target, !hasRecordedTargetThisSession {
            hasRecordedTargetThisSession = true
            targetFeedback.notificationOccurred(.success)
            pendingCompletions[DayKey.make(from: Date()), default: 0] += 1
        }
        scheduleSave()
    }

    func decrement() {
        guard counter.count > 0 else { return }
        counter.count -= 1
        counter.updatedAt = Date()
        scheduleSave()
    }

    /// Moves the current count into the lifetime total and starts fresh.
    func reset() async {
        counter.lifetimeCount += counter.count
        counter.count = 0
        counter.updatedAt = Date()
        hasRecordedTargetThisSession = false
        saveTask?.cancel()
        await persist()
    }

    /// Applies edits (title/target) coming back from the editor sheet.
    func apply(_ updated: TasbihCounter) async throws {
        saveTask?.cancel()
        await saveTask?.value
        await persist()
        if saveFailed { throw CocoaError(.fileWriteUnknown) }
        var saved = counter
        saved.title = updated.title
        saved.target = updated.target
        saved.updatedAt = Date()
        try await trackerRepository.saveTasbihCounter(saved)
        counter = saved
        saveFailed = false
        if let target = counter.target, target > 0, counter.count < target {
            hasRecordedTargetThisSession = false
        }
        await devotionalMetrics.refresh(reference: saved.updatedAt)
    }

    /// Flush when backgrounded or dismissed, retaining an actionable failure.
    @discardableResult
    func persistOnExit() -> Task<Void, Never> {
        let previous = saveTask
        previous?.cancel()
        let task = Task {
            await previous?.value
            await self.persist()
        }
        saveTask = task
        return task
    }

    func retrySave() async {
        guard !isRetryingSave else { return }
        isRetryingSave = true
        defer { isRetryingSave = false }
        saveTask?.cancel()
        await saveTask?.value
        await persist()
    }

    // MARK: - Private

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 400_000_000)
            } catch {
                return
            }
            await self?.persist()
        }
    }

    private func persist() async {
        if let pending = persistenceTask {
            await pending.value
            return
        }
        // Keep the write alive when a debounce is canceled. A committed
        // completion must be acknowledged before another write can retry it.
        let task = Task { @MainActor in
            while true {
                let snapshot = self.counter
                let completions = self.pendingCompletions
                do {
                    try await self.trackerRepository.saveTasbihProgress(snapshot, completions: completions)
                    for (day, saved) in completions {
                        let remaining = self.pendingCompletions[day, default: 0] - saved
                        if remaining > 0 { self.pendingCompletions[day] = remaining }
                        else { self.pendingCompletions.removeValue(forKey: day) }
                    }
                    if self.counter == snapshot && self.pendingCompletions.isEmpty {
                        self.saveFailed = false
                        await self.devotionalMetrics.refresh(reference: snapshot.updatedAt)
                        // Taps may arrive while refreshing metrics.
                        if self.counter == snapshot && self.pendingCompletions.isEmpty { break }
                    }
                } catch {
                    self.saveFailed = true
                    break
                }
            }
        }
        persistenceTask = task
        await task.value
        persistenceTask = nil
    }
}
