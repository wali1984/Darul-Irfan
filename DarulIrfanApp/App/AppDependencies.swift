import Foundation
import SwiftUI

/// Composition root: constructs the database, repositories, and services once
/// at launch and hands them to features. ViewModels receive what they need in
/// their initializers; nothing reaches into globals.
@MainActor
final class AppDependencies {
    // Persistence
    let database: AppDatabase

    // Repositories
    let quranRepository: any QuranRepositoryProtocol
    let contentRepository: any ContentRepositoryProtocol
    let mediaRepository: any MediaRepositoryProtocol
    let downloadsRepository: any DownloadsRepositoryProtocol
    let trackerRepository: any TrackerRepositoryProtocol
    let eventsRepository: any EventsRepositoryProtocol

    // Services
    let settingsStore: any SettingsStoring
    let prayerCalculation: any PrayerCalculationServicing
    let qibla: any QiblaServicing
    let location: any LocationServicing
    let notifications: any NotificationScheduling
    let hijri: any HijriCalendarServicing
    let audioPlayer: any AudioPlayerServicing
    let downloadManager: any DownloadManaging
    let contentSync: any ContentSyncServicing
    let searchIndex: any SearchIndexServicing

    init(
        database: AppDatabase,
        quranRepository: any QuranRepositoryProtocol,
        contentRepository: any ContentRepositoryProtocol,
        mediaRepository: any MediaRepositoryProtocol,
        downloadsRepository: any DownloadsRepositoryProtocol,
        trackerRepository: any TrackerRepositoryProtocol,
        eventsRepository: any EventsRepositoryProtocol,
        settingsStore: any SettingsStoring,
        prayerCalculation: any PrayerCalculationServicing,
        qibla: any QiblaServicing,
        location: any LocationServicing,
        notifications: any NotificationScheduling,
        hijri: any HijriCalendarServicing,
        audioPlayer: any AudioPlayerServicing,
        downloadManager: any DownloadManaging,
        contentSync: any ContentSyncServicing,
        searchIndex: any SearchIndexServicing
    ) {
        self.database = database
        self.quranRepository = quranRepository
        self.contentRepository = contentRepository
        self.mediaRepository = mediaRepository
        self.downloadsRepository = downloadsRepository
        self.trackerRepository = trackerRepository
        self.eventsRepository = eventsRepository
        self.settingsStore = settingsStore
        self.prayerCalculation = prayerCalculation
        self.qibla = qibla
        self.location = location
        self.notifications = notifications
        self.hijri = hijri
        self.audioPlayer = audioPlayer
        self.downloadManager = downloadManager
        self.contentSync = contentSync
        self.searchIndex = searchIndex
    }

    /// Builds the full live graph. Called once from DarulIrfanApp at launch.
    static func live() async throws -> AppDependencies {
        let database = try await AppDatabase.live()

        let quranRepository = QuranRepository(database: database)
        let contentRepository = ContentRepository(database: database)
        let mediaRepository = MediaRepository(database: database)
        let downloadsRepository = DownloadsRepository(database: database)
        let trackerRepository = TrackerRepository(database: database)
        let eventsRepository = EventsRepository(database: database)

        let settingsStore = SettingsStore(database: database)
        let calculation = PrayerCalculationService()
        let hijri = HijriCalendarService()
        let searchIndex = SearchIndexService(
            database: database,
            quranRepository: quranRepository,
            contentRepository: contentRepository,
            mediaRepository: mediaRepository,
            eventsRepository: eventsRepository
        )
        let contentSync = ContentSyncService(
            quranRepository: quranRepository,
            contentRepository: contentRepository,
            mediaRepository: mediaRepository,
            eventsRepository: eventsRepository,
            database: database,
            searchIndex: searchIndex
        )

        return AppDependencies(
            database: database,
            quranRepository: quranRepository,
            contentRepository: contentRepository,
            mediaRepository: mediaRepository,
            downloadsRepository: downloadsRepository,
            trackerRepository: trackerRepository,
            eventsRepository: eventsRepository,
            settingsStore: settingsStore,
            prayerCalculation: calculation,
            qibla: calculation,
            location: LocationService(),
            notifications: NotificationScheduler(),
            hijri: hijri,
            audioPlayer: AudioPlayerService(mediaRepository: mediaRepository),
            downloadManager: DownloadManager(downloadsRepository: downloadsRepository),
            contentSync: contentSync,
            searchIndex: searchIndex
        )
    }
}
