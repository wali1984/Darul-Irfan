import SwiftUI
import Observation

/// One topic: its anchor Qur'an verses (with translation) and related content
/// found across tafseer/books/articles and audio bayans — the cross-reference
/// surface tying the whole app together.
struct TopicDetailView: View {
    let topic: Topic
    let dependencies: AppDependencies
    let appState: AppState
    @State private var viewModel: TopicDetailViewModel

    init(topic: Topic, dependencies: AppDependencies, appState: AppState) {
        self.topic = topic
        self.dependencies = dependencies
        self.appState = appState
        _viewModel = State(initialValue: TopicDetailViewModel(
            topic: topic,
            quranRepository: dependencies.quranRepository,
            searchIndex: dependencies.searchIndex,
            language: appState.settings.language
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                if viewModel.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, DISpacing.xl)
                } else {
                    if !viewModel.verses.isEmpty {
                        DISectionHeader(titleKey: "From the Qur'an", systemImage: "book.closed")
                        ForEach(viewModel.verses) { verse in
                            verseCard(verse)
                        }
                    }
                    if !viewModel.related.isEmpty {
                        DISectionHeader(titleKey: "Related in the Library & Bayans", systemImage: "link")
                        ForEach(viewModel.related) { result in
                            relatedRow(result)
                        }
                    }
                    if viewModel.verses.isEmpty && viewModel.related.isEmpty {
                        DIEmptyState(systemImage: "sparkles",
                                     titleKey: "Nothing linked yet",
                                     messageKey: "Related content will appear here as the library grows.")
                    }
                }
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .navigationTitle(topic.name(for: appState.settings.language))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    private func verseCard(_ verse: TopicDetailViewModel.VerseItem) -> some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text(verse.arabic)
                    .font(DIFont.quranArabic(scale: 1.0))
                    .foregroundStyle(DIColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .environment(\.layoutDirection, .rightToLeft)
                if let translation = verse.translation, !translation.isEmpty {
                    Rectangle().fill(DIColor.accent).frame(height: 1).opacity(0.4)
                    Text(translation)
                        .font(.body)
                        .foregroundStyle(DIColor.textPrimary)
                }
                Text(verse.reference)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DIColor.primary)
            }
        }
    }

    private func relatedRow(_ result: SearchResult) -> some View {
        DICard(padding: DISpacing.sm) {
            HStack(spacing: DISpacing.sm) {
                Image(systemName: icon(for: result.domain))
                    .font(.headline)
                    .foregroundStyle(DIColor.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DIColor.textPrimary)
                        .lineLimit(2)
                    if let snippet = result.snippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func icon(for domain: SearchDomain) -> String {
        switch domain {
        case .quran: return "book.closed"
        case .library: return "books.vertical"
        case .media: return "play.circle"
        case .events: return "calendar"
        }
    }
}

@Observable
@MainActor
final class TopicDetailViewModel {
    struct VerseItem: Identifiable, Equatable {
        var id: String
        var reference: String
        var arabic: String
        var translation: String?
    }

    let topic: Topic
    private let quranRepository: any QuranRepositoryProtocol
    private let searchIndex: any SearchIndexServicing
    private let language: AppLanguage

    private(set) var verses: [VerseItem] = []
    private(set) var related: [SearchResult] = []
    private(set) var isLoading = true

    init(topic: Topic, quranRepository: any QuranRepositoryProtocol,
         searchIndex: any SearchIndexServicing, language: AppLanguage) {
        self.topic = topic
        self.quranRepository = quranRepository
        self.searchIndex = searchIndex
        self.language = language
    }

    func load() async {
        await resolveVerses()
        await findRelated()
        isLoading = false
    }

    private func resolveVerses() async {
        let refs = topic.ayahRefs.compactMap { AyahRef($0) }
        guard !refs.isEmpty else { return }

        // Choose an offline translation edition matching the language.
        let editions = (try? await quranRepository.editions()) ?? []
        let langCode = language.forcedLocaleIdentifier ?? "en"
        let edition = editions.first { $0.kind == .translation && $0.isAvailableOffline && $0.language == langCode }
            ?? editions.first { $0.kind == .translation && $0.isAvailableOffline }

        // Cache per-surah data to avoid refetching a surah for adjacent refs.
        var ayahCache: [Int: [Int: String]] = [:]
        var transCache: [Int: [Int: String]] = [:]

        var items: [VerseItem] = []
        for ref in refs {
            if ayahCache[ref.surah] == nil {
                let rows = (try? await quranRepository.ayahs(inSurah: ref.surah)) ?? []
                ayahCache[ref.surah] = Dictionary(rows.map { ($0.ayahNumber, $0.textArabic) },
                                                  uniquingKeysWith: { a, _ in a })
                if let edition {
                    let t = (try? await quranRepository.translations(editionID: edition.id, surahNumber: ref.surah)) ?? []
                    transCache[ref.surah] = Dictionary(t.map { ($0.ayahNumber, $0.text) },
                                                       uniquingKeysWith: { a, _ in a })
                }
            }
            let arabic = (ref.start...ref.end).compactMap { ayahCache[ref.surah]?[$0] }.joined(separator: " ")
            let translation = (ref.start...ref.end).compactMap { transCache[ref.surah]?[$0] }.joined(separator: " ")
            guard !arabic.isEmpty else { continue }
            items.append(VerseItem(id: "\(ref.surah):\(ref.start)", reference: ref.reference,
                                   arabic: arabic, translation: translation.isEmpty ? nil : translation))
        }
        verses = items
    }

    private func findRelated() async {
        let query = topic.searchQuery
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let results = (try? await searchIndex.search(query, domains: [.library, .media, .events], limit: 25)) ?? []
        related = results
    }
}
