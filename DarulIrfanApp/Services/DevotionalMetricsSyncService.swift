import Foundation
import WidgetKit

/// Builds one compact on-device summary for widgets and Apple Watch.
/// Repositories remain the source of truth; this service never uploads data.
@MainActor
final class DevotionalMetricsSyncService {
    private let quranRepository: any QuranRepositoryProtocol
    private let trackerRepository: any TrackerRepositoryProtocol
    private let watchSync: WatchSyncService

    init(
        quranRepository: any QuranRepositoryProtocol,
        trackerRepository: any TrackerRepositoryProtocol,
        watchSync: WatchSyncService
    ) {
        self.quranRepository = quranRepository
        self.trackerRepository = trackerRepository
        self.watchSync = watchSync
    }

    func refresh(reference: Date = Date()) async {
        guard var snapshot = PrayerWidgetSnapshot.load() else { return }

        let dayKey = DayKey.make(from: reference)
        let prayerRows = (try? await trackerRepository.prayerLog(dayKeys: [dayKey])) ?? []
        let summary = try? await trackerRepository.streakSummary(endingAt: dayKey, windowDays: 30)
        let lastRead = try? await quranRepository.lastReadPosition()
        let counters = (try? await trackerRepository.tasbihCounters()) ?? []
        let zikrHabit = (try? await trackerRepository.zikrHabit(dayKeys: [dayKey]))?.first

        let completed = prayerRows.filter { row in
            switch row.completion {
            case .unmarked: return false
            case .prayed, .jamaat: return true
            case .qaza: return false
            }
        }.count
        let activeCounter = counters.max { lhs, rhs in lhs.updatedAt < rhs.updatedAt }

        snapshot.devotionalMetrics = WidgetDevotionalMetrics(
            prayersCompleted: min(completed, 5),
            prayerGoal: 5,
            prayerStreakDays: summary?.currentStreakDays ?? 0,
            prayerCompletionRate: min(max(summary?.completionRate ?? 0, 0), 1),
            quranSurahNumber: lastRead?.surahNumber,
            quranAyahNumber: lastRead?.ayahNumber,
            tasbihTitle: activeCounter?.title,
            tasbihCount: activeCounter?.count ?? 0,
            tasbihTarget: activeCounter?.target,
            zikrCompletionsToday: zikrHabit?.completedCount ?? 0,
            updatedAt: reference
        )
        snapshot.save()
        watchSync.send(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
