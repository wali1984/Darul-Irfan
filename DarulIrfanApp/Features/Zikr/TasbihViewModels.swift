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
        } catch {
            counters = []
        }
        await loadHabitStrip()
        await devotionalMetrics.refresh()
        isLoaded = true
    }

    func save(_ counter: TasbihCounter) async {
        do {
            try await trackerRepository.saveTasbihCounter(counter)
        } catch {
            // Local persistence failure; the list reload below shows the
            // stored truth either way.
        }
        await load()
    }

    func delete(_ counter: TasbihCounter) async {
        do {
            try await trackerRepository.deleteTasbihCounter(id: counter.id)
        } catch {
            // See note in save(_:).
        }
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

    @ObservationIgnored private var saveTask: Task<Void, Never>?
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
            Task { await self.recordHabitCompletion() }
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
    func apply(_ updated: TasbihCounter) async {
        counter = updated
        counter.updatedAt = Date()
        if let target = counter.target, target > 0, counter.count < target {
            hasRecordedTargetThisSession = false
        }
        saveTask?.cancel()
        await persist()
    }

    /// Called when the screen disappears so no taps are lost.
    func persistOnExit() {
        saveTask?.cancel()
        let snapshot = counter
        let repository = trackerRepository
        let metrics = devotionalMetrics
        Task {
            do {
                try await repository.saveTasbihCounter(snapshot)
                await metrics.refresh(reference: snapshot.updatedAt)
            } catch {
                // Local persistence failure; nothing actionable mid-dismissal.
            }
        }
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
        let snapshot = counter
        do {
            try await trackerRepository.saveTasbihCounter(snapshot)
            await devotionalMetrics.refresh(reference: snapshot.updatedAt)
        } catch {
            // Local persistence failure; the next save attempt retries.
        }
    }

    private func recordHabitCompletion() async {
        let key = DayKey.make(from: Date())
        var completed = 0
        if let existing = (try? await trackerRepository.zikrHabit(dayKeys: [key]))?.first {
            completed = existing.completedCount
        }
        let entry = ZikrHabitEntry(dayKey: key, completedCount: completed + 1, updatedAt: Date())
        do {
            try await trackerRepository.saveZikrHabit(entry)
            await devotionalMetrics.refresh(reference: entry.updatedAt)
        } catch {
            // Habit record is best-effort; the counter itself is preserved.
        }
    }
}
