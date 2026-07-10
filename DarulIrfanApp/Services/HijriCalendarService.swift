import Foundation

/// Live implementation of `HijriCalendarServicing` backed by the Umm al-Qura
/// astronomical calendar (`Calendar(identifier: .islamicUmmAlQura)`).
///
/// Per Docs/RESEARCH_NOTES.md: the user's ±day offset is always applied to
/// the *Date* (`calendar.date(byAdding: .day, ...)`) before Hijri components
/// are extracted — never to the extracted day component, which would break at
/// month boundaries.
struct HijriCalendarService: HijriCalendarServicing {

    init() {}

    // MARK: - HijriCalendarServicing

    func hijriComponents(for date: Date, offsetDays: Int) -> DateComponents {
        let calendar = Self.makeCalendar()
        let adjusted = Self.adjusted(date, byDays: offsetDays, calendar: calendar)
        return calendar.dateComponents([.year, .month, .day], from: adjusted)
    }

    func hijriDateText(for date: Date, offsetDays: Int, locale: Locale) -> String {
        let calendar = Self.makeCalendar(locale: locale)
        let adjusted = Self.adjusted(date, byDays: offsetDays, calendar: calendar)

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        // Day + full Hijri month name + year, no era suffix,
        // e.g. "15 Muharram 1448" / "١٥ محرم ١٤٤٨".
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: adjusted)
    }

    func isRamadan(_ date: Date, offsetDays: Int) -> Bool {
        return hijriComponents(for: date, offsetDays: offsetDays).month == 9
    }

    func upcomingIslamicDays(
        from date: Date,
        within days: Int,
        offsetDays: Int
    ) -> [(day: IslamicDay, gregorianDate: Date)] {
        guard days > 0 else { return [] }
        let notableDays: [IslamicDay] = SeedBundle.islamicDays()
        guard !notableDays.isEmpty else { return [] }

        let gregorian = Calendar(identifier: .gregorian)
        var matches: [(day: IslamicDay, gregorianDate: Date)] = []

        // Scan each of the next `days` civil days (starting today), compute
        // its Hijri month/day, and collect any bundled notable days that fall
        // on it. Results come out in ascending date order by construction.
        for dayOffset in 0..<days {
            guard let scanned = gregorian.date(byAdding: .day, value: dayOffset, to: date) else {
                continue
            }
            let components = hijriComponents(for: scanned, offsetDays: offsetDays)
            guard let hijriMonth = components.month, let hijriDay = components.day else {
                continue
            }
            for notable in notableDays
            where notable.hijriMonth == hijriMonth && notable.hijriDay == hijriDay {
                matches.append((day: notable, gregorianDate: gregorian.startOfDay(for: scanned)))
            }
        }
        return matches
    }

    // MARK: - Helpers

    private static func makeCalendar(locale: Locale? = nil) -> Calendar {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        if let locale = locale {
            calendar.locale = locale
        }
        return calendar
    }

    private static func adjusted(_ date: Date, byDays offsetDays: Int, calendar: Calendar) -> Date {
        guard offsetDays != 0 else { return date }
        return calendar.date(byAdding: .day, value: offsetDays, to: date)
            ?? date.addingTimeInterval(TimeInterval(offsetDays) * 86_400)
    }
}
