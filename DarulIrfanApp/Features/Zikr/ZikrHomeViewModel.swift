import Foundation
import Observation

/// State for the Zikr home screen: the online zikr schedule (from bundled
/// seed data, remotely updatable via the content manifest), per-session
/// reminder toggles persisted in UserDefaults, the live broadcast, the
/// recorded zikr and recent bayans, and the Tasbih tile's last counter.
@Observable
@MainActor
final class ZikrHomeViewModel {
    private let notifications: any NotificationScheduling
    private let platform: OfficialPlatformService
    private let watchSync: WatchSyncService
    private let prayerCalculation: any PrayerCalculationServicing
    /// The personal counters, for the Tasbih tile; nil shows no count.
    private let trackerRepository: (any TrackerRepositoryProtocol)?

    private(set) var sessions: [ZikrSession] = []
    private(set) var nextOccurrences: [String: Date] = [:]
    private(set) var reminderEnabled: [String: Bool] = [:]
    private(set) var isLoaded = false
    private(set) var live: LiveBroadcast = .offline
    /// Latest official videos, shown as in-app playable "Recent Bayans" so the
    /// section is useful even when no live session is on air.
    private(set) var recentBayans: [OfficialFeedItem] = []
    /// The channel's recordings of the daily online zikr, newest first,
    /// listed under the Daily Zikr Join button for anyone who wants to play one.
    private(set) var recordedZikr: [OfficialFeedItem] = []
    /// The signed-in member's groups where zikr (or a meeting) is live now.
    private(set) var liveGroups: [MemberGroup] = []
    /// The counter used last, shown on the Tasbih tile.
    private(set) var practice: ZikrPracticeSummary?
    var showPermissionAlert = false

    init(
        notifications: any NotificationScheduling,
        platform: OfficialPlatformService,
        watchSync: WatchSyncService,
        prayerCalculation: any PrayerCalculationServicing,
        trackerRepository: (any TrackerRepositoryProtocol)? = nil
    ) {
        self.notifications = notifications
        self.platform = platform
        self.watchSync = watchSync
        self.prayerCalculation = prayerCalculation
        self.trackerRepository = trackerRepository
    }

    /// Daily Zikr's session, shown inside the Daily Zikr card. It stays in
    /// `sessions`, which the reminders, widgets and Today follow.
    var dailySession: ZikrSession? { ZikrSessionRoles.dailySession(in: sessions) }

    /// The sessions with a card of their own: the Tahajjud zikr, and any
    /// further one the administrators publish.
    var otherSessions: [ZikrSession] { ZikrSessionRoles.otherSessions(in: sessions) }

    /// A recording of the daily online zikr, which the channel uploads every
    /// day; "Recent Bayans" lists everything else.
    static func isZikrRecording(_ item: OfficialFeedItem) -> Bool {
        item.title.localizedCaseInsensitiveContains("online zikr")
    }

    func load(forceRefresh: Bool = false) async {
        let bootstrap = await platform.bootstrap(forceRefresh: forceRefresh)
        live = await platform.currentLiveBroadcast(forceRefresh: forceRefresh)
        // The channel's uploads are mostly the daily zikr streams: they are
        // listed as recordings under the Join button, not as bayans, and the
        // feed is read on (three pages at most) until six bayans are found.
        // When no page loads, both lists keep what they showed.
        var bayans: [OfficialFeedItem]?
        var recordings: [OfficialFeedItem] = []
        var cursor: String?
        for _ in 0..<3 {
            guard let page = try? await platform.feed(after: cursor, forceRefresh: forceRefresh) else { break }
            let videos = page.items.filter { $0.videoID != nil }
            bayans = (bayans ?? []) + videos.filter { !Self.isZikrRecording($0) }
            recordings += videos.filter { Self.isZikrRecording($0) }
            guard (bayans?.count ?? 0) < 6, let next = page.nextCursor else { break }
            cursor = next
        }
        if let bayans {
            recentBayans = Array(bayans.prefix(6))
            recordedZikr = Array(recordings.sorted { $0.publishedAt > $1.publishedAt }.prefix(10))
        }
        let remote = bootstrap.schedules.map { schedule in
            ZikrSession(
                id: schedule.id,
                title: schedule.title,
                weekdays: schedule.weekdays,
                startHour: schedule.startHour,
                startMinute: schedule.startMinute,
                durationMinutes: schedule.durationMinutes,
                timeZoneIdentifier: schedule.timeZoneIdentifier,
                joinUrl: schedule.joinURL?.absoluteString,
                instructions: schedule.instructions,
                availabilityNote: schedule.availabilityNote,
                sourceUrl: nil
            )
        }
        // A schedule the administrators publish wins. Without one, the
        // bundled sessions are the official schedule itself - "After Isha and
        // Tahajjud (Pakistan Time)", from naqshbandiaowaisiah.org - computed
        // at Dar-ul-Irfan for today rather than a fixed guess. (A reachable
        // control plane with no schedule used to blank the section; it has
        // published none, so every tester saw "Schedule not available".)
        let now = Date()
        let source = remote.isEmpty ? SeedBundle.zikrSessions() : remote
        let loaded = source.map { ZikrAnchorResolver.resolved($0, at: now, calculator: prayerCalculation) }
        sessions = loaded
        watchSync.updateZikrSessions(loaded)

        var occurrences: [String: Date] = [:]
        for session in loaded {
            occurrences[session.id] = ZikrScheduleMath.nextOccurrence(of: session, after: now)
        }
        nextOccurrences = occurrences

        for session in loaded {
            let enabled = UserDefaults.standard.bool(forKey: reminderKey(session.id))
            reminderEnabled[session.id] = enabled
            if enabled {
                // Each reminder is a one-off notification: refresh the coming
                // week of them every time the screen loads.
                await scheduleReminder(for: session)
            }
        }
        isLoaded = true
    }

    /// Keeps the live state current while the screen is open, so a session's
    /// Join turns on when its video goes live or its room opens: every 10
    /// seconds during the broadcast, so the host's cue shows promptly, and
    /// every 30 otherwise.
    func followLive() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(live.state == .live ? 10 : 30))
            if Task.isCancelled { break }
            live = await platform.currentLiveBroadcast(forceRefresh: true)
        }
    }

    /// Keeps the live halqahs current while the screen is open.
    func followLiveGroups(service: MemberGroupService) async {
        while !Task.isCancelled {
            await refreshLiveGroups(service: service)
            try? await Task.sleep(for: .seconds(30))
        }
    }

    /// Re-reads the counters, so the Tasbih tile shows the count left on
    /// returning from them.
    func refreshPractice() async {
        guard let trackerRepository else {
            practice = nil
            return
        }
        let counters = (try? await trackerRepository.tasbihCounters()) ?? []
        practice = ZikrPracticeSummary.latest(from: counters)
    }

    func refreshLiveGroups(service: MemberGroupService) async {
        guard await service.isSignedIn, let list = try? await service.groups() else {
            liveGroups = []
            return
        }
        liveGroups = list.groups.filter { $0.isLive == true }
    }

    func isReminderEnabled(_ sessionID: String) -> Bool {
        reminderEnabled[sessionID] ?? false
    }

    func nextOccurrence(forSessionID sessionID: String) -> Date? {
        nextOccurrences[sessionID]
    }

    func setReminder(_ enabled: Bool, for session: ZikrSession) async {
        if enabled {
            let granted = await notifications.requestPermission()
            guard granted else {
                reminderEnabled[session.id] = false
                UserDefaults.standard.set(false, forKey: reminderKey(session.id))
                showPermissionAlert = true
                return
            }
            reminderEnabled[session.id] = true
            UserDefaults.standard.set(true, forKey: reminderKey(session.id))
            await scheduleReminder(for: session)
        } else {
            reminderEnabled[session.id] = false
            UserDefaults.standard.set(false, forKey: reminderKey(session.id))
            await notifications.cancelReminder(id: reminderKey(session.id))
        }
    }

    // MARK: - Private

    private func reminderKey(_ sessionID: String) -> String {
        "zikrReminder.\(sessionID)"
    }

    /// The coming week of reminders for one session. A single reminder fired
    /// once and then stayed silent until this screen was opened again; the
    /// app now also refreshes them with the prayer alerts (ZikrReminders).
    /// The Tahajjud zikr's says it is joined on Paltalk.
    private func scheduleReminder(for session: ZikrSession) async {
        // Always recompute: the occurrence cached at load() may have passed
        // while the screen stayed open.
        let now = Date()
        let current = ZikrAnchorResolver.resolved(session, at: now, calculator: prayerCalculation)
        if let next = ZikrScheduleMath.nextOccurrence(of: current, after: now) {
            nextOccurrences[session.id] = next
        }
        await ZikrReminders.schedule(
            session,
            id: reminderKey(session.id),
            body: ZikrReminders.body(for: session),
            notifications: notifications,
            calculator: prayerCalculation,
            now: now
        )
    }
}
