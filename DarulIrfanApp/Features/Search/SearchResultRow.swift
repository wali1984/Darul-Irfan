import SwiftUI
import UIKit

/// One informational search hit rendered as an elevated "live panel": a gilded
/// domain crest, the title, and a highlighted native snippet. A press-and-hold
/// context menu offers a private, app-native reference for copying.
struct SearchResultRow: View {
    let result: SearchResult
    /// Plain-text reference placed on the pasteboard by "Copy reference".
    let reference: String

    /// Urdu/Arabic content blocks lay out right-to-left; row chrome (the
    /// domain crest) stays in the surrounding layout direction.
    private var isRightToLeftContent: Bool {
        result.language == "ur" || result.language == "ar"
    }

    private var titleFont: Font {
        result.language == "ur" ? DIFont.urduBody() : .headline
    }

    private var snippetFont: Font {
        result.language == "ur" ? DIFont.urduBody(scale: 0.85) : .subheadline
    }

    var body: some View {
        DIElevatedCard(padding: DISpacing.md) {
            HStack(alignment: .top, spacing: DISpacing.md) {
                domainCrest
                if isRightToLeftContent {
                    textBlock
                        .environment(\.layoutDirection, .rightToLeft)
                } else {
                    textBlock
                }
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = reference
                DIHaptics.success()
            } label: {
                Label("Copy reference", systemImage: "doc.on.doc")
            }
        }
    }

    // A rounded emerald crest for the domain, echoing the seal's medallion.
    private var domainCrest: some View {
        Image(systemName: result.domain.iconName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DIColor.primary)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous)
                    .fill(DIColor.primary.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous)
                    .stroke(DIColor.accent.opacity(0.35), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: DISpacing.xs) {
            Text(result.title)
                .font(titleFont)
                .foregroundStyle(DIColor.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)

            if let snippet = result.snippet, !snippet.isEmpty {
                Text(highlightedSnippet(from: snippet))
                    .font(snippetFont)
                    .foregroundStyle(DIColor.textMuted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Keeps the shared snippet parser intact (marker handling preserved) and
    /// only tints the already-bolded match ranges emerald so hits truly stand
    /// out against the muted snippet text.
    private func highlightedSnippet(from snippet: String) -> AttributedString {
        var attributed = SearchSnippetFormatter.attributedSnippet(from: snippet)
        let matchRanges = attributed.runs
            .filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
            .map { $0.range }
        for range in matchRanges {
            attributed[range].foregroundColor = DIColor.primary
        }
        return attributed
    }
}
