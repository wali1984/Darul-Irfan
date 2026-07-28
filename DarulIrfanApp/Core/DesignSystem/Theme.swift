import SwiftUI
import UIKit

// Design language: reverent, classical, scholarly — derived from the
// naqshbandiaowaisiah.org identity. The site's chrome is warm CHARCOAL INK +
// GOLD/SANDSTONE + CREAM, with EMERALD reserved for the silsila seal (brand
// mark, primary actions). Sacred text gets a soft gold halo. Al-Murshid TV
// keeps its own crimson skin. All tokens adapt to light/dark and stay warm
// (never cold gray). See Docs/BRAND.md.

// MARK: - Colors

extension Color {
    fileprivate init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }

    /// Hex initializer for fixed-canvas contexts (share cards, ornaments) that
    /// need explicit colors independent of the semantic tokens. Accepts 0xRRGGBB.
    init(hex: UInt32) {
        self.init(uiColor: UIColor(rgb: hex))
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
    /// Seal emerald; brand mark, primary actions, selected states.
    static let primary = Color(light: 0x0B7250, dark: 0x1E9068)
    /// Forest emerald; seal ring, pressed states, gradients, hero fills.
    static let primaryDeep = Color(light: 0x064B34, dark: 0x0B6E4F)
    /// The site's true gold; highlights, dividers, current-prayer marker, accents.
    static let accent = Color(light: 0xC6A253, dark: 0xE0B75F)
    /// Warm cream app background (matches the site cream).
    static let background = Color(light: 0xF2EFE7, dark: 0x141310)
    /// Warm paper card surface.
    static let surface = Color(light: 0xFCFAF3, dark: 0x1F1D18)
    /// Sandstone surface, for hero panels and elevated devotional cards.
    static let sandstone = Color(light: 0xEFE7D8, dark: 0x262319)
    /// Charcoal ink — the signature (never pure black).
    static let textPrimary = Color(light: 0x1D1C1C, dark: 0xF3EEE2)
    /// Warm taupe muted text.
    static let textMuted = Color(light: 0x6B6357, dark: 0xA79E8C)
    /// Warm sand hairline borders and separators.
    static let border = Color(light: 0xE4D9C6, dark: 0x33302A)
    /// Errors/destructive.
    static let danger = Color(light: 0xB3261E, dark: 0xE5695F)
    /// Al-Murshid TV sub-brand crimson (media/video section only).
    static let crimson = Color(light: 0xB01E1E, dark: 0xD84A46)
    /// The saffron-gold used for the halo/glow around sacred text.
    static let goldGlow = Color(hex: 0xFBCE54)
    /// Text/icons on top of `primary`/`primaryDeep`.
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0xF3EEE2)
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
    /// Quran Arabic text in the bundled Amiri Quran Uthmanic face (OFL) for an
    /// authentic mushaf look, scaled with Dynamic Type. Uses the runtime-
    /// resolved font name (see AppFonts); falls back to system if unavailable.
    static func quranArabic(scale: Double = 1.0) -> Font {
        .custom(AppFonts.quranArabicName, size: 27 * scale, relativeTo: .title2)
    }

    /// Urdu body text in the bundled Noto Nastaliq Urdu face (OFL) for proper
    /// Nastaliq rendering, scaled with Dynamic Type.
    static func urduBody(scale: Double = 1.0) -> Font {
        .custom(AppFonts.urduName, size: 17 * scale, relativeTo: .body)
    }

    /// Section headings with a slightly bookish feel.
    static let heading = Font.system(.title2, design: .serif).weight(.semibold)
    static let subheading = Font.system(.headline, design: .serif)

    /// Large prayer countdown numerals.
    static let countdown = Font.system(size: 44, weight: .light, design: .rounded)
        .monospacedDigit()
}

// MARK: - Sacred-text glow

private struct GoldGlow: ViewModifier {
    var radius: CGFloat
    var opacity: Double
    func body(content: Content) -> some View {
        content.shadow(color: DIColor.goldGlow.opacity(opacity), radius: radius)
    }
}

extension View {
    /// The site's signature soft golden halo around devotional Nastaliq/Arabic
    /// text (mirrors `text-shadow: 0 0 25px #fbce54`). Use sparingly, only on
    /// sacred headings/verses.
    func diGoldGlow(radius: CGFloat = 12, opacity: Double = 0.55) -> some View {
        modifier(GoldGlow(radius: radius, opacity: opacity))
    }
}

// MARK: - The anchoring verse (Qur'an 13:28) — the app's spiritual signature

enum DIBrand {
    /// اَلَا بِذِکْرِ اللّٰہِ تَطْمَئِنُّ الْقُلُوْبُ — used on splash/home headers.
    static let anchorVerseArabic = "اَلَا بِذِكْرِ اللّٰهِ تَطْمَئِنُّ الْقُلُوْبُ"
    /// English rendering of 13:28 (Pickthall, public domain).
    static let anchorVerseEnglish = "Verily, in the remembrance of Allah do hearts find peace."
    static let anchorVerseReference = "Qur'an 13:28"
    /// Site tagline, used as an onboarding/subtitle line.
    static let tagline = "Exploring the Treasures of the Heart"
    static let wordmark = "Darul Irfan"
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
