import Foundation
import XCTest
@testable import DarulIrfan

/// The Zikr tab of the October 2026 redesign: one Daily Zikr card for the
/// broadcast and its session (YouTube only, played in the app), the Tahajjud
/// zikr joined on Paltalk, one Reminders menu over the two existing switches,
/// this phone's time and Pakistan's, and the Tasbih tile.
final class ZikrTabTests: XCTestCase {

    func testTasbihTargetAcceptsUrduAndArabicKeyboardDigits() {
        XCTAssertEqual(TasbihCounter.parseTarget(" 100 "), 100)
        XCTAssertEqual(TasbihCounter.parseTarget("\u{0663}\u{0663}"), 33)
        XCTAssertEqual(TasbihCounter.parseTarget("\u{06F9}\u{06F9}"), 99)
        for input in ["", "0", "-5", "abc", "999999999999999999999999"] {
            XCTAssertNil(TasbihCounter.parseTarget(input))
        }
    }

    private let https = URL(string: "https://example.com/live") ?? URL(fileURLWithPath: "/")

    private func session(id: String, title: String, hour: Int, minute: Int, anchor: String? = nil) -> ZikrSession {
        ZikrSession(
            id: id,
            title: title,
            weekdays: Array(1...7),
            startHour: hour,
            startMinute: minute,
            durationMinutes: 30,
            timeZoneIdentifier: "Asia/Karachi",
            joinUrl: nil,
            instructions: nil,
            availabilityNote: nil,
            sourceUrl: nil,
            anchor: anchor,
            anchorOffsetMinutes: anchor == nil ? nil : 60
        )
    }

    private var daily: ZikrSession {
        session(id: "zikr-after-isha", title: "Daily Zikr", hour: 21, minute: 15)
    }

    private var tahajjud: ZikrSession {
        session(id: "zikr-tahajjud", title: "Tahajjud Zikr", hour: 4, minute: 0, anchor: "beforeFajr")
    }

    // MARK: - One Daily Zikr card

    /// Daily Zikr's session goes inside the Daily Zikr card; only the
    /// Tahajjud zikr keeps a card of its own. The schedule itself keeps both,
    /// for the reminders, the widgets and Today.
    func testDailyZikrSessionShowsInsideTheDailyZikrCard() {
        let sessions = [daily, tahajjud]
        XCTAssertEqual(ZikrSessionRoles.dailySession(in: sessions)?.id, "zikr-after-isha")
        XCTAssertEqual(ZikrSessionRoles.otherSessions(in: sessions).map(\.id), ["zikr-tahajjud"])
        XCTAssertEqual(sessions.count, 2, "Nothing is taken out of the schedule")
    }

    /// A schedule the administrators publish names its sessions itself: the
    /// first one not joined on Paltalk is Daily Zikr's.
    func testPublishedScheduleFindsDailyZikrByHowItIsJoined() {
        let evening = session(id: "evening", title: "Online Zikr", hour: 21, minute: 15)
        XCTAssertEqual(ZikrSessionRoles.dailySession(in: [tahajjud, evening])?.id, "evening")
        XCTAssertEqual(ZikrSessionRoles.otherSessions(in: [tahajjud, evening]).map(\.id), ["zikr-tahajjud"])
        XCTAssertNil(ZikrSessionRoles.dailySession(in: [tahajjud]))
        XCTAssertEqual(ZikrSessionRoles.otherSessions(in: [tahajjud]).map(\.id), ["zikr-tahajjud"])
    }

    /// A link to Daily Zikr's session lands on the Daily Zikr card, one to
    /// the Tahajjud zikr on its own card.
    func testSessionLinksScrollToTheirCards() {
        let sessions = [daily, tahajjud]
        XCTAssertEqual(ZikrSessionRoles.scrollTarget(forSessionNamed: "tahajjud", in: sessions, dailyTarget: "live"), "zikr-tahajjud")
        XCTAssertEqual(ZikrSessionRoles.scrollTarget(forSessionNamed: "zikr-after-isha", in: sessions, dailyTarget: "live"), "live")
        XCTAssertNil(ZikrSessionRoles.scrollTarget(forSessionNamed: "friday", in: sessions, dailyTarget: "live"))
    }

    // MARK: - Joining

    /// Daily Zikr is YouTube only, played in the app: Join waits for the
    /// broadcast to be live, and never offers the Paltalk room.
    func testDailyZikrJoinOffersOnlyWhatPlaysInTheAppWhileLive() {
        var live = LiveBroadcast.offline
        live.sources = [LiveSource(kind: .youtube, url: https, videoID: "video", supportsBackgroundAudio: false)]
        XCTAssertNil(DailyZikrPresentation.joinSource(for: live), "Greyed until live")

        live.state = .live
        XCTAssertEqual(DailyZikrPresentation.joinSource(for: live)?.videoID, "video")

        live.sources = [LiveSource(kind: .paltalk, url: https, supportsBackgroundAudio: false)]
        XCTAssertNil(DailyZikrPresentation.joinSource(for: live), "The room is never Daily Zikr's Join")
    }

    /// The Tahajjud zikr is joined in the Paltalk room, only while it is open
    /// before dawn in Pakistan; other sessions follow the live video.
    func testTahajjudJoinsTheOpenRoomBeforeDawnInPakistan() {
        var live = LiveBroadcast.offline
        live.room = LiveRoom(platform: "paltalk", listeners: 12, since: nil, url: URL(string: "https://paltalk.im/room"))
        let beforeDawn = TestDates.make(year: 2026, month: 10, day: 30, hour: 4, minute: 10, timeZone: TestDates.karachi)
        let evening = TestDates.make(year: 2026, month: 10, day: 30, hour: 21, minute: 20, timeZone: TestDates.karachi)

        XCTAssertTrue(ZikrSessionJoin.joinsOnPaltalk(tahajjud))
        XCTAssertFalse(ZikrSessionJoin.joinsOnPaltalk(daily))
        XCTAssertEqual(ZikrSessionJoin.openRoom(for: tahajjud, live: live, at: beforeDawn)?.listeners, 12)
        XCTAssertNil(ZikrSessionJoin.openRoom(for: tahajjud, live: live, at: evening), "The evening room carries Daily Zikr")
        XCTAssertNil(ZikrSessionJoin.openRoom(for: daily, live: live, at: beforeDawn))

        live.state = .live
        live.sources = [LiveSource(kind: .youtube, url: https, videoID: "video", supportsBackgroundAudio: false)]
        XCTAssertEqual(ZikrSessionJoin.liveVideoID(for: daily, live: live), "video")
        XCTAssertNil(ZikrSessionJoin.liveVideoID(for: tahajjud, live: live))
    }

    func testTahajjudSubtitleSaysWhereItIsJoined() {
        XCTAssertEqual(
            ZikrSessionJoin.subtitle(for: tahajjud),
            [String(localized: "Before Fajr at Dar-ul-Irfan"), String(localized: "on Paltalk")].joined(separator: " · ")
        )
    }

    // MARK: - Headline and notes

    /// The server's name for the broadcast is split as the card shows it:
    /// the zikr, then its host and length. A name an administrator gives a
    /// special broadcast is shown as sent.
    func testOfficialBroadcastShowsItsHostUnderTheTitle() {
        var live = LiveBroadcast.offline
        live.title = DailyZikrPresentation.officialTitle
        let headline = DailyZikrPresentation.headline(for: live)
        XCTAssertEqual(headline.title, String(localized: "Online Zikr with Sheikh-ul-Mukarram"))
        XCTAssertEqual(headline.host, String(localized: "Hazrat Ameer Abdul Qadeer Awan MZA"))
        XCTAssertEqual(DailyZikrPresentation.headline(for: .offline), headline, "The same before the server answers")

        live.title = "Salana Ijtema Zikr"
        let special = DailyZikrPresentation.headline(for: live)
        XCTAssertEqual(special.title, "Salana Ijtema Zikr")
        XCTAssertNil(special.host)

        live.title = "100% Zikr"
        XCTAssertEqual(DailyZikrPresentation.headline(for: live).title, "100% Zikr")

        XCTAssertEqual(
            DailyZikrPresentation.subtitle(host: headline.host, durationMinutes: 30),
            [String(localized: "Hazrat Ameer Abdul Qadeer Awan MZA"), String(localized: "About \(30) minutes")].joined(separator: " · ")
        )
        XCTAssertNil(DailyZikrPresentation.subtitle(host: nil, durationMinutes: 0))
    }

    /// The server's standing sentence is said under Join already; an
    /// administrator's own note is shown.
    func testOnlyAnAdministratorsNoteIsShown() {
        var live = LiveBroadcast.offline
        live.details = DailyZikrPresentation.standingDetails
        XCTAssertNil(DailyZikrPresentation.note(for: live))
        live.details = "  "
        XCTAssertNil(DailyZikrPresentation.note(for: live))
        live.details = "Tonight's zikr is from the Salana Ijtema."
        XCTAssertEqual(DailyZikrPresentation.note(for: live), "Tonight's zikr is from the Salana Ijtema.")
    }

    func testStatusBadgeKeepsItsFourStates() {
        XCTAssertEqual(DailyZikrPresentation.statusKey(for: .offline), "OFF AIR")
        XCTAssertEqual(DailyZikrPresentation.statusKey(for: .scheduled), "SCHEDULED")
        XCTAssertEqual(DailyZikrPresentation.statusKey(for: .live), "LIVE")
        XCTAssertEqual(DailyZikrPresentation.statusKey(for: .ended), "ENDED")
    }

    func testOnAirDetailSaysThatItPlaysInTheApp() {
        let now = Date()
        let plays = String(localized: "Plays here in the app")
        XCTAssertEqual(DailyZikrPresentation.onAirDetail(startedAt: nil, now: now), plays)
        let began = DailyZikrPresentation.onAirDetail(startedAt: now.addingTimeInterval(-720), now: now)
        XCTAssertTrue(began.hasSuffix(" · " + plays))
        XCTAssertNotEqual(began, plays)
    }

    // MARK: - Countdown and times

    func testRingFillsThroughTheDayThenThroughTheSession() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let window = ZikrCountdown.Window(start: start, end: start.addingTimeInterval(1_800))
        XCTAssertEqual(ZikrCountdown.ringProgress(window, at: start.addingTimeInterval(-90_000)), 0)
        XCTAssertEqual(ZikrCountdown.ringProgress(window, at: start.addingTimeInterval(-21_600)), 0.75, accuracy: 0.0001)
        XCTAssertEqual(ZikrCountdown.ringProgress(window, at: start), 0)
        XCTAssertEqual(ZikrCountdown.ringProgress(window, at: start.addingTimeInterval(900)), 0.5, accuracy: 0.0001)
        XCTAssertTrue(window.isActive(at: start.addingTimeInterval(900)))
        XCTAssertFalse(window.isActive(at: start.addingTimeInterval(1_800)))
    }

    /// The countdown follows the session under way, else the next one.
    func testCountdownWindowKeepsTheSessionUnderWay() throws {
        let during = TestDates.make(year: 2026, month: 1, day: 15, hour: 21, minute: 30, timeZone: TestDates.karachi)
        let window = try XCTUnwrap(ZikrCountdown.window(for: daily, at: during))
        XCTAssertEqual(window.start, TestDates.make(year: 2026, month: 1, day: 15, hour: 21, minute: 15, timeZone: TestDates.karachi))
        XCTAssertEqual(window.end.timeIntervalSince(window.start), 1_800, accuracy: 0.5)
        XCTAssertTrue(window.isActive(at: during))
    }

    /// A phone in New York sees its own time, then Pakistan's; a phone in
    /// Pakistan only its own. The Tahajjud zikr's Pakistan time is "about".
    func testTimeLineGivesThisPhonesTimeThenPakistans() {
        let start = TestDates.make(year: 2026, month: 1, day: 15, hour: 21, minute: 15, timeZone: TestDates.karachi)
        let locale = Locale(identifier: "en_US")
        let pakistanTime = start.formatted(Date.FormatStyle(locale: locale, timeZone: TestDates.karachi).hour().minute())
        let newYorkTime = ZikrScheduleMath.localTimeText(start, timeZone: TestDates.newYork, locale: locale)
        let karachiTime = ZikrScheduleMath.localTimeText(start, timeZone: TestDates.karachi, locale: locale)

        XCTAssertEqual(
            ZikrTimeLine.text(for: start, session: daily, timeZone: TestDates.newYork, locale: locale),
            [String(localized: "Your time: \(newYorkTime)"), String(localized: "In Pakistan: \(pakistanTime)")].joined(separator: " · ")
        )
        XCTAssertEqual(
            ZikrTimeLine.text(for: start, session: daily, timeZone: TestDates.karachi, locale: locale),
            String(localized: "Your time: \(karachiTime)")
        )
        XCTAssertTrue(
            ZikrTimeLine.text(for: start, session: tahajjud, timeZone: TestDates.newYork, locale: locale)
                .hasSuffix(String(localized: "In Pakistan: about \(pakistanTime)"))
        )
    }

    // MARK: - One Reminders menu

    /// The menu's line says which of the two existing switches is on.
    func testRemindersSummaryNamesWhatIsOn() {
        let before = String(localized: "\(ZikrReminders.leadMinutes) minutes before")
        let whenLive = String(localized: "When live")
        XCTAssertEqual(ZikrReminderSummary.text(beforeEachSession: true, whenLive: true), before + " · " + whenLive)
        XCTAssertEqual(ZikrReminderSummary.text(beforeEachSession: true, whenLive: false), before)
        XCTAssertEqual(ZikrReminderSummary.text(beforeEachSession: false, whenLive: true), whenLive)
        XCTAssertEqual(ZikrReminderSummary.text(beforeEachSession: nil, whenLive: false), String(localized: "Off"))
    }

    // MARK: - Tasbih tile

    func testTasbihTileShowsTheCounterUsedLast() throws {
        let older = TasbihCounter(id: UUID(), title: "SubhanAllah", target: 33, count: 20, lifetimeCount: 0,
                                  updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = TasbihCounter(id: UUID(), title: "Astaghfirullah", target: 100, count: 25, lifetimeCount: 0,
                                  updatedAt: Date(timeIntervalSince1970: 1_700_000_100))
        let openEnded = TasbihCounter(id: UUID(), title: "Allah", target: nil, count: 7, lifetimeCount: 0,
                                      updatedAt: Date(timeIntervalSince1970: 1_600_000_000))

        let summary = try XCTUnwrap(ZikrPracticeSummary.latest(from: [older, newer, openEnded]))
        XCTAssertEqual(summary.count, 25)
        XCTAssertEqual(summary.progress ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertNil(ZikrPracticeSummary.latest(from: [openEnded])?.progress)
        XCTAssertNil(ZikrPracticeSummary.latest(from: []))
    }
}
