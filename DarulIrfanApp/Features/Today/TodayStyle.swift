import SwiftUI
import UIKit

// The October 2026 redesign's look for Today and the Prayer times page
// (parity-spec/redesign, boards Main, TodayDark and Prayer): the colours the
// shared tokens do not carry, the glass the cards sit on, the pill buttons,
// the slowly turning octagram and the section titles. Every value is the
// boards' own, light and dark. Motion stops under Reduce Motion.

// MARK: - Colours

/// The boards' colours for Today and the Prayer times page, each with its
/// light and dark value.
enum TodayPalette {
    /// Emerald text and icons: #0B7250, and #3FC596 at night.
    static let emerald = dynamic(light: 0x0B7250, dark: 0x3FC596)
    /// The gold of ornaments and small marks: #B8913F, and #E0B75F at night.
    static let accent = dynamic(light: 0xB8913F, dark: 0xE0B75F)
    /// Small gold text that stays readable (4.5:1): #7A5A14 on cream,
    /// #E0B75F at night.
    static let goldText = dynamic(light: 0x7A5A14, dark: 0xE0B75F)
    /// The Arabic of the daily cards: deep emerald by day, soft gold at night.
    static let arabicInk = dynamic(light: 0x0A5C40, dark: 0xF5D98A)
    /// Arabic set back a step, as the hadith's original.
    static let arabicSoft = dynamic(light: 0x4A4438, dark: 0xCFC6B2)
    /// The glass under cards and lists.
    static let glassFill = dynamic(light: 0xFCFAF3, dark: 0x1F1D18, lightAlpha: 0.72, darkAlpha: 0.62)
    /// The glass's bright edge.
    static let glassEdge = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.85, darkAlpha: 0.10)
    /// The daily card's paper, top and bottom.
    static let cardTop = dynamic(light: 0xFFFDF7, dark: 0x26231C, lightAlpha: 0.92, darkAlpha: 0.86)
    static let cardBottom = dynamic(light: 0xFAF6EA, dark: 0x181612, lightAlpha: 0.78, darkAlpha: 0.80)
    /// The gold glow breathing at the top of the daily card.
    static let cardGlow = dynamic(light: 0xFBCE54, dark: 0xFBCE54, lightAlpha: 0.32, darkAlpha: 0.22)
    /// The soft gold light at the top of the page.
    static let topGlow = dynamic(light: 0xFBCE54, dark: 0xFBCE54, lightAlpha: 0.26, darkAlpha: 0.14)
    /// Quiet fills for chips and tiles on glass.
    static let chipFill = dynamic(light: 0x0B7250, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.06)
    /// The hairline round a tile on glass.
    static let tileEdge = dynamic(light: 0x0B7250, dark: 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.08)
    /// A row's dividing line on glass.
    static let rowEdge = dynamic(light: 0x0B7250, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.06)
    /// An empty mark: the ring of a prayer not marked, and its dot.
    static let dotOff = dynamic(light: 0x0B7250, dark: 0xFFFFFF, lightAlpha: 0.18, darkAlpha: 0.18)
    /// The page dots under the daily card, when not the one shown.
    static let pageDot = dynamic(light: 0x0B7250, dark: 0xFFFFFF, lightAlpha: 0.22, darkAlpha: 0.22)
    /// A progress track.
    static let track = dynamic(light: 0x0B7250, dark: 0xFFFFFF, lightAlpha: 0.12, darkAlpha: 0.10)
    /// Qaza, to make up: a warm rust by day, a soft coral at night.
    static let qazaInk = dynamic(light: 0xB3561E, dark: 0xFFB4A2)

    private static func dynamic(
        light: UInt32,
        dark: UInt32,
        lightAlpha: CGFloat = 1,
        darkAlpha: CGFloat = 1
    ) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? TodayPalette.uiColor(dark, alpha: darkAlpha)
                : TodayPalette.uiColor(light, alpha: lightAlpha)
        })
    }

    private static func uiColor(_ rgb: UInt32, alpha: CGFloat) -> UIColor {
        UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

/// The boards' gradients: emerald for an action, gold for the key one.
enum TodayGradients {
    static let emerald = LinearGradient(
        colors: [Color(hex: 0x13A06F), Color(hex: 0x0B7250)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let gold = LinearGradient(
        colors: [Color(hex: 0xFFE9A8), Color(hex: 0xE0B75F)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// The brighter gold of a prayer prayed in congregation, on the card.
    static let brightGold = LinearGradient(
        colors: [Color(hex: 0xFFF4CF), Color(hex: 0xFBCE54)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// A prayer marked prayed, on glass.
    static let markEmerald = LinearGradient(
        colors: [Color(hex: 0x34B98A), Color(hex: 0x0B7250)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// The lit row of the next prayer.
    static let nextRow = LinearGradient(
        colors: [Color(hex: 0x0E8A60), Color(hex: 0x0B7250), Color(hex: 0x075C40)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// Ink on gold.
    static let onGold = Color(hex: 0x064B34)
}

// MARK: - Glass

extension View {
    /// The redesign's glass under Today's cards and lists: the warm
    /// translucent fill over the material of `diGlassPanel`, with the
    /// boards' bright edge.
    func todayGlass(cornerRadius: CGFloat = 26) -> some View {
        self
            .background(TodayPalette.glassFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .todayGlassChrome(cornerRadius: cornerRadius)
    }

    /// The glass's material, edge and shadow, for a surface that draws its
    /// own fill.
    func todayGlassChrome(cornerRadius: CGFloat = 26) -> some View {
        self
            .diGlassPanel(cornerRadius: cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(TodayPalette.glassEdge, lineWidth: 1)
            )
    }
}

/// The soft gold light at the top of the redesign's pages, behind the
/// content.
struct TodayPageGlow: View {
    var body: some View {
        VStack(spacing: 0) {
            RadialGradient(
                colors: [TodayPalette.topGlow, Color.clear],
                center: .top,
                startRadius: 0,
                endRadius: 380
            )
            .frame(height: 380)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Section title

/// A section's title on Today: a gold glyph and the name in heavy type.
struct TodaySectionTitle: View {
    let titleKey: LocalizedStringKey
    let systemImage: String

    var body: some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(TodayPalette.accent)
                .accessibilityHidden(true)
            Text(titleKey)
                .font(.title3.weight(.heavy))
                .foregroundStyle(DIColor.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Pill buttons

/// The redesign's pill button face, 44 pt high: emerald for an action, gold
/// for the key one, glass for a quieter one. Put it in a Button or a
/// NavigationLink with `DIPressableStyle`.
struct TodayPill: View {
    enum Kind {
        case emerald, gold, glass
    }

    let titleKey: LocalizedStringKey
    var systemImage: String? = nil
    var kind: Kind = .emerald
    /// Takes the width left in its row.
    var expands = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.bold))
                    .accessibilityHidden(true)
            }
            Text(titleKey)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 16)
        .frame(maxWidth: expands ? CGFloat.infinity : nil, minHeight: 44)
        .background(fill, in: Capsule())
        .overlay(Capsule().stroke(kind == .glass ? TodayPalette.glassEdge : Color.clear, lineWidth: 1))
        .shadow(color: glow, radius: 9, y: kind == .gold ? 0 : 6)
        .contentShape(Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .emerald: return Color.white
        case .gold: return TodayGradients.onGold
        case .glass: return TodayPalette.emerald
        }
    }

    private var fill: AnyShapeStyle {
        switch kind {
        case .emerald: return AnyShapeStyle(TodayGradients.emerald)
        case .gold: return AnyShapeStyle(TodayGradients.gold)
        case .glass: return AnyShapeStyle(TodayPalette.glassFill)
        }
    }

    private var glow: Color {
        switch kind {
        case .emerald: return Color(hex: 0x0B7250).opacity(0.35)
        case .gold: return DIColor.goldGlow.opacity(0.45)
        case .glass: return Color.clear
        }
    }
}

// MARK: - Ornaments

/// The redesign's octagram outline (two squares, one turned through 45
/// degrees), turning slowly. Still under Reduce Motion, and when `turns` is
/// false (a card kept laid out but out of sight).
struct TodayTurningOctagram: View {
    let size: CGFloat
    var color: Color = TodayPalette.accent
    var lineWidth: CGFloat = 1
    /// Seconds for one turn.
    var period: Double = 90
    var turns = true

    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .stroke(color, lineWidth: lineWidth)
                .frame(width: size * 0.7, height: size * 0.7)
            Rectangle()
                .stroke(color, lineWidth: lineWidth)
                .frame(width: size * 0.7, height: size * 0.7)
                .rotationEffect(.degrees(45))
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(turning ? 360 : 0))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard turns, !reduceMotion else { return }
            withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                turning = true
            }
        }
    }
}

/// A gold rule with a small octagram at its centre, between a verse and its
/// translation.
struct TodayOrnamentRule: View {
    var body: some View {
        HStack(spacing: 10) {
            LinearGradient(colors: [Color.clear, TodayPalette.accent], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
            ZStack {
                Rectangle()
                    .stroke(TodayPalette.accent, lineWidth: 1.2)
                    .frame(width: 9, height: 9)
                Rectangle()
                    .stroke(TodayPalette.accent, lineWidth: 1.2)
                    .frame(width: 9, height: 9)
                    .rotationEffect(.degrees(45))
            }
            .frame(width: 14, height: 14)
            LinearGradient(colors: [TodayPalette.accent, Color.clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

/// A small glossy orb holding an icon, as on the Continue tiles: emerald,
/// or gold.
struct TodayOrbIcon: View {
    let systemImage: String
    var gold = false
    var diameter: CGFloat = 38

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(gold ? TodayGradients.onGold : Color.white)
            .frame(width: diameter, height: diameter)
            .background(
                Circle().fill(
                    RadialGradient(
                        colors: gold
                            ? [Color(hex: 0xFFE9A8), Color(hex: 0xE0B75F), Color(hex: 0xB48A2C)]
                            : [Color(hex: 0x34B98A), Color(hex: 0x0B7250), Color(hex: 0x064B34)],
                        center: UnitPoint(x: 0.32, y: 0.26),
                        startRadius: 0,
                        endRadius: diameter * 0.7
                    )
                )
            )
            .shadow(color: (gold ? Color(hex: 0xB48A2C) : Color(hex: 0x0B7250)).opacity(0.35), radius: 7, y: 6)
            .accessibilityHidden(true)
    }
}
