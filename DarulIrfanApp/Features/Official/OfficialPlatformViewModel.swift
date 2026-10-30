import Foundation
import Observation

@Observable
@MainActor
final class OfficialPlatformViewModel {
    private let feedService: any OfficialFeedServicing
    private let liveService: any LiveBroadcastServicing

    private(set) var bootstrap: AppBootstrap = .offline
    private(set) var feedItems: [OfficialFeedItem] = []
    private(set) var live: LiveBroadcast = .offline
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isShowingCachedContent = false
    private(set) var errorMessage: String?

    var isOfficialFeedEnabled: Bool {
        bootstrap.generatedAt == .distantPast || bootstrap.featureFlags.officialFeed
    }

    var isLiveHubEnabled: Bool {
        bootstrap.generatedAt == .distantPast || bootstrap.featureFlags.liveHub
    }

    init(feedService: any OfficialFeedServicing, liveService: any LiveBroadcastServicing) {
        self.feedService = feedService
        self.liveService = liveService
    }

    func load(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        bootstrap = await feedService.bootstrap(forceRefresh: forceRefresh)

        if isOfficialFeedEnabled {
            do {
                let page = try await feedService.feed(after: nil, forceRefresh: forceRefresh)
                feedItems = Self.deduplicated(page.items)
                nextCursor = page.nextCursor
                isShowingCachedContent = page.isFromCache
            } catch {
                errorMessage = String(localized: "Official updates could not be refreshed. Please check your connection and try again.")
            }
        } else {
            feedItems = []
            nextCursor = nil
            isShowingCachedContent = false
        }

        if isLiveHubEnabled {
            live = await liveService.currentLiveBroadcast(forceRefresh: forceRefresh)
        } else {
            live = .offline
        }
    }

    func loadMore() async {
        guard isOfficialFeedEnabled, !isLoadingMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await feedService.feed(after: cursor, forceRefresh: true)
            feedItems = Self.deduplicated(feedItems + page.items)
            nextCursor = page.nextCursor
        } catch {
            errorMessage = String(localized: "More updates could not be loaded.")
        }
    }

    private static func deduplicated(_ items: [OfficialFeedItem]) -> [OfficialFeedItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Announcements and press

/// One entry of Updates' "Announcements and press".
enum UpdatesNewsEntry: Identifiable, Equatable {
    /// An announcement the official feed carries.
    case feed(OfficialFeedItem)
    /// A library announcement or press release, opened in its reader.
    case library(ContentItem)
    /// One of the app's own notes, such as its welcome note.
    case note(Announcement)

    var id: String {
        switch self {
        case .feed(let item): return "feed|\(item.id)"
        case .library(let item): return "library|\(item.id)"
        case .note(let note): return "note|\(note.id)"
        }
    }

    var date: Date? {
        switch self {
        case .feed(let item): return item.publishedAt
        case .library(let item): return item.publishedAt ?? item.updatedAt
        case .note(let note): return note.publishedAt
        }
    }
}

/// The Library's announcements and press releases, joined with the feed's
/// own announcements, for Updates. They used to sit under Library › News
/// and again under Events › Announcements.
enum UpdatesNews {
    /// Every entry once, newest first; undated ones last.
    static func merged(
        feed: [OfficialFeedItem],
        library: [ContentItem],
        notes: [Announcement]
    ) -> [UpdatesNewsEntry] {
        let libraryNews = library.filter { $0.type == .announcement || $0.type == .pressRelease }
        let libraryIDs = Set(libraryNews.map(\.id))
        let fromFeed: [UpdatesNewsEntry] = feed
            .filter { $0.source == .announcement }
            .map { UpdatesNewsEntry.feed($0) }
        let fromLibrary: [UpdatesNewsEntry] = libraryNews.map { UpdatesNewsEntry.library($0) }
        let fromNotes: [UpdatesNewsEntry] = notes
            .filter { !libraryIDs.contains($0.id) }
            .map { UpdatesNewsEntry.note($0) }
        var seen = Set<String>()
        let unique = (fromFeed + fromLibrary + fromNotes).filter { seen.insert($0.id).inserted }
        return unique.sorted { lhs, rhs in
            let left = lhs.date ?? .distantPast
            let right = rhs.date ?? .distantPast
            if left != right { return left > right }
            return lhs.id < rhs.id
        }
    }
}

/// The library side of "Announcements and press": the announcements and
/// press releases in the library, and the app's own notes.
@Observable
@MainActor
final class UpdatesNewsModel {
    private let contentRepository: any ContentRepositoryProtocol
    private let eventsRepository: any EventsRepositoryProtocol

    private(set) var library: [ContentItem] = []
    private(set) var notes: [Announcement] = []
    private(set) var isLoaded = false

    init(contentRepository: any ContentRepositoryProtocol, eventsRepository: any EventsRepositoryProtocol) {
        self.contentRepository = contentRepository
        self.eventsRepository = eventsRepository
    }

    func loadIfNeeded() async {
        guard !isLoaded else { return }
        await load()
    }

    func load() async {
        let announcements = (try? await contentRepository.items(
            category: nil, type: .announcement, language: nil, limit: 200
        )) ?? []
        let pressReleases = (try? await contentRepository.items(
            category: nil, type: .pressRelease, language: nil, limit: 200
        )) ?? []
        library = announcements + pressReleases
        notes = (try? await eventsRepository.announcements(limit: 20)) ?? []
        isLoaded = true
    }

    /// The entries, with the feed's announcements among those loaded.
    func entries(feed: [OfficialFeedItem]) -> [UpdatesNewsEntry] {
        UpdatesNews.merged(feed: feed, library: library, notes: notes)
    }
}
