import SwiftUI

// The October 2026 redesign's light (parity-spec/redesign): slow aurora light
// in hero cards, rays of light behind the Zikr ayah, a band of gold passing
// over gilded Arabic, glossy tool orbs, and the glass panel every list and
// card sits on. Calm and slow; Reduce Motion stills all of it.

// MARK: - Aurora

/// Three soft, blurred blobs of light (emerald, gold, blue) drifting slowly
/// across a hero card. Sits behind the content, clipped by the card.
struct DIAuroraLayer: View {
    var intensity: Double = 1
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack {
                blob(Color(hex: 0x40D6A0), opacity: 0.55, size: width * 0.85)
                    .offset(x: drift ? width * 0.10 : -width * 0.30, y: drift ? -width * 0.05 : -width * 0.30)
                blob(DIColor.goldGlow, opacity: 0.40, size: width * 0.75)
                    .offset(x: drift ? width * 0.20 : width * 0.40, y: drift ? width * 0.10 : -width * 0.05)
                blob(Color(hex: 0x1A78A0), opacity: 0.30, size: width * 0.70)
                    .offset(x: drift ? -width * 0.15 : width * 0.05, y: drift ? width * 0.35 : width * 0.55)
            }
            .frame(width: width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func blob(_ color: Color, opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity * intensity), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .blur(radius: 18)
    }
}

// MARK: - Hero surface

/// The emerald hero surface: a deep gradient with the aurora drifting over it
/// and the octagram watermark. Content goes on top in white and gold.
struct DIHeroBackground: View {
    var cornerRadius: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: 0x0E8A60), Color(hex: 0x0B7250), Color(hex: 0x064B34), Color(hex: 0x03261A)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                DIAuroraLayer()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color(hex: 0x064B34).opacity(0.40), radius: 22, y: 14)
            .accessibilityHidden(true)
    }
}

// MARK: - Light rays

/// Slow rays of gold light turning behind a centred block, such as the ayah
/// at the head of the Zikr tab. Fades out towards its edges.
struct DILightRays: View {
    var color: Color = DIColor.goldGlow
    var opacity: Double = 0.18
    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height) * 1.6
            AngularGradient(gradient: Gradient(stops: rayStops), center: .center)
                .frame(width: side, height: side)
                .mask(
                    RadialGradient(
                        colors: [Color.black, Color.black.opacity(0)],
                        center: .center,
                        startRadius: side * 0.08,
                        endRadius: side * 0.45
                    )
                )
                .rotationEffect(.degrees(turning ? 360 : 0))
                .position(x: geo.size.width / 2, y: geo.size.height * 0.22)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 80).repeatForever(autoreverses: false)) {
                turning = true
            }
        }
    }

    /// Twelve narrow rays: clear, a soft peak of light, clear again.
    private var rayStops: [Gradient.Stop] {
        (0..<12).flatMap { index -> [Gradient.Stop] in
            let start = Double(index) / 12
            return [
                Gradient.Stop(color: color.opacity(0), location: start),
                Gradient.Stop(color: color.opacity(opacity), location: start + 1.0 / 48),
                Gradient.Stop(color: color.opacity(0), location: start + 2.0 / 48),
            ]
        }
    }
}

// MARK: - Gold light over text

/// A slow band of light passing over gilded text, like the ayah on the Zikr
/// tab. Slower and warmer than `diShimmer`.
private struct GoldTextShimmer: ViewModifier {
    var highlight: Color
    /// Seconds before the band's first pass.
    var delay: Double = 0.8
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                if !reduceMotion {
                    LinearGradient(
                        colors: [.clear, highlight.opacity(0.85), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.35)
                    .offset(x: phase * geo.size.width * 1.4)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 6.5).repeatForever(autoreverses: false).delay(delay)) {
                            phase = 1.2
                        }
                    }
                }
            }
            .mask(content)
            .allowsHitTesting(false)
        )
    }
}

extension View {
    /// A slow band of gold light passing over gilded text. `delay` holds
    /// back its first pass, so lines shown together need not move in step.
    func diGoldTextShimmer(highlight: Color = Color(hex: 0xFFF4CF), delay: Double = 0.8) -> some View {
        modifier(GoldTextShimmer(highlight: highlight, delay: delay))
    }

    /// The redesign's glass surface: material fill, a light edge and a soft
    /// shadow. Lists, tiles and cards sit on it.
    func diGlassPanel(cornerRadius: CGFloat = 26) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 14, y: 8)
    }
}

// MARK: - Tool orb

/// A glossy round tool button with its name under it (Today's tools). The
/// last one, "All tools", is gold.
struct DIToolOrb: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    var gold = false

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(gold ? DIColor.primaryDeep : Color.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(
                        RadialGradient(
                            colors: gold
                                ? [Color(hex: 0xFFE9A8), Color(hex: 0xE0B75F), Color(hex: 0xB48A2C)]
                                : [Color(hex: 0x34B98A), Color(hex: 0x0B7250), Color(hex: 0x064B34)],
                            center: UnitPoint(x: 0.32, y: 0.26),
                            startRadius: 0,
                            endRadius: 40
                        )
                    )
                )
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
                .shadow(color: (gold ? DIColor.accent : DIColor.primary).opacity(0.35), radius: 10, y: 6)
                .accessibilityHidden(true)
            Text(titleKey)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DIColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
