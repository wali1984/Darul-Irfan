import Foundation
import UserNotifications

// Live prayer notification scheduler.
//
// Design: all planning logic (which notifications, identifiers, titles,
// fire dates, ordering, the 64-pending cap) lives in the pure
// `PrayerNotificationPlan.build` function so unit tests can exercise it
// without UserNotifications. `NotificationScheduler` is a thin layer that
// turns a plan into `UNNotificationRequest`s.
//
// Platform facts honored here (see Docs/RESEARCH_NOTES.md):
// - iOS keeps only the soonest-firing 64 pending local notifications, so the
//   plan caps itself and appends one trailing "open the app" reminder.
// - Triggers are non-repeating `UNCalendarNotificationTrigger`s with full
//   year/month/day/hour/minute components in the schedule place's timezone.
// - Custom sounds must be short PCM/IMA4 files in the main bundle; missing
//   files silently fall back to the default sound, so the azan clip is
//   resolved against the bundle at scheduling time.

// MARK: - Planned notification (pure model)

/// The sound a planned notification should carry, resolved to a concrete
/// `UNNotificationSound` only at scheduling time.
enum PlannedNotificationSound: String, Sendable, Equatable {
    /// Banner only, no sound (used for the `.silent` alert style).
    case silent
    /// The system default notification sound.
    case defaultSound
    /// The short bundled azan/chime clip, resolved against the bundle.
    case azanClip
}

/// One fully-described local notification, independent of UserNotifications.
struct PlannedNotification: Sendable, Equatable {
    var identifier: String
    var title: String
    var body: String
    var soundKind: PlannedNotificationSound
    var fireDate: Date
    /// Full year/month/day/hour/minute components (with the schedule place's
    /// timezone set) for a non-repeating calendar trigger.
    var dateComponents: DateComponents
}

// MARK: - Plan builder (pure)

/// Pure planner that converts day schedules + preferences into an ordered,
/// capped list of notifications. Unit tests target this type directly.
enum PrayerNotificationPlan {

    /// Identifier prefix for at-time prayer notifications: "prayer|<dayKey>|<prayerRaw>".
    static let prayerIdentifierPrefix = "prayer|"
    /// Identifier prefix for pre-prayer reminders: "prayer-pre|<dayKey>|<prayerRaw>".
    static let preReminderIdentifierPrefix = "prayer-pre|"
    /// Identifier of the single trailing "keep alerts fresh" reminder.
    static let refreshReminderIdentifier = "prayer-refresh"

    /// Minutes after the last planned notification at which the trailing
    /// "keep alerts fresh" reminder fires.
    static let refreshReminderDelayMinutes = 5

    /// True for identifiers owned by the prayer scheduler (and therefore safe
    /// to remove on reschedule). One-off "reminder|" requests never match.
    static func isPrayerIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(prayerIdentifierPrefix)
            || identifier.hasPrefix(preReminderIdentifierPrefix)
            || identifier == refreshReminderIdentifier
    }

    /// Builds the rolling notification plan.
    ///
    /// Rules:
    /// - For each schedule day and each prayer whose alert style is not `.off`
    ///   (sunrise is included only when the user turned its alert on) with a
    ///   fire date after `now`: one at-time notification.
    /// - A pre-reminder preference other than `.off` adds a second
    ///   notification N minutes earlier (when that instant is also after `now`).
    /// - Candidates are sorted chronologically and capped at `limit - 1`, then
    ///   one trailing "Open Darul Irfan to keep prayer alerts fresh" reminder
    ///   is appended after the last planned notification, keeping the total
    ///   within the iOS pending limit.
    static func build(
        schedules: [PrayerDaySchedule],
        preferences: PrayerNotificationPreferences,
        now: Date,
        limit: Int = 64
    ) -> [PlannedNotification] {
        var candidates: [PlannedNotification] = []

        for schedule in schedules {
            let timeZone = schedule.location.timeZone
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            // Midnight of the schedule's civil day, used for a stable day key.
            let scheduleDayDate = calendar.date(from: schedule.date)

            for prayer in Prayer.allCases {
                let style = preferences.style(for: prayer)
                guard style != .off else { continue }
                guard let fireDate = schedule.time(for: prayer), fireDate > now else { continue }

                let dayKey = DayKey.make(from: scheduleDayDate ?? fireDate, timeZone: timeZone)

                candidates.append(
                    PlannedNotification(
                        identifier: "\(prayerIdentifierPrefix)\(dayKey)|\(prayer.rawValue)",
                        title: title(for: prayer),
                        body: body(for: prayer),
                        soundKind: soundKind(for: style),
                        fireDate: fireDate,
                        dateComponents: triggerComponents(for: fireDate, timeZone: timeZone)
                    )
                )

                let preReminder = preferences.preReminder(for: prayer)
                if preReminder != .off {
                    let minutes = preReminder.rawValue
                    let preFireDate = fireDate.addingTimeInterval(TimeInterval(-minutes * 60))
                    if preFireDate > now {
                        candidates.append(
                            PlannedNotification(
                                identifier: "\(preReminderIdentifierPrefix)\(dayKey)|\(prayer.rawValue)",
                                title: String(localized: "Prayer reminder"),
                                body: preReminderBody(for: prayer, minutes: minutes),
                                soundKind: style == .silent ? .silent : .defaultSound,
                                fireDate: preFireDate,
                                dateComponents: triggerComponents(for: preFireDate, timeZone: timeZone)
                            )
                        )
                    }
                }
            }
        }

        // Chronological order, deterministic on equal fire dates.
        candidates.sort { lhs, rhs in
            if lhs.fireDate != rhs.fireDate {
                return lhs.fireDate < rhs.fireDate
            }
            return lhs.identifier < rhs.identifier
        }

        // Leave one slot for the trailing refresh reminder.
        let capacity = max(0, limit - 1)
        var planned = Array(candidates.prefix(capacity))

        if let last = planned.last {
            let refreshDate = last.fireDate.addingTimeInterval(TimeInterval(refreshReminderDelayMinutes * 60))
            let timeZone = last.dateComponents.timeZone ?? TimeZone.current
            planned.append(
                PlannedNotification(
                    identifier: refreshReminderIdentifier,
                    title: String(localized: "Prayer alerts"),
                    body: String(localized: "Open Darul Irfan to keep prayer alerts fresh."),
                    soundKind: .defaultSound,
                    fireDate: refreshDate,
                    dateComponents: triggerComponents(for: refreshDate, timeZone: timeZone)
                )
            )
        }

        return planned
    }

    // MARK: Components

    /// Full y/m/d/h/m components in `timeZone` for a non-repeating
    /// `UNCalendarNotificationTrigger`. The timezone is set on the components
    /// so the trigger fires at the correct instant even if the device is in a
    /// different timezone than the prayer place.
    static func triggerComponents(for date: Date, timeZone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.timeZone = timeZone
        return components
    }

    // MARK: Text (natural-English literals as String Catalog keys)

    static func title(for prayer: Prayer) -> String {
        switch prayer {
        case .fajr: return String(localized: "Fajr time")
        case .sunrise: return String(localized: "Sunrise time")
        case .dhuhr: return String(localized: "Dhuhr time")
        case .asr: return String(localized: "Asr time")
        case .maghrib: return String(localized: "Maghrib time")
        case .isha: return String(localized: "Isha time")
        }
    }

    static func body(for prayer: Prayer) -> String {
        switch prayer {
        case .fajr: return String(localized: "It is time for Fajr prayer.")
        case .sunrise: return String(localized: "The sun is rising.")
        case .dhuhr: return String(localized: "It is time for Dhuhr prayer.")
        case .asr: return String(localized: "It is time for Asr prayer.")
        case .maghrib: return String(localized: "It is time for Maghrib prayer.")
        case .isha: return String(localized: "It is time for Isha prayer.")
        }
    }

    static func preReminderBody(for prayer: Prayer, minutes: Int) -> String {
        switch prayer {
        case .fajr: return String(localized: "Fajr in \(minutes) minutes")
        case .sunrise: return String(localized: "Sunrise in \(minutes) minutes")
        case .dhuhr: return String(localized: "Dhuhr in \(minutes) minutes")
        case .asr: return String(localized: "Asr in \(minutes) minutes")
        case .maghrib: return String(localized: "Maghrib in \(minutes) minutes")
        case .isha: return String(localized: "Isha in \(minutes) minutes")
        }
    }

    private static func soundKind(for style: PrayerAlertStyle) -> PlannedNotificationSound {
        switch style {
        case .off, .silent: return .silent
        case .defaultSound: return .defaultSound
        case .azanClip: return .azanClip
        }
    }
}

// MARK: - Live scheduler

/// Live `NotificationScheduling` implementation over `UNUserNotificationCenter`.
/// Stateless: every call reads the shared center, so the type is Sendable.
final class NotificationScheduler: NotificationScheduling {

    /// Total requests iOS keeps pending per app. The prayer plan gets this
    /// budget minus any non-prayer requests already pending (zikr/event
    /// reminders), and the plan itself reserves one slot for the trailing
    /// refresh reminder.
    static let pendingRequestLimit = 64

    init() {}

    // MARK: Permission

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: Prayer notifications

    func reschedulePrayerNotifications(
        schedules: [PrayerDaySchedule],
        preferences: PrayerNotificationPreferences
    ) async {
        let center = UNUserNotificationCenter.current()

        // Remove only our own prayer notifications; one-off "reminder|"
        // requests (zikr sessions, events) are left untouched.
        let pending = await center.pendingNotificationRequests()
        let staleIdentifiers = pending
            .map { $0.identifier }
            .filter { PrayerNotificationPlan.isPrayerIdentifier($0) }
        if !staleIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
        }

        // Requests that are not ours (zikr/event "reminder|" one-offs) share
        // the iOS 64-pending budget; leave room for them so scheduling the
        // prayer window never evicts a user-set reminder.
        let otherPendingCount = pending.count - staleIdentifiers.count
        let planned = PrayerNotificationPlan.build(
            schedules: schedules,
            preferences: preferences,
            now: Date(),
            limit: max(0, Self.pendingRequestLimit - otherPendingCount)
        )
        guard !planned.isEmpty else { return }

        // Resolve the azan clip against the bundle once per reschedule.
        let azanSound = Self.resolvedAzanClipSound()

        for notification in planned {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            switch notification.soundKind {
            case .silent:
                content.sound = nil
            case .defaultSound:
                content.sound = .default
            case .azanClip:
                content.sound = azanSound
            }

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: notification.dateComponents,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: notification.identifier,
                content: content,
                trigger: trigger
            )
            // A single failed add should not abort the rest of the window.
            try? await center.add(request)
        }
    }

    // MARK: One-off reminders (zikr sessions, events)

    func scheduleReminder(id: String, title: String, body: String, at date: Date) async {
        guard date > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = PrayerNotificationPlan.triggerComponents(for: date, timeZone: .current)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "reminder|\(id)",
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelReminder(id: String) async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["reminder|\(id)"])
    }

    // MARK: Diagnostics

    func pendingCount() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests().count
    }

    // MARK: Sound resolution

    /// Picks the best available bundled clip for the `.azanClip` style at
    /// scheduling time: a licensed short azan if present, then the app's own
    /// chime, then the system default sound. See Resources/Audio/README.md.
    private static func resolvedAzanClipSound() -> UNNotificationSound {
        if Bundle.main.url(forResource: "azan-short", withExtension: "caf") != nil {
            return UNNotificationSound(named: UNNotificationSoundName("azan-short.caf"))
        }
        if Bundle.main.url(forResource: "prayer-chime", withExtension: "wav") != nil {
            return UNNotificationSound(named: UNNotificationSoundName("prayer-chime.wav"))
        }
        return .default
    }
}
