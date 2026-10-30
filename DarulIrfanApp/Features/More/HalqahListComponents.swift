import SwiftUI
import UIKit

// The Halqah tab's own pieces, drawn as its board (parity-spec/redesign/
// boards/Halqah.dc.html) draws them: the brand header on glass, the small
// capital labels over each group, the glass lists of rows with their
// coloured symbol tiles, and the Silsila's star turning slowly behind the
// page. Settings uses the same rows, so every setting reads the same.

// MARK: - Colours

/// The board's colours that the design system has no token for.
enum HalqahInk {
    /// Small gold text: #7A5A14 on cream, #E0B75F at night, for 4.5:1.
    static let goldText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 224.0 / 255.0, green: 183.0 / 255.0, blue: 95.0 / 255.0, alpha: 1)
            : UIColor(red: 122.0 / 255.0, green: 90.0 / 255.0, blue: 20.0 / 255.0, alpha: 1)
    })

    /// The soft gold glow at the top of the page, fainter at night.
    static let pageGlow = Color(uiColor: UIColor { traits in
        UIColor(red: 251.0 / 255.0, green: 206.0 / 255.0, blue: 84.0 / 255.0, alpha: traits.userInterfaceStyle == .dark ? 0.15 : 0.26)
    })

    static let tileGreen = LinearGradient(
        colors: [Color(hex: 0x13A06F), Color(hex: 0x0B7250)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let tileGold = LinearGradient(
        colors: [Color(hex: 0xFFE9A8), Color(hex: 0xE0B75F)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Brand header

/// The tab's brand header: the living Silsila seal beside Darul Irfan, the
/// site's tagline and the Silsila's name, on glass. The seal stays where it
/// always was on this tab.
struct HalqahBrandHeader: View {
    var body: some View {
        HStack(spacing: DISpacing.md) {
            DILivingSealMark(diameter: 54)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: DIBrand.wordmark)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(DIColor.textPrimary)
                Text(verbatim: DIBrand.tagline)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HalqahInk.goldText)
                Text("Silsila Naqshbandia Owaisiah")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.leading, 14)
        .padding(.trailing, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .diGlassPanel(cornerRadius: 26)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Section label

/// The small capital label over a group of rows ("MY HALQAHS", "SILSILA").
/// Urdu is never spaced out, and has no capitals to change to.
struct HalqahSectionLabel: View {
    let titleKey: LocalizedStringKey
    @Environment(\.locale) private var locale

    var body: some View {
        Text(titleKey)
            .font(.footnote.weight(.heavy))
            .tracking(DIBrand.readsUrdu(locale) ? 0 : 1.2)
            .textCase(.uppercase)
            .foregroundStyle(DIColor.textMuted)
            .padding(.horizontal, DISpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Glass list

/// Rows on one glass panel, as the board's lists are. The rows are divided
/// with `HalqahRowDivider`.
struct HalqahGlassList<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .diGlassPanel(cornerRadius: 24)
    }
}

/// The hairline between two rows of a glass list.
struct HalqahRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(DIColor.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 12)
            .accessibilityHidden(true)
    }
}

/// The colour of a row's symbol tile.
enum HalqahRowTint {
    case green, gold, danger
}

/// A row's symbol on its small rounded tile: emerald, gold, or the soft red
/// of a destructive action.
struct HalqahRowTile: View {
    let systemImage: String
    var tint: HalqahRowTint = .green
    /// Turns an arrow to point the way Urdu reads.
    var mirrors = false
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 32

    var body: some View {
        Image(systemName: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(foreground)
            .flipsForRightToLeftLayoutDirection(mirrors)
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tileFill))
            .accessibilityHidden(true)
    }

    private var foreground: Color {
        switch tint {
        case .green: return Color.white
        case .gold: return Color(hex: 0x064B34)
        case .danger: return DIColor.danger
        }
    }

    private var tileFill: AnyShapeStyle {
        switch tint {
        case .green: return AnyShapeStyle(HalqahInk.tileGreen)
        case .gold: return AnyShapeStyle(HalqahInk.tileGold)
        case .danger: return AnyShapeStyle(DIColor.danger.opacity(0.12))
        }
    }
}

/// One row of a glass list: its symbol tile, its name, a value at a glance,
/// and a chevron (or the menu's up-and-down chevron).
struct HalqahListRowLabel: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    var value: Text? = nil
    var tint: HalqahRowTint = .green
    var mirrorsSymbol = false
    var showsChevron = true
    var chevronSymbol = "chevron.forward"
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 52

    var body: some View {
        HStack(spacing: 12) {
            HalqahRowTile(systemImage: systemImage, tint: tint, mirrors: mirrorsSymbol)
            Text(titleKey)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint == .danger ? DIColor.danger : DIColor.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DISpacing.sm)
            if let value {
                value
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: chevronSymbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - The turning star

/// Two squares, one turned on its point: the eight-point star the boards
/// draw behind the page and in the corner of a hero card.
struct HalqahStarOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let minX = rect.midX - side / 2
        let minY = rect.midY - side / 2
        let inset = side * 0.15
        var path = Path()
        // The upright square, 15% in from each edge.
        path.move(to: CGPoint(x: minX + inset, y: minY + inset))
        path.addLine(to: CGPoint(x: minX + side - inset, y: minY + inset))
        path.addLine(to: CGPoint(x: minX + side - inset, y: minY + side - inset))
        path.addLine(to: CGPoint(x: minX + inset, y: minY + side - inset))
        path.closeSubpath()
        // The square on its point, corner to corner.
        path.move(to: CGPoint(x: rect.midX, y: minY))
        path.addLine(to: CGPoint(x: minX + side, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: minY + side))
        path.addLine(to: CGPoint(x: minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// The star, turning very slowly; still under Reduce Motion.
struct HalqahTurningStar: View {
    var color: Color = DIColor.goldGlow
    var lineWidth: CGFloat = 1
    /// Seconds for one turn.
    var period: Double = 90
    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HalqahStarOutline()
            .stroke(color, lineWidth: lineWidth)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                    turning = true
                }
            }
    }
}

/// The page's light, as the board draws it: a soft gold glow at the top and
/// the Silsila's star turning very slowly at the right edge. It sits behind
/// the page's content and takes no part in its layout.
struct HalqahPageDecor: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(
                    colors: [HalqahInk.pageGlow, Color.clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: max(geo.size.width, 1) * 0.8
                )
                .frame(width: geo.size.width, height: 320)
                .position(x: geo.size.width / 2, y: 100)
                HalqahTurningStar(color: DIColor.accent, lineWidth: 1.8, period: 180)
                    .frame(width: 520, height: 520)
                    .opacity(0.2)
                    .position(x: geo.size.width, y: 780)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
