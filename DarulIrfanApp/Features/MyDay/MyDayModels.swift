import Foundation

// My Day: a person's own tasks, notes and fasts.
//
// Everything here is private devotional and personal data. It lives in one
// file on this device, is never synced, needs no account, and is never sent
// anywhere - which is also why it is a plain file rather than a table in the
// content database that the app rebuilds from the bundle.

/// When in the day a task falls.
enum DayTaskTiming: Codable, Sendable, Equatable, Hashable {
    /// No particular time.
    case anytime
    /// A clock time.
    case clock(hour: Int, minute: Int)
    /// Minutes after a prayer's time, e.g. "after Fajr" is `.afterPrayer(.fajr, 0)`.
    case afterPrayer(Prayer, minutes: Int)
    /// Minutes before a prayer's time.
    case beforePrayer(Prayer, minutes: Int)

    var isTimed: Bool { self != .anytime }

    var prayer: Prayer? {
        switch self {
        case .afterPrayer(let prayer, _), .beforePrayer(let prayer, _): return prayer
        case .anytime, .clock: return nil
        }
    }
}

/// How a task repeats.
enum DayTaskRepeat: String, Codable, Sendable, CaseIterable, Identifiable {
    case never
    case daily
    /// Monday to Friday.
    case weekdays
    /// The same weekday as the start day.
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return "Does not repeat"
        case .daily: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekly: return "Every week"
        }
    }
}

struct DayTask: Codable, Sendable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    /// The first day the task falls on (start of that day, device calendar).
    var startDay: Date
    var timing: DayTaskTiming = .anytime
    var repeatRule: DayTaskRepeat = .never
    /// Whether a local notification is scheduled for the next occurrence.
    var remind = false
    var note: String?
    /// Days ("yyyy-MM-dd") on which this task was done.
    var completedDays: Set<String> = []
    var createdAt = Date()

    /// Whether the task falls on `day` (any instant within it).
    func occurs(on day: Date, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: startDay)
        let target = calendar.startOfDay(for: day)
        guard target >= start else { return false }
        switch repeatRule {
        case .never:
            return target == start
        case .daily:
            return true
        case .weekdays:
            let weekday = calendar.component(.weekday, from: target)
            return (2...6).contains(weekday)
        case .weekly:
            return calendar.component(.weekday, from: target) == calendar.component(.weekday, from: start)
        }
    }

    func isDone(on day: Date, calendar: Calendar = .current) -> Bool {
        completedDays.contains(DayKey.make(from: day, timeZone: calendar.timeZone))
    }
}

/// A private note, optionally tied to what it was written about.
struct DayNote: Codable, Sendable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var reference: NoteReference?
    var createdAt = Date()
    var updatedAt = Date()
}

/// What a note was written about, so it can be shown beside its source.
struct NoteReference: Codable, Sendable, Equatable, Hashable {
    enum Kind: String, Codable, Sendable {
        case ayah
        case media
        case library
    }

    var kind: Kind
    /// "2:255" for an ayah, otherwise the item's id.
    var itemID: String
    /// What to show, e.g. "Al-Baqarah 2:255".
    var label: String
}

/// A recorded fast.
enum FastKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case ramadan
    case qada
    case voluntary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ramadan: return "Ramadan"
        case .qada: return "Qada (make-up)"
        case .voluntary: return "Voluntary"
        }
    }
}

/// Everything My Day keeps, as one versioned document.
struct MyDayDocument: Codable, Sendable, Equatable {
    var version = 1
    var tasks: [DayTask] = []
    var notes: [DayNote] = []
    /// Fasts by day key ("yyyy-MM-dd").
    var fasts: [String: FastKind] = [:]
}
