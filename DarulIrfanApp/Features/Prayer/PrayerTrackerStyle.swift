import SwiftUI

/// Shared color/symbol vocabulary for the prayer tracker circles, used by
/// both the dashboard strip and the history grid so they read identically.
///
/// Mapping: primary = prayed, accent (gold) = jamaat, muted outline =
/// unmarked, danger tint = qaza.
enum PrayerTrackerPalette {
    static func fill(for completion: PrayerCompletion) -> Color {
        switch completion {
        case .unmarked: return Color.clear
        case .prayed: return DIColor.primary
        case .jamaat: return DIColor.accent
        case .qaza: return DIColor.danger.opacity(0.12)
        }
    }

    static func stroke(for completion: PrayerCompletion) -> Color {
        switch completion {
        case .unmarked: return DIColor.textMuted.opacity(0.5)
        case .prayed: return DIColor.primary
        case .jamaat: return DIColor.accent
        case .qaza: return DIColor.danger
        }
    }

    static func symbolName(for completion: PrayerCompletion) -> String? {
        switch completion {
        case .unmarked: return nil
        case .prayed: return "checkmark"
        case .jamaat: return "person.2.fill"
        case .qaza: return "clock.arrow.circlepath"
        }
    }

    static func symbolColor(for completion: PrayerCompletion) -> Color {
        switch completion {
        case .unmarked: return Color.clear
        case .prayed, .jamaat: return DIColor.onPrimary
        case .qaza: return DIColor.danger
        }
    }
}
