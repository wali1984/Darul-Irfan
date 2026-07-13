import SwiftUI
import UIKit

// Tasteful motion that makes cards feel like living panels: spring press
// feedback, staggered appear, a slow breathing glow, and a gold shimmer sweep.
// Reverent, never noisy — respects Reduce Motion.

// MARK: - Press feedback

/// Cards/rows that scale and soften slightly when pressed, with a spring.
struct DIPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Appear animation

private struct DIAppear: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Springs the view up into place on appear, with an optional stagger delay.
    func diAppear(delay: Double = 0) -> some View { modifier(DIAppear(delay: delay)) }
}

// MARK: - Breathing glow

private struct BreathingGlow: ViewModifier {
    var color: Color
    var maxRadius: CGFloat
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(on ? 0.6 : 0.25), radius: on ? maxRadius : maxRadius * 0.5)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

extension View {
    /// A soft, slow pulsing glow — used on the seal and the next-prayer focal.
    func diBreathingGlow(color: Color = DIColor.goldGlow, maxRadius: CGFloat = 22) -> some View {
        modifier(BreathingGlow(color: color, maxRadius: maxRadius))
    }
}

// MARK: - Gold shimmer sweep

private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                if !reduceMotion {
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.35), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: phase * geo.size.width * 1.5)
                    .onAppear {
                        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false).delay(0.6)) {
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
    /// A slow gold/white shimmer sweep across gilded elements.
    func diShimmer() -> some View { modifier(Shimmer()) }
}

// MARK: - Haptics

enum DIHaptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
