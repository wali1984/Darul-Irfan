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
    /// Page to open at, e.g. where a surah begins inside a parah volume when
    /// the Quran reader sends someone here. Nil opens at the start.
    var startPage: Int?

    @State private var pages: [BookPage] = []
    /// Urdu pages laid out into headings, paragraphs and quotations.
    @State private var formatted: [String: BookPageFormatter.Page] = [:]
    @State private var isLoading = true
    @State private var hasScrolledToStart = false

    private var unresolvedPageCount: Int {
        pages.filter { $0.isMachineProvisional && !$0.isFullyResolved }.count
    }

    /// The proofreading notice only applies while original OCR text remains.
    private var hasMachineProvisionalPages: Bool {
        pages.contains { $0.isMachineProvisional }
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
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DISpacing.lg) {
                            if hasMachineProvisionalPages {
                                provenanceNote
                            }
                            ForEach(pages) { page in
                                pageView(page)
                            }
                        }
                        .padding(DISpacing.md)
                    }
                    .onAppear { scrollToStartIfNeeded(proxy) }
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
                if page.isMachineProvisional && !page.isFullyResolved {
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
            if let layout = formatted[page.id] {
                FormattedBookPage(page: layout)
            } else {
                pageText(page.text)
            }
            Divider().overlay(DIColor.border)
        }
        .id("book-page-\(page.page)")
    }

    /// Direction and face follow the page's own script, not a fixed Urdu
    /// layout: the English Asrar-at-Tanzil volumes used to open right-aligned
    /// in Nastaliq. Deciding per page (with the book's language as the tie
    /// breaker) also keeps an English book's Urdu quotation pages readable.
    @ViewBuilder
    private func pageText(_ text: String) -> some View {
        if ScriptDirection.isRightToLeft(text, fallbackLanguage: item.language) {
            Text(verbatim: text)
                .font(DIFont.urduBody())
                .foregroundStyle(DIColor.textPrimary)
                .lineSpacing(10)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .rightToLeft)
                .textSelection(.enabled)
        } else {
            Text(verbatim: text)
                .font(.body)
                .foregroundStyle(DIColor.textPrimary)
                .lineSpacing(5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .leftToRight)
                .textSelection(.enabled)
        }
    }

    private func scrollToStartIfNeeded(_ proxy: ScrollViewProxy) {
        guard !hasScrolledToStart, let startPage, !pages.isEmpty else { return }
        hasScrolledToStart = true
        // The nearest page at or after the requested one: scans skip blank
        // pages, so the exact number is not always present.
        guard let target = pages.first(where: { $0.page >= startPage }) ?? pages.last else { return }
        DispatchQueue.main.async {
            proxy.scrollTo("book-page-\(target.page)", anchor: .top)
        }
    }

    private func load() async {
        isLoading = true
        let loaded = (try? await dependencies.contentRepository.bookPages(bookID: item.id)) ?? []
        let language = item.language
        formatted = await Task.detached(priority: .userInitiated) {
            BookPageFormatter.format(pages: loaded.filter {
                ScriptDirection.isRightToLeft($0.text, fallbackLanguage: language)
            })
        }.value
        // A cover or blank page re-read from the scan carries no text.
        pages = loaded.filter { !$0.text.isEmpty }
        isLoading = false
    }
}

/// Urdu text as `BookPageFormatter` laid it out: a book page, or the
/// tafsir under an ayah.
struct FormattedBookPage: View {
    let page: BookPageFormatter.Page
    /// The reader's text size.
    var scale: Double = 1
    @State private var showsContents = false

    var body: some View {
        Group {
            if page.isContents {
                DisclosureGroup(isExpanded: $showsContents) {
                    Text(verbatim: contentsText)
                        .font(DIFont.urduBody(scale: 0.85 * scale))
                        .foregroundStyle(DIColor.textMuted)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } label: {
                    Label("Contents page", systemImage: "list.bullet")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DIColor.textMuted)
                }
                .tint(DIColor.primary)
            } else {
                VStack(alignment: .leading, spacing: DISpacing.md) {
                    ForEach(Array(page.blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var contentsText: String {
        guard case .paragraph(let runs)? = page.blocks.first else { return "" }
        return runs.map(\.text).joined(separator: " ")
    }

    @ViewBuilder
    private func blockView(_ block: BookPageFormatter.Block) -> some View {
        switch block {
        case .heading(let text):
            Text(verbatim: text)
                .font(DIFont.urduBody(scale: 1.1 * scale).weight(.semibold))
                .foregroundStyle(DIColor.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, DISpacing.xs)
        case .paragraph(let runs):
            prose(runs)
                .font(DIFont.urduBody(scale: scale))
                .foregroundStyle(DIColor.textPrimary)
                .lineSpacing(CGFloat(10 * scale))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        case .quran(let text):
            Text(verbatim: text)
                .font(DIFont.quranArabic(scale: 0.8 * scale))
                .foregroundStyle(DIColor.primaryDeep)
                .lineSpacing(8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(DISpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                        .fill(DIColor.primary.opacity(0.07))
                )
                .textSelection(.enabled)
        }
    }

    /// Prose, with a short Qur'anic quotation kept inline in the Qur'an face.
    private func prose(_ runs: [BookPageFormatter.Run]) -> Text {
        var text = Text(verbatim: "")
        for (index, run) in runs.enumerated() {
            if index > 0 { text = text + Text(verbatim: " ") }
            if run.isQuranic {
                text = text + Text(verbatim: run.text)
                    .font(DIFont.quranArabic(scale: 0.72 * scale))
                    .foregroundStyle(DIColor.primary)
            } else {
                text = text + Text(verbatim: run.text)
            }
        }
        return text
    }
}

/// Decides reading direction from the text itself.
enum ScriptDirection {
    /// True when Arabic-script letters outnumber Latin ones. Ties and
    /// letterless text fall back to the language the content is labelled with.
    static func isRightToLeft(_ text: String, fallbackLanguage: String?) -> Bool {
        var arabic = 0
        var latin = 0
        for scalar in text.unicodeScalars.prefix(4000) {
            switch scalar.value {
            case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF:
                arabic += 1
            case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F:
                latin += 1
            default:
                break
            }
        }
        if arabic == latin {
            return fallbackLanguage == "ur" || fallbackLanguage == "ar"
        }
        return arabic > latin
    }
}
