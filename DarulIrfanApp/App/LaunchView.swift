import SwiftUI

/// Brand splash shown while the dependency graph is built and settings load.
/// Deliberately quiet: deep emerald field, the app's name in Urdu and
/// English, the tagline, and a subtle progress indicator.
struct LaunchView: View {
    var body: some View {
        ZStack {
            DIGradient.hero().ignoresSafeArea()
            DIPatternTexture(tint: .white, opacity: 0.08).ignoresSafeArea()
            DIGradient.auraGold.ignoresSafeArea()

            VStack(spacing: DISpacing.lg) {
                DISealEmblem(diameter: 132, glow: true)
                    .diBreathingGlow(color: DIColor.goldGlow, maxRadius: 26)

                VStack(spacing: DISpacing.sm) {
                    Text(verbatim: "دارالعرفان")
                        .font(DIFont.urduBody(scale: 2.2))
                        .foregroundStyle(DIColor.onPrimary)
                        .diGoldGlow(radius: 14, opacity: 0.5)

                    Text("Darul Irfan")
                        .font(.system(.title, design: .serif).weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(DIColor.onPrimary.opacity(0.95))

                    Text(DIBrand.tagline)
                        .font(.subheadline)
                        .foregroundStyle(DIColor.accent)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)

                Text(DIBrand.anchorVerseArabic)
                    .font(DIFont.quranArabic(scale: 0.8))
                    .foregroundStyle(DIColor.onPrimary.opacity(0.9))
                    .diGoldGlow(radius: 12, opacity: 0.45)
                    .environment(\.layoutDirection, .rightToLeft)
                    .multilineTextAlignment(.center)
                    .padding(.top, DISpacing.sm)

                ProgressView()
                    .tint(DIColor.accent)
                    .padding(.top, DISpacing.md)
                    .accessibilityLabel("Loading")
            }
            .padding(DISpacing.xl)
        }
    }
}
