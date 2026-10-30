import SwiftUI

// Small ornaments the Zikr tab's cards share: the Silsila's octagram drawn
// as two squares, one turned on its corner, as the redesign's boards draw it.

/// Two squares, one turned on its corner: the octagram as an outline.
struct ZikrOctagramOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // The upright square spans 70% of the side; the turned one reaches
        // the edges, so both are the same size.
        let half = side * 0.35
        let reach = side * 0.5
        var path = Path()
        path.addRect(CGRect(x: center.x - half, y: center.y - half, width: half * 2, height: half * 2))
        path.move(to: CGPoint(x: center.x, y: center.y - reach))
        path.addLine(to: CGPoint(x: center.x + reach, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + reach))
        path.addLine(to: CGPoint(x: center.x - reach, y: center.y))
        path.closeSubpath()
        return path
    }
}

/// A faint gold octagram turning very slowly in a hero card's corner. It
/// stands still under Reduce Motion.
struct ZikrTurningOctagram: View {
    var size: CGFloat = 240
    var color: Color = DIColor.goldGlow
    var opacity: Double = 0.15
    /// Seconds for one turn.
    var period: Double = 90

    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZikrOctagramOutline()
            .stroke(color, lineWidth: max(1, size * 0.008))
            .frame(width: size, height: size)
            .opacity(opacity)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                    turning = true
                }
            }
    }
}
