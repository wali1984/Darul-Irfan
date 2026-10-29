import Foundation
import CoreLocation

// Protocol-first service layer. Every service has a live implementation in
// Services/ and, where useful for previews/tests, a mock in
// Services/Mocks/. ViewModels depend only on these protocols, injected via
// AppDependencies.

// MARK: - Prayer calculation

protocol PrayerCalculationServicing: Sendable {
    /// Computes the schedule for one civil day at a place. Returns nil only
    /// for degenerate inputs (e.g. extreme polar dates the engine rejects).
    func schedule(
        for date: DateComponents,
        at place: PlaceCoordinate,
        preferences: PrayerCalculationPreferences
    ) -> PrayerDaySchedule?

    /// Convenience: schedules for `days` consecutive days starting at `start`
    /// (used by the notification scheduler and widget snapshot writer).
    func schedules(
        forDaysStarting start: Date,
        days: Int,
        at place: PlaceCoordinate,
        preferences: PrayerCalculationPreferences
    ) -> [PrayerDaySchedule]

    /// The next upcoming prayer at/after `reference`.
    func nextPrayer(
        after reference: Date,
        at place: PlaceCoordinate,
        preferences: PrayerCalculationPreferences
    ) -> NextPrayerInfo?
}

// MARK: - Qibla

protocol QiblaServicing: Sendable {
    /// Great-circle bearing from `place` to the Kaaba, degrees from true north.
    func qiblaDirection(from place: PlaceCoordinate) -> Double
}

// MARK: - Location

enum LocationServiceError: Error {
    case permissionDenied
    case unavailable
}

protocol LocationServicing: Sendable {
    /// Current authorization, mapped to a simple tri-state.
    var authorizationStatus: LocationAuthorizationStatus { get async }

    /// Requests when-in-use permission if not determined.
    func requestPermission() async -> LocationAuthorizationStatus

    /// One-shot device location resolved to a named place (reverse-geocoded
    /// city name; falls back to coordinates text). Never persisted by the
    /// service itself.
    func currentPlace() async throws -> PlaceCoordinate

    /// Forward-geocodes a city search string into candidate places.
    func searchPlaces(matching query: String) async throws -> [PlaceCoordinate]
}

enum LocationAuthorizationStatus: Sendable {
    case notDetermined
    case denied
    case authorized
}

// MARK: - Compass heading (Qibla screen)

/// Continuous heading updates for the compass UI.
@MainActor
protocol HeadingProviding: AnyObject {
    var isHeadingAvailable: Bool { get }
    /// Degrees from north; prefers true heading, falls back to magnetic.
    var currentHeading: Double? { get }
    /// True while `currentHeading` is magnetic rather than true north.
    /// CoreLocation gives true north only while location updates run, which
    /// needs location permission; magnetic north is off by the local
    /// declination (about 13 degrees in New York).
    var isMagneticHeading: Bool { get }
    /// Whether location permission, and so true north, is available.
    var canUseTrueNorth: Bool { get }
    /// Negative accuracy from CoreLocation means the compass needs calibration.
    var needsCalibration: Bool { get }
    func startUpdates(onChange: @escaping @MainActor () -> Void)
    func stopUpdates()
}

// MARK: - Notifications

protocol NotificationScheduling: Sendable {
    /// Requests notification permission; returns whether granted.
    func requestPermission() async -> Bool

    /// Replaces all pending prayer notifications with a rolling window
    /// derived from `schedules` and `preferences`. Stays within the iOS
    /// 64-pending-notification limit (adds a trailing "open the app to keep
    /// alerts fresh" reminder when the window is exhausted).
    func reschedulePrayerNotifications(
        schedules: [PrayerDaySchedule],
        preferences: PrayerNotificationPreferences
    ) async

    /// Schedules a one-off reminder (event, focus session, test) at `date`.
    /// Does nothing when a recurring set for `id` is already pending, since
    /// that set holds this reminder too.
    func scheduleReminder(id: String, title: String, body: String, at date: Date) async

    /// Schedules one reminder per date under `id`, replacing every reminder
    /// already pending for it (a one-off or an earlier set). Each is its own
    /// one-off request, so a recurring session or task keeps reminding
    /// without the app being opened in between.
    func scheduleReminders(id: String, title: String, body: String, at dates: [Date]) async

    /// Removes the reminder for `id`, or every reminder of its recurring set.
    func cancelReminder(id: String) async

    /// Whether this app's notifications are allowed (including provisionally).
    func notificationsAllowed() async -> Bool

    /// Count of currently pending requests (used by tests/diagnostics).
    func pendingCount() async -> Int
}

// MARK: - Hijri calendar

protocol HijriCalendarServicing: Sendable {
    func hijriComponents(for date: Date, offsetDays: Int, timeZone: TimeZone) -> DateComponents
    func hijriDateText(for date: Date, offsetDays: Int, locale: Locale, timeZone: TimeZone) -> String
    func isRamadan(_ date: Date, offsetDays: Int, timeZone: TimeZone) -> Bool
    func upcomingIslamicDays(from date: Date, within days: Int, offsetDays: Int, timeZone: TimeZone) -> [(day: IslamicDay, gregorianDate: Date)]
}

extension HijriCalendarServicing {
    func hijriComponents(for date: Date, offsetDays: Int) -> DateComponents {
        hijriComponents(for: date, offsetDays: offsetDays, timeZone: .current)
    }
    func hijriDateText(for date: Date, offsetDays: Int, locale: Locale) -> String {
        hijriDateText(for: date, offsetDays: offsetDays, locale: locale, timeZone: .current)
    }
    func isRamadan(_ date: Date, offsetDays: Int) -> Bool {
        isRamadan(date, offsetDays: offsetDays, timeZone: .current)
    }
    func upcomingIslamicDays(from date: Date, within days: Int, offsetDays: Int) -> [(day: IslamicDay, gregorianDate: Date)] {
        upcomingIslamicDays(from: date, within: days, offsetDays: offsetDays, timeZone: .current)
    }
}

// MARK: - Audio playback

/// Item queued into the shared audio player.
struct AudioPlayableItem: Sendable, Equatable, Identifiable {
    var id: String
    var title: String
    var subtitle: String?
    /// Local file URL (downloaded) or remote stream URL.
    var url: URL
    var mediaItemID: String?
}

@MainActor
protocol AudioPlayerServicing: AnyObject {
    var nowPlaying: AudioPlayableItem? { get }
    var isPlaying: Bool { get }
    var isBuffering: Bool { get }
    var playbackError: String? { get }
    var currentTime: Double { get }
    var duration: Double { get }
    var playbackSpeed: PlaybackSpeed { get set }
    var queue: [AudioPlayableItem] { get }

    func play(_ item: AudioPlayableItem, queue: [AudioPlayableItem])
    func togglePlayPause()
    func seek(to seconds: Double)
    func skipForward(_ seconds: Double)
    func skipBackward(_ seconds: Double)
    func playNext()
    func playPrevious()
    func stop()

    /// Called by the app on scene-background to persist progress.
    func snapshotProgress() -> PlaybackProgress?
}

// MARK: - Downloads

@MainActor
protocol DownloadManaging: AnyObject {
    /// Active + queued downloads keyed by remote URL string.
    var activeDownloads: [String: Double] { get }

    func download(url: URL, forContentItem contentItemID: String?, mediaItemID: String?) async throws -> DownloadedAsset
    func cancelDownload(url: URL)
    func deleteAsset(_ asset: DownloadedAsset) async throws
    /// Local file URL for an asset if it exists on disk.
    func localURL(for asset: DownloadedAsset) -> URL?
    /// Total bytes used by downloads (storage controls in Settings).
    func totalBytesUsed() async -> Int64
}

// MARK: - Content sync

protocol ContentSyncServicing: Sendable {
    /// Imports the parts of the bundled seed that changed since they were
    /// last imported (all of it on first launch), reporting each step that
    /// runs through `progress`. Returns the number of imported records.
    @discardableResult
    func importSeedDataIfNeeded(progress: @escaping @Sendable (SeedImportStep) async -> Void) async throws -> Int
}

extension ContentSyncServicing {
    @discardableResult
    func importSeedDataIfNeeded() async throws -> Int {
        try await importSeedDataIfNeeded(progress: { _ in })
    }
}

// MARK: - Search

protocol SearchIndexServicing: Sendable {
    /// Rebuilds/updates the FTS index for the given domains.
    func reindex(domains: [SearchDomain]) async throws

    /// FTS query across domains; empty query returns [].
    func search(_ query: String, domains: [SearchDomain], limit: Int) async throws -> [SearchResult]
}

// MARK: - Settings store

/// Persists AppSettings (key_value table) and broadcasts changes.
protocol SettingsStoring: Sendable {
    func load() async -> AppSettings
    func save(_ settings: AppSettings) async
}

// MARK: - Official platform

protocol OfficialFeedServicing: Sendable {
    func bootstrap(forceRefresh: Bool) async -> AppBootstrap
    func feed(after cursor: String?, forceRefresh: Bool) async throws -> OfficialFeedPage
}

protocol LiveBroadcastServicing: Sendable {
    func currentLiveBroadcast(forceRefresh: Bool) async -> LiveBroadcast
}

protocol PushRegistrationServicing: Sendable {
    func registerForPush(token: Data, preferences: PushPreferences) async throws
    func unregisterFromPush() async
}

protocol DiagnosticsServicing: Sendable {
    func setConsent(_ consent: DiagnosticsConsent) async
    func uploadMetricPayload(_ data: Data) async
    func uploadDiagnosticPayload(_ data: Data) async
}
