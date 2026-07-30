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
