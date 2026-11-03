import Foundation

// Compiled into the app, the iPhone widgets, the Watch app and the Watch
// complications (see project.yml). Foundation only.

/// Ayah of the Day as Today shows it: the mushaf's own Arabic, the Silsila's
/// translation and the full reference, resolved by the app for one day.
struct WidgetDailyAyah: Codable, Sendable, Equatable {
    var surah: Int
    var ayahStart: Int
    var ayahEnd: Int
    var arabic: String
    var translation: String?
    var reference: String
    /// "en" or "ur": the language the translation and reference are in.
    var languageCode: String

    /// Opens the reader at the ayah (DeepLinkRouter "quran/<surah>/<ayah>").
    var link: URL? { URL(string: "darulirfan://quran/\(surah)/\(ayahStart)") }
}

extension PrayerWidgetSnapshot {
    /// The five obligatory prayers of the place's day of `date`.
    func fivePrayers(on date: Date) -> [WidgetPrayerTime] {
        times(onSameDayAs: date).filter(\.isObligatory)
    }

    /// The last obligatory prayer at or before `date`.
    func previousPrayer(atOrBefore date: Date) -> WidgetPrayerTime? {
        upcomingTimes.last { $0.isObligatory && $0.time <= date }
    }

    /// The span a countdown to `next` runs over, seen at `date`: from the
    /// prayer before it (so a ring shows how much of the wait is gone) to
    /// `next`. Never empty or reversed, which `Text(timerInterval:)` and
    /// `ProgressView(timerInterval:)` do not accept.
    func countdownInterval(to next: WidgetPrayerTime, at date: Date) -> ClosedRange<Date> {
        let start = previousPrayer(atOrBefore: date)?.time ?? date
        let lower = min(start, date, next.time)
        return lower...max(lower, next.time)
    }

    /// The day's ayah for the phone's day of `date`, if the app wrote one in
    /// the snapshot's language.
    func dailyAyah(on date: Date, phoneTimeZone: TimeZone = .current) -> WidgetDailyAyah? {
        guard let ayah = dailyAyahs?[Self.dayKey(for: date, in: phoneTimeZone)] else { return nil }
        if let languageCode, ayah.languageCode != languageCode { return nil }
        return ayah
    }

    /// The locale the widgets write times and dates in: the app's language,
    /// always with Western digits (owner's rule), or nil for the phone's.
    var displayLocale: Locale? {
        guard let languageCode else { return nil }
        var components = Locale.Components(locale: Locale(identifier: languageCode))
        components.numberingSystem = Locale.NumberingSystem("latn")
        return Locale(components: components)
    }

    /// True for Urdu, false for English, nil when the snapshot does not say.
    var readsRightToLeft: Bool? {
        languageCode.map { $0 == "ur" }
    }
}

/// When the widgets and complications must show something new, so iOS and
/// watchOS can switch entries on time without the app running: every prayer
/// time (sunrise included, for the highlighted row), each zikr session's
/// start and end, midnight where the place is (today's grid and the Hijri
/// date) and midnight where the phone is (the day's ayah and today's counts).
enum WidgetTimelinePlan {
    /// How far ahead one timeline reaches.
    static let horizon: TimeInterval = 48 * 60 * 60
    /// Most entries one timeline carries.
    static let entryLimit = 40
    /// The longest a timeline waits before asking for a new one.
    static let longestWait: TimeInterval = 6 * 60 * 60
    /// The wait when there is nothing ahead to plan for.
    static let emptyWait: TimeInterval = 30 * 60

    /// The entry dates from `now`: `now` first, then each moment above
    /// within the horizon, in order, without repeats.
    static func dates(
        for snapshot: PrayerWidgetSnapshot,
        from now: Date,
        phoneTimeZone: TimeZone = .current
    ) -> [Date] {
        let end = now.addingTimeInterval(horizon)
        var moments: [Date] = snapshot.upcomingTimes.map(\.time)
        for session in snapshot.zikrSessions ?? [] {
            moments.append(session.startsAt)
            moments.append(session.endsAt)
        }
        moments += midnights(after: now, until: end, in: snapshot.timeZone)
        if phoneTimeZone.identifier != snapshot.timeZone.identifier {
            moments += midnights(after: now, until: end, in: phoneTimeZone)
        }
        let ahead = Set(moments.filter { $0 > now && $0 <= end }).sorted()
        return [now] + ahead.prefix(entryLimit - 1)
    }

    /// When to ask for a new timeline: at its last entry, but never more
    /// than six hours on, and half an hour on when it has only `now`.
    static func reloadDate(after dates: [Date], from now: Date) -> Date {
        guard dates.count > 1, let last = dates.last else { return now.addingTimeInterval(emptyWait) }
        return min(last, now.addingTimeInterval(longestWait))
    }

    /// The starts of the days after `now`'s, up to `end`, in `timeZone`.
    static func midnights(after now: Date, until end: Date, in timeZone: TimeZone) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var result: [Date] = []
        var day = calendar.startOfDay(for: now)
        while let next = calendar.date(byAdding: .day, value: 1, to: day), next <= end {
            result.append(next)
            day = next
        }
        return result
    }
}

/// How the Watch's seal moves: fully animated while the app is frontmost and
/// awake, held still for Reduce Motion, and held still and dimmed while the
/// wrist is down (Always On, luminance reduced).
enum WatchSealMotion: Equatable {
    case animated
    case still
    case dimmed

    static func resolve(reduceMotion: Bool, luminanceReduced: Bool) -> WatchSealMotion {
        if luminanceReduced { return .dimmed }
        return reduceMotion ? .still : .animated
    }

    /// The seal's appearance `elapsed` seconds after it first appeared.
    func phase(elapsed: TimeInterval) -> WatchSealPhase {
        switch self {
        case .animated:
            let t = max(0, elapsed)
            let reveal = min(1, t / WatchSealPhase.revealDuration)
            // Ease out: quick at first, settling gently.
            let eased = 1 - pow(1 - reveal, 3)
            let breath = (1 - cos(2 * Double.pi * t / WatchSealPhase.breathPeriod)) / 2
            let sweep = (t / WatchSealPhase.sweepPeriod).truncatingRemainder(dividingBy: 1) * 360 - 35
            return WatchSealPhase(reveal: eased, glow: 0.16 + 0.16 * breath, sweepDegrees: sweep, showsSweep: true, opacity: 1)
        case .still:
            return WatchSealPhase(reveal: 1, glow: 0.22, sweepDegrees: -35, showsSweep: true, opacity: 1)
        case .dimmed:
            return WatchSealPhase(reveal: 1, glow: 0, sweepDegrees: -35, showsSweep: false, opacity: 0.55)
        }
    }
}

/// One frame of the Watch's seal.
struct WatchSealPhase: Equatable {
    static let revealDuration: TimeInterval = 1.2
    static let breathPeriod: TimeInterval = 5.2
    static let sweepPeriod: TimeInterval = 12

    /// 0 when it begins to appear, 1 once it is fully drawn.
    var reveal: Double
    /// Opacity of the gold halo.
    var glow: Double
    /// Where the light travelling round the rim is.
    var sweepDegrees: Double
    var showsSweep: Bool
    var opacity: Double
}
