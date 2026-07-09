import Foundation

// MARK: - App-wide settings

/// App display language, switchable independently of the system language.
enum AppLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case system
    case english = "en"
    case urdu = "ur"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .urdu: return "اردو"
        }
    }

    /// Locale identifier to force, or nil to follow the system.
    var forcedLocaleIdentifier: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .urdu: return "ur"
        }
    }

    var isRightToLeft: Bool { self == .urdu }
}

enum AppTheme: String, Codable, Sendable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var localizationKey: String { "settings.theme.\(rawValue)" }
}

/// Reader font scale applied on top of Dynamic Type in Quran/Library readers.
enum ReaderFontScale: Double, Codable, Sendable, CaseIterable, Identifiable {
    case small = 0.85
    case standard = 1.0
    case large = 1.2
    case extraLarge = 1.45

    var id: Double { rawValue }
}

/// Root user settings persisted locally. Everything here is on-device only.
struct AppSettings: Codable, Sendable, Equatable {
    // Identity & appearance
    var language: AppLanguage = .system
    var theme: AppTheme = .system
    var readerFontScale: ReaderFontScale = .standard

    // Location
    var locationMode: LocationMode = .device
    /// Persisted only when `locationMode == .manual`.
    var manualPlace: PlaceCoordinate?
    /// Last place used for calculations, kept so prayer times work offline
    /// at launch. City-level named place, not a location history.
    var lastKnownPlace: PlaceCoordinate?

    // Prayer calculation
    var calculation = PrayerCalculationPreferences()

    // Notifications
    var prayerNotifications = PrayerNotificationPreferences.default

    // Hijri
    var hijri = HijriPreferences()

    // Onboarding
    var hasCompletedOnboarding = false

    // Content
    /// Whether to auto-download new content packs on Wi-Fi.
    var autoDownloadOnWifi = false

    static let `default` = AppSettings()
}

// MARK: - Search

/// Domains searchable from the global search screen.
enum SearchDomain: String, Codable, Sendable, CaseIterable, Identifiable {
    case quran
    case library
    case media
    case events

    var id: String { rawValue }
    var localizationKey: String { "search.domain.\(rawValue)" }
}

/// One global-search hit.
struct SearchResult: Sendable, Identifiable, Equatable {
    var id: String { "\(domain.rawValue)|\(itemID)" }
    var domain: SearchDomain
    /// ID within the domain (ayah "1:5", content item ID, media item ID, event ID).
    var itemID: String
    var title: String
    /// Snippet with the match, for display.
    var snippet: String?
    var language: String?
}
