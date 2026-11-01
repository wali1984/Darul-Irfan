import SwiftUI
import UIKit

/// Content to render into a shareable square card. One renderer serves the
/// daily ayah, dua, Aqwal-e-Sheikh, and Name-of-the-day cards.
struct ShareableContent: Equatable {
    var badge: String
    var arabic: String?
    var translation: String?
    var attribution: String
    var isQuran = false
}

/// A devotional card for sharing, 1080 wide: emerald "paper", octagram
/// watermark, strict type hierarchy, and a quiet wordmark footer carrying
/// provenance. Explicit point sizes (not Dynamic Type), since it is an image.
///
/// Square for most texts, and taller when the text needs it: a verse is never
/// cut short. The canvas used to be a fixed square with the translation held
/// to six lines, which dropped the end of long ayat such as Ayat al-Kursi.
struct ShareCardView: View {
    let content: ShareableContent
    var side: CGFloat = 1080

    private func isRTL(_ text: String) -> Bool {
        ScriptDirection.isRightToLeft(text, fallbackLanguage: nil)
    }

    // ImageRenderer has no parent screen locale; the localized badge identifies
    // the share language even when the phone itself is configured in English.
    private var wordmark: String {
        String(localized: "Darul Irfan", locale: Locale(identifier: isRTL(content.badge) ? "ur" : "en"))
    }

    private func proseFont(_ text: String, size: CGFloat, weight: Font.Weight,
                           design: Font.Design = .default) -> Font {
        if isRTL(text), let name = AppFonts.urduNastaliqName {
            return .custom(name, fixedSize: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: design)
    }

    var body: some View {
        VStack(spacing: side * 0.045) {
            Text(content.badge.uppercased())
                .font(proseFont(content.badge, size: side * 0.028, weight: .semibold))
                .tracking(isRTL(content.badge) ? 0 : side * 0.006)
                .foregroundStyle(Color(hex: 0xE0B75F))

            if let arabic = content.arabic, !arabic.isEmpty {
                Text(arabic)
                    .font(.custom(content.isQuran ? AppFonts.quranArabicName : AppFonts.generalArabicName, fixedSize: side * 0.062))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(side * 0.02)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.layoutDirection, .rightToLeft)
            }

            Rectangle()
                .fill(Color(hex: 0xC6A253))
                .frame(width: side * 0.16, height: 2)

            if let translation = content.translation, !translation.isEmpty {
                Text(translation)
                    .font(proseFont(translation, size: side * 0.034, weight: .regular, design: .serif))
                    .foregroundStyle(Color(hex: 0xF3EEE2))
                    .multilineTextAlignment(.center)
                    .lineSpacing(side * 0.008)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(content.attribution)
                .font(proseFont(content.attribution, size: side * 0.026, weight: .medium))
                .tracking(isRTL(content.attribution) ? 0 : side * 0.003)
                .foregroundStyle(Color(hex: 0xE0B75F))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, side * 0.10)
        .padding(.top, side * 0.12)
        // Room for the wordmark below the text.
        .padding(.bottom, side * 0.16)
        .frame(width: side)
        .frame(minHeight: side)
        .background {
            ZStack {
                LinearGradient(
                    colors: [DIColor.primary, DIColor.primaryDeep],
                    startPoint: .top, endPoint: .bottom
                )
                DIOctagram(innerRatio: 0.5)
                    .stroke(Color(hex: 0xC6A253), lineWidth: 3)
                    .frame(width: side * 0.62, height: side * 0.62)
                    .opacity(0.10)
            }
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: side * 0.014) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: side * 0.026))
                Text(verbatim: wordmark)
                    .font(proseFont(wordmark, size: side * 0.028, weight: .semibold, design: .serif))
            }
            .environment(\.layoutDirection, isRTL(wordmark) ? .rightToLeft : .leftToRight)
            .foregroundStyle(.white.opacity(0.75))
            .padding(.bottom, side * 0.06)
        }
    }
}

enum ShareCardRenderer {
    /// Renders the card at 1080 points wide and as tall as its text needs.
    /// @2x (2160 pixels wide) is sharper than any sharing app shows and keeps
    /// a tall card for a long verse to a sensible size in memory.
    /// `@MainActor` because `ImageRenderer` is main-actor isolated.
    @MainActor
    static func image(for content: ShareableContent) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(content: content))
        renderer.proposedSize = ProposedViewSize(width: 1080, height: nil)
        renderer.scale = 2
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
