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

// MARK: - The redesign's marks

/// Where a mark is drawn: on Today's emerald prayer card, where the marks
/// are gold, or on the Prayer times page's glass, where prayed is emerald,
/// in congregation gold and qaza a warm rust, as the tracker's dots.
enum PrayerMarkSurface {
    case hero
    case glass
}

/// The redesign's colours for the four marks (boards Main and Prayer).
enum PrayerMarkStyle {
    static func fill(_ mark: PrayerCompletion, on surface: PrayerMarkSurface) -> AnyShapeStyle {
        switch (mark, surface) {
        case (.unmarked, _): return AnyShapeStyle(Color.clear)
        case (.prayed, .hero): return AnyShapeStyle(TodayGradients.gold)
        case (.jamaat, .hero): return AnyShapeStyle(TodayGradients.brightGold)
        case (.qaza, .hero): return AnyShapeStyle(Color.white.opacity(0.12))
        case (.prayed, .glass): return AnyShapeStyle(TodayGradients.markEmerald)
        case (.jamaat, .glass): return AnyShapeStyle(TodayGradients.gold)
        case (.qaza, .glass): return AnyShapeStyle(Color.clear)
        }
    }

    /// The ring round the mark. The next prayer's empty ring is gold.
    static func edge(_ mark: PrayerCompletion, on surface: PrayerMarkSurface, emphasised: Bool = false) -> Color {
        switch (mark, surface) {
        case (.unmarked, .hero): return emphasised ? DIColor.goldGlow.opacity(0.9) : Color.white.opacity(0.45)
        case (.unmarked, .glass): return TodayPalette.dotOff
        case (.prayed, .hero), (.jamaat, .hero), (.jamaat, .glass): return Color(hex: 0xFFE9A8)
        case (.prayed, .glass): return Color(hex: 0x34B98A).opacity(0.9)
        case (.qaza, .hero): return Color(hex: 0xFFB4A2)
        case (.qaza, .glass): return TodayPalette.qazaInk
        }
    }

    /// The mark's symbol colour.
    static func ink(_ mark: PrayerCompletion, on surface: PrayerMarkSurface) -> Color {
        switch (mark, surface) {
        case (.unmarked, _): return Color.clear
        case (.prayed, .hero), (.jamaat, .hero), (.jamaat, .glass): return TodayGradients.onGold
        case (.prayed, .glass): return Color.white
        case (.qaza, .hero): return Color(hex: 0xFFB4A2)
        case (.qaza, .glass): return TodayPalette.qazaInk
        }
    }

    /// The soft light round a prayed mark.
    static func glow(_ mark: PrayerCompletion, on surface: PrayerMarkSurface) -> Color {
        switch (mark, surface) {
        case (.prayed, .hero): return DIColor.goldGlow.opacity(0.6)
        case (.jamaat, _): return DIColor.goldGlow.opacity(surface == .hero ? 0.85 : 0.6)
        case (.prayed, .glass): return Color(hex: 0x34B98A).opacity(0.5)
        case (.unmarked, _), (.qaza, _): return Color.clear
        }
    }

    /// A day's dot in the week strip, one per prayer.
    static func dot(_ mark: PrayerCompletion) -> Color {
        switch mark {
        case .unmarked: return TodayPalette.dotOff
        case .prayed: return Color(hex: 0x34B98A)
        case .jamaat: return Color(hex: 0xE0B75F)
        case .qaza: return TodayPalette.qazaInk
        }
    }
}

/// A prayer's mark as a round badge: an empty ring, a check (prayed), two
/// people (in congregation) or the make-up clock (qaza).
struct PrayerMarkBadge: View {
    let mark: PrayerCompletion
    var surface: PrayerMarkSurface = .glass
    var size: CGFloat = 30
    /// The next prayer's empty ring is drawn in gold.
    var emphasised = false

    var body: some View {
        ZStack {
            Circle()
                .fill(PrayerMarkStyle.fill(mark, on: surface))
            Circle()
                .strokeBorder(PrayerMarkStyle.edge(mark, on: surface, emphasised: emphasised), lineWidth: 1.5)
            if let symbol = PrayerTrackerPalette.symbolName(for: mark) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(PrayerMarkStyle.ink(mark, on: surface))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: PrayerMarkStyle.glow(mark, on: surface), radius: 5)
        .accessibilityHidden(true)
    }
}

/// The spoken names of the marks, in the app's language.
enum PrayerMarkText {
    /// "Fajr: prayed" and so on, for a prayer's mark button.
    static func accessibilityLabel(prayer: Prayer, completion: PrayerCompletion) -> Text {
        let name = String(localized: String.LocalizationValue(prayer.englishName))
        switch completion {
        case .unmarked: return Text("\(name): not marked yet")
        case .prayed: return Text("\(name): prayed")
        case .jamaat: return Text("\(name): prayed in congregation")
        case .qaza: return Text("\(name): marked as Qaza")
        }
    }
}
