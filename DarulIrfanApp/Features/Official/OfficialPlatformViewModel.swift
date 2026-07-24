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

    init(feedService: any OfficialFeedServicing, liveService: any LiveBroadcastServicing) {
        self.feedService = feedService
        self.liveService = liveService
    }

    func load(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let bootstrapValue = feedService.bootstrap(forceRefresh: forceRefresh)
        async let liveValue = liveService.currentLiveBroadcast(forceRefresh: forceRefresh)
        do {
            let page = try await feedService.feed(after: nil, forceRefresh: forceRefresh)
            feedItems = Self.deduplicated(page.items)
            nextCursor = page.nextCursor
            isShowingCachedContent = page.isFromCache
        } catch {
            errorMessage = "Official updates could not be refreshed. Please check your connection and try again."
        }
        bootstrap = await bootstrapValue
        live = await liveValue
    }

    func loadMore() async {
        guard !isLoadingMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await feedService.feed(after: cursor, forceRefresh: true)
            feedItems = Self.deduplicated(feedItems + page.items)
            nextCursor = page.nextCursor
        } catch {
            errorMessage = "More updates could not be loaded."
        }
    }

    private static func deduplicated(_ items: [OfficialFeedItem]) -> [OfficialFeedItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
