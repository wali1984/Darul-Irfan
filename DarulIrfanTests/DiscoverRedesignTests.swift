import Foundation
import XCTest
@testable import DarulIrfan

/// The Discover redesign (parity-spec/redesign, October 2026): the section
/// it opens on, the theme of the day it took from Today, the Library's news
/// joining Updates, and the bayans on YouTube.
final class DiscoverRedesignTests: XCTestCase {

    // MARK: - Section

    /// Bayans on the first visit, then the last section chosen.
    func testBayansOnTheFirstVisitThenTheLastChoice() throws {
        let suite = "DiscoverRedesignTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(DiscoverSection.remembered(in: defaults), .bayans)
        defaults.set(DiscoverSection.events.rawValue, forKey: DiscoverSection.storageKey)
        XCTAssertEqual(DiscoverSection.remembered(in: defaults), .events)
        defaults.set(DiscoverSection.topics.rawValue, forKey: DiscoverSection.storageKey)
        XCTAssertEqual(DiscoverSection.remembered(in: defaults), .topics)

        // The older layout's chips are not sections any more.
        for stale in ["library", "media", "Topics", ""] {
            XCTAssertEqual(DiscoverSection.remembered(stale), .bayans, stale)
        }
        XCTAssertEqual(DiscoverSection.remembered(nil), .bayans)
        XCTAssertEqual(DiscoverSection.allCases, [.bayans, .updates, .events, .topics])
    }

    /// Links and notifications still open the right section. A library link
    /// is no longer Discover's: the books moved to Read.
    func testLinksSelectTheirSection() {
        XCTAssertEqual(DiscoverSection(route: .media), .bayans)
        XCTAssertEqual(DiscoverSection(route: .updates(itemID: nil)), .updates)
        XCTAssertEqual(DiscoverSection(route: .updates(itemID: "post-1")), .updates)
        XCTAssertEqual(DiscoverSection(route: .events(eventID: nil)), .events)
        XCTAssertEqual(DiscoverSection(route: .events(eventID: "seminar-1")), .events)
        XCTAssertEqual(DiscoverSection(route: .topics), .topics)
        XCTAssertNil(DiscoverSection(route: .library))
        XCTAssertNil(DiscoverSection(route: .today))
        XCTAssertNil(DiscoverSection(route: .live))
        XCTAssertNil(DiscoverSection(route: .groups))

        XCTAssertEqual(AppRoute(path: "feed/abc").flatMap { DiscoverSection(route: $0) }, .updates)
        XCTAssertEqual(AppRoute(path: "darulirfan://events/seminar-1").flatMap { DiscoverSection(route: $0) }, .events)
        XCTAssertEqual(AppRoute(path: "lectures").flatMap { DiscoverSection(route: $0) }, .bayans)
        XCTAssertEqual(AppRoute(path: "media").flatMap { DiscoverSection(route: $0) }, .bayans)
        XCTAssertEqual(AppRoute(path: "topics").flatMap { DiscoverSection(route: $0) }, .topics)
    }

    // MARK: - Theme of the day

    private func topic(_ id: String) -> Topic {
        Topic(id: id, nameEnglish: id, nameUrdu: nil, systemIcon: "sparkles", searchTerms: [id], ayahRefs: [])
    }

    /// The theme of the day is the choice Today's "Understand something
    /// today" card made: the day's place in the era, modulo the themes. The
    /// same theme all day, the next one the next day.
    func testThemeOfTheDayIsTodaysFormerUnderstandChoice() throws {
        let topics = ["tawhid", "zikr", "sabr", "shukr", "tawakkul"].map { topic($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TestDates.karachi
        let morning = TestDates.make(year: 2026, month: 10, day: 30, hour: 6, timeZone: TestDates.karachi)
        let evening = TestDates.make(year: 2026, month: 10, day: 30, hour: 23, minute: 30, timeZone: TestDates.karachi)
        let nextDay = TestDates.make(year: 2026, month: 10, day: 31, hour: 6, timeZone: TestDates.karachi)

        // TodayUnderstandCard: topics[ordinality(of: .day, in: .era) % count].
        let day = try XCTUnwrap(calendar.ordinality(of: .day, in: .era, for: morning))
        let expected = topics[day % topics.count]
        XCTAssertEqual(ThemeOfTheDay.topic(from: topics, on: morning, calendar: calendar), expected)
        XCTAssertEqual(ThemeOfTheDay.topic(from: topics, on: evening, calendar: calendar), expected)

        let index = try XCTUnwrap(topics.firstIndex(of: expected))
        XCTAssertEqual(ThemeOfTheDay.topic(from: topics, on: nextDay, calendar: calendar), topics[(index + 1) % topics.count])
        XCTAssertNil(ThemeOfTheDay.topic(from: [], on: morning, calendar: calendar))
    }

    /// Over as many days as there are themes, each comes once.
    func testEveryThemeComesRoundInTurn() {
        let topics = (1...20).map { topic("theme-\($0)") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TestDates.utc
        let start = TestDates.make(year: 2026, month: 1, day: 1, timeZone: TestDates.utc)
        let days = (0..<20).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let themes = days.compactMap { ThemeOfTheDay.topic(from: topics, on: $0, calendar: calendar)?.id }
        XCTAssertEqual(themes.count, 20)
        XCTAssertEqual(Set(themes).count, 20)
    }

    // MARK: - Updates

    private func feedItem(
        _ id: String,
        _ source: OfficialFeedSource,
        _ title: String = "Update",
        video: String? = nil,
        at date: Date
    ) -> OfficialFeedItem {
        OfficialFeedItem(
            id: id,
            source: source,
            kind: source == .youtube ? .video : .post,
            title: title,
            body: nil,
            sourceURL: URL(fileURLWithPath: "/"),
            imageURL: nil,
            videoID: video,
            publishedAt: date,
            isFeatured: false
        )
    }

    private func libraryItem(_ id: String, _ type: ContentType, _ category: ContentCategory, published: Date?) -> ContentItem {
        ContentItem(
            id: id, sourceUrl: "", type: type, title: id, titleUrdu: nil, language: "ur",
            author: nil, category: category, bodyHtml: nil, bodyPlainText: nil, excerpt: nil,
            publishedAt: published, updatedAt: nil, mediaUrls: [], downloadUrls: [], checksum: nil,
            rightsStatus: .permissionConfirmed
        )
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        TestDates.make(year: year, month: month, day: day, hour: 0, timeZone: TestDates.utc)
    }

    /// The Library's announcements and press releases join the feed's own
    /// announcements under "Announcements and press", newest first and each
    /// once; other library items and other updates stay out.
    func testLibraryNewsJoinsUpdatesNewestFirst() {
        let feed = [
            feedItem("video", .youtube, video: "abcdefghijk", at: day(2026, 10, 2)),
            feedItem("feed-notice", .announcement, at: day(2026, 10, 1)),
            feedItem("post", .facebook, at: day(2026, 9, 5)),
            feedItem("event", .event, at: day(2026, 9, 6)),
        ]
        let library = [
            libraryItem("announcement-2023", .announcement, .announcements, published: day(2023, 1, 1)),
            libraryItem("press-2024", .pressRelease, .pressReleases, published: day(2024, 5, 1)),
            libraryItem("book", .book, .books, published: day(2025, 1, 1)),
            libraryItem("announcement-undated", .announcement, .announcements, published: nil),
        ]
        let notes = [
            Announcement(id: "announcement-welcome", title: "Welcome", body: "Hello", publishedAt: day(2026, 7, 9), sourceUrl: nil),
            // A note that is also a library item is listed once, as the item.
            Announcement(id: "announcement-2023", title: "Twice", body: nil, publishedAt: day(2023, 1, 1), sourceUrl: nil),
        ]
        let merged = UpdatesNews.merged(feed: feed, library: library, notes: notes)
        XCTAssertEqual(merged.map(\.id), [
            "feed|feed-notice",
            "note|announcement-welcome",
            "library|press-2024",
            "library|announcement-2023",
            "library|announcement-undated",
        ])
        XCTAssertTrue(UpdatesNews.merged(feed: [], library: [], notes: []).isEmpty)
    }

    /// The filters: All, Videos, Posts, Articles, and Announcements and
    /// press. Events have their own section and no filter.
    func testUpdatesFilters() {
        let now = Date()
        let items = [
            feedItem("video", .youtube, video: "abcdefghijk", at: now),
            feedItem("post", .facebook, at: now),
            feedItem("article", .website, at: now),
            feedItem("notice", .announcement, at: now),
            feedItem("event", .event, at: now),
        ]
        XCTAssertEqual(UpdatesFilter.allCases.map(\.rawValue), ["All", "Videos", "Posts", "Articles", "Announcements and press"])
        XCTAssertEqual(items.filter { UpdatesFilter.all.includes($0) }.count, 5)
        XCTAssertEqual(items.filter { UpdatesFilter.videos.includes($0) }.map(\.id), ["video"])
        XCTAssertEqual(items.filter { UpdatesFilter.posts.includes($0) }.map(\.id), ["post"])
        XCTAssertEqual(items.filter { UpdatesFilter.articles.includes($0) }.map(\.id), ["article"])
        XCTAssertEqual(items.filter { UpdatesFilter.announcements.includes($0) }.map(\.id), ["notice"])
    }

    // MARK: - Bayans

    /// Recent on YouTube lists the channel's videos that are not the daily
    /// zikr recordings, by the Zikr tab's own rule.
    @MainActor
    func testRecentOnYouTubeLeavesOutTheDailyZikrRecordings() {
        let now = Date()
        let items = [
            feedItem("zikr", .youtube, "Online Zikr with Sheikh-ul-Mukarram", video: "zzzzzzzzzzz", at: now),
            feedItem("bayan", .youtube, "Deen ki Tableegh | Surah Al Imran Ayat 186-188", video: "bbbbbbbbbbb", at: now),
            feedItem("post", .facebook, "Mahana Ijtima", at: now),
        ]
        XCTAssertTrue(ZikrHomeViewModel.isZikrRecording(items[0]))
        XCTAssertEqual(BayansFeedModel.bayanVideos(in: items).map(\.id), ["bayan"])
    }

    /// The feed is read a few pages at a time until enough bayans are
    /// found, and further for the full list.
    @MainActor
    func testBayansAreReadOnUntilEnoughAreFound() async {
        let now = Date()
        let zikr = { (n: Int) in self.feedItem("zikr-\(n)", .youtube, "Online Zikr \(n)", video: "z\(n)", at: now) }
        let bayan = { (n: Int) in self.feedItem("bayan-\(n)", .youtube, "Bayan \(n)", video: "b\(n)", at: now) }
        let feed = StubFeed(pages: [
            "": OfficialFeedPage(items: [zikr(1), bayan(1), zikr(2)], nextCursor: "p2"),
            "p2": OfficialFeedPage(items: [zikr(3), bayan(2)], nextCursor: "p3"),
            "p3": OfficialFeedPage(items: [bayan(3)], nextCursor: "p4"),
            "p4": OfficialFeedPage(items: [bayan(4), zikr(4)], nextCursor: nil),
        ])
        let model = BayansFeedModel(feed: feed)
        await model.load()
        XCTAssertEqual(model.videos.map(\.id), ["bayan-1", "bayan-2", "bayan-3"])
        XCTAssertEqual(model.nextCursor, "p4")
        XCTAssertTrue(model.hasLoaded)

        await model.loadMore()
        XCTAssertEqual(model.videos.map(\.id), ["bayan-1", "bayan-2", "bayan-3", "bayan-4"])
        XCTAssertNil(model.nextCursor)
    }

    /// While the server has paused the official feed, no bayans are listed.
    @MainActor
    func testNoBayansWhileTheFeedIsPaused() async {
        let now = Date()
        var feed = StubFeed(pages: [
            "": OfficialFeedPage(items: [feedItem("bayan", .youtube, "Bayan", video: "bbbbbbbbbbb", at: now)], nextCursor: nil),
        ])
        feed.flags = RemoteFeatureFlags(officialFeed: false)
        let model = BayansFeedModel(feed: feed)
        await model.load()
        XCTAssertFalse(model.isFeedEnabled)
        XCTAssertTrue(model.videos.isEmpty)
    }

    /// A bayan's card shows the name, and under it what follows the
    /// channel's " | ". Nothing is reworded.
    func testBayanTitleSplitsAtTheChannelsBar() {
        let split = BayanVideoTitle.split("Deen ki Tableegh | Surah Al Imran Ayat 186-188")
        XCTAssertEqual(split.headline, "Deen ki Tableegh")
        XCTAssertEqual(split.detail, "Surah Al Imran Ayat 186-188")
        let whole = BayanVideoTitle.split("Aqalmand Loag")
        XCTAssertEqual(whole.headline, "Aqalmand Loag")
        XCTAssertNil(whole.detail)
    }
}

/// A feed of fixed pages, keyed by cursor ("" for the first).
private struct StubFeed: OfficialFeedServicing {
    var pages: [String: OfficialFeedPage]
    var flags = RemoteFeatureFlags(officialFeed: true)

    func bootstrap(forceRefresh: Bool) async -> AppBootstrap {
        var value = AppBootstrap.offline
        value.generatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        value.featureFlags = flags
        return value
    }

    func feed(after cursor: String?, forceRefresh: Bool) async throws -> OfficialFeedPage {
        guard let page = pages[cursor ?? ""] else { throw OfficialPlatformError.invalidResponse }
        return page
    }
}
