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

    private static let pageSize = 50

    private var languageCode: String { appState.settings.language.rawValue }

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

                    ForEach(entries) { entry in
                        hadithCard(entry)
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
        .task { await loadFirstPage() }
    }

    private func hadithCard(_ entry: HadithEntry) -> some View {
        DICard(
            background: DIColor.primary.opacity(0.045),
            borderColor: DIColor.primary.opacity(0.35),
            borderWidth: 1
        ) {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) {
                    DIPillBadge(text: "#\(entry.hadithNumber)", color: DIColor.primary)
                    if let grades = entry.grades, let first = grades.first {
                        DIPillBadge(text: first, color: DIColor.accent)
                    }
                    Spacer(minLength: 0)
                }

                if showsArabic, let arabic = entry.textArabic, !arabic.isEmpty {
                    Text(verbatim: arabic)
                        .font(DIFont.quranArabic(scale: 0.62))
                        .foregroundStyle(DIColor.textPrimary)
                        .environment(\.layoutDirection, .rightToLeft)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().overlay(DIColor.border)
                }

                if let text = entry.text(languageCode: languageCode), !text.isEmpty {
                    if languageCode == "ur" {
                        Text(verbatim: text)
                            .font(DIFont.urduBody())
                            .foregroundStyle(DIColor.textPrimary)
                            .environment(\.layoutDirection, .rightToLeft)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(verbatim: text)
                            .font(.body)
                            .foregroundStyle(DIColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func loadFirstPage() async {
        guard entries.isEmpty else { return }
        entries = (try? await repository.entries(
            bookID: book.id, limit: Self.pageSize, offset: 0
        )) ?? []
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
