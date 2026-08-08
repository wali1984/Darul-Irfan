import SwiftUI

/// One collection, paged. Each hadith shows its Arabic alongside the reader's
/// language, using the same RTL and script handling as the Quran reader.
@MainActor
struct HadithBookView: View {
    let book: HadithBook
    let repository: any HadithRepositoryProtocol
    let appState: AppState

    @State private var entries: [HadithEntry] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var reachedEnd = false
    @State private var showsArabic = true
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    /// Search results mix books, so the book (kitab) headers that group the
    /// ordinary listing are suppressed while showing them.
    @State private var isSearchResults = false

    private static let pageSize = 50

    private var languageCode: String { appState.settings.language.rawValue }
    /// Same reader text-size setting the Quran uses, so both scale together.
    private var fontScale: Double { appState.settings.readerFontScale.rawValue }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DISpacing.md) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(DISpacing.xl)
                } else if entries.isEmpty {
                    DIEmptyState(
                        systemImage: "book.closed",
                        titleKey: "This collection is not on your device yet",
                        messageKey: "It will arrive with the next content update."
                    )
                } else {
                    Toggle(isOn: $showsArabic) {
                        Text("Show Arabic")
                            .font(.subheadline)
                            .foregroundStyle(DIColor.textPrimary)
                    }
                    .tint(DIColor.primary)
                    .padding(.horizontal, DISpacing.xs)

                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        VStack(alignment: .leading, spacing: DISpacing.sm) {
                            if !isSearchResults, showsHeader(at: index) {
                                sectionHeader(for: entry)
                            }
                            hadithCard(entry)
                        }
                        .onAppear {
                            if entry.id == entries.last?.id { Task { await loadMore() } }
                        }
                    }

                    if isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(DISpacing.md)
                    }
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .navigationTitle(Text(verbatim: book.title(languageCode: languageCode)))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: Text("Search in this collection"))
        .onChange(of: searchText) { _, term in
            searchTask?.cancel()
            let query = term.trimmingCharacters(in: .whitespaces)
            guard query.count >= 2 else {
                // Back to the normal paged listing.
                Task { await restorePagedListing() }
                return
            }
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                let found = (try? await repository.search(
                    query, bookID: book.id, limit: 200
                )) ?? []
                guard !Task.isCancelled else { return }
                entries = found
                isSearchResults = true
                reachedEnd = true          // results are not paged
                isLoading = false
            }
        }
        .task { await loadFirstPage() }
    }

    private func hadithCard(_ entry: HadithEntry) -> some View {
        DICard(
            background: DIColor.primary.opacity(0.055),
            borderColor: DIColor.primary.opacity(0.45),
            borderWidth: 1.5
        ) {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) {
                    // The number exactly as the collection prints it, including
                    // sub-numbers such as 402.2 — never rounded to an integer.
                    DIPillBadge(text: "#\(entry.displayNumber)", color: DIColor.primary)
                    if let grades = entry.grades, let first = grades.first {
                        DIPillBadge(text: first, color: DIColor.accent)
                    }
                    Spacer(minLength: 0)
                }

                if showsArabic, let arabic = entry.textArabic, !arabic.isEmpty {
                    // Same IndoPak face and rhythm as the Quran reader so Arabic
                    // looks identical across the app.
                    Text(verbatim: arabic)
                        .font(DIFont.quranArabic(scale: fontScale * 1.15))
                        .lineSpacing(CGFloat(18 * fontScale))
                        .foregroundStyle(DIColor.textPrimary)
                        .diGoldGlow(radius: 5, opacity: 0.18)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .rightToLeft)
                    Divider().overlay(DIColor.border)
                }

                // Strictly the reader's own language. No cross-language
                // fallback: English prose set in Nastaliq and laid out
                // right-to-left would read as though it were the Urdu
                // translation, and repeating the Arabic would present the
                // source text as its own translation. A gap is shown as a gap.
                if let text = entry.text(languageCode: languageCode) {
                    if languageCode == "ur" {
                        Text(verbatim: text)
                            .font(DIFont.urduBody(scale: fontScale))
                            .lineSpacing(CGFloat(6 * fontScale))
                            .foregroundStyle(DIColor.textPrimary)
                            .environment(\.layoutDirection, .rightToLeft)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(verbatim: text)
                            .font(.system(size: 17 * fontScale))
                            .lineSpacing(CGFloat(5 * fontScale))
                            .foregroundStyle(DIColor.textPrimary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    missingTranslationNote
                }

                referenceBlock(entry)
            }
        }
    }

    /// The citation block shown beneath each narration: the collection
    /// reference (with its exact printed number, sub-numbers and all) and, when
    /// the source carries it, the in-book "Book N, Hadith M".
    @ViewBuilder
    private func referenceBlock(_ entry: HadithEntry) -> some View {
        Divider().overlay(DIColor.border)
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(book.title(languageCode: languageCode)) \(entry.displayNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DIColor.textMuted)
            if let refBook = entry.sourceBook, let refHadith = entry.sourceHadith {
                Text("In-book reference: Book \(refBook), Hadith \(refHadith)")
                    .font(.caption2)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// True when `entries[index]` opens a new book (kitab) and so should carry a
    /// heading. The listing is in source order, so a change of book is a change
    /// of `sourceBook` from the previous row.
    private func showsHeader(at index: Int) -> Bool {
        guard index < entries.count else { return false }
        guard index > 0 else { return true }
        return entries[index].sourceBook != entries[index - 1].sourceBook
    }

    /// A book (kitab) heading: the book's number, its English name, and its
    /// Arabic name in the Quran face.
    @ViewBuilder
    private func sectionHeader(for entry: HadithEntry) -> some View {
        if let number = entry.sourceBook {
            let section = book.section(number: number)
            VStack(alignment: .leading, spacing: 2) {
                Text("Book \(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DIColor.accent)
                Text(verbatim: section?.titleEnglish ?? "")
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                if let arabic = section?.titleArabic, !arabic.isEmpty {
                    Text(verbatim: arabic)
                        .font(DIFont.quranArabic(scale: fontScale * 0.7))
                        .foregroundStyle(DIColor.textMuted)
                        .environment(\.layoutDirection, .rightToLeft)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DISpacing.sm)
            .padding(.bottom, DISpacing.xs)
        }
    }

    /// Shown when this narration has no text in the reader's language. Says so
    /// plainly rather than substituting another language's text.
    private var missingTranslationKey: LocalizedStringKey {
        switch languageCode {
        case "ur": return "This narration has no Urdu translation"
        case "ar": return "This narration has no Arabic text"
        default: return "This narration has no English translation"
        }
    }

    private var missingTranslationNote: some View {
        Text(missingTranslationKey)
            .font(.footnote)
            .italic()
            .foregroundStyle(DIColor.textMuted)
            .frame(maxWidth: .infinity, alignment: languageCode == "ur" ? .trailing : .leading)
    }

    private func loadFirstPage() async {
        guard entries.isEmpty else { return }
        entries = (try? await repository.entries(
            bookID: book.id, limit: Self.pageSize, offset: 0
        )) ?? []
        isSearchResults = false
        reachedEnd = entries.count < Self.pageSize
        isLoading = false
    }

    /// Clearing the search box returns to the ordinary paged listing.
    private func restorePagedListing() async {
        entries = (try? await repository.entries(
            bookID: book.id, limit: Self.pageSize, offset: 0
        )) ?? []
        isSearchResults = false
        reachedEnd = entries.count < Self.pageSize
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoadingMore, !reachedEnd else { return }
        isLoadingMore = true
        let next = (try? await repository.entries(
            bookID: book.id, limit: Self.pageSize, offset: entries.count
        )) ?? []
        if next.isEmpty || next.count < Self.pageSize { reachedEnd = true }
        let known = Set(entries.map(\.id))
        entries.append(contentsOf: next.filter { !known.contains($0.id) })
        isLoadingMore = false
    }
}
