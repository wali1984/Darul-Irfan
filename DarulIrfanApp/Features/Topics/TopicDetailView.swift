import SwiftUI
import Observation

/// One topic: its Qur'an verses, the hadith on it, and related library works
/// and bayans - the cross-reference surface tying the whole app together.
/// Every row opens what it names: an ayah in the Quran reader, a hadith in
/// its collection, a book or article in the library, a bayan in the player.
struct TopicDetailView: View {
    let topic: Topic
    let dependencies: AppDependencies
    let appState: AppState
    @State private var viewModel: TopicDetailViewModel
    @State private var showsAllVerses = false
    @State private var showsAllHadith = false
    @State private var video: TopicVideo?

    private static let previewCount = 6

    init(topic: Topic, dependencies: AppDependencies, appState: AppState) {
        self.topic = topic
        self.dependencies = dependencies
        self.appState = appState
        _viewModel = State(initialValue: TopicDetailViewModel(
            topic: topic,
            dependencies: dependencies,
            language: appState.settings.language
        ))
    }

    /// Urdu content, including "System" on an Urdu phone.
    private var isUrdu: Bool { appState.settings.language.contentLanguageCode == "ur" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                if viewModel.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, DISpacing.xl)
                } else {
                    if !viewModel.verses.isEmpty {
                        DISectionHeader(titleKey: "From the Qur'an", systemImage: "book.closed")
                        ForEach(showsAllVerses ? viewModel.verses : Array(viewModel.verses.prefix(Self.previewCount))) { verse in
                            verseCard(verse)
                        }
                        showAllButton(total: viewModel.verses.count, expanded: $showsAllVerses)
                    }
                    if !viewModel.hadith.isEmpty {
                        DISectionHeader(titleKey: "From the Hadith", systemImage: "text.book.closed")
                        ForEach(showsAllHadith ? viewModel.hadith : Array(viewModel.hadith.prefix(Self.previewCount))) { item in
                            TopicHadithCard(item: item, dependencies: dependencies, appState: appState, books: viewModel.books)
                        }
                        showAllButton(total: viewModel.hadith.count, expanded: $showsAllHadith)
                    }
                    if !viewModel.related.isEmpty {
                        DISectionHeader(titleKey: "Related in the Library & Bayans", systemImage: "link")
                        ForEach(viewModel.related) { item in
                            relatedRow(item)
                        }
                    }
                    if viewModel.verses.isEmpty && viewModel.hadith.isEmpty && viewModel.related.isEmpty {
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
        .sheet(item: $video) { video in YouTubePlayerSheet(videoID: video.id, title: video.title) }
    }

    @ViewBuilder
    private func showAllButton(total: Int, expanded: Binding<Bool>) -> some View {
        if total > Self.previewCount {
            Button {
                withAnimation { expanded.wrappedValue.toggle() }
            } label: {
                if expanded.wrappedValue {
                    Label("Show fewer", systemImage: "chevron.up")
                } else {
                    Label("Show all \(total)", systemImage: "chevron.down")
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
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
                    TopicTranslationText(text: translation)
                }
                HStack {
                    Text(verse.reference)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DIColor.primary)
                    Spacer()
                    Button {
                        DIHaptics.soft()
                        DeepLinkRouter.shared.open(.quranAyah(surah: verse.surah, ayah: verse.ayah))
                    } label: {
                        Label("Open in the Quran", systemImage: "book.closed")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    @ViewBuilder
    private func relatedRow(_ item: TopicDetailViewModel.RelatedItem) -> some View {
        switch item.domain {
        case .library:
            NavigationLink {
                ContentItemDetailView(
                    itemID: item.itemID,
                    dependencies: dependencies,
                    appState: appState,
                    libraryViewModel: viewModel.libraryViewModel
                )
            } label: {
                relatedLabel(item)
            }
            .buttonStyle(.plain)
        default:
            Button {
                Task { await play(item) }
            } label: {
                relatedLabel(item)
            }
            .buttonStyle(.plain)
        }
    }

    private func relatedLabel(_ item: TopicDetailViewModel.RelatedItem) -> some View {
        DICard(padding: DISpacing.sm) {
            HStack(spacing: DISpacing.sm) {
                Image(systemName: item.domain == .library ? "books.vertical" : "play.circle")
                    .font(.headline)
                    .foregroundStyle(DIColor.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.title)
                        .font(item.isUrdu ? DIFont.urduBody(scale: 0.9) : .subheadline.weight(.medium))
                        .foregroundStyle(DIColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(verbatim: subtitle)
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: item.domain == .library ? "chevron.forward" : "play.fill")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
    }

    /// A bayan plays in the app's own player; a video bayan opens its player.
    private func play(_ item: TopicDetailViewModel.RelatedItem) async {
        guard let media = try? await dependencies.mediaRepository.item(id: item.itemID) else { return }
        if let videoID = media.youtubeId, !videoID.isEmpty, media.streamUrl == nil {
            video = TopicVideo(id: videoID, title: media.title)
            return
        }
        guard let url = media.streamUrl.flatMap({ URL(string: $0) }) else {
            if let videoID = media.youtubeId, !videoID.isEmpty { video = TopicVideo(id: videoID, title: media.title) }
            return
        }
        DIHaptics.soft()
        dependencies.audioPlayer.play(
            AudioPlayableItem(id: media.id, title: media.title, subtitle: media.speaker, url: url, mediaItemID: media.id),
            queue: []
        )
    }
}

private struct TopicVideo: Identifiable {
    let id: String
    let title: String
}

/// A translation laid out by its own script: Urdu right to left, English
/// left to right, whatever the app's layout direction is.
private struct TopicTranslationText: View {
    let text: String
    var lineLimit: Int? = nil

    var body: some View {
        if ScriptDirection.isRightToLeft(text, fallbackLanguage: nil) {
            Text(verbatim: text)
                .font(DIFont.urduBody())
                .lineSpacing(6)
                .foregroundStyle(DIColor.textPrimary)
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .rightToLeft)
        } else {
            Text(verbatim: text)
                .font(.body)
                .foregroundStyle(DIColor.textPrimary)
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}

/// One narration: its translation in the app's language where the
/// collection has it, the Arabic, the reference, and a way into the
/// collection at that hadith.
private struct TopicHadithCard: View {
    let item: TopicDetailViewModel.HadithItem
    let dependencies: AppDependencies
    let appState: AppState
    let books: [String: HadithBook]
    @State private var expanded = false

    private var isUrdu: Bool { appState.settings.language.contentLanguageCode == "ur" }

    var body: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                if let translation = item.translation {
                    TopicTranslationText(text: translation, lineLimit: expanded ? nil : 6)
                    if isUrdu && !item.translationIsUrdu {
                        Text("This collection has no Urdu translation; English is shown.")
                            .font(.caption2)
                            .foregroundStyle(DIColor.textMuted)
                    }
                }
                if let arabic = item.arabic, !arabic.isEmpty {
                    Text(verbatim: arabic)
                        .font(DIFont.quranArabic(scale: 0.7))
                        .foregroundStyle(DIColor.textMuted)
                        .lineLimit(expanded ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                HStack(spacing: DISpacing.sm) {
                    Text(verbatim: reference)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DIColor.primary)
                    Spacer()
                    Button(expanded ? "Show less" : "Read more") {
                        withAnimation { expanded.toggle() }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                    if let book = books[item.bookID] {
                        NavigationLink {
                            HadithBookView(
                                book: book,
                                repository: dependencies.hadithRepository,
                                appState: appState,
                                initialHadith: item.id
                            )
                        } label: {
                            Label("Open", systemImage: "arrow.up.forward.square")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var reference: String {
        let title = books[item.bookID].map { isUrdu ? $0.titleUrdu : $0.titleEnglish } ?? item.bookID
        return "\(title) \(item.number)"
    }
}

@Observable
@MainActor
final class TopicDetailViewModel {
    struct VerseItem: Identifiable, Equatable {
        var id: String
        var surah: Int
        var ayah: Int
        var reference: String
        var arabic: String
        var translation: String?
    }

    struct HadithItem: Identifiable, Equatable {
        /// The canonical id, which the collection reader opens at.
        var id: String
        var bookID: String
        var number: String
        var arabic: String?
        var translation: String?
        var translationIsUrdu: Bool
    }

    struct RelatedItem: Identifiable, Equatable {
        var id: String
        var domain: SearchDomain
        var itemID: String
        var title: String
        var subtitle: String?
        var isUrdu: Bool
    }

    let topic: Topic
    private let dependencies: AppDependencies
    private let language: AppLanguage

    private(set) var verses: [VerseItem] = []
    private(set) var hadith: [HadithItem] = []
    private(set) var books: [String: HadithBook] = [:]
    private(set) var related: [RelatedItem] = []
    private(set) var isLoading = true
    /// One library state for the related works, with the favourites loaded,
    /// so a work's star is right and starring it twice cannot add it twice.
    let libraryViewModel: LibraryViewModel

    init(topic: Topic, dependencies: AppDependencies, language: AppLanguage) {
        self.topic = topic
        self.dependencies = dependencies
        self.language = language
        self.libraryViewModel = LibraryViewModel(contentRepository: dependencies.contentRepository)
    }

    func load() async {
        guard isLoading else { return }
        await resolveVerses()
        await resolveHadith()
        await findRelated()
        await libraryViewModel.loadFavorites()
        isLoading = false
    }

    /// Urdu content, including "System" on an Urdu phone.
    private var isUrdu: Bool { language.contentLanguageCode == "ur" }

    private func resolveVerses() async {
        let refs = topic.ayahRefs.compactMap { AyahRef($0) }
        guard !refs.isEmpty else { return }
        let repository = dependencies.quranRepository

        // Choose an offline translation edition matching the language.
        let editions = (try? await repository.editions()) ?? []
        let langCode = language.contentLanguageCode
        // The Silsila's own Akram-ut-Tarajum first, as in the reader.
        let edition = editions.first { $0.id == "akram-ut-tarajum-\(langCode)" }
            ?? editions.first { $0.kind == .translation && $0.isAvailableOffline && $0.language == langCode }
            ?? editions.first { $0.kind == .translation && $0.isAvailableOffline }

        // Cache per-surah data to avoid refetching a surah for adjacent refs.
        var ayahCache: [Int: [Int: String]] = [:]
        var transCache: [Int: [Int: String]] = [:]

        var items: [VerseItem] = []
        for ref in refs {
            if ayahCache[ref.surah] == nil {
                let rows = (try? await repository.ayahs(inSurah: ref.surah)) ?? []
                ayahCache[ref.surah] = Dictionary(rows.map { ($0.ayahNumber, $0.textArabic) },
                                                  uniquingKeysWith: { a, _ in a })
                if let edition {
                    let t = (try? await repository.translations(editionID: edition.id, surahNumber: ref.surah)) ?? []
                    transCache[ref.surah] = Dictionary(t.map { ($0.ayahNumber, $0.text) },
                                                       uniquingKeysWith: { a, _ in a })
                }
            }
            let arabic = (ref.start...ref.end).compactMap { ayahCache[ref.surah]?[$0] }.joined(separator: " ")
            let translation = (ref.start...ref.end).compactMap { transCache[ref.surah]?[$0] }.joined(separator: " ")
            guard !arabic.isEmpty else { continue }
            items.append(VerseItem(id: "\(ref.surah):\(ref.start)", surah: ref.surah, ayah: ref.start,
                                   reference: ref.reference, arabic: arabic,
                                   translation: translation.isEmpty ? nil : translation))
        }
        verses = items
    }

    private func resolveHadith() async {
        let refs = topic.hadithRefs ?? []
        guard !refs.isEmpty else { return }
        let repository = dependencies.hadithRepository
        let catalogue = (try? await repository.books()) ?? []
        books = Dictionary(catalogue.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let entries = (try? await repository.entries(canonicalIDs: refs)) ?? []
        hadith = entries.map { entry in
            let urdu = entry.textUrdu.flatMap { $0.isEmpty ? nil : $0 }
            let english = entry.textEnglish.flatMap { $0.isEmpty ? nil : $0 }
            return HadithItem(
                id: entry.canonicalID,
                bookID: entry.bookID,
                number: entry.displayNumber,
                arabic: entry.textArabic,
                translation: isUrdu ? (urdu ?? english) : (english ?? urdu),
                translationIsUrdu: isUrdu && urdu != nil
            )
        }
    }

    /// Each search term on its own, merged in order. The terms used to go in
    /// as one query, which full-text search reads as "all of these words" -
    /// "tawhid oneness unity of Allah" - so almost every topic came back
    /// empty and showed "Nothing linked yet". In Urdu, Urdu works come first
    /// and a work's Urdu title is shown where it has one.
    private func findRelated() async {
        var seen = Set<String>()
        var merged: [SearchResult] = []
        for term in topic.searchTerms where !term.trimmingCharacters(in: .whitespaces).isEmpty {
            let results = (try? await dependencies.searchIndex.search(term, domains: [.library, .media], limit: 12)) ?? []
            for result in results {
                // A matching page of a book stands for the book itself: the
                // related list names works, not pages.
                let work = result.bookPage.map {
                    SearchResult(domain: .library, itemID: $0.bookID, title: result.title,
                                 snippet: result.snippet, language: result.language)
                } ?? result
                if seen.insert(work.id).inserted { merged.append(work) }
            }
            if merged.count >= 40 { break }
        }
        var items: [RelatedItem] = []
        for result in merged {
            var title = result.title
            if result.domain == .library,
               let item = try? await dependencies.contentRepository.item(id: result.itemID) {
                title = item.title
                if isUrdu, let urduTitle = item.titleUrdu, !urduTitle.isEmpty { title = urduTitle }
            }
            let titleIsUrdu = ScriptDirection.isRightToLeft(title, fallbackLanguage: nil)
            // The snippet only where it is in the same script as the title:
            // an English snippet under an Urdu title read as untranslated.
            let snippet = result.snippet.flatMap {
                ScriptDirection.isRightToLeft($0, fallbackLanguage: nil) == titleIsUrdu ? $0 : nil
            }
            items.append(RelatedItem(
                id: result.id, domain: result.domain, itemID: result.itemID, title: title,
                subtitle: snippet, isUrdu: titleIsUrdu
            ))
        }
        // Works in the reader's language first, each group in search order.
        let preferred = items.filter { $0.isUrdu == isUrdu }
        let others = items.filter { $0.isUrdu != isUrdu }
        related = Array((preferred + others).prefix(30))
    }
}
