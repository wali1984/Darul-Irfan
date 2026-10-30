import SwiftUI

/// Hadith section: the bundled collections, opening into a paged reader.
@MainActor
struct HadithHomeView: View {
    private let dependencies: AppDependencies
    private let appState: AppState
    @State private var books: [HadithBook] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var results: [HadithEntry] = []
    /// How many narrations matched in all, when known; the results are a few
    /// from each collection, so this is usually more than are shown.
    @State private var matchCount: Int?
    @State private var isSearching = false
    /// Debounces typing so a long corpus scan does not run on every keystroke.
    @State private var searchTask: Task<Void, Never>?

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
    }

    /// The content language: "System" on an Urdu phone reads in Urdu.
    private var languageCode: String { appState.settings.language.contentLanguageCode }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchSection
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(DISpacing.xl)
                } else if books.isEmpty {
                    DIEmptyState(
                        systemImage: "books.vertical",
                        titleKey: "Hadith collections are being prepared",
                        messageKey: "They will appear here after the next content update."
                    )
                } else {
                    DISectionHeader(titleKey: "Collections", systemImage: "books.vertical.fill")
                    ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                        // Value-based so the Read tab can own this reader's
                        // navigation history; see HadithTabView.
                        NavigationLink(value: HadithRoute.collection(book)) {
                            bookCard(book)
                        }
                        .buttonStyle(DIPressableStyle())
                        .diAppear(delay: 0.04 * Double(index))
                    }
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .diPageHeading("Hadith")
        .searchable(
            text: $searchText,
            prompt: Text("Search hadith by word or topic")
        )
        .onChange(of: searchText) { _, term in
            searchTask?.cancel()
            let query = term.trimmingCharacters(in: .whitespaces)
            guard query.count >= 2 else {
                results = []; matchCount = nil; isSearching = false; return
            }
            isSearching = true
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                let repository = dependencies.hadithRepository
                let found = (try? await repository.search(query, bookID: nil, limit: 100)) ?? []
                let total = (try? await repository.searchCount(query, bookID: nil)) ?? nil
                guard !Task.isCancelled else { return }
                results = found
                matchCount = total
                isSearching = false
            }
        }
        .task { await load() }
    }

    /// Results across every collection, searched in all three scripts.
    @ViewBuilder
    private var searchSection: some View {
        if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(DISpacing.xl)
        } else if results.isEmpty {
            DIEmptyState(
                systemImage: "magnifyingglass",
                titleKey: "No hadith match that search",
                messageKey: "Try a different word. Search looks through the Arabic, English and Urdu of every bundled collection."
            )
        } else {
            DISectionHeader(titleKey: "Results", systemImage: "magnifyingglass")
            Group {
                if let matchCount, matchCount > results.count {
                    Text("Showing \(results.count) of \(matchCount) matches, a few from each collection")
                } else {
                    Text("Matches: \(results.count)")
                }
            }
            .font(.caption)
            .foregroundStyle(DIColor.textMuted)
            ForEach(results) { entry in
                // A result must open the exact narration in its collection, not
                // just sit there: wrap it in the same value-based link the
                // collection list uses so tapping navigates within this stack.
                if let book = books.first(where: { $0.id == entry.bookID }) {
                    NavigationLink(value: HadithRoute.hadith(book, entry.canonicalID)) {
                        resultCard(entry)
                    }
                    .buttonStyle(DIPressableStyle())
                } else {
                    resultCard(entry)
                }
            }
        }
    }

    private func resultCard(_ entry: HadithEntry) -> some View {
        let bookTitle = books.first { $0.id == entry.bookID }?
            .title(languageCode: languageCode) ?? entry.bookID
        return DICard {
            VStack(alignment: .leading, spacing: DISpacing.xs) {
                HStack(spacing: DISpacing.sm) {
                    DIPillBadge(text: bookTitle, color: DIColor.primary)
                    Text(verbatim: "#\(entry.displayNumber)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DIColor.textMuted)
                    Spacer(minLength: 0)
                }
                // A search can match a script the reader is not currently in, so
                // the preview shows whatever text exists — but styled for the
                // language it actually is, never the reader's. English set in
                // Nastaliq and reversed would misrepresent it as the Urdu.
                if let preview = entry.availableText(preferring: languageCode) {
                    let style = Self.snippetStyle(for: preview.languageCode)
                    Text(verbatim: preview.text)
                        .font(style.font)
                        .foregroundStyle(DIColor.textPrimary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, style.isRTL ? .rightToLeft : .leftToRight)
                }
            }
        }
    }

    /// Typography for a snippet, chosen by the language the text actually is
    /// rather than the reader's, so a match in one script is never dressed up
    /// as another.
    private static func snippetStyle(for languageCode: String) -> (font: Font, isRTL: Bool) {
        switch languageCode {
        case "ur": return (DIFont.urduBody(scale: 0.95), true)
        case "ar": return (DIFont.quranArabic(scale: 0.62), true)
        default: return (.subheadline, false)
        }
    }

    private func bookCard(_ book: HadithBook) -> some View {
        DIElevatedCard(glow: DIColor.accent) {
            HStack(spacing: DISpacing.md) {
                ZStack {
                    Circle().fill(DIGradient.emerald)
                    Image(systemName: "book.closed.fill")
                        .font(.headline)
                        .foregroundStyle(DIColor.onPrimary)
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text(verbatim: book.title(languageCode: languageCode))
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: DISpacing.sm) {
                        Text("\(book.hadithCount) hadith")
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                        if let note = translationNote(for: book) {
                            DIPillBadge(text: note, color: DIColor.accent)
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Says on the card when a collection cannot be read in translation, so
    /// nobody opens 30,000 narrations to find each one "has no English
    /// translation".
    private func translationNote(for book: HadithBook) -> String? {
        if !book.hasEnglish && !book.hasUrdu { return String(localized: "Arabic only") }
        if !book.hasUrdu { return String(localized: "No Urdu translation") }
        if !book.hasEnglish { return String(localized: "No English translation") }
        return nil
    }

    private func load() async {
        // In reading order: the two Sahihs and the Sunan first, the
        // Arabic-only works after them (HadithRepository.collectionOrder).
        books = (try? await dependencies.hadithRepository.books()) ?? []
        isLoading = false
    }
}
