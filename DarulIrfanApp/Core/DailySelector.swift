import Foundation

/// Deterministic, date-seeded selection for the daily companion content.
///
/// Every stream (ayah, dua, name, quote) is chosen as a pure function of the
/// civil date, so:
/// - the choice is stable all day and flips at the user's local midnight,
/// - it is identical for everyone computing the same date (a shared "today's
///   ayah" moment, clean screenshots),
/// - it is fully reproducible and unit-testable.
///
/// Never uses `hashValue`/`Hasher` (per-process randomized seed) — indices are
/// arithmetic on the date with a per-stream salt so the streams don't rotate in
/// lockstep.
enum DailySelector {

    /// Streams get distinct constant salts so ayah/dua/name/quote differ on the
    /// same day. Values are arbitrary fixed primes, baked in forever.
    enum Stream: Int, CaseIterable {
        case ayah = 0
        case dua = 101
        case name = 211
        case aqwal = 337
        case dhikr = 449
    }

    /// Whole civil days since the Unix epoch for `date` in `timeZone`
    /// (defaults to the user's current zone). Pure function of the date.
    static func epochDay(for date: Date, timeZone: TimeZone = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfDay = calendar.startOfDay(for: date)
        return Int((startOfDay.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    /// A stable index into a list of length `count` for `date` and `stream`.
    /// Double-mod guards negative epoch days (pre-1970 test dates).
    static func index(count: Int, for date: Date, stream: Stream, timeZone: TimeZone = .current) -> Int {
        guard count > 0 else { return 0 }
        let seed = epochDay(for: date, timeZone: timeZone) + stream.rawValue
        return ((seed % count) + count) % count
    }

    /// Picks the element of `items` for `date` and `stream`, or nil if empty.
    static func pick<T>(_ items: [T], for date: Date, stream: Stream, timeZone: TimeZone = .current) -> T? {
        guard !items.isEmpty else { return nil }
        return items[index(count: items.count, for: date, stream: stream, timeZone: timeZone)]
    }

    /// Name of Allah number (1...99) for the day.
    static func nameNumber(for date: Date, timeZone: TimeZone = .current) -> Int {
        (index(count: 99, for: date, stream: .name, timeZone: timeZone)) + 1
    }
}
