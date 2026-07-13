import SwiftUI

// Premium, living building blocks: elevated cards with depth + press feedback,
// a glass hero card, a gilded stat pill, and the animated prayer countdown ring.

// MARK: - Elevated card

/// A card with real depth (soft layered shadow), a hairline gold-tinted edge,
/// and a spring press response so it feels like a live panel, not flat text.
struct DIElevatedCard<Content: View>: View {
    var padding: CGFloat = DISpacing.md
    var tint: Color = DIColor.surface
    var glow: Color? = nil
    var onTap: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        let card = content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [DIColor.accent.opacity(0.35), DIColor.border.opacity(0.4)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous))
            .shadow(color: (glow ?? Color.black).opacity(glow == nil ? 0.10 : 0.22),
                    radius: glow == nil ? 10 : 16, x: 0, y: 6)

        if let onTap {
            Button { DIHaptics.soft(); onTap() } label: { card }
                .buttonStyle(DIPressableStyle())
        } else {
            card
        }
    }
}

// MARK: - Glass hero card

/// A translucent glass card for laying over the living gradient hero.
struct DIGlassCard<Content: View>: View {
    var padding: CGFloat = DISpacing.lg
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
    }
}

// MARK: - Gilded stat pill

/// A small "live" metric pill (e.g. a streak, a count) with a gold gradient.
struct DIStatPill: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DIColor.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(DIColor.textPrimary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
        .padding(.horizontal, DISpacing.md)
        .padding(.vertical, DISpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                .fill(DIColor.accent.opacity(0.10))
        )
    }
}

// MARK: - Prayer countdown ring

/// An animated circular ring showing progress through the interval between the
/// previous and next prayer, with the live countdown at its center. The focal,
/// living element of the home hero.
struct PrayerCountdownRing: View {
    /// 0…1 fraction of the interval already elapsed.
    let progress: Double
    let prayerName: String
    /// The moment the next prayer begins (drives the live timer text).
    let target: Date
    var diameter: CGFloat = 190

    @State private var animatedProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 10)
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(colors: [Color(hex: 0xC6A253), Color(hex: 0xE9CE86), Color(hex: 0xFBCE54)],
                                    center: .center),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .diBreathingGlow(color: DIColor.goldGlow, maxRadius: 14)
            VStack(spacing: 2) {
                Text(prayerName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(target, style: .timer)
                    .font(.system(size: diameter * 0.20, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("until adhan")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear { setProgress(progress) }
        .onChange(of: progress) { _, newValue in setProgress(newValue) }
    }

    private func setProgress(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        if reduceMotion {
            animatedProgress = clamped
        } else {
            withAnimation(.easeInOut(duration: 0.9)) { animatedProgress = clamped }
        }
    }
}
