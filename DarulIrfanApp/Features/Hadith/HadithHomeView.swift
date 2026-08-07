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
    @State private var isSearching = false
    /// Debounces typing so a long corpus scan does not run on every keystroke.
    @State private var searchTask: Task<Void, Never>?

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
    }

    private var languageCode: String { appState.settings.language.rawValue }

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
                        NavigationLink {
                            HadithBookView(
                                book: book,
                                repository: dependencies.hadithRepository,
                                appState: appState
                            )
                        } label: {
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
                results = []; isSearching = false; return
            }
            isSearching = true
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                let found = (try? await dependencies.hadithRepository.search(
                    query, bookID: nil, limit: 100
                )) ?? []
                guard !Task.isCancelled else { return }
                results = found
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
            Text("\(results.count) match\(results.count == 1 ? "" : "es")")
                .font(.caption)
                .foregroundStyle(DIColor.textMuted)
            ForEach(results) { entry in
                resultCard(entry)
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
                    Text("#\(entry.hadithNumber)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DIColor.textMuted)
                    Spacer(minLength: 0)
                }
                if let text = entry.text(languageCode: languageCode), !text.isEmpty {
                    Text(verbatim: text)
                        .font(languageCode == "ur" ? DIFont.urduBody(scale: 0.95) : .subheadline)
                        .foregroundStyle(DIColor.textPrimary)
                        .lineLimit(4)
                        .multilineTextAlignment(languageCode == "ur" ? .trailing : .leading)
                        .environment(\.layoutDirection, languageCode == "ur" ? .rightToLeft : .leftToRight)
                        .frame(maxWidth: .infinity, alignment: languageCode == "ur" ? .trailing : .leading)
                }
            }
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
                    Text("\(book.hadithCount) hadith")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
    }

    private func load() async {
        books = (try? await dependencies.hadithRepository.books()) ?? []
        isLoading = false
    }
}
