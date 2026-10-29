import Foundation

// Compiled into BOTH the app target and the widget extension (see project.yml).
// The app writes this snapshot to the shared App Group container after every
// prayer-time recalculation; the widget reads it in its TimelineProvider.
// Keep this file dependency-free (Foundation only).

/// App Group shared between the app and its widgets.
enum SharedAppGroup {
    static let identifier = "group.us.naqshbaniaowaisiah"
    static let prayerSnapshotFilename = "prayer-widget-snapshot.json"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var prayerSnapshotURL: URL? {
        containerURL?.appendingPathComponent(prayerSnapshotFilename)
    }
}

/// A single prayer's time within a widget snapshot.
struct WidgetPrayerTime: Codable, Sendable, Equatable {
    /// Raw value of the app's `Prayer` enum ("fajr", "sunrise", ...).
    var prayerKey: String
    /// Localized display name resolved by the app at snapshot time.
    var displayName: String
    var time: Date
    var isObligatory: Bool
}

/// One concrete online-zikr occurrence sent to Apple Watch. Recurrence is
/// resolved on iPhone so the Watch stays useful offline and never needs to
/// duplicate timezone/schedule rules.
struct WidgetZikrSession: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var title: String
    var startsAt: Date
    var endsAt: Date

    func isActive(at date: Date) -> Bool {
        startsAt <= date && date < endsAt
    }
}

/// Privacy-preserving devotional summary shared only through the App Group
/// and WatchConnectivity. No worship history or location leaves the device.
struct WidgetDevotionalMetrics: Codable, Sendable, Equatable {
    var prayersCompleted: Int
    var prayerGoal: Int
    var prayerStreakDays: Int
    var prayerCompletionRate: Double
    var quranSurahNumber: Int?
    var quranAyahNumber: Int?
    var tasbihTitle: String?
    var tasbihCount: Int
    var tasbihTarget: Int?
    var zikrCompletionsToday: Int
    var updatedAt: Date

    /// Prayers marked on the day of `date`. The counts belong to the day the
    /// app last refreshed them (the phone's own day, as the tracker keeps
    /// it), so on a later day nothing is marked yet until the app runs again.
    func completedPrayers(on date: Date, calendar: Calendar = .current) -> Int {
        calendar.isDate(updatedAt, inSameDayAs: date) ? prayersCompleted : 0
    }

    /// Zikr completions on the day of `date`; see `completedPrayers(on:)`.
    func zikrCompletions(on date: Date, calendar: Calendar = .current) -> Int {
        calendar.isDate(updatedAt, inSameDayAs: date) ? zikrCompletionsToday : 0
    }
}

/// Everything the widgets need, precomputed by the app. Covers several days
/// so widgets stay correct even if the app is not opened daily.
struct PrayerWidgetSnapshot: Codable, Sendable, Equatable {
    /// Schema version for forward compatibility.
    var version: Int = 1
    var generatedAt: Date
    /// Display name of the place times were computed for.
    var placeName: String
    /// Chronologically sorted times spanning today + following days.
    var upcomingTimes: [WidgetPrayerTime]
    /// Hijri date string precomputed with the user's offset, e.g. "15 Muharram 1448".
    var hijriDateText: String
    /// Ramadan extras; nil outside Ramadan.
    var suhoorEndsAt: Date?
    var iftarAt: Date?
    /// Upcoming concrete zikr occurrences. Optional for backward-compatible
    /// decoding of snapshots written by pre-Watch-zikr app versions.
    var zikrSessions: [WidgetZikrSession]? = nil
    /// Optional for backward-compatible decoding of pre-dashboard snapshots.
    var devotionalMetrics: WidgetDevotionalMetrics? = nil
    /// Time zone of the place the times were computed for. Times are shown on
    /// that place's clock and "today" is that place's day, as the app shows
    /// them; nil in snapshots from earlier builds, which means the phone's.
    var timeZoneIdentifier: String? = nil
    /// The Hijri date text of each civil day the snapshot covers, keyed
    /// "yyyy-MM-dd" in `timeZone`, so widgets turn the date over at midnight
    /// without the app running. Nil in snapshots from earlier builds.
    var hijriDates: [String: String]? = nil

    /// The place's time zone (the phone's for older snapshots).
    var timeZone: TimeZone {
        timeZoneIdentifier.flatMap { TimeZone(identifier: $0) } ?? .current
    }

    /// A Gregorian calendar on the place's clock.
    var placeCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The next prayer strictly after `date`, or nil if the snapshot is exhausted.
    func nextPrayer(after date: Date) -> WidgetPrayerTime? {
        upcomingTimes.first { $0.isObligatory && $0.time > date }
    }

    /// All times falling on the place's civil day of `date` (widget "today" view).
    func times(onSameDayAs date: Date) -> [WidgetPrayerTime] {
        times(onSameDayAs: date, calendar: placeCalendar)
    }

    /// All times falling on the same civil day as `date` in `calendar`.
    func times(onSameDayAs date: Date, calendar: Calendar) -> [WidgetPrayerTime] {
        upcomingTimes.filter { calendar.isDate($0.time, inSameDayAs: date) }
    }

    /// The Hijri date of the place's day of `date`, falling back to the text
    /// written with the snapshot.
    func hijriText(on date: Date) -> String {
        hijriDates?[Self.dayKey(for: date, in: timeZone)] ?? hijriDateText
    }

    /// When the place's next civil day begins after `date`.
    func startOfNextDay(after date: Date) -> Date? {
        let calendar = placeCalendar
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
    }

    /// Civil-day key "yyyy-MM-dd" of `date` in `timeZone` (the format the
    /// app's trackers use).
    static func dayKey(for date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Active occurrence first, otherwise the next future zikr session.
    func currentOrNextZikr(at date: Date) -> WidgetZikrSession? {
        zikrSessions?
            .filter { $0.endsAt > date }
            .sorted { lhs, rhs in
                let lhsActive = lhs.isActive(at: date)
                let rhsActive = rhs.isActive(at: date)
                if lhsActive != rhsActive { return lhsActive }
                return lhs.startsAt < rhs.startsAt
            }
            .first
    }

    static func load(from url: URL? = SharedAppGroup.prayerSnapshotURL) -> PrayerWidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PrayerWidgetSnapshot.self, from: data)
    }

    /// Deletes the snapshot, so widgets ask for a place to be set up.
    static func remove(at url: URL? = SharedAppGroup.prayerSnapshotURL) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func save(to url: URL? = SharedAppGroup.prayerSnapshotURL) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(self) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
