import Foundation

/// Pure date math for the online zikr schedule. Sessions are announced in a
/// specific timezone (e.g. Asia/Karachi); these helpers convert the announced
/// weekday + wall-clock time into concrete `Date`s for display in the user's
/// local time and for reminder scheduling.
enum ZikrScheduleMath {

    /// The occurrence currently in progress, or the next occurrence. Unlike
    /// `nextOccurrence`, this can return a start in the recent past while its
    /// configured duration is still active.
    static func currentOrNextOccurrence(of session: ZikrSession, at reference: Date) -> Date? {
        let lookback = reference.addingTimeInterval(-TimeInterval(max(session.durationMinutes, 0) * 60))
        guard let candidate = nextOccurrence(of: session, after: lookback) else { return nil }
        let end = candidate.addingTimeInterval(TimeInterval(max(session.durationMinutes, 0) * 60))
        if candidate <= reference, end > reference {
            return candidate
        }
        return nextOccurrence(of: session, after: reference)
    }

    /// The next concrete start `Date` of a session at/after `reference`,
    /// computed in the session's announced timezone.
    static func nextOccurrence(of session: ZikrSession, after reference: Date) -> Date? {
        nextOccurrence(
            weekdays: session.weekdays,
            hour: session.startHour,
            minute: session.startMinute,
            timeZoneIdentifier: session.timeZoneIdentifier,
            after: reference
        )
    }

    /// The next `Date` matching any of `weekdays` (1 = Sunday ... 7 = Saturday)
    /// at `hour:minute` wall-clock time in the given timezone. Returns nil only
    /// when the timezone identifier is unknown.
    static func nextOccurrence(
        weekdays: [Int],
        hour: Int,
        minute: Int,
        timeZoneIdentifier: String,
        after reference: Date
    ) -> Date? {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let validDays = weekdays.filter { (1...7).contains($0) }
        let effectiveDays = validDays.isEmpty ? Array(1...7) : validDays

        var earliest: Date?
        for weekday in effectiveDays {
            var components = DateComponents()
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
            if let candidate = calendar.nextDate(
                after: reference,
                matching: components,
                matchingPolicy: .nextTime
            ) {
                if let current = earliest {
                    if candidate < current { earliest = candidate }
                } else {
                    earliest = candidate
                }
            }
        }
        return earliest
    }

    /// True when the session runs every day (empty weekday list is treated as daily).
    static func isDaily(_ weekdays: [Int]) -> Bool {
        if weekdays.isEmpty { return true }
        return Set(weekdays).isSuperset(of: Set(1...7))
    }

    /// Localized short weekday names for a session's weekday numbers,
    /// in Sunday-first order.
    static func shortWeekdaySymbols(for weekdays: [Int], calendar: Calendar = .current) -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        return weekdays
            .filter { (1...7).contains($0) }
            .sorted()
            .map { symbols[$0 - 1] }
    }

    /// A start in this phone's own time, with its zone named so a reader in
    /// Toronto or Houston knows the time is theirs: "Mon 10:05 AM EDT".
    static func localTimeText(_ date: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        let time = date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.abbreviated).hour().minute())
        let style: NSTimeZone.NameStyle = timeZone.isDaylightSavingTime(for: date) ? .shortDaylightSaving : .shortStandard
        return "\(time) \(timeZone.localizedName(for: style, locale: locale) ?? timeZone.identifier)"
    }

    /// The announced start time formatted in the session's own timezone,
    /// e.g. "9:15 PM (Pakistan Standard Time)".
    static func announcedTimeText(for session: ZikrSession, locale: Locale = .current) -> String {
        let timeZone = TimeZone(identifier: session.timeZoneIdentifier) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let base = calendar.date(
            bySettingHour: session.startHour,
            minute: session.startMinute,
            second: 0,
            of: Date()
        )
        let timeText: String
        if let base {
            timeText = formatter.string(from: base)
        } else {
            timeText = String(format: "%02d:%02d", session.startHour, session.startMinute)
        }
        let zoneName = timeZone.localizedName(for: .standard, locale: locale) ?? session.timeZoneIdentifier
        return "\(timeText) (\(zoneName))"
    }
}

/// Turns a session announced against a prayer time ("after Isha",
/// "before Fajr") into a concrete time, computed at Dar-ul-Irfan with the
/// Pakistan convention (Karachi method, Hanafi Asr). The result is written
/// back into `startHour`/`startMinute` in Pakistan time, so the countdown,
/// reminders, widgets and Watch all keep using one schedule path. Isha moves
/// by about a minute a day, so resolving on each load keeps it current.
enum ZikrAnchorResolver {
    /// Dar-ul-Irfan, Munara, District Chakwal.
    static let darulIrfan = PlaceCoordinate(
        latitude: 32.6678,
        longitude: 72.5133,
        name: "Dar-ul-Irfan",
        timeZoneIdentifier: "Asia/Karachi"
    )

    /// The anchored session with its start set for the occurrence in
    /// progress or next. Sessions without a known anchor pass through.
    static func resolved(
        _ session: ZikrSession,
        at reference: Date,
        calculator: any PrayerCalculationServicing
    ) -> ZikrSession {
        guard session.zikrAnchor != nil else { return session }
        let lookback = reference.addingTimeInterval(-TimeInterval(max(session.durationMinutes, 0) * 60))
        guard let start = nextStart(for: session, after: lookback, calculator: calculator) else { return session }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = darulIrfan.timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: start)
        var copy = session
        copy.startHour = parts.hour ?? session.startHour
        copy.startMinute = parts.minute ?? session.startMinute
        copy.timeZoneIdentifier = darulIrfan.timeZoneIdentifier
        return copy
    }

    /// The first anchored start at or after `reference`.
    static func nextStart(
        for session: ZikrSession,
        after reference: Date,
        calculator: any PrayerCalculationServicing
    ) -> Date? {
        guard let anchor = session.zikrAnchor else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = darulIrfan.timeZone
        let firstDay = calendar.startOfDay(for: reference.addingTimeInterval(-86_400))
        let days = calculator.schedules(
            forDaysStarting: firstDay,
            days: 10,
            at: darulIrfan,
            preferences: PrayerCalculationPreferences()
        )
        let validDays = Set(session.weekdays.filter { (1...7).contains($0) })
        var candidates: [Date] = []
        for day in days {
            switch anchor {
            case .afterIsha:
                if let isha = day.time(for: .isha) { candidates.append(isha) }
            case .beforeFajr, .tahajjud:
                // The Tahajjud zikr starts a set time before Fajr at Dar-ul-Irfan.
                guard let fajr = day.time(for: .fajr) else { continue }
                let lead = max(session.anchorOffsetMinutes ?? 60, 0)
                candidates.append(fajr.addingTimeInterval(-TimeInterval(lead * 60)))
            }
        }
        return candidates
            .filter { $0 >= reference }
            .filter { validDays.isEmpty || validDays.contains(calendar.component(.weekday, from: $0)) }
            .min()
    }

    /// How the session is announced, for display, e.g. "After Isha at
    /// Dar-ul-Irfan". Nil for a session at a fixed clock time.
    static func announcement(for session: ZikrSession) -> String? {
        switch session.zikrAnchor {
        case .afterIsha: return String(localized: "After Isha at Dar-ul-Irfan")
        case .beforeFajr, .tahajjud: return String(localized: "Before Fajr at Dar-ul-Irfan")
        case nil: return nil
        }
    }
}
