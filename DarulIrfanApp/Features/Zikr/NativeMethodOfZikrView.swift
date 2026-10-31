import SwiftUI

/// Native presentation of the verified illustrated Method of Zikr entry. The
/// repository may refresh its source metadata remotely, but the user remains
/// inside Darul Irfan for text and images. Opened from the Zikr tab's Method
/// of Zikr tile, it opens with the order's method in brief (the paragraphs
/// that used to stand on the Zikr tab), then the verified text and the
/// illustrations.
struct NativeMethodOfZikrView: View {
    let repository: any ContentRepositoryProtocol
    var readerFontScale: Double = 1
    @State private var item: ContentItem?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                if isLoading {
                    ProgressView("Preparing illustrated method…")
                        .frame(maxWidth: .infinity)
                        .padding(DISpacing.xl)
                } else {
                    SilsilaPageHeader(title: "Method of Zikr")

                    MethodOfZikrIntro()
                        .diAppear()

                    if let item {
                        methodText(item)
                    } else {
                        DIEmptyState(
                            systemImage: "book.pages",
                            titleKey: "Method of Zikr is being prepared",
                            messageKey: "The verified native guide will appear after the next content refresh."
                        )
                    }
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .navigationTitle("Method of Zikr")
        .navigationBarTitleDisplayMode(.inline)
        .diScreenBackground()
        .task {
            await Task.detached(priority: .userInitiated) { QuranQuotation.warmUp() }.value
            let stored = try? await repository.item(id: Self.itemID)
            if let stored {
                item = stored
            } else {
                // Never "being prepared" while the verified text is in the
                // app: read the bundled copy when the database lacks it.
                item = await Task.detached(priority: .userInitiated) {
                    SeedBundle.libraryItem(id: Self.itemID)
                }.value
            }
            isLoading = false
        }
    }

    /// The verified text, then each illustration.
    @ViewBuilder
    private func methodText(_ item: ContentItem) -> some View {
        if let text = item.bodyPlainText, !text.isEmpty {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                    FormattedBookPage(page: BookPageFormatter.articleParagraph(paragraph), scale: readerFontScale)
                }
            }
                .padding(DISpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .diGlassPanel(cornerRadius: 24)
        }

        ForEach(item.mediaUrls.compactMap { nativeURL($0) }, id: \.absoluteString) { url in
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                case .failure:
                    DIEmptyState(
                        systemImage: "photo",
                        titleKey: "Illustration unavailable",
                        messageKey: "It will be restored automatically after a verified content refresh."
                    )
                default:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
            .padding(DISpacing.sm)
            .diGlassPanel(cornerRadius: 24)
        }
    }

    private static let itemID = "page-method-of-zikr"

    private func nativeURL(_ raw: String) -> URL? {
        URL(string: raw) ?? URL(string: raw.replacingOccurrences(of: " ", with: "%20"))
    }
}

/// The order's method in brief: Zikr-e Khafi Qalbi with Pas Anfas, and the
/// Owaisiah transmission. Verified description only (Docs/RESEARCH_NOTES.md);
/// the full illustrated instructions follow from the verified content.
private struct MethodOfZikrIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            HStack(spacing: DISpacing.sm) {
                Image(systemName: "heart.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DIColor.primary)
                    .accessibilityHidden(true)
                Text("Zikr-e Khafi Qalbi")
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
            }
            DIJaliDivider(height: 14, opacity: 0.4)
                .padding(.vertical, DISpacing.xs)
            Text("The method of zikr in the Naqshbandia Owaisiah order is Zikr-e Khafi Qalbi, practised with Pas Anfas — \"guarding every breath\".")
                .font(.body)
                .foregroundStyle(DIColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("A distinguishing feature of this order is spiritual bai'at directly at the hands of the holy Prophet ﷺ — the Owaisiah transmission.")
                .font(.body)
                .foregroundStyle(DIColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DISpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .diGlassPanel(cornerRadius: 24)
    }
}
