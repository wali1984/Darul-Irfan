import SwiftUI

// Shared visual language for the Media feature so every screen reads as one
// premium, living system — mirroring the flagship Today hero. Audio sections
// wear the calm emerald/gold brand; the AlMurshid TV / video sections keep
// their own crimson sub-brand skin (mirrors the real Al-Murshid TV mark).

// MARK: - Category styling

enum MediaStyle {

    /// The AlMurshid TV / video sub-brand categories that wear crimson. Audio
    /// and Kalam sections stay in the calm emerald brand.
    static func isVideoBrand(_ category: MediaCategory) -> Bool {
        switch category {
        case .videoLectures, .tafseerQuranVideos, .alMurshidTV, .alMurshidQA:
            return true
        case .audioLectures, .shortClips, .recommended, .kalamESheikh:
            return false
        }
    }

    /// Solid accent color for a category (crimson for the TV sub-brand).
    static func accent(_ category: MediaCategory) -> Color {
        isVideoBrand(category) ? DIColor.crimson : DIColor.primary
    }

    /// A soft, top-lit gradient used to fill a category's icon medallion.
    static func iconGradient(_ category: MediaCategory) -> LinearGradient {
        isVideoBrand(category) ? crimson : DIGradient.emerald
    }

    /// The crimson AlMurshid TV gradient — deep and alive.
    static let crimson = LinearGradient(
        colors: [DIColor.crimson, Color(hex: 0x7A1414), Color(hex: 0x4A0D0D)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static func icon(_ category: MediaCategory) -> String {
        switch category {
        case .audioLectures: return "headphones"
        case .videoLectures: return "play.rectangle.fill"
        case .tafseerQuranVideos: return "book.closed.fill"
        case .alMurshidTV: return "dot.radiowaves.left.and.right"
        case .alMurshidQA: return "questionmark.bubble.fill"
        case .shortClips: return "waveform"
        case .recommended: return "star.fill"
        case .kalamESheikh: return "quote.opening"
        }
    }
}

// MARK: - Gradient icon medallion

/// A small gilded/crimson gradient disc with a glyph — the recurring "artwork"
/// mark for categories, resume cards, and rows.
struct MediaIconMedallion: View {
    let category: MediaCategory
    var diameter: CGFloat = 44
    var glyph: String?

    var body: some View {
        ZStack {
            Circle()
                .fill(MediaStyle.iconGradient(category))
            Image(systemName: glyph ?? MediaStyle.icon(category))
                .font(.system(size: diameter * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: MediaStyle.accent(category).opacity(0.35), radius: 6, y: 3)
        .accessibilityHidden(true)
    }
}

// MARK: - Pulsing LIVE pill

/// A "LIVE" pill whose dot gently breathes to signal an on-air broadcast.
/// Respects Reduce Motion. Used on the AlMurshid TV card and the players.
struct MediaLivePill: View {
    /// Capsule fill. Defaults to the AlMurshid crimson.
    var fill: Color = DIColor.crimson
    /// Dot + text color that reads on the fill.
    var foreground: Color = .white

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(foreground)
                .frame(width: 6, height: 6)
                .opacity(pulse ? 0.35 : 1.0)
                .scaleEffect(pulse ? 0.7 : 1.0)
            Text(verbatim: "LIVE")
                .font(.caption2.weight(.heavy))
                .tracking(0.9)
                .foregroundStyle(foreground)
        }
        .padding(.horizontal, DISpacing.sm)
        .padding(.vertical, 4)
        .background(Capsule().fill(fill))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityLabel(Text("Live"))
    }
}
