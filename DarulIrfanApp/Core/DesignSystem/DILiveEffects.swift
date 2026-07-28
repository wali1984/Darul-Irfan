import SwiftUI

/// An animated broadcast pulse — a solid dot with expanding, fading rings, like
/// a live radar ping. Falls back to a static dot when Reduce Motion is on.
struct DILivePulse: View {
    var color: Color = DIColor.crimson
    var size: CGFloat = 10

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .stroke(color, lineWidth: 1.5)
                        .frame(width: size, height: size)
                        .scaleEffect(animating ? 3.2 : 1)
                        .opacity(animating ? 0 : 0.55)
                        .animation(
                            .easeOut(duration: 1.9)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.95),
                            value: animating
                        )
                }
            }
            Circle().fill(color).frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .onAppear { animating = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Scroll reveal

private struct DIScrollReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.scrollTransition { view, phase in
                view
                    .opacity(phase.isIdentity ? 1 : 0.15)
                    .scaleEffect(phase.isIdentity ? 1 : 0.94)
                    .offset(y: phase.isIdentity ? 0 : phase.value * 24)
            }
        }
    }
}

extension View {
    /// Fades, lifts, and gently scales a card as it enters/leaves the viewport
    /// (iOS 17 scroll transition). No-op under Reduce Motion. Apply to cards
    /// inside a vertical `ScrollView`/`LazyVStack`.
    func diScrollReveal() -> some View { modifier(DIScrollReveal()) }
}
