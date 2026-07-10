import SwiftUI
import UIKit

/// The compass face: a rotating card of tick marks and cardinal letters, a
/// gold Kaaba marker at the Qibla bearing, and a fixed needle that represents
/// the direction the device is facing (always up). When the user turns to
/// within tolerance the face glows softly in the brand emerald.
struct QiblaDialView: View {
    /// Rotation of the compass card (`-heading`) so north tracks true north.
    var dialRotation: Double
    /// Rotation of the Kaaba marker arm (`qibla - heading`).
    var kaabaRotation: Double
    /// Hides the facing needle when no live heading exists.
    var showsNeedle: Bool
    var isAligned: Bool

    private static let dialSize: CGFloat = 280

    /// Older SF Symbols catalogs have no Kaaba glyph; fall back to a simple
    /// filled square, which rendered in gold still reads as the Kaaba marker.
    private static let kaabaSymbolName: String = {
        UIImage(systemName: "kaaba") != nil ? "kaaba" : "square.fill"
    }()

    private struct Cardinal: Identifiable {
        let letter: String
        let degrees: Double
        var id: Double { degrees }
    }

    private static let cardinals: [Cardinal] = [
        Cardinal(letter: "N", degrees: 0),
        Cardinal(letter: "E", degrees: 90),
        Cardinal(letter: "S", degrees: 180),
        Cardinal(letter: "W", degrees: 270),
    ]

    var body: some View {
        ZStack {
            // Base face
            Circle()
                .fill(DIColor.surface)
            Circle()
                .stroke(DIColor.border, lineWidth: 2)

            // Soft green glow while facing the Qibla
            if isAligned {
                Circle()
                    .stroke(DIColor.primary.opacity(0.8), lineWidth: 3)
                    .shadow(color: DIColor.primary.opacity(0.55), radius: 14)
            }

            // Rotating compass card (ticks + cardinal letters)
            compassCard
                .rotationEffect(.degrees(dialRotation))

            // Kaaba marker at the Qibla bearing relative to facing direction
            kaabaArm
                .rotationEffect(.degrees(kaabaRotation))

            // Fixed needle: the direction the device is facing
            if showsNeedle {
                needle
            }

            // Center cap
            Circle()
                .fill(DIColor.primaryDeep)
                .frame(width: 14, height: 14)
            Circle()
                .stroke(DIColor.accent, lineWidth: 1.5)
                .frame(width: 14, height: 14)
        }
        .frame(width: Self.dialSize, height: Self.dialSize)
        .animation(.easeInOut(duration: 0.2), value: dialRotation)
        .animation(.easeInOut(duration: 0.2), value: kaabaRotation)
        .animation(.easeInOut(duration: 0.2), value: isAligned)
    }

    // MARK: - Pieces

    private var compassCard: some View {
        ZStack {
            ForEach(0..<36, id: \.self) { index in
                tick(at: index)
            }
            ForEach(Self.cardinals) { cardinal in
                VStack {
                    Text(verbatim: cardinal.letter)
                        .font(.system(.subheadline, design: .rounded)
                            .weight(cardinal.degrees == 0 ? .bold : .medium))
                        .foregroundStyle(cardinal.degrees == 0 ? DIColor.accent : DIColor.textMuted)
                    Spacer()
                }
                .padding(.top, 26)
                .rotationEffect(.degrees(cardinal.degrees))
            }
        }
        .accessibilityHidden(true)
    }

    private func tick(at index: Int) -> some View {
        let isCardinalTick = index % 9 == 0
        return VStack {
            RoundedRectangle(cornerRadius: 1)
                .fill(isCardinalTick ? DIColor.accent : DIColor.border)
                .frame(width: isCardinalTick ? 3 : 1.5, height: isCardinalTick ? 14 : 8)
            Spacer()
        }
        .padding(.top, 8)
        .rotationEffect(.degrees(Double(index) * 10))
    }

    private var kaabaArm: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(DIColor.accent.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: Self.kaabaSymbolName)
                    .font(.system(size: 20))
                    .foregroundStyle(DIColor.accent)
            }
            // Counter-rotate the badge so the glyph stays upright while the
            // arm sweeps around the dial.
            .rotationEffect(.degrees(-kaabaRotation))
            Spacer()
        }
        .padding(.top, 44)
        .accessibilityHidden(true)
    }

    private var needle: some View {
        VStack(spacing: -3) {
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 18))
                .foregroundStyle(isAligned ? DIColor.primary : DIColor.textPrimary)
            Capsule()
                .fill(isAligned ? DIColor.primary : DIColor.textPrimary)
                .frame(width: 4, height: 58)
        }
        .offset(y: -37)
        .accessibilityHidden(true)
    }
}
