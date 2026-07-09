import Foundation

// Compiled into BOTH the app target and the widget extension (see project.yml).
// The app writes this snapshot to the shared App Group container after every
// prayer-time recalculation; the widget reads it in its TimelineProvider.
// Keep this file dependency-free (Foundation only).

/// App Group shared between the app and its widgets.
enum SharedAppGroup {
    static let identifier = "group.org.naqshbandiaowaisiah.darulirfan"
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

    /// The next prayer strictly after `date`, or nil if the snapshot is exhausted.
    func nextPrayer(after date: Date) -> WidgetPrayerTime? {
        upcomingTimes.first { $0.isObligatory && $0.time > date }
    }

    /// All times falling on the same civil day as `date` (widget "today" view).
    func times(onSameDayAs date: Date, calendar: Calendar = .current) -> [WidgetPrayerTime] {
        upcomingTimes.filter { calendar.isDate($0.time, inSameDayAs: date) }
    }

    static func load(from url: URL? = SharedAppGroup.prayerSnapshotURL) -> PrayerWidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PrayerWidgetSnapshot.self, from: data)
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
