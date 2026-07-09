import Foundation

// MARK: - Online Zikr

/// One recurring online zikr session. The schedule is remotely configurable
/// (fetched via the content manifest) because website timings change.
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
    /// Official joining instructions, verbatim from the website.
    var instructions: String?
    /// Note such as "Room available only during session".
    var availabilityNote: String?
    var sourceUrl: String?
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
