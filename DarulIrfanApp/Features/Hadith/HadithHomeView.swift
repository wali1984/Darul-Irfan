import SwiftUI

/// Hadith section: the bundled collections, opening into a paged reader.
@MainActor
struct HadithHomeView: View {
    private let dependencies: AppDependencies
    private let appState: AppState
    @State private var books: [HadithBook] = []
    @State private var isLoading = true

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
    }

    private var languageCode: String { appState.settings.language.rawValue }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                if isLoading {
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
        .task { await load() }
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
