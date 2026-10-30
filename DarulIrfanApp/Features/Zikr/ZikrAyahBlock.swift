import SwiftUI

/// Qur'an 13:28 at the head of the Zikr tab, centred on a glass panel (the
/// owner: "Ayat and its translation needs to be centerd as well as add
/// animations to it"): the living seal, the ayah with a band of gold light
/// passing over it and slow rays turning behind, then the Silsila's own
/// translation rising in under it, and the reference.
struct ZikrAyahBlock: View {
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme

    private var inUrdu: Bool { DIBrand.readsUrdu(locale) }
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(spacing: 10) {
            DILivingSealMark(diameter: 56)
            Text(DIBrand.anchorVerseArabic)
                .font(DIFont.quranArabic(scale: 1.1))
                .foregroundStyle(isDark ? Color(hex: 0xF5D98A) : Color(hex: 0x0A5C40))
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .environment(\.layoutDirection, .rightToLeft)
                .diGoldTextShimmer(highlight: isDark ? Color(hex: 0xFFF7DA) : Color(hex: 0xD9A93C))
                .diGoldGlow(radius: isDark ? 12 : 8, opacity: isDark ? 0.55 : 0.35)
                .padding(.top, 6)
            translation
                .diAppear(delay: 0.3)
            Text(DIBrand.anchorVerseReference)
                .font(.caption2.weight(.heavy))
                .tracking(inUrdu ? 0 : 1.8)
                .textCase(.uppercase)
                .foregroundStyle(isDark ? DIColor.accent : Color(hex: 0x7A5A14))
                .diAppear(delay: 0.7)
        }
        .padding(.horizontal, DISpacing.md)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background { lightBehind }
        .diGlassPanel(cornerRadius: 30)
        .accessibilityElement(children: .combine)
    }

    /// The Silsila's translation of 13:28 in the reader's language.
    @ViewBuilder
    private var translation: some View {
        if inUrdu {
            Text(verbatim: DIBrand.anchorVerseUrdu)
                .font(DIFont.urduBody(scale: 0.95))
                .foregroundStyle(DIColor.textPrimary)
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: 300)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(verbatim: DIBrand.anchorVerseEnglish)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DIColor.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 300)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A soft gold glow from the top and the slow rays, inside the panel.
    private var lightBehind: some View {
        ZStack {
            RadialGradient(
                colors: [DIColor.goldGlow.opacity(isDark ? 0.16 : 0.18), DIColor.goldGlow.opacity(0)],
                center: .top,
                startRadius: 0,
                endRadius: 280
            )
            DILightRays(color: isDark ? DIColor.goldGlow : Color(hex: 0xE0B75F), opacity: isDark ? 0.14 : 0.20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}
