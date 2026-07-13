import SwiftUI

/// Display helpers for `EventKind`, used by the events list and detail
/// screens. Names deliberately prefixed with `event` to stay clear of other
/// features' extensions on the shared model.
extension EventKind {
    var eventSymbolName: String {
        switch self {
        case .monthlyIjtema: return "person.3"
        case .salanaIjtema: return "person.3.sequence"
        case .ramadanAitekaaf: return "moon.stars"
        case .announcement: return "megaphone"
        case .other: return "calendar"
        }
    }

    /// A brand-family accent used for the kind's medallion and gradient trim.
    /// Gold for the year's high points (Salana, Aitekaaf), emerald otherwise —
    /// all within the app's reverent palette.
    var eventTint: Color {
        switch self {
        case .salanaIjtema, .ramadanAitekaaf: return DIColor.accent
        case .monthlyIjtema, .announcement, .other: return DIColor.primary
        }
    }

    var eventDisplayNameKey: LocalizedStringKey {
        switch self {
        case .monthlyIjtema: return "Monthly Ijtema"
        case .salanaIjtema: return "Salana Ijtema"
        case .ramadanAitekaaf: return "Ramadan Aitekaaf"
        case .announcement: return "Announcement"
        case .other: return "Program"
        }
    }

    /// Plain-string variant for components that take `String` (e.g. badges).
    var eventDisplayName: String {
        switch self {
        case .monthlyIjtema: return String(localized: "Monthly Ijtema")
        case .salanaIjtema: return String(localized: "Salana Ijtema")
        case .ramadanAitekaaf: return String(localized: "Ramadan Aitekaaf")
        case .announcement: return String(localized: "Announcement")
        case .other: return String(localized: "Program")
        }
    }
}
