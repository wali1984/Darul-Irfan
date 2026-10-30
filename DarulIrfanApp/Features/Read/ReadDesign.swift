import SwiftUI
import UIKit

// The Read tab's look (parity-spec/redesign/boards: Read, Book and
// BookReader): glass panels, the octagram surah badge, glossy orbs, a line of
// gold progress light and small-capital labels. Colours follow the boards in
// light and dark. Every movement here is still under Reduce Motion.

// MARK: - Colours

/// The boards' colours that the shared tokens do not carry, light and dark.
enum ReadPalette {
    /// Emerald text and icons on glass: #0B7250, #3FC596 at night.
    static let emeraldInk = adaptive(light: 0x0B7250, dark: 0x3FC596)
    /// Small gold text, 4.5:1 on cream; the gold itself at night.
    static let goldInk = adaptive(light: 0x7A5A14, dark: 0xE0B75F)
    /// Gold icons and rules: #B8913F, #E0B75F at night.
    static let goldLine = adaptive(light: 0xB8913F, dark: 0xE0B75F)
    /// The Arabic names in the surah list.
    static let arabicInk = adaptive(light: 0x0A5C40, dark: 0xF5D98A)
    /// The revelation-place pills.
    static let makkahInk = adaptive(light: 0x0B7250, dark: 0x3FC596)
    static let madinahInk = adaptive(light: 0x7A5A14, dark: 0xE0B75F)
    /// The hairline between rows on a glass panel.
    static let rowEdge = adaptive(light: 0x0B7250, lightAlpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.06)
    /// The track under a small toggle, a find field or a chip.
    static let chipTrack = adaptive(light: 0x0B7250, lightAlpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.08)
    /// The chosen side of a small toggle.
    static let chipOn = adaptive(light: 0xFFFFFF, dark: 0xFFFFFF, darkAlpha: 0.16)
    /// The light edge of glass.
    static let glassEdge = adaptive(light: 0xFFFFFF, lightAlpha: 0.85, dark: 0xFFFFFF, darkAlpha: 0.10)
    /// The soft shadow under glass: emerald by day, black at night.
    static let softShadow = adaptive(light: 0x064B34, lightAlpha: 0.13, dark: 0x000000, darkAlpha: 0.45)
    /// The reader's page: paper by day, a warm dark page at night.
    static let paper = adaptive(light: 0xFFFDF7, dark: 0x1B1914)
    static let paperEdge = adaptive(light: 0xE0B75F, lightAlpha: 0.35, dark: 0xE0B75F, darkAlpha: 0.22)
    static let pageGlow = adaptive(light: 0xFBCE54, lightAlpha: 0.18, dark: 0xFBCE54, darkAlpha: 0.10)

    private static func adaptive(
        light: UInt32,
        lightAlpha: CGFloat = 1,
        dark: UInt32,
        darkAlpha: CGFloat = 1
    ) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? ReadPalette.uiColor(dark, alpha: darkAlpha)
                : ReadPalette.uiColor(light, alpha: lightAlpha)
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

// MARK: - Glass for long lists

extension View {
    /// The glass of `diGlassPanel` (material, a light edge and a soft shadow)
    /// for a long list such as the 114 surahs. The shadow is drawn from the
    /// panel's shape alone: one taken from every row would be redrawn on
    /// each frame of a scroll.
    func readGlassList(cornerRadius: CGFloat = 26) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.08), radius: 14, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    /// A slow band of light passing across a hero card, clipped to its shape.
    func readSheen(cornerRadius: CGFloat = 26, period: Double = 7, strength: Double = 0.14) -> some View {
        modifier(ReadSheen(cornerRadius: cornerRadius, period: period, strength: strength))
    }
}

private struct ReadSheen: ViewModifier {
    let cornerRadius: CGFloat
    let period: Double
    let strength: Double
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                if !reduceMotion {
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(strength), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.4)
                    .offset(x: phase * geo.size.width * 1.6)
                    .onAppear {
                        withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: false).delay(1.2)) {
                            phase = 1.2
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        )
    }
}

// MARK: - Labels

/// The small capitals over a card's title ("CONTINUE READING"). Urdu has no
/// capitals and takes no letter spacing.
struct ReadCaps: View {
    let titleKey: LocalizedStringKey
    var color: Color
    @Environment(\.locale) private var locale

    init(_ titleKey: LocalizedStringKey, color: Color = ReadPalette.goldInk) {
        self.titleKey = titleKey
        self.color = color
    }

    var body: some View {
        Text(titleKey)
            .font(.caption2.weight(.heavy))
            .tracking(readsUrdu ? 0 : 1.6)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    private var readsUrdu: Bool { locale.language.languageCode?.identifier == "ur" }
}

/// A group's title over its panel: small capitals, letter-spaced, muted.
struct ReadGroupTitle: View {
    let titleKey: LocalizedStringKey
    @Environment(\.locale) private var locale

    var body: some View {
        Text(titleKey)
            .font(.footnote.weight(.heavy))
            .tracking(readsUrdu ? 0 : 1.2)
            .textCase(.uppercase)
            .foregroundStyle(DIColor.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DISpacing.xs)
            .padding(.top, DISpacing.xs)
            .accessibilityAddTraits(.isHeader)
    }

    private var readsUrdu: Bool { locale.language.languageCode?.identifier == "ur" }
}

/// The hairline between two rows of a glass panel.
struct ReadRowRule: View {
    var body: some View {
        Rectangle()
            .fill(ReadPalette.rowEdge)
            .frame(height: 1)
            .padding(.horizontal, 12)
            .accessibilityHidden(true)
    }
}

// MARK: - Badges and orbs

/// A number on a filled eight-pointed star: emerald for a Makkan surah or a
/// parah, gold for a Madinan surah.
struct ReadOctagramBadge: View {
    let number: Int
    var gold = false

    var body: some View {
        ZStack {
            DIOctagram(innerRatio: 0.76)
                .fill(gold ? Color(hex: 0xB48A2C) : Color(hex: 0x0B7250))
                .accessibilityHidden(true)
            Text("\(number)")
                .font(.system(size: 13, weight: .heavy).monospacedDigit())
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 5)
        }
        .frame(width: 40, height: 40)
    }
}

/// A small glossy orb holding a symbol: emerald, or gold for the treasures.
struct ReadOrb: View {
    let systemImage: String
    var gold = false
    var diameter: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: diameter * 0.42, weight: .semibold))
            .foregroundStyle(gold ? Color(hex: 0x064B34) : Color.white)
            .frame(width: diameter, height: diameter)
            .background(
                Circle().fill(
                    RadialGradient(
                        colors: gold
                            ? [Color(hex: 0xFFE9A8), Color(hex: 0xE0B75F), Color(hex: 0xB48A2C)]
                            : [Color(hex: 0x34B98A), Color(hex: 0x0B7250), Color(hex: 0x064B34)],
                        center: UnitPoint(x: 0.32, y: 0.26),
                        startRadius: 0,
                        endRadius: diameter * 0.75
                    )
                )
            )
            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
            .shadow(color: ReadPalette.softShadow, radius: 7, y: 6)
            .accessibilityHidden(true)
    }
}

/// The gold play disc at the end of the Quran's Continue reading card.
struct ReadPlayDisc: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color(hex: 0x064B34))
            .frame(width: 44, height: 44)
            .background(
                Circle().fill(
                    LinearGradient(
                        colors: [Color(hex: 0xFFE9A8), Color(hex: 0xE0B75F)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .shadow(color: DIColor.goldGlow.opacity(0.55), radius: 9)
            .accessibilityHidden(true)
    }
}

/// How far through: a thin line of light on a faint track.
struct ReadProgressLight: View {
    let fraction: Double
    var height: CGFloat = 5
    var track: Color = Color.white.opacity(0.18)
    var colors: [Color] = [Color(hex: 0xFFE9A8), Color(hex: 0xFBCE54)]
    var glows = true

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
                    .shadow(color: glows ? DIColor.goldGlow.opacity(0.8) : Color.clear, radius: 5)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Controls

/// The switch at the top of every reader's page: Quran | Hadith | Books.
struct ReadSectionPicker: View {
    @Binding var selection: ReadSection

    var body: some View {
        DISegmentedControl(
            items: ReadSection.allCases,
            title: { $0.title },
            selection: $selection
        )
    }
}

/// A small two-way toggle on the chip track (Surah | Parah): the chosen side
/// is a white pill.
struct ReadChipToggle<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> LocalizedStringKey
    @Binding var selection: Item
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                segment(item)
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(ReadPalette.chipTrack))
    }

    private func segment(_ item: Item) -> some View {
        let selected = item == selection
        return Button {
            DIHaptics.soft()
            if reduceMotion {
                selection = item
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { selection = item }
            }
        } label: {
            Text(title(item))
                .font(.subheadline.weight(selected ? .bold : .semibold))
                .foregroundStyle(selected ? DIColor.textPrimary : DIColor.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background {
                    if selected {
                        Capsule(style: .continuous)
                            .fill(ReadPalette.chipOn)
                            .shadow(color: ReadPalette.softShadow, radius: 4, y: 2)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The find field on the Quran and Hadith pages, on the chip track.
struct ReadFindField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DIColor.textMuted)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(DIColor.textPrimary)
            if !text.isEmpty {
                Button {
                    DIHaptics.light()
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DIColor.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search text")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Capsule(style: .continuous).fill(ReadPalette.chipTrack))
    }
}
