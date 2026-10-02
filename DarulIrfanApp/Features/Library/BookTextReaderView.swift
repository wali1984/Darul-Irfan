import SwiftUI

/// Reads a book's OCR'd text, one printed page at a time.
///
/// Distinct from `BookReaderView`, which renders the work's PDF through
/// PDFKit. This view shows the *text* layer: selectable, searchable, and
/// available with no download. A work can offer both.
///
/// Pages are rendered in a `LazyVStack` and stored one row per printed page
/// (largest ~10 KB). The library detail view builds its paragraphs eagerly,
/// which is what made a large body unrenderable; nothing here holds more than
/// the visible pages.
///
/// The text is `machineProvisional`: OCR arbitration plus a visual
/// cross-check, no human proofreading. That is stated once at the top rather
/// than left for the reader to discover, and any page the validator could not
/// fully settle is marked. Arabic quotations are the book's own and are not
/// presented as Qur'an or hadith.
struct BookTextReaderView: View {
    let item: ContentItem
    let dependencies: AppDependencies

    @State private var pages: [BookPage] = []
    @State private var isLoading = true

    private var unresolvedPageCount: Int {
        pages.filter { !$0.isFullyResolved }.count
    }

    var body: some View {
        Group {
            if isLoading && pages.isEmpty {
                ProgressView()
                    .tint(DIColor.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if pages.isEmpty {
                DIEmptyState(
                    systemImage: "text.book.closed",
                    titleKey: "No text for this book yet",
                    messageKey: "This work is available as a PDF. Its text has not been added yet."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DISpacing.lg) {
                        provenanceNote
                        ForEach(pages) { page in
                            pageView(page)
                        }
                    }
                    .padding(DISpacing.md)
                }
            }
        }
        .diScreenBackground()
        .navigationTitle(Text(verbatim: item.title))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
    }

    /// Stated once at the top of the work, not repeated per page.
    private var provenanceNote: some View {
        DICard(background: DIColor.sandstone) {
            VStack(alignment: .leading, spacing: DISpacing.xs) {
                Label {
                    Text("Machine-read text — pending proofreading")
                        .font(.caption.weight(.semibold))
                } icon: {
                    Image(systemName: "info.circle")
                }
                .foregroundStyle(DIColor.textPrimary)
                Text("Scanned and machine-corrected from the printed book. It has not been checked by a person. Read the PDF for the authoritative text.")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
                if unresolvedPageCount > 0 {
                    Text("\(unresolvedPageCount) of \(pages.count) pages have passages the checker could not settle; those are marked.")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
        }
    }

    @ViewBuilder
    private func pageView(_ page: BookPage) -> some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            HStack(spacing: DISpacing.sm) {
                Text("Page \(page.page)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DIColor.textMuted)
                if !page.isFullyResolved {
                    Label {
                        Text("unchecked passages")
                            .font(.caption2)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .foregroundStyle(DIColor.accent)
                    .accessibilityLabel(Text("This page has \(page.unresolvedBlocks) passages the checker could not settle"))
                }
                Spacer()
            }
            Text(verbatim: page.text)
                .font(DIFont.urduBody())
                .foregroundStyle(DIColor.textPrimary)
                .lineSpacing(10)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)
                .textSelection(.enabled)
            Divider().overlay(DIColor.border)
        }
        .id("book-page-\(page.page)")
    }

    private func load() async {
        isLoading = true
        pages = (try? await dependencies.contentRepository.bookPages(bookID: item.id)) ?? []
        isLoading = false
    }
}
