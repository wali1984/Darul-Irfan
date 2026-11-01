import XCTest
@testable import DarulIrfan

private actor DelayedOfficialFeed: OfficialFeedServicing, LiveBroadcastServicing {
    private var loads = 0
    private var pending: CheckedContinuation<OfficialFeedPage, Error>?
    private var started: CheckedContinuation<Void, Never>?

    func bootstrap(forceRefresh: Bool) async -> AppBootstrap { .offline }
    func currentLiveBroadcast(forceRefresh: Bool) async -> LiveBroadcast { .offline }

    private func item(_ id: String) -> OfficialFeedItem {
        OfficialFeedItem(id: id, source: .website, kind: .post, title: id, body: nil,
                         sourceURL: URL(string: "https://example.org/" + id)!, imageURL: nil,
                         videoID: nil, publishedAt: .distantPast, isFeatured: false)
    }

    func feed(after cursor: String?, forceRefresh: Bool) async throws -> OfficialFeedPage {
        if cursor == nil {
            loads += 1
            let id = loads == 1 ? "initial" : "fresh"
            return OfficialFeedPage(items: [item(id)], nextCursor: id + "-cursor")
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            started?.resume()
            started = nil
        }
    }

    func waitForPage() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finishPage() {
        pending?.resume(returning: OfficialFeedPage(items: [item("stale")], nextCursor: "stale-cursor"))
        pending = nil
    }
}

@MainActor
final class OfficialFeedLifecycleTests: XCTestCase {
    func testLatePaginationCannotAppendToRefreshedFeed() async {
        let service = DelayedOfficialFeed()
        let model = OfficialPlatformViewModel(feedService: service, liveService: service)
        await model.load()
        let page = Task { await model.loadMore() }
        await service.waitForPage()
        await model.load(forceRefresh: true)
        await service.finishPage()
        await page.value
        XCTAssertEqual(model.feedItems.map(\.id), ["fresh"])
        XCTAssertEqual(model.nextCursor, "fresh-cursor")
        XCTAssertFalse(model.isLoadingMore)
        XCTAssertNil(model.errorMessage)
    }

    func testCancelledPaginationDoesNotPublishOrReportFailure() async {
        let service = DelayedOfficialFeed()
        let model = OfficialPlatformViewModel(feedService: service, liveService: service)
        await model.load()
        let page = Task { await model.loadMore() }
        await service.waitForPage()
        page.cancel()
        await service.finishPage()
        await page.value
        XCTAssertEqual(model.feedItems.map(\.id), ["initial"])
        XCTAssertEqual(model.nextCursor, "initial-cursor")
        XCTAssertFalse(model.isLoadingMore)
        XCTAssertNil(model.errorMessage)
    }
}
