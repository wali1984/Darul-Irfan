import Foundation
import Observation

/// State for the Zikr home screen: the online zikr schedule (from bundled
/// seed data, remotely updatable via the content manifest) and per-session
/// reminder toggles persisted in UserDefaults.
@Observable
@MainActor
final class ZikrHomeViewModel {
    private let notifications: any NotificationScheduling
    private let platform: OfficialPlatformService
    private let watchSync: WatchSyncService

    private(set) var sessions: [ZikrSession] = []
    private(set) var nextOccurrences: [String: Date] = [:]
    private(set) var reminderEnabled: [String: Bool] = [:]
    private(set) var isLoaded = false
    private(set) var live: LiveBroadcast = .offline
    /// Latest official videos, shown as in-app playable "Recent Bayans" so the
    /// section is useful even when no live session is on air.
    private(set) var recentBayans: [OfficialFeedItem] = []
    var showPermissionAlert = false

    /// Minutes before the session start that the reminder fires.
    private let reminderLeadMinutes = 10

    init(notifications: any NotificationScheduling, platform: OfficialPlatformService, watchSync: WatchSyncService) {
        self.notifications = notifications
        self.platform = platform
        self.watchSync = watchSync
    }

    func load() async {
        let bootstrap = await platform.bootstrap(forceRefresh: false)
        live = await platform.currentLiveBroadcast(forceRefresh: false)
        if let page = try? await platform.feed(after: nil, forceRefresh: false) {
            recentBayans = Array(page.items.filter { $0.videoID != nil }.prefix(6))
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
        // A reachable control plane with no active schedule is authoritative:
        // do not resurrect the old approximate timings that conflicted with
        // the official site. Bundled sessions are used only for a true
        // first-launch/offline fallback and are labelled for verification.
        let loaded: [ZikrSession]
        if !remote.isEmpty {
            loaded = remote
        } else if bootstrap.generatedAt == .distantPast {
            loaded = SeedBundle.zikrSessions().map { session in
                var fallback = session
                fallback.availabilityNote = String(localized: "Offline fallback timing — pull down later to verify the current schedule before joining.")
                return fallback
            }
        } else {
            loaded = []
        }
        sessions = loaded
        watchSync.updateZikrSessions(loaded)

        var occurrences: [String: Date] = [:]
        let now = Date()
        for session in loaded {
            occurrences[session.id] = ZikrScheduleMath.nextOccurrence(of: session, after: now)
        }
        nextOccurrences = occurrences

        for session in loaded {
            let enabled = UserDefaults.standard.bool(forKey: reminderKey(session.id))
            reminderEnabled[session.id] = enabled
            if enabled {
                // Reminders are one-off notifications; refresh to the next
                // occurrence every time the screen loads so they stay current.
                await scheduleReminder(for: session)
            }
        }
        isLoaded = true
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

    private func scheduleReminder(for session: ZikrSession) async {
        // Always recompute: the occurrence cached at load() may have passed
        // while the screen stayed open. nextOccurrence(after:) is strictly
        // in the future, so a valid fire date always exists.
        let now = Date()
        guard let next = ZikrScheduleMath.nextOccurrence(of: session, after: now) else { return }
        nextOccurrences[session.id] = next

        var fireDate = next.addingTimeInterval(TimeInterval(-reminderLeadMinutes * 60))
        if fireDate <= now {
            fireDate = next
        }

        await notifications.scheduleReminder(
            id: reminderKey(session.id),
            title: session.title,
            body: String(localized: "The online zikr session begins soon. The Paltalk room opens while the session is in progress."),
            at: fireDate
        )
    }
}
