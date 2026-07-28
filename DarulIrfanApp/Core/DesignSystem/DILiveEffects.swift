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

// MARK: - Parallax hero

private struct DIParallaxHero: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.visualEffect { view, proxy in
                let y = proxy.frame(in: .scrollView).minY
                let h = max(proxy.size.height, 1)
                return view
                    // Drift slower than the scroll (parallax depth) as it moves up.
                    .offset(y: y < 0 ? -y * 0.32 : 0)
                    // Soft fade as the hero scrolls away past the top.
                    .opacity(y < 0 ? max(0.3, 1 + y / (h * 1.3)) : 1)
            }
        }
    }
}

extension View {
    /// A hero header that drifts slower than the scroll and fades as it leaves
    /// the top (iOS 17 visual effect). Apply to the hero card at the top of a
    /// vertical `ScrollView`. No-op under Reduce Motion.
    func diParallaxHero() -> some View { modifier(DIParallaxHero()) }
}

// MARK: - Responsive width

private struct DIResponsiveWidth: ViewModifier {
    let maxWidth: CGFloat
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: sizeClass == .regular ? maxWidth : .infinity)
            .frame(maxWidth: .infinity) // centre the capped column on wide screens
    }
}

extension View {
    /// Caps the content column width and centres it on wide screens (iPad,
    /// large landscape) so layouts stay composed instead of stretching edge to
    /// edge; full width on compact iPhone. Apply to a screen's content stack.
    func diResponsiveWidth(_ maxWidth: CGFloat = 620) -> some View {
        modifier(DIResponsiveWidth(maxWidth: maxWidth))
    }
}
