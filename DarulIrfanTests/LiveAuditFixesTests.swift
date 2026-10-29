import Foundation
import XCTest
@testable import DarulIrfan

/// Regression tests for the live, Halqah and Events fixes of the October
/// 2026 audit (live track): server dates, notification and widget links, and
/// past programs.
final class LiveAuditFixesTests: XCTestCase {

    // MARK: - Server dates (LIVE-001)

    /// /v1/live exactly as production sent it on 2026-10-29, milliseconds
    /// and all: the stock `.iso8601` strategy of the iOS versions the app
    /// supports rejected it, so the Daily Zikr card stayed off air and both
    /// Join buttons stayed grey. (Newer systems' stock strategy accepts these
    /// bytes, so that is not asserted here; the app decodes with its own
    /// strategy on every version.)
    private let productionLive = #"{"id":"official-live","state":"live","title":"Online Zikr with Sheikh-ul-Mukarram Hazrat Ameer Abdul Qadeer Awan MZA","details":"Join the official live zikr when a broadcast is available.","startedAt":"2026-10-28T16:17:18Z","endedAt":"2026-10-28T17:15:16.645Z","sources":[{"kind":"youtube","url":"https://www.youtube.com/watch?v=TQJMn7Nw13s","videoID":"TQJMn7Nw13s","supportsBackgroundAudio":false}],"updatedAt":"2026-10-29T00:24:00.011Z","automaticBroadcast":false,"cue":{"text":"L-3","sender":"host","at":"2026-10-28T16:40:02.456Z"},"room":{"platform":"paltalk","listeners":12,"since":"2026-10-28T23:01:05.120Z","url":"https://paltalk.im/egnMPD3Y"}}"#

    func testDecodesProductionLivePayloadWithMilliseconds() throws {
        let live = try JSONDecoder.darulIrfanServer().decode(LiveBroadcast.self, from: Data(productionLive.utf8))
        XCTAssertEqual(live.state, .live)
        XCTAssertEqual(live.preferredSource?.videoID, "TQJMn7Nw13s")
        XCTAssertEqual(live.room?.listeners, 12)
        XCTAssertEqual(live.cue?.text, "L-3")
        let ended = try XCTUnwrap(live.endedAt)
        XCTAssertEqual(ended.timeIntervalSince1970.truncatingRemainder(dividingBy: 1), 0.645, accuracy: 0.0005)
    }

    /// A feed page holding a website article (milliseconds) and a video
    /// (whole seconds) decodes; such a page stopped Updates at 60 items.
    func testFeedPageWithMixedDateFormsDecodes() throws {
        let json = #"{"items":[{"id":"website:announcement-4276","source":"website","kind":"post","title":"Announcement","sourceURL":"https://www.naqshbandiaowaisiah.org/","publishedAt":"2026-09-05T00:00:00.000Z","isFeatured":false},"#
            + #"{"id":"youtube:abc","source":"youtube","kind":"video","title":"Zikr","sourceURL":"https://www.youtube.com/watch?v=abc","videoID":"abc","publishedAt":"2026-10-28T16:06:07Z","isFeatured":false}],"nextCursor":"0|2026-09-05T00:00:00.000Z|website:x"}"#
        let page = try JSONDecoder.darulIrfanServer().decode(OfficialFeedPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.nextCursor, "0|2026-09-05T00:00:00.000Z|website:x")
    }

    func testServerDateWritesWholeSeconds() throws {
        let date = try XCTUnwrap(ServerDate.date(from: "2026-10-28T17:15:16.645Z"))
        XCTAssertEqual(ServerDate.string(from: date), "2026-10-28T17:15:16Z")
        XCTAssertNotNil(ServerDate.date(from: "2026-10-28T17:15:16Z"))
        XCTAssertNil(ServerDate.date(from: "2026-10-28"))
    }

    // MARK: - Routes (LIVE-011, IOSCORE-006/007, IOSR-013, LINK-0017/18/19)

    /// Every path the server sends in a push lands on its own screen, read
    /// by exact name: a Halqah called Liverpool is a group, not the live zikr.
    func testPushPathsRouteByExactName() {
        XCTAssertEqual(AppRoute(path: "darulirfan://live/official-live"), .live)
        XCTAssertEqual(AppRoute(path: "darulirfan://zikr"), .zikr(session: nil))
        XCTAssertEqual(AppRoute(path: "darulirfan://zikr/tahajjud"), .zikr(session: "tahajjud"))
        XCTAssertEqual(AppRoute(path: "darulirfan://groups/usa"), .group(id: "usa"))
        XCTAssertEqual(AppRoute(path: "darulirfan://groups/liverpool"), .group(id: "liverpool"))
        XCTAssertEqual(AppRoute(path: "groups/halqah-zikr-lahore"), .group(id: "halqah-zikr-lahore"))
        XCTAssertEqual(AppRoute(path: "darulirfan://groups"), .groups)
    }

    func testScreenAndWidgetPathsRoute() {
        XCTAssertEqual(AppRoute(path: "quran"), .quran(surah: nil, ayah: nil))
        XCTAssertEqual(AppRoute(path: "darulirfan://quran/2/255"), .quranAyah(surah: 2, ayah: 255))
        XCTAssertEqual(AppRoute(path: "quran/115/1"), .quran(surah: nil, ayah: nil))
        XCTAssertEqual(AppRoute(path: "hadith"), .hadith)
        XCTAssertEqual(AppRoute(path: "darulirfan://today"), .today)
        XCTAssertEqual(AppRoute(path: "events/seminar-1"), .events(eventID: "seminar-1"))
        XCTAssertEqual(AppRoute(path: "feed"), .updates(itemID: nil))
        let widget = URL(string: "darulirfan://zikr")
        XCTAssertEqual(widget.flatMap(AppRoute.init(url:)), .zikr(session: nil))
    }

    func testUnknownOrForeignLinksAreIgnored() {
        XCTAssertNil(AppRoute(path: ""))
        XCTAssertNil(AppRoute(path: "darulirfan://nowhere"))
        XCTAssertNil(AppRoute(path: "https://www.naqshbandiaowaisiah.org/groups/usa"))
        XCTAssertNil(URL(string: "https://example.com/live").flatMap(AppRoute.init(url:)))
        // A group id the server could not have made is not opened as one.
        XCTAssertEqual(AppRoute(path: "groups/USA Halqah!"), .groups)
    }

    /// A request made before any screen listens (a push tapped while the app
    /// was closed) waits; the tab bar moves once, and the screen it names
    /// takes it once.
    @MainActor
    func testRouterKeepsARequestUntilItsScreenTakesIt() {
        let router = DeepLinkRouter()
        XCTAssertTrue(router.open(path: "darulirfan://groups/usa"))
        XCTAssertEqual(router.requestCount, 1)
        XCTAssertEqual(router.takeTabRequest(), .group(id: "usa"))
        XCTAssertNil(router.takeTabRequest())
        XCTAssertNil(router.take(\.eventID))
        XCTAssertEqual(router.take(\.groupID), "usa")
        XCTAssertNil(router.pending)
        XCTAssertFalse(router.open(path: "darulirfan://nowhere"))
        XCTAssertEqual(router.requestCount, 1)
    }

    @MainActor
    func testTheSameLinkHeardTwiceIsOneRequest() throws {
        let router = DeepLinkRouter()
        let url = try XCTUnwrap(URL(string: "darulirfan://zikr"))
        XCTAssertTrue(router.open(url: url))
        XCTAssertTrue(router.open(url: url))
        XCTAssertEqual(router.requestCount, 1)
        router.clear(.zikr(session: nil))
        XCTAssertNil(router.pending)
    }

    // MARK: - Events (LIVE-016)

    private func event(_ id: String, start: Date?, approximate: Bool = true) -> CommunityEvent {
        CommunityEvent(
            id: id, kind: start == nil ? .monthlyIjtema : .other, title: id, titleUrdu: nil, details: nil,
            startDate: start, endDate: nil, datesAreApproximate: approximate, venue: nil, sourceUrl: nil, updatedAt: nil
        )
    }

    func testAProgramIsOverADayAfterItsLastDay() {
        let now = Date()
        XCTAssertTrue(event("old", start: now.addingTimeInterval(-3 * 86_400)).hasEnded(at: now))
        XCTAssertFalse(event("today", start: now.addingTimeInterval(-3_600)).hasEnded(at: now))
        XCTAssertFalse(event("standing", start: nil).hasEnded(at: now))
    }

    /// Every seminar is marked approximate in the catalogue; past ones were
    /// listed as "upcoming", the oldest first. They are past now, newest first.
    @MainActor
    func testPastProgramsAreListedAsPastNewestFirst() async throws {
        let database = try await AppDatabase.inMemory()
        let repository = EventsRepository(database: database)
        let now = Date()
        try await repository.upsertEvents([
            event("seminar-2020", start: now.addingTimeInterval(-6 * 365 * 86_400)),
            event("seminar-last-month", start: now.addingTimeInterval(-40 * 86_400)),
            event("seminar-next-week", start: now.addingTimeInterval(7 * 86_400), approximate: false),
            event("monthly-ijtema", start: nil),
        ])
        let model = EventsHomeViewModel(eventsRepository: repository)
        await model.load()
        XCTAssertEqual(model.upcoming.map(\.id), ["seminar-next-week"])
        XCTAssertEqual(model.regular.map(\.id), ["monthly-ijtema"])
        XCTAssertEqual(model.past.map(\.id), ["seminar-last-month", "seminar-2020"])
    }
}
