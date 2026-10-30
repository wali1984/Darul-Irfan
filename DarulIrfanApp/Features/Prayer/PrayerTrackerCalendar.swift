import Foundation

/// The calendar behind the prayer tracker on the Prayer times page: weeks of
/// seven days from Saturday to Friday (as the tracker board lays them out,
/// so each week closes on Jumu'ah), paged back from the week holding today;
/// which days can be marked; and the order the four marks cycle in. Pure,
/// so the paging, the day keys and the locks are unit-tested.
///
/// Days follow the tracker's own rule: the civil day in the phone's time
/// zone (`DayKey`'s default), the same key a mark made on Today has always
/// used, so a past day's mark lands beside the marks already recorded.
enum PrayerTrackerCalendar {
    /// Saturday, in the Gregorian calendar's numbering (Sunday is 1).
    static let firstWeekday = 7

    /// A Gregorian calendar in `timeZone` whose weeks begin on Saturday.
    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    /// The next of the app's four marks, in the order a tap moves them: not
    /// marked, prayed, prayed in congregation, qaza, and round again.
    static func nextMark(after mark: PrayerCompletion) -> PrayerCompletion {
        switch mark {
        case .unmarked: return .prayed
        case .prayed: return .jamaat
        case .jamaat: return .qaza
        case .qaza: return .unmarked
        }
    }

    /// Paging never goes past the week holding today: 0 is that week, -1 the
    /// week before it, and so on back.
    static func clampedWeekOffset(_ offset: Int) -> Int {
        min(0, offset)
    }

    /// Whether the week after this one can be shown: only from a past week.
    static func canShowNextWeek(from offset: Int) -> Bool {
        clampedWeekOffset(offset) < 0
    }

    /// The start of the Saturday-to-Friday week holding `date`.
    static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let back = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: day) ?? day
    }

    /// The seven days, Saturday first, of the week `weekOffset` weeks from
    /// the one holding `today`, each at the start of its day. An offset past
    /// the current week is held at the current week.
    static func days(weekOffset: Int, today: Date, calendar: Calendar) -> [Date] {
        let start = weekStart(containing: today, calendar: calendar)
        let weeks = clampedWeekOffset(weekOffset)
        guard let first = calendar.date(byAdding: .day, value: 7 * weeks, to: start) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    /// The tracker's day keys for those seven days.
    static func dayKeys(weekOffset: Int, today: Date, calendar: Calendar) -> [String] {
        days(weekOffset: weekOffset, today: today, calendar: calendar).map {
            DayKey.make(from: $0, timeZone: calendar.timeZone)
        }
    }

    /// Whether `day` can be marked: any day up to and including today. A day
    /// after today is locked until it comes.
    static func isMarkable(_ day: Date, today: Date, calendar: Calendar) -> Bool {
        calendar.startOfDay(for: day) <= calendar.startOfDay(for: today)
    }

    /// Whether two instants fall on the same civil day.
    static func isSameDay(_ first: Date, _ second: Date, calendar: Calendar) -> Bool {
        DayKey.make(from: first, timeZone: calendar.timeZone) == DayKey.make(from: second, timeZone: calendar.timeZone)
    }

    /// The day the tracker shows in a week: the chosen one while it lies in
    /// that week and can be marked; otherwise today in the current week, or a
    /// past week's last day (its Friday).
    static func shownDay(selected: Date?, weekOffset: Int, today: Date, calendar: Calendar) -> Date {
        let week = days(weekOffset: weekOffset, today: today, calendar: calendar)
        if let selected,
           let match = week.first(where: { isSameDay($0, selected, calendar: calendar) }),
           isMarkable(match, today: today, calendar: calendar) {
            return match
        }
        if let current = week.first(where: { isSameDay($0, today, calendar: calendar) }) {
            return current
        }
        return week.last ?? calendar.startOfDay(for: today)
    }

    /// The tracker entry that moves `prayer` on `day` from `current` to its
    /// next mark, keyed by that day, or nil when `day` is after today
    /// (`now`) and cannot be marked yet.
    static func entry(
        cycling current: PrayerCompletion,
        for prayer: Prayer,
        on day: Date,
        now: Date,
        timeZone: TimeZone = .current
    ) -> PrayerLogEntry? {
        guard isMarkable(day, today: now, calendar: calendar(timeZone: timeZone)) else { return nil }
        return PrayerLogEntry(
            dayKey: DayKey.make(from: day, timeZone: timeZone),
            prayer: prayer,
            completion: nextMark(after: current),
            updatedAt: now
        )
    }
}
