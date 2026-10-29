import SwiftUI

/// A search hit that opens what it names: an ayah in the Quran reader, a
/// narration in its collection, a library work in its reader - a page of a
/// book's text at that page - a bayan in the player, an event's details.
/// Search results used to be rows with nothing behind them.
@MainActor
struct SearchResultLink<RowContent: View>: View {
    let result: SearchResult
    let dependencies: AppDependencies
    let appState: AppState
    /// One library state for every result, with the favourites loaded, so a
    /// work's star is right.
    let libraryViewModel: LibraryViewModel
    /// Closes the search sheet before the Quran tab takes over.
    let close: () -> Void
    @ViewBuilder let label: () -> RowContent

    @State private var video: SearchVideo?

    var body: some View {
        Group {
            switch result.domain {
            case .library:
                if let page = result.bookPage {
                    NavigationLink {
                        BookPageDestination(
                            bookID: page.bookID,
                            page: page.page,
                            dependencies: dependencies,
                            fontScale: appState.settings.readerFontScale.rawValue
                        )
                    } label: { label() }
                } else {
                    NavigationLink {
                        ContentItemDetailView(
                            itemID: result.itemID,
                            dependencies: dependencies,
                            appState: appState,
                            libraryViewModel: libraryViewModel
                        )
                    } label: { label() }
                }
            case .events:
                NavigationLink {
                    SearchEventDestination(eventID: result.itemID, dependencies: dependencies)
                } label: { label() }
            case .quran:
                Button { openAyah() } label: { label() }
            case .hadith:
                NavigationLink {
                    SearchHadithDestination(canonicalID: result.itemID, dependencies: dependencies, appState: appState)
                } label: { label() }
            case .media:
                Button { Task { await play() } } label: { label() }
            }
        }
        .buttonStyle(.plain)
        .sheet(item: $video) { video in YouTubePlayerSheet(videoID: video.id, title: video.title) }
    }

    /// "2:255" (an ayah, or the first ayah of a tafsir passage) opens the
    /// reader at that ayah, on the Quran tab.
    private func openAyah() {
        guard let reference = result.ayahReference else { return }
        DIHaptics.soft()
        close()
        // After the sheet has gone, so the tab switch is not hidden behind it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            DeepLinkRouter.shared.open(.quranAyah(surah: reference.surah, ayah: reference.ayah))
        }
    }

    /// Audio plays in the app's own player; a video-only bayan opens its player.
    private func play() async {
        guard let media = try? await dependencies.mediaRepository.item(id: result.itemID) else { return }
        if let url = media.streamUrl.flatMap({ URL(string: $0) }) {
            DIHaptics.soft()
            dependencies.audioPlayer.play(
                AudioPlayableItem(id: media.id, title: media.title, subtitle: media.speaker, url: url, mediaItemID: media.id),
                queue: []
            )
        } else if let videoID = media.youtubeId, !videoID.isEmpty {
            video = SearchVideo(id: videoID, title: media.title)
        }
    }
}

private struct SearchVideo: Identifiable {
    let id: String
    let title: String
}

/// Loads a book's catalogue entry, then opens its text at the page found.
private struct BookPageDestination: View {
    let bookID: String
    let page: Int
    let dependencies: AppDependencies
    let fontScale: Double
    @State private var item: ContentItem?

    var body: some View {
        Group {
            if let item {
                BookTextReaderView(item: item, dependencies: dependencies, startPage: page, fontScale: fontScale)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            let stored = try? await dependencies.contentRepository.item(id: bookID)
            item = stored ?? ContentItem(
                id: bookID,
                sourceUrl: "",
                type: .book,
                title: bookID,
                titleUrdu: nil,
                language: "ur",
                author: nil,
                category: .books,
                bodyHtml: nil,
                bodyPlainText: nil,
                excerpt: nil,
                publishedAt: nil,
                updatedAt: nil,
                mediaUrls: [],
                downloadUrls: [],
                checksum: nil,
                rightsStatus: .permissionConfirmed
            )
        }
    }
}

/// Loads a narration's collection, then opens the collection at that
/// narration, as a result in the Hadith tab does.
private struct SearchHadithDestination: View {
    /// `bookID|displayNumber|sourceSequence`.
    let canonicalID: String
    let dependencies: AppDependencies
    let appState: AppState
    @State private var book: HadithBook?
    @State private var loaded = false

    var body: some View {
        Group {
            if let book {
                HadithBookView(
                    book: book,
                    repository: dependencies.hadithRepository,
                    appState: appState,
                    initialHadith: canonicalID
                )
            } else if loaded {
                DIEmptyState(systemImage: "text.book.closed", titleKey: "Hadith not found",
                             messageKey: "This narration is not among the collections in the app.")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            let bookID = canonicalID.split(separator: "|").first.map(String.init) ?? canonicalID
            book = (try? await dependencies.hadithRepository.books())?.first { $0.id == bookID }
            loaded = true
        }
    }
}

/// Loads an event by id, then shows its details.
private struct SearchEventDestination: View {
    let eventID: String
    let dependencies: AppDependencies
    @State private var event: CommunityEvent?
    @State private var loaded = false

    var body: some View {
        Group {
            if let event {
                EventDetailView(event: event, notifications: dependencies.notifications)
            } else if loaded {
                DIEmptyState(systemImage: "calendar", titleKey: "Event not found",
                             messageKey: "It may have ended or been removed.")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            event = (try? await dependencies.eventsRepository.events())?.first { $0.id == eventID }
            loaded = true
        }
    }
}
