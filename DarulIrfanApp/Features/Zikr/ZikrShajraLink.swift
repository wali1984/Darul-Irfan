import SwiftUI

/// The Zikr tab's way to the Shajra, under the ayah (owner, 30 October 2026:
/// "Chain of Transmission/Shajra Silsila Naqshbandia Owaisia, and similar in
/// Urdu"; in Urdu it reads as the chart's own title). It opens `ShajraView`
/// in the tab's own stack.
///
/// A glass card: the Silsila's seal on a gold orb with a small octagram
/// turning behind it, the two lines, and a chevron; a gold edge that
/// breathes and a band of light sweeping across. Reduce Motion stills all
/// of it. VoiceOver reads it as one button with both lines.
struct ZikrShajraLink: View {
    var body: some View {
        NavigationLink {
            ShajraView()
        } label: {
            ZikrShajraCard()
        }
        .buttonStyle(DIPressableStyle())
    }
}

/// The card the link shows.
private struct ZikrShajraCard: View {
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 64

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        HStack(spacing: 14) {
            ZikrShajraOrb()
            VStack(alignment: .leading, spacing: 2) {
                Text("Chain of Transmission")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(DIColor.textPrimary)
                Text("Shajra Silsila Naqshbandia Owaisiah")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HalqahInk.goldText)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DISpacing.sm)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.bold))
                .foregroundStyle(HalqahInk.goldText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background {
            // Glass with a faint gold wash, and the band of light passing
            // across it, kept to the card's shape.
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(goldWash))
                .diShimmer()
                .shadow(color: Color.black.opacity(0.08), radius: 14, y: 8)
        }
        .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 1))
        .overlay(ZikrShajraEdge(cornerRadius: 22))
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }

    private var goldWash: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xFFE9A8).opacity(0.22), Color(hex: 0xE0B75F).opacity(0.05)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// The card's gold edge (#E0B75F), breathing gently around half strength;
/// still under Reduce Motion.
private struct ZikrShajraEdge: View {
    let cornerRadius: CGFloat
    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color(hex: 0xE0B75F), lineWidth: 1.2)
            .opacity(reduceMotion ? 0.5 : (breathing ? 0.68 : 0.32))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}

/// The Silsila's seal on a 40 pt gold orb, with a small octagram turning
/// slowly behind it.
private struct ZikrShajraOrb: View {
    var body: some View {
        ZStack {
            ZikrShajraTurningStar()
                .frame(width: 54, height: 54)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0xFFE9A8), Color(hex: 0xE0B75F), Color(hex: 0xB48A2C)],
                        center: UnitPoint(x: 0.32, y: 0.26),
                        startRadius: 0,
                        endRadius: 30
                    )
                )
                .frame(width: 40, height: 40)
                .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 0.5))
                .shadow(color: DIColor.goldGlow.opacity(0.45), radius: 7, y: 3)
            DISealEmblem(diameter: 32, glow: false)
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}

/// A small gold octagram turning slowly; still under Reduce Motion.
private struct ZikrShajraTurningStar: View {
    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DIOctagram(innerRatio: 0.5)
            .stroke(Color(hex: 0xE0B75F).opacity(0.7), lineWidth: 1)
            .rotationEffect(.degrees(turning ? 360 : 0))
            // SwiftUI turns a rotation the other way in a right-to-left
            // layout; the star turns the same way in Urdu.
            .environment(\.layoutDirection, .leftToRight)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) {
                    turning = true
                }
            }
    }
}
