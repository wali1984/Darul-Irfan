import Foundation
import Observation

/// The channel's recent videos that are bayans, for Discover › Bayans:
/// every video in the official feed except the daily zikr recordings, by the
/// rule the Zikr tab's Recent Bayans use (`ZikrHomeViewModel.isZikrRecording`).
/// The channel's uploads are mostly the daily zikr streams, so the feed is
/// read on, a few pages at a time, until enough bayans are found.
@Observable
@MainActor
final class BayansFeedModel {
    private let feed: any OfficialFeedServicing

    /// Bayans found so far, in the feed's order (newest first).
    private(set) var videos: [OfficialFeedItem] = []
    /// Where the feed goes on, while there is more of it.
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// False while the server has paused the official feed.
    private(set) var isFeedEnabled = true

    /// How many bayans the carousel shows, and one read looks for.
    static let carouselCount = 8
    /// Pages read at most for one look.
    static let pagesPerRead = 3

    init(feed: any OfficialFeedServicing) {
        self.feed = feed
    }

    /// The feed's videos that are bayans: not the daily zikr recordings,
    /// and not posts without a video.
    static func bayanVideos(in items: [OfficialFeedItem]) -> [OfficialFeedItem] {
        items.filter { $0.videoID != nil && !ZikrHomeViewModel.isZikrRecording($0) }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    /// Reads the feed from its first page until enough bayans are found.
    /// When no page loads, the bayans shown stay.
    func load(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let bootstrap = await feed.bootstrap(forceRefresh: forceRefresh)
        isFeedEnabled = bootstrap.generatedAt == .distantPast || bootstrap.featureFlags.officialFeed
        guard isFeedEnabled else {
            videos = []
            nextCursor = nil
            hasLoaded = true
            return
        }
        if let found = await read(from: nil, forceRefresh: forceRefresh) {
            videos = found.videos
            nextCursor = found.cursor
        }
        hasLoaded = true
    }

    /// The next pages, for the full list.
    func loadMore() async {
        guard !isLoading, isFeedEnabled, let cursor = nextCursor else { return }
        isLoading = true
        defer { isLoading = false }
        guard let found = await read(from: cursor, forceRefresh: true) else { return }
        var seen = Set(videos.map(\.id))
        videos += found.videos.filter { seen.insert($0.id).inserted }
        nextCursor = found.cursor
    }

    /// Pages from `start` on, until `carouselCount` bayans or the end of
    /// the feed; nil when not even the first page loads.
    private func read(from start: String?, forceRefresh: Bool) async -> (videos: [OfficialFeedItem], cursor: String?)? {
        var found: [OfficialFeedItem] = []
        var cursor = start
        var readAny = false
        for _ in 0..<Self.pagesPerRead {
            guard let page = try? await feed.feed(after: cursor, forceRefresh: forceRefresh) else { break }
            readAny = true
            found += Self.bayanVideos(in: page.items)
            cursor = page.nextCursor
            if found.count >= Self.carouselCount || cursor == nil { break }
        }
        guard readAny else { return nil }
        return (found, cursor)
    }
}

/// A bayan video's title in two parts for its card: the name, and what
/// follows the channel's " | " ("Deen ki Tableegh | Surah Al Imran Ayat
/// 186-188"). Nothing is reworded; a title without one stays whole.
enum BayanVideoTitle {
    static func split(_ title: String) -> (headline: String, detail: String?) {
        let parts = title
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count > 1 else { return (title, nil) }
        return (parts[0], parts.dropFirst().joined(separator: " | "))
    }
}
