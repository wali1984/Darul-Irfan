import Foundation
import Observation

/// State for the Zikr home screen: the online zikr schedule (from bundled
/// seed data, remotely updatable via the content manifest) and per-session
/// reminder toggles persisted in UserDefaults.
@Observable
@MainActor
final class ZikrHomeViewModel {
    private let notifications: any NotificationScheduling

    private(set) var sessions: [ZikrSession] = []
    private(set) var nextOccurrences: [String: Date] = [:]
    private(set) var reminderEnabled: [String: Bool] = [:]
    private(set) var isLoaded = false
    var showPermissionAlert = false

    /// Minutes before the session start that the reminder fires.
    private let reminderLeadMinutes = 10

    init(notifications: any NotificationScheduling) {
        self.notifications = notifications
    }

    func load() async {
        let loaded: [ZikrSession] = (try? SeedBundle.zikrSessions()) ?? []
        sessions = loaded

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
        let now = Date()
        guard let next = nextOccurrences[session.id]
                ?? ZikrScheduleMath.nextOccurrence(of: session, after: now) else { return }

        var fireDate = next.addingTimeInterval(TimeInterval(-reminderLeadMinutes * 60))
        if fireDate <= now {
            fireDate = next
        }
        guard fireDate > now else { return }

        await notifications.scheduleReminder(
            id: reminderKey(session.id),
            title: session.title,
            body: String(localized: "The online zikr session begins soon. The Paltalk room opens while the session is in progress."),
            at: fireDate
        )
    }
}
