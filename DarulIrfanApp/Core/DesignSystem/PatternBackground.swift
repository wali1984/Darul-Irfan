import SwiftUI

// The signature Islamic geometric texture (8-pointed khatam tessellation),
// woven subtly through backgrounds and heroes so the app reads as rich and
// crafted rather than flat. Template-rendered so it tints to any color.

struct DIPatternTexture: View {
    var tint: Color = DIColor.accent
    var opacity: Double = 0.06
    var scale: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            Image("islamic-pattern")
                .renderingMode(.template)
                .resizable(resizingMode: .tile)
                .foregroundStyle(tint)
                .frame(width: geo.size.width, height: geo.size.height)
                .opacity(opacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Lays the geometric pattern faintly OVER the view (heroes, gradient panels).
    func diPatternOverlay(tint: Color = DIColor.accent, opacity: Double = 0.08) -> some View {
        overlay(DIPatternTexture(tint: tint, opacity: opacity).clipped())
    }

    /// Lays the geometric pattern faintly BEHIND the view (screen backgrounds).
    func diPatternBackground(tint: Color = DIColor.accent, opacity: Double = 0.045) -> some View {
        background(DIPatternTexture(tint: tint, opacity: opacity))
    }
}
