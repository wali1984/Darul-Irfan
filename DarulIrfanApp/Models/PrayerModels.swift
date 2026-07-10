import Foundation

// MARK: - Prayer identity

/// The five daily prayers plus sunrise, in chronological order.
enum Prayer: String, CaseIterable, Codable, Sendable, Identifiable {
    case fajr
    case sunrise
    case dhuhr
    case asr
    case maghrib
    case isha

    var id: String { rawValue }

    /// The five obligatory prayers (sunrise excluded).
    static var obligatory: [Prayer] { [.fajr, .dhuhr, .asr, .maghrib, .isha] }

    var isObligatory: Bool { self != .sunrise }

    /// Localization key for the prayer name, resolved via String Catalogs.
    var localizationKey: String { "prayer.name.\(rawValue)" }

    /// English display name used as a development-language fallback.
    var englishName: String {
        switch self {
        case .fajr: return "Fajr"
        case .sunrise: return "Sunrise"
        case .dhuhr: return "Dhuhr"
        case .asr: return "Asr"
        case .maghrib: return "Maghrib"
        case .isha: return "Isha"
        }
    }
}

// MARK: - Calculated times

/// Prayer times for a single civil day at a specific location.
struct PrayerDaySchedule: Codable, Sendable, Equatable {
    var date: DateComponents
    var location: PlaceCoordinate
    var times: [Prayer: Date]

    func time(for prayer: Prayer) -> Date? { times[prayer] }

    /// Times in chronological order for display. Sorted by actual time, not
    /// canonical prayer order: opposing manual offsets or wrapped
    /// high-latitude times must not reorder next/current-prayer logic.
    var orderedTimes: [(prayer: Prayer, time: Date)] {
        Prayer.allCases.compactMap { prayer in
            times[prayer].map { (prayer, $0) }
        }
        .sorted { $0.time < $1.time }
    }
}

/// The prayer occurring next relative to a reference instant.
struct NextPrayerInfo: Sendable, Equatable {
    var prayer: Prayer
    var time: Date
    /// The day the prayer belongs to (may be tomorrow after Isha).
    var scheduleDate: DateComponents
}

// MARK: - Location

/// A named coordinate. Precise device location is never persisted;
/// only user-chosen manual places are stored.
struct PlaceCoordinate: Codable, Sendable, Equatable, Hashable {
    var latitude: Double
    var longitude: Double
    /// Display name, e.g. "Rawalpindi" or "Current Location".
    var name: String
    /// IANA timezone identifier, e.g. "Asia/Karachi".
    var timeZoneIdentifier: String

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }
}

/// How the app determines the user's place for calculations.
enum LocationMode: String, Codable, Sendable, CaseIterable {
    /// One-shot device location, refreshed on demand; never stored.
    case device
    /// A manually selected city, persisted.
    case manual
}

// MARK: - Calculation preferences

/// Library-independent calculation method choice. `PrayerCalculationService`
/// maps these onto the underlying engine.
enum CalculationMethodChoice: String, Codable, Sendable, CaseIterable, Identifiable {
    case muslimWorldLeague
    case northAmerica          // ISNA
    case egyptian
    case ummAlQura
    case karachi
    case moonsightingCommittee
    case dubai
    case kuwait
    case qatar
    case singapore
    case tehran
    case turkey
    case custom

    var id: String { rawValue }

    var localizationKey: String { "calculation.method.\(rawValue)" }

    var englishName: String {
        switch self {
        case .muslimWorldLeague: return "Muslim World League"
        case .northAmerica: return "ISNA (North America)"
        case .egyptian: return "Egyptian General Authority"
        case .ummAlQura: return "Umm al-Qura (Makkah)"
        case .karachi: return "University of Islamic Sciences, Karachi"
        case .moonsightingCommittee: return "Moonsighting Committee"
        case .dubai: return "Dubai"
        case .kuwait: return "Kuwait"
        case .qatar: return "Qatar"
        case .singapore: return "Singapore"
        case .tehran: return "Tehran"
        case .turkey: return "Turkey (Diyanet)"
        case .custom: return "Custom Angles"
        }
    }
}

/// Custom twilight angles used when `CalculationMethodChoice.custom` is selected.
struct CustomCalculationAngles: Codable, Sendable, Equatable {
    /// Solar depression angle for Fajr, in degrees (e.g. 18.0).
    var fajrAngle: Double = 18.0
    /// Solar depression angle for Isha, in degrees (e.g. 17.0). Ignored when `ishaInterval` > 0.
    var ishaAngle: Double = 17.0
    /// Fixed minutes after Maghrib for Isha (e.g. 90 for Umm al-Qura style); 0 disables.
    var ishaIntervalMinutes: Int = 0
}

/// Juristic method for Asr shadow length.
enum AsrMethodChoice: String, Codable, Sendable, CaseIterable, Identifiable {
    case shafi
    case hanafi

    var id: String { rawValue }
    var localizationKey: String { "calculation.asr.\(rawValue)" }
    var englishName: String { self == .shafi ? "Shafi (standard)" : "Hanafi" }
}

/// Strategy for Fajr/Isha at high latitudes.
enum HighLatitudeRuleChoice: String, Codable, Sendable, CaseIterable, Identifiable {
    case automatic
    case middleOfTheNight
    case seventhOfTheNight
    case twilightAngle

    var id: String { rawValue }
    var localizationKey: String { "calculation.highLatitude.\(rawValue)" }

    var englishName: String {
        switch self {
        case .automatic: return "Automatic"
        case .middleOfTheNight: return "Middle of the Night"
        case .seventhOfTheNight: return "Seventh of the Night"
        case .twilightAngle: return "Twilight Angle"
        }
    }
}

/// Per-prayer manual minute offsets applied after calculation.
struct PrayerMinuteAdjustments: Codable, Sendable, Equatable {
    var fajr: Int = 0
    var sunrise: Int = 0
    var dhuhr: Int = 0
    var asr: Int = 0
    var maghrib: Int = 0
    var isha: Int = 0

    func offset(for prayer: Prayer) -> Int {
        switch prayer {
        case .fajr: return fajr
        case .sunrise: return sunrise
        case .dhuhr: return dhuhr
        case .asr: return asr
        case .maghrib: return maghrib
        case .isha: return isha
        }
    }

    mutating func setOffset(_ minutes: Int, for prayer: Prayer) {
        switch prayer {
        case .fajr: fajr = minutes
        case .sunrise: sunrise = minutes
        case .dhuhr: dhuhr = minutes
        case .asr: asr = minutes
        case .maghrib: maghrib = minutes
        case .isha: isha = minutes
        }
    }

    static let none = PrayerMinuteAdjustments()
}

/// Everything `PrayerCalculationService` needs to compute times.
struct PrayerCalculationPreferences: Codable, Sendable, Equatable {
    var method: CalculationMethodChoice = .karachi
    var customAngles = CustomCalculationAngles()
    var asrMethod: AsrMethodChoice = .hanafi
    var highLatitudeRule: HighLatitudeRuleChoice = .automatic
    var adjustments = PrayerMinuteAdjustments.none
}

// MARK: - Notifications

/// How a single prayer's alert should behave.
enum PrayerAlertStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case off
    /// Delivered silently (banner only).
    case silent
    /// System default notification sound.
    case defaultSound
    /// Short bundled Azan/chime clip (must be < 30 s for iOS).
    case azanClip

    var id: String { rawValue }
    var localizationKey: String { "notification.style.\(rawValue)" }

    var englishName: String {
        switch self {
        case .off: return "Off"
        case .silent: return "Silent"
        case .defaultSound: return "Default Sound"
        case .azanClip: return "Azan Clip"
        }
    }
}

/// Optional reminder scheduled before a prayer.
enum PrePrayerReminder: Int, Codable, Sendable, CaseIterable, Identifiable {
    case off = 0
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30

    var id: Int { rawValue }
}

/// Notification preferences for every prayer.
struct PrayerNotificationPreferences: Codable, Sendable, Equatable {
    var styles: [Prayer: PrayerAlertStyle]
    var preReminders: [Prayer: PrePrayerReminder]

    static let `default` = PrayerNotificationPreferences(
        styles: [
            .fajr: .azanClip,
            .sunrise: .off,
            .dhuhr: .azanClip,
            .asr: .azanClip,
            .maghrib: .azanClip,
            .isha: .azanClip,
        ],
        preReminders: [:]
    )

    func style(for prayer: Prayer) -> PrayerAlertStyle {
        styles[prayer] ?? (prayer == .sunrise ? .off : .defaultSound)
    }

    func preReminder(for prayer: Prayer) -> PrePrayerReminder {
        preReminders[prayer] ?? .off
    }
}

// MARK: - Prayer tracker

/// How a prayer was performed, for the personal tracker.
enum PrayerCompletion: String, Codable, Sendable, CaseIterable {
    /// Not yet marked.
    case unmarked
    /// Prayed individually.
    case prayed
    /// Prayed in congregation.
    case jamaat
    /// Missed, to be made up (qaza).
    case qaza
}

/// One prayer's tracker entry for one day. Stored locally only.
struct PrayerLogEntry: Codable, Sendable, Equatable, Identifiable {
    /// "yyyy-MM-dd|prayer" — stable per day+prayer.
    var id: String { "\(dayKey)|\(prayer.rawValue)" }
    /// Civil day key "yyyy-MM-dd" in the user's timezone.
    var dayKey: String
    var prayer: Prayer
    var completion: PrayerCompletion
    var updatedAt: Date
}

/// Aggregated tracker statistics for gentle, non-judgmental display.
struct PrayerStreakSummary: Sendable, Equatable {
    var currentStreakDays: Int
    var bestStreakDays: Int
    /// Fraction of obligatory prayers marked prayed/jamaat over the window.
    var completionRate: Double
    var windowDays: Int
}
