import Foundation
import XCTest
@testable import DarulIrfan

/// What an official update opens (Discover › Updates): an article the
/// library holds on its library page, a programme on its event page, and
/// the update's own sheet only when the app holds nothing more about it.
final class UpdateDestinationTests: XCTestCase {

    // MARK: - Fixtures

    private func makeStore() async throws -> (content: ContentRepository, events: EventsRepository) {
        let database = try await AppDatabase.inMemory()
        return (ContentRepository(database: database), EventsRepository(database: database))
    }

    private func update(
        _ id: String,
        _ source: OfficialFeedSource,
        title: String = "Update",
        body: String? = nil,
        video: String? = nil,
        libraryID: String? = nil,
        eventID: String? = nil
    ) -> OfficialFeedItem {
        OfficialFeedItem(
            id: id,
            source: source,
            kind: source == .youtube ? .video : .post,
            title: title,
            body: body,
            sourceURL: URL(fileURLWithPath: "/"),
            imageURL: nil,
            videoID: video,
            libraryID: libraryID,
            eventID: eventID,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000),
            isFeatured: false
        )
    }

    private func pressRelease(_ id: String) -> ContentItem {
        ContentItem(
            id: id,
            sourceUrl: "https://example.org/\(id)",
            type: .pressRelease,
            title: id,
            titleUrdu: nil,
            language: "en",
            author: nil,
            category: .pressReleases,
            bodyHtml: nil,
            bodyPlainText: "The text of the press release.",
            excerpt: nil,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: nil,
            mediaUrls: [],
            downloadUrls: [],
            checksum: nil,
            rightsStatus: .permissionConfirmed
        )
    }

    private func programme(_ id: String) -> CommunityEvent {
        CommunityEvent(
            id: id,
            kind: .other,
            title: id,
            titleUrdu: nil,
            details: nil,
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: nil,
            datesAreApproximate: false,
            venue: nil,
            sourceUrl: nil,
            updatedAt: nil
        )
    }

    // MARK: - Articles

    /// A "website:<id>" row whose id is in the library opens that item's
    /// library page, where its text is read, not the sheet with its title.
    func testWebsiteUpdateInTheLibraryOpensItsLibraryPage() async throws {
        let (content, events) = try await makeStore()
        try await content.upsertItems([pressRelease("press-release-3985")])

        let row = update("website:press-release-3985", .website)
        XCTAssertEqual(row.libraryItemID, "press-release-3985")
        let opened = await UpdateDestination.resolve(
            row, opensLibrary: true, contentRepository: content, eventsRepository: events
        )
        XCTAssertEqual(opened, .libraryItem(id: "press-release-3985"))

        // The id the server names is the one followed.
        let named = update("website:another-id", .website, libraryID: "press-release-3985")
        XCTAssertEqual(named.libraryItemID, "press-release-3985")
        let openedByName = await UpdateDestination.resolve(
            named, opensLibrary: true, contentRepository: content, eventsRepository: events
        )
        XCTAssertEqual(openedByName, .libraryItem(id: "press-release-3985"))
    }

    /// The sheet stays for an article the library does not hold, and on a
    /// page that cannot open the library.
    func testWebsiteUpdateOutsideTheLibraryKeepsItsSheet() async throws {
        let (content, events) = try await makeStore()
        try await content.upsertItems([pressRelease("press-release-3985")])

        let unknown = update("website:press-release-9999", .website)
        let openedUnknown = await UpdateDestination.resolve(
            unknown, opensLibrary: true, contentRepository: content, eventsRepository: events
        )
        XCTAssertEqual(openedUnknown, .sheet(unknown))

        let held = update("website:press-release-3985", .website)
        let openedWithoutLibrary = await UpdateDestination.resolve(
            held, opensLibrary: false, contentRepository: content, eventsRepository: events
        )
        XCTAssertEqual(openedWithoutLibrary, .sheet(held))
    }

    /// Only a website update names a library item, and only a programme
    /// names an event.
    func testOnlyItsOwnKindOfUpdateNamesALibraryItemOrAnEvent() {
        XCTAssertNil(update("website:press-release-3985", .facebook).libraryItemID)
        XCTAssertNil(update("website:", .website).libraryItemID)
        XCTAssertNil(update("press-release-3985", .website).libraryItemID)
        XCTAssertNil(update("website:press-release-3985", .website).programmeID)
        XCTAssertNil(update("event:seminar-3420", .website).programmeID)
        XCTAssertNil(update("event:", .event).programmeID)
        XCTAssertNil(update("event:seminar-3420", .event).libraryItemID)
        XCTAssertEqual(update("event:seminar-3420", .event).programmeID, "seminar-3420")
        XCTAssertEqual(update("event:other", .event, eventID: "seminar-3420").programmeID, "seminar-3420")
    }

    // MARK: - Programmes

    /// An "event:<id>" row whose id is among the app's events opens that
    /// programme's page; one the app does not hold keeps the sheet.
    func testProgrammeUpdateOpensItsEventPage() async throws {
        let (content, events) = try await makeStore()
        try await events.upsertEvents([programme("seminar-3420"), programme("seminar-3421")])

        let row = update("event:seminar-3420", .event)
        let opened = await UpdateDestination.resolve(
            row, opensLibrary: true, contentRepository: content, eventsRepository: events
        )
        guard case .event(let event) = opened else {
            return XCTFail("The programme's page should open")
        }
        XCTAssertEqual(event.id, "seminar-3420")

        let unknown = update("event:seminar-9999", .event)
        let openedUnknown = await UpdateDestination.resolve(
            unknown, opensLibrary: true, contentRepository: content, eventsRepository: events
        )
        XCTAssertEqual(openedUnknown, .sheet(unknown))
    }

    /// When the events cannot be read, the update still opens: in its sheet.
    func testProgrammeUpdateKeepsItsSheetWhenTheEventsCannotBeRead() async throws {
        let (content, _) = try await makeStore()
        let row = update("event:seminar-3420", .event)
        let opened = await UpdateDestination.resolve(
            row, opensLibrary: true, contentRepository: content, eventsRepository: UnreadableEvents()
        )
        XCTAssertEqual(opened, .sheet(row))
    }

    // MARK: - Videos and posts

    /// A video plays; a post, and a video without its id, open in the sheet.
    func testVideosPlayAndPostsKeepTheirSheet() async throws {
        let (content, events) = try await makeStore()

        let video = update("youtube:abcdefghijk", .youtube, title: "Bayan", video: "abcdefghijk")
        let openedVideo = await UpdateDestination.resolve(
            video, opensLibrary: true, contentRepository: content, eventsRepository: events
        )
        XCTAssertEqual(openedVideo, .video(id: "abcdefghijk", title: "Bayan"))

        let bare = update("youtube:none", .youtube, title: "Bayan")
        let openedBare = await UpdateDestination.resolve(
            bare, opensLibrary: true, contentRepository: content, eventsRepository: events
        )
        XCTAssertEqual(openedBare, .sheet(bare))

        let post = update("facebook:1", .facebook, title: "Post", body: "Post")
        let openedPost = await UpdateDestination.resolve(
            post, opensLibrary: true, contentRepository: content, eventsRepository: events
        )
        XCTAssertEqual(openedPost, .sheet(post))
    }

    /// The feed names what an update opens; a row without the names (an
    /// older server, a saved copy) is still read.
    func testFeedNamesWhatAnUpdateOpens() throws {
        let json = """
        {"items":[
          {"id":"website:press-1","source":"website","kind":"post","title":"Press","sourceURL":"https://example.org/press-1","libraryID":"press-1","publishedAt":"2026-11-20T10:00:00Z","isFeatured":false},
          {"id":"event:seminar-1","source":"event","kind":"event","title":"Seminar","sourceURL":"https://example.org/seminar-1","eventID":"seminar-1","publishedAt":"2026-11-20T10:00:00Z","isFeatured":false},
          {"id":"website:press-2","source":"website","kind":"post","title":"Press","sourceURL":"https://example.org/press-2","publishedAt":"2026-11-20T10:00:00Z","isFeatured":false},
          {"id":"facebook:1","source":"facebook","kind":"post","title":"Post","body":"Post","sourceURL":"https://example.org/1","publishedAt":"2026-11-20T10:00:00Z","isFeatured":false}
        ]}
        """
        let page = try JSONDecoder.darulIrfanServer().decode(OfficialFeedPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.items.map(\.libraryID), ["press-1", nil, nil, nil])
        XCTAssertEqual(page.items.map(\.eventID), [nil, "seminar-1", nil, nil])
        XCTAssertEqual(page.items.map(\.libraryItemID), ["press-1", nil, "press-2", nil])
        XCTAssertEqual(page.items.map(\.programmeID), [nil, "seminar-1", nil, nil])
    }

    // MARK: - A post's sheet

    /// A Facebook post has no headline: its title is how its text begins,
    /// so the sheet shows the text alone and not its opening words twice.
    func testAPostsOpeningWordsAreNotShownAboveItsText() {
        let text = "The monthly gathering will be held at Dar-ul-Irfan on Sunday after Zuhr. All are welcome."

        // Cut on a whole word, with an ellipsis.
        XCTAssertTrue(update("facebook:1", .facebook, title: "The monthly gathering will be held at Dar-ul-Irfan…", body: text).titleRepeatsBody)
        // An older feed's title: the first characters, cut inside a word.
        XCTAssertTrue(update("facebook:2", .facebook, title: "The monthly gathering will be held at Dar-ul-Ir", body: text).titleRepeatsBody)
        // A short post: the title is all of it.
        XCTAssertTrue(update("facebook:3", .facebook, title: "Jumma Mubarak", body: "Jumma Mubarak").titleRepeatsBody)
        // Cut between an Urdu letter and the mark under it.
        XCTAssertTrue(update("facebook:4", .facebook, title: "\u{0630}", body: "\u{0630}\u{0650}\u{06A9}\u{0631}").titleRepeatsBody)

        // A title of its own stays above the text.
        XCTAssertFalse(update("facebook:5", .facebook, title: "Announcement", body: text).titleRepeatsBody)
        XCTAssertFalse(update("facebook:6", .facebook, title: "Post", body: nil).titleRepeatsBody)
        XCTAssertFalse(update("facebook:7", .facebook, title: "…", body: text).titleRepeatsBody)
        // An article keeps its heading whatever its text begins with.
        XCTAssertFalse(update("website:press-1", .website, title: "The monthly gathering", body: text).titleRepeatsBody)
    }
}

/// Events that cannot be read.
private struct UnreadableEvents: EventsRepositoryProtocol {
    func events() async throws -> [CommunityEvent] {
        throw NSError(domain: "UpdateDestinationTests", code: 1)
    }
    func announcements(limit: Int) async throws -> [Announcement] { [] }
    func upsertEvents(_ events: [CommunityEvent]) async throws {}
    func upsertAnnouncements(_ announcements: [Announcement]) async throws {}
}
