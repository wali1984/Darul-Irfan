import Foundation

// MARK: - Online Zikr

/// One recurring online zikr session. The schedule is remotely configurable
/// (fetched via the content manifest) because published timings change.
struct ZikrSession: Codable, Sendable, Identifiable, Equatable {
    var id: String
    /// e.g. "Daily Online Zikr".
    var title: String
    /// Weekdays the session runs on; 1 = Sunday ... 7 = Saturday (Calendar convention).
    var weekdays: [Int]
    /// Local start time components in `timeZoneIdentifier`.
    var startHour: Int
    var startMinute: Int
    var durationMinutes: Int
    /// Timezone the schedule is announced in, e.g. "Asia/Karachi".
    var timeZoneIdentifier: String
    /// Join link (e.g. Paltalk room URL) if published.
    var joinUrl: String?
    /// Official joining instructions supplied by the verified content feed.
    var instructions: String?
    /// Note such as "Room available only during session".
    var availabilityNote: String?
    var sourceUrl: String?
    /// When set, the start follows a prayer time at Dar-ul-Irfan instead of a
    /// fixed clock time: `afterIsha` (a group's own zikr), or `beforeFajr`
    /// (the Tahajjud zikr). Daily Zikr itself is at a fixed 9:15 PM Pakistan
    /// time, so it carries no anchor. `startHour`/`startMinute` stay as the
    /// fallback. A string rather than an enum so a value this build does not
    /// know never fails the whole decode.
    var anchor: String? = nil
    /// Minutes before a `beforeFajr` start (60 when absent).
    var anchorOffsetMinutes: Int? = nil
    /// A group's zikr time that plays a recording by itself: what it plays.
    var autoplayTitle: String? = nil
    /// The Urdu wording of `title` and `availabilityNote`, shown when the app
    /// is in Urdu; the catalogue fills them once the owner approves the
    /// wording, and the English is shown until then.
    var titleUrdu: String? = nil
    var availabilityNoteUrdu: String? = nil

    var zikrAnchor: ZikrAnchor? { anchor.flatMap(ZikrAnchor.init(rawValue:)) }

    /// The Urdu name for Urdu readers when there is one, else the English,
    /// as `Dua` and `IslamicDay` choose theirs.
    func displayTitle(urdu: Bool) -> String {
        if urdu, let titleUrdu, !titleUrdu.isEmpty { return titleUrdu }
        return title
    }

    func displayAvailabilityNote(urdu: Bool) -> String? {
        if urdu, let availabilityNoteUrdu, !availabilityNoteUrdu.isEmpty { return availabilityNoteUrdu }
        return availabilityNote
    }

    func title(inUrdu urdu: Bool) -> String { displayTitle(urdu: urdu) }

    func availabilityNote(inUrdu urdu: Bool) -> String? { displayAvailabilityNote(urdu: urdu) }
}

/// Prayer-time events an online zikr session is announced against.
enum ZikrAnchor: String, Sendable {
    case afterIsha
    case beforeFajr
    /// What group zikr times saved by 1.11.0 carry; it now means `beforeFajr`.
    case tahajjud
}

/// User's reminder preference for a zikr session.
struct ZikrReminderPreference: Codable, Sendable, Equatable {
    var sessionID: String
    var isEnabled: Bool
    /// Minutes before session start to remind.
    var minutesBefore: Int
}

// MARK: - Personal tasbih

/// A named personal zikr/tasbih counter. This is a neutral counting utility;
/// spiritual instruction text comes only from official content.
struct TasbihCounter: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var title: String
    /// Optional target per session (e.g. 100); nil for open-ended.
    var target: Int?
    var count: Int
    /// Lifetime accumulated count across resets.
    var lifetimeCount: Int
    var updatedAt: Date

    /// Accept targets typed with an Urdu/Arabic keyboard; display remains Western digits.
    static func parseTarget(_ text: String) -> Int? {
        let folded = text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map { scalar -> String in
            switch scalar.value {
            case 0x0660...0x0669: return String(scalar.value - 0x0660)
            case 0x06F0...0x06F9: return String(scalar.value - 0x06F0)
            default: return String(scalar)
            }
        }.joined()
        guard let value = Int(folded), value > 0 else { return nil }
        return value
    }
}

/// One day's zikr habit record.
struct ZikrHabitEntry: Codable, Sendable, Identifiable, Equatable {
    /// Civil day key "yyyy-MM-dd".
    var id: String { dayKey }
    var dayKey: String
    var completedCount: Int
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case dayKey, completedCount, updatedAt
    }
}
