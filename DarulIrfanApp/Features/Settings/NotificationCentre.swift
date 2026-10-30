import Foundation
import Observation
import UIKit

// What Settings > Notifications gathers besides the prayer alerts: the zikr
// reminders, the Halqah notices, the official alerts and the event reminders
// that are set. Each is the same setting, under the same key, as where it
// is also offered (the Zikr tab, the Halqah tab, a program's page); only
// where it appears is new.

// MARK: - The saved settings

/// How the alert switches change the saved settings, as the Zikr tab and
/// Official Alerts always have.
enum AlertSettingsRules {
    /// The Zikr tab's "Notify me when Daily Zikr goes live".
    static func dailyZikrLiveIsOn(_ settings: AppSettings) -> Bool {
        settings.push.isEnabled && settings.push.topics.contains(.liveZikr)
    }

    /// On turns official alerts on with the live zikr topic; off drops only
    /// that topic.
    static func setDailyZikrLive(_ enabled: Bool, in settings: inout AppSettings) {
        if enabled {
            settings.push.isEnabled = true
            settings.push.topics.insert(.liveZikr)
        } else {
            settings.push.topics.remove(.liveZikr)
        }
        settings.push.consentVersion = PushPreferences.currentConsentVersion
    }

    /// "Official live and update alerts".
    static func setOfficialAlerts(_ enabled: Bool, in settings: inout AppSettings) {
        settings.push.isEnabled = enabled
        settings.push.consentVersion = PushPreferences.currentConsentVersion
    }

    /// One of the official alert topics.
    static func setTopic(_ topic: PushTopic, _ enabled: Bool, in settings: inout AppSettings) {
        if enabled {
            settings.push.topics.insert(topic)
        } else {
            settings.push.topics.remove(topic)
        }
        settings.push.consentVersion = PushPreferences.currentConsentVersion
    }
}

/// The switches themselves: the saved setting and what goes with it (asking
/// iOS, registering the phone for its topics, or unregistering it).
@MainActor
enum OfficialAlertSwitches {
    /// Official live and update alerts. Turning them on asks iOS first and
    /// returns false when it refuses.
    static func setOfficialAlerts(_ enabled: Bool, dependencies: AppDependencies, appState: AppState) async -> Bool {
        if enabled {
            guard await dependencies.notifications.requestPermission() else { return false }
            await appState.updateSettings { settings in
                AlertSettingsRules.setOfficialAlerts(true, in: &settings)
            }
            UIApplication.shared.registerForRemoteNotifications()
        } else {
            await appState.updateSettings { settings in
                AlertSettingsRules.setOfficialAlerts(false, in: &settings)
            }
            await dependencies.officialPlatform.unregisterFromPush()
        }
        return true
    }

    /// One official alert topic. Registration carries the topics, so a
    /// change is sent the same way.
    static func setTopic(_ topic: PushTopic, _ enabled: Bool, appState: AppState) async {
        await appState.updateSettings { settings in
            AlertSettingsRules.setTopic(topic, enabled, in: &settings)
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Daily Zikr going live, as the Zikr tab's switch does it. Turning it
    /// on asks iOS first and returns false when it refuses.
    static func setDailyZikrLive(_ enabled: Bool, dependencies: AppDependencies, appState: AppState) async -> Bool {
        if enabled {
            guard await dependencies.notifications.requestPermission() else { return false }
        }
        await appState.updateSettings { settings in
            AlertSettingsRules.setDailyZikrLive(enabled, in: &settings)
        }
        UIApplication.shared.registerForRemoteNotifications()
        return true
    }

    /// Whether anonymous diagnostics are shared.
    static func setDiagnostics(_ consent: DiagnosticsConsent, dependencies: AppDependencies, appState: AppState) async {
        await appState.updateSettings { $0.diagnosticsConsent = consent }
        await dependencies.officialPlatform.setConsent(consent)
    }

    /// The next-prayer Live Activity; saving the setting starts or ends it.
    static func setLiveActivity(_ enabled: Bool, appState: AppState) async {
        await appState.updateSettings { $0.liveActivitiesEnabled = enabled }
    }
}

// MARK: - Zikr reminders

/// The official sessions' "10 minutes before" reminders, as the Zikr tab
/// keeps them: the same `zikrReminder.<session>` keys, the same week of
/// reminders, so a reminder switched on here is on in the Zikr tab too.
@MainActor
@Observable
final class ZikrReminderSettingsModel {
    private(set) var sessions: [ZikrSession] = []
    private(set) var enabled: [String: Bool] = [:]
    /// iOS refused to show notifications; the screen says so.
    var permissionDenied = false

    private let notifications: any NotificationScheduling
    private let calculator: (any PrayerCalculationServicing)?
    private let defaults: UserDefaults

    init(
        notifications: any NotificationScheduling,
        calculator: (any PrayerCalculationServicing)?,
        defaults: UserDefaults = .standard
    ) {
        self.notifications = notifications
        self.calculator = calculator
        self.defaults = defaults
    }

    /// The official sessions as the app last knew them, and which have a
    /// reminder on.
    func load(sessions: [ZikrSession] = OfficialZikrSchedule.sessions()) {
        self.sessions = sessions
        var states: [String: Bool] = [:]
        for session in sessions {
            states[session.id] = defaults.bool(forKey: ZikrReminders.reminderID(forSession: session.id))
        }
        enabled = states
    }

    func isOn(_ session: ZikrSession) -> Bool {
        enabled[session.id] ?? false
    }

    func set(_ on: Bool, for session: ZikrSession) async {
        let key = ZikrReminders.reminderID(forSession: session.id)
        if on {
            guard await notifications.requestPermission() else {
                enabled[session.id] = false
                defaults.set(false, forKey: key)
                permissionDenied = true
                return
            }
            enabled[session.id] = true
            defaults.set(true, forKey: key)
            await ZikrReminders.schedule(
                session,
                id: key,
                body: ZikrReminders.body(for: session),
                notifications: notifications,
                calculator: calculator
            )
        } else {
            enabled[session.id] = false
            defaults.set(false, forKey: key)
            await notifications.cancelReminder(id: key)
        }
    }
}

// MARK: - Event reminders

/// The programs with a reminder set, as a program's page sets it
/// ("eventReminder.<id>"), still to come.
enum EventReminderList {
    /// The key a program's page keeps its reminder under.
    static func key(forEvent eventID: String) -> String {
        "eventReminder.\(eventID)"
    }

    /// Dated programs with a reminder on that have not taken place, soonest
    /// first.
    static func upcomingWithReminders(
        in events: [CommunityEvent],
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> [CommunityEvent] {
        events
            .filter { event in
                event.startDate != nil
                    && !event.hasEnded(at: now)
                    && defaults.bool(forKey: key(forEvent: event.id))
            }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }
}
