import SwiftUI
import UIKit

/// Content to render into a shareable square card. One renderer serves the
/// daily ayah, dua, Aqwal-e-Sheikh, and Name-of-the-day cards.
struct ShareableContent: Equatable {
    var badge: String
    var arabic: String?
    var translation: String?
    var attribution: String
}

/// A fixed-canvas devotional card for sharing (1080×1080). Emerald "paper",
/// gold hairline frame, octagram watermark, strict type hierarchy, and a quiet
/// wordmark footer carrying provenance. Uses explicit point sizes (not Dynamic
/// Type) because the canvas is fixed.
struct ShareCardView: View {
    let content: ShareableContent
    var side: CGFloat = 1080

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DIColor.primary, DIColor.primaryDeep],
                startPoint: .top, endPoint: .bottom
            )
            DIOctagram(innerRatio: 0.5)
                .stroke(Color(hex: 0xC6A253), lineWidth: 3)
                .frame(width: side * 0.62, height: side * 0.62)
                .opacity(0.10)

            VStack(spacing: side * 0.045) {
                Text(content.badge.uppercased())
                    .font(.system(size: side * 0.028, weight: .semibold))
                    .tracking(side * 0.006)
                    .foregroundStyle(Color(hex: 0xE0B75F))

                if let arabic = content.arabic, !arabic.isEmpty {
                    Text(arabic)
                        .font(.system(size: side * 0.062, weight: .regular))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(side * 0.02)
                        .environment(\.layoutDirection, .rightToLeft)
                }

                Rectangle()
                    .fill(Color(hex: 0xC6A253))
                    .frame(width: side * 0.16, height: 2)

                if let translation = content.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.system(size: side * 0.034, weight: .regular, design: .serif))
                        .foregroundStyle(Color(hex: 0xF3EEE2))
                        .multilineTextAlignment(.center)
                        .lineSpacing(side * 0.008)
                        .lineLimit(6)
                }

                Text(content.attribution)
                    .font(.system(size: side * 0.026, weight: .medium))
                    .tracking(side * 0.003)
                    .foregroundStyle(Color(hex: 0xE0B75F))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, side * 0.10)

            VStack {
                Spacer()
                HStack(spacing: side * 0.014) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: side * 0.026))
                    Text("Darul Irfan")
                        .font(.system(size: side * 0.028, weight: .semibold, design: .serif))
                }
                .foregroundStyle(.white.opacity(0.75))
                .padding(.bottom, side * 0.06)
            }
        }
        .frame(width: side, height: side)
    }
}

enum ShareCardRenderer {
    /// Renders the card to a crisp @3x image. `@MainActor` because
    /// `ImageRenderer` is main-actor isolated.
    @MainActor
    static func image(for content: ShareableContent) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(content: content))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// UIActivityViewController wrapper for sharing the rendered card image.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
