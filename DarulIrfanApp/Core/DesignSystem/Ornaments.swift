import SwiftUI

// The signature geometric ornament of the app: the 8-point Naqshbandi
// octagram / star-knot lifted from the Dar-ul-Irfan Munara's pierced jali
// lattice. Deployed as hairline dividers, header watermarks, and the seal
// emblem so the app reads as an authentic extension of naqshbandiaowaisiah.org
// rather than a generic azan clone.

// MARK: - Octagram star

/// An 8-point star (two overlaid squares) inscribed in its rect.
struct DIOctagram: Shape {
    /// Inner-to-outer radius ratio; smaller = spikier.
    var innerRatio: CGFloat = 0.42

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        let points = 8
        var path = Path()
        for i in 0..<(points * 2) {
            let radius = i.isMultiple(of: 2) ? outer : inner
            // Start at the top (−90°) and step by half-sector each vertex.
            let angle = -CGFloat.pi / 2 + CGFloat(i) * (.pi / CGFloat(points))
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Jali lattice band (divider / trim)

/// A thin horizontal band of repeating octagram motifs, for section dividers
/// and card-header trim. Gold, low opacity — a whisper, not a shout.
struct DIJaliDivider: View {
    var tint: Color = DIColor.accent
    var height: CGFloat = 18
    var opacity: Double = 0.45

    var body: some View {
        GeometryReader { geo in
            let count = max(3, Int(geo.size.width / (height * 1.4)))
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { _ in
                    DIOctagram(innerRatio: 0.5)
                        .stroke(tint, lineWidth: 1)
                        .frame(width: height, height: height)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: geo.size.height)
        }
        .frame(height: height)
        .opacity(opacity)
        .accessibilityHidden(true)
    }
}

// MARK: - Seal emblem

/// A distilled, flat rendition of the silsila seal — an emerald medallion
/// ringed in gold rope with a gold octagram-knot at its heart. Used as the
/// home/splash brandmark and header watermark. Not a substitute for the app
/// icon; a lightweight in-UI emblem.
struct DISealEmblem: View {
    var diameter: CGFloat = 120
    var glow: Bool = true
    var assetName: String = "BrandEmblem"

    var body: some View {
        Image(assetName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .modifier(SealGlow(active: glow))
            .accessibilityHidden(true)
    }
}

/// A living presentation of the selected brand emblem: white circular plate,
/// fine gold edge, broad radial halo, and one slow moving glint. The emblem
/// itself stays still and fully legible.
struct DILivingSealMark: View {
    var diameter: CGFloat = 120
    var assetName: String = "BrandEmblem"

    @State private var rotating = false
    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [DIColor.goldGlow.opacity(breathing ? 0.30 : 0.16), .clear],
                        center: .center,
                        startRadius: diameter * 0.40,
                        endRadius: diameter * 0.86
                    )
                )
                .frame(width: diameter * 1.72, height: diameter * 1.72)

            Circle()
                .fill(Color.white.opacity(0.98))
                .frame(width: diameter * 1.055, height: diameter * 1.055)
                .overlay(
                    Circle().stroke(DIColor.accent.opacity(0.75), lineWidth: max(1, diameter * 0.008))
                )
                .shadow(color: DIColor.accent.opacity(0.10), radius: 0, x: 0, y: 0)
                .shadow(color: DIColor.accent.opacity(breathing ? 0.34 : 0.20), radius: diameter * 0.20)
                .shadow(color: Color.black.opacity(0.28), radius: diameter * 0.20, y: diameter * 0.10)

            DISealEmblem(diameter: diameter, glow: true, assetName: assetName)
                .padding(diameter * 0.025)

            Circle()
                .trim(from: 0.02, to: 0.20)
                .stroke(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.92), DIColor.goldGlow.opacity(0.85), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: max(1.5, diameter * 0.018), lineCap: .round)
                )
                .frame(width: diameter * 1.10, height: diameter * 1.10)
                .rotationEffect(.degrees(reduceMotion ? -35 : (rotating ? 325 : -35)))
        }
        .frame(width: diameter * 1.22, height: diameter * 1.22)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                rotating = true
            }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Darul Irfan")
    }
}

private struct SealGlow: ViewModifier {
    var active: Bool
    func body(content: Content) -> some View {
        if active {
            content.shadow(color: DIColor.goldGlow.opacity(0.35), radius: 16)
        } else {
            content
        }
    }
}

// MARK: - Watermark helper

extension View {
    /// Places a large, very faint octagram behind content (home headers,
    /// empty states) for the "lit-from-within" devotional feel.
    func diOctagramWatermark(size: CGFloat = 320, opacity: Double = 0.05) -> some View {
        background(
            DIOctagram(innerRatio: 0.5)
                .stroke(DIColor.accent, lineWidth: 2)
                .frame(width: size, height: size)
                .opacity(opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }
}
