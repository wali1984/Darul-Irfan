import Foundation
import XCTest
@testable import DarulIrfan

/// Owner, 2026-11-06: "we use our stream for daily zikr and our relay for
/// tahajjud zikr". Every Join opens Our Sheikh's live stage with the app's
/// own live sound, live only while that Zikr is; and the stage closes with
/// the Shajra Sharif, then the Dua. Android SheikhLiveJoinTest.
final class SheikhLiveJoinTests: XCTestCase {

    // MARK: - Whether Our Sheikh's Zikr is live

    func testOurSheikhsPublicLiveSaysWhenTheZikrIsLive() throws {
        let json = #"{"halqahs":[{"id":"our-sheikh","name":"Our Sheikh","live":{"kind":"zikr","title":"Tahajjud Zikr","startedAt":"2026-11-06T00:01:12.345Z"},"stage":{"stageID":"latifa-2","title":"2nd Latifa","titleUr":"دوسرا لطیفہ","at":"2026-11-06T00:20:00Z"}}]}"#
        let live = try XCTUnwrap(SheikhLiveZikr.parse(Data(json.utf8)))
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-06T00:01:12Z")).timeIntervalSince1970 + 0.345
        XCTAssertEqual(try XCTUnwrap(live.startedAt).timeIntervalSince1970, expected, accuracy: 0.01)
        XCTAssertEqual(live.stage(urdu: false), "2nd Latifa")
        XCTAssertEqual(live.stage(urdu: true), "دوسرا لطیفہ")
        XCTAssertNotNil(live.stageAt)
    }

    func testNothingLiveATestZikrOrAnotherHalqahIsNotLive() {
        let offline = #"{"halqahs":[{"id":"our-sheikh","name":"Our Sheikh","live":null,"stage":null}]}"#
        let test = #"{"halqahs":[{"id":"our-sheikh","live":{"kind":"zikr","isTest":true},"stage":null}]}"#
        let meeting = #"{"halqahs":[{"id":"our-sheikh","live":{"kind":"meeting"},"stage":null}]}"#
        let other = #"{"halqahs":[{"id":"usa","live":{"kind":"zikr"},"stage":null}]}"#
        for body in [offline, test, meeting, other, "{}", "not json"] {
            XCTAssertNil(SheikhLiveZikr.parse(Data(body.utf8)), body)
        }
    }

    func testTheLiveZikrIsTahajjudBeforeSevenInPakistanAndDailyZikrAfter() {
        let dawn = TestDates.make(year: 2026, month: 11, day: 6, hour: 5, minute: 0, timeZone: TestDates.karachi)
        let seven = TestDates.make(year: 2026, month: 11, day: 6, hour: 7, minute: 0, timeZone: TestDates.karachi)
        let evening = TestDates.make(year: 2026, month: 11, day: 6, hour: 21, minute: 15, timeZone: TestDates.karachi)
        XCTAssertEqual(SheikhLiveZikr.session(at: dawn), .tahajjud)
        XCTAssertEqual(SheikhLiveZikr.session(at: seven), .daily)
        XCTAssertEqual(SheikhLiveZikr.session(at: evening), .daily)
        XCTAssertNil(SheikhLiveZikr.liveSession(nil, at: evening))
        XCTAssertEqual(SheikhLiveZikr.liveSession(SheikhLiveZikr(), at: dawn), .tahajjud)
    }

    // MARK: - Where the live-zikr notices go

    func testLiveZikrNotificationsOpenOurSheikhsStage() {
        // "Daily Zikr has started" and a host's cue.
        XCTAssertEqual(AppRoute.notification(path: "darulirfan://live/official-live"), .sheikhStage)
        // "Tahajjud Zikr has started".
        XCTAssertEqual(AppRoute.notification(path: "darulirfan://zikr/tahajjud"), .sheikhStage)
        XCTAssertEqual(AppRoute.notification(path: "darulirfan://live/our-sheikh"), .sheikhStage)
        // Everything else goes where it says.
        XCTAssertEqual(AppRoute.notification(path: "darulirfan://groups/usa"), .group(id: "usa"))
        XCTAssertEqual(AppRoute.notification(path: "darulirfan://zikr"), .zikr(session: nil))
        XCTAssertEqual(AppRoute.notification(path: "darulirfan://quran/2/255"), .quranAyah(surah: 2, ayah: 255))
        XCTAssertNil(AppRoute.notification(path: "https://paltalk.im/egnMPD3Y"))
        // An in-app link to the Tahajjud card still scrolls to it.
        XCTAssertEqual(AppRoute(path: "zikr/tahajjud"), .zikr(session: "tahajjud"))
    }

    // MARK: - The Shajra and the Dua on the stage

    func testShajraAndDuaHaveCardsOfTheirOwn() {
        XCTAssertEqual(HalqahStage.card(for: "shajra"), .shajra)
        XCTAssertEqual(HalqahStage.card(for: "dua"), .dua)
        XCTAssertEqual(HalqahStage.card(for: "masjid-nabawi"), .standard)
        XCTAssertEqual(HalqahStage.card(for: "latifa-1"), .standard)
    }

    func testAStageIsNeverShownByItsRawID() {
        XCTAssertEqual(HalqahStage.title(stageID: "shajra", title: "Shajra Sharif", titleUr: "شجرہ شریف", urdu: false), "Shajra Sharif")
        XCTAssertEqual(HalqahStage.title(stageID: "shajra", title: "Shajra Sharif", titleUr: "شجرہ شریف", urdu: true), "شجرہ شریف")
        // A cue that names the Shajra only by its id.
        XCTAssertEqual(HalqahStage.title(stageID: "shajra", title: "shajra", titleUr: nil, urdu: false), "Shajra Sharif")
        XCTAssertEqual(HalqahStage.title(stageID: "shajra", title: "", titleUr: nil, urdu: true), "شجرہ شریف")
        XCTAssertEqual(HalqahStage.secondaryTitle(stageID: "shajra", titleUr: nil, urdu: false), "شجرہ شریف")
        XCTAssertNil(HalqahStage.secondaryTitle(stageID: "shajra", titleUr: "شجرہ شریف", urdu: true))
        XCTAssertEqual(HalqahStage.title(stageID: "dua", title: "dua", titleUr: nil, urdu: false), "Dua")
        // A stage the app has never heard of reads as words, not an id.
        XCTAssertEqual(HalqahStage.title(stageID: "new-stage", title: "new-stage", titleUr: nil, urdu: false), "New Stage")
        // Every other stage keeps the server's own names.
        XCTAssertEqual(HalqahStage.title(stageID: "masjid-nabawi", title: "Masjid-e-Nabawi", titleUr: "مسجدِ نبوی", urdu: true), "مسجدِ نبوی")
        XCTAssertEqual(HalqahStage.title(stageID: "latifa-3", title: "3rd Latifa", titleUr: nil, urdu: true), "3rd Latifa")
    }

    /// The Shajra rises from its first line to its last and stops there; a
    /// stage opened late joins it where it is.
    func testTheShajraRisesFromTheFirstLineToTheLastAndStops() {
        XCTAssertEqual(ShajraStageScroll.lineCount, ShajraText.entries.count + 1)
        XCTAssertEqual(ShajraStageScroll.progress(elapsed: 0), 0)
        XCTAssertEqual(ShajraStageScroll.progress(elapsed: ShajraStageScroll.lead), 0)
        XCTAssertEqual(ShajraStageScroll.progress(elapsed: ShajraStageScroll.lead + ShajraStageScroll.duration / 2), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ShajraStageScroll.progress(elapsed: ShajraStageScroll.lead + ShajraStageScroll.duration), 1)
        XCTAssertEqual(ShajraStageScroll.progress(elapsed: 3_600), 1, "Opened after the end: the last line, still")
        XCTAssertEqual(ShajraStageScroll.progress(elapsed: -30), 0, "A phone clock behind the server's")
        XCTAssertEqual(ShajraStageScroll.remaining(elapsed: 3_600), 0)
        XCTAssertEqual(ShajraStageScroll.remaining(elapsed: 0), ShajraStageScroll.duration, accuracy: 0.0001)
        // Owner, 2026-11-06: the whole roll, pause included, in under 60 seconds (about 51).
        XCTAssertLessThan(ShajraStageScroll.lead + ShajraStageScroll.duration, 60)
        XCTAssertEqual(ShajraStageScroll.lead + ShajraStageScroll.duration, 51, accuracy: 0.0001)
        XCTAssertGreaterThan(ShajraStageScroll.duration, 30, "Still slow enough to read")
    }
}
