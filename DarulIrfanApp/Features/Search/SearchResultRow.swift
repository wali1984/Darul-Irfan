import SwiftUI
import UIKit

/// One informational search hit: domain icon, title, bolded snippet, and —
/// for library/media/events items with a known website page — a source link.
/// Rows deliberately have no chevron: in-app navigation into matched items is
/// wired by the owning feature teams as a follow-up. A context menu offers
/// "Copy reference" and, when derivable, opening the source page.
struct SearchResultRow: View {
    let result: SearchResult
    let sourceURL: URL?
    /// Plain-text reference placed on the pasteboard by "Copy reference".
    let reference: String

    /// Urdu/Arabic content blocks lay out right-to-left; row chrome (the
    /// domain icon) stays in the surrounding layout direction.
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
        HStack(alignment: .top, spacing: DISpacing.sm) {
            domainIcon
            if isRightToLeftContent {
                textBlock
                    .environment(\.layoutDirection, .rightToLeft)
            } else {
                textBlock
            }
        }
        .padding(.vertical, DISpacing.xs)
        .contextMenu {
            Button {
                UIPasteboard.general.string = reference
            } label: {
                Label("Copy reference", systemImage: "doc.on.doc")
            }
            if let sourceURL {
                Link(destination: sourceURL) {
                    Label("Open source page", systemImage: "safari")
                }
            }
        }
    }

    private var domainIcon: some View {
        Image(systemName: result.domain.iconName)
            .font(.subheadline)
            .foregroundStyle(DIColor.primary)
            .frame(width: 28, height: 28)
            .background(
                DIColor.primary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous)
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
                Text(SearchSnippetFormatter.attributedSnippet(from: snippet))
                    .font(snippetFont)
                    .foregroundStyle(DIColor.textMuted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }

            if let sourceURL {
                Link(destination: sourceURL) {
                    Label("View source", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DIColor.primary)
                }
                .accessibilityLabel("View source on the Naqshbandia Owaisiah website")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
