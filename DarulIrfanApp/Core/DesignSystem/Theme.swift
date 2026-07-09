import SwiftUI
import UIKit

// Design language: calm, reverent, scholarly. Deep emerald + warm cream with
// restrained gold accents, carried over from the Darul Irfan brand palette
// (see Docs/RESEARCH_NOTES.md). All tokens adapt to light/dark.

// MARK: - Colors

extension Color {
    fileprivate init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

/// Semantic color tokens. Use these — never raw hex — in feature code.
enum DIColor {
    /// Deep emerald; primary actions, selected states.
    static let primary = Color(light: 0x0B6E4F, dark: 0x4CA383)
    /// Darker emerald; headers, prominent surfaces.
    static let primaryDeep = Color(light: 0x063D2C, dark: 0x0B4635)
    /// Restrained gold; highlights, current-prayer marker, accents only.
    static let accent = Color(light: 0xC9A24B, dark: 0xD9BC72)
    /// Warm cream app background.
    static let background = Color(light: 0xF6F3EC, dark: 0x141714)
    /// Card/surface background.
    static let surface = Color(light: 0xFFFFFF, dark: 0x1E231F)
    /// Primary text.
    static let textPrimary = Color(light: 0x1C1C1C, dark: 0xF2EFE6)
    /// Secondary/muted text.
    static let textMuted = Color(light: 0x6B6B6B, dark: 0xA8A69C)
    /// Hairline borders and separators.
    static let border = Color(light: 0xE2DCCD, dark: 0x343A33)
    /// Errors/destructive.
    static let danger = Color(light: 0xB3261E, dark: 0xE5695F)
    /// Text/icons on top of `primary`/`primaryDeep`.
    static let onPrimary = Color.white
}

// MARK: - Spacing & radii

enum DISpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum DIRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 20
}

// MARK: - Typography

enum DIFont {
    /// Quran Arabic text. SF's Arabic glyphs are high quality; sized generously
    /// and scaled with Dynamic Type via `relativeTo`.
    static func quranArabic(scale: Double = 1.0) -> Font {
        .system(size: 28 * scale, weight: .regular)
    }

    /// Urdu body text. iOS bundles Noto Nastaliq Urdu; fall back is automatic
    /// if the face is unavailable.
    static func urduBody(scale: Double = 1.0) -> Font {
        .custom("NotoNastaliqUrdu", size: 18 * scale, relativeTo: .body)
    }

    /// Section headings with a slightly bookish feel.
    static let heading = Font.system(.title2, design: .serif).weight(.semibold)
    static let subheading = Font.system(.headline, design: .serif)

    /// Large prayer countdown numerals.
    static let countdown = Font.system(size: 44, weight: .light, design: .rounded)
        .monospacedDigit()
}

// MARK: - Theme application

extension AppTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
