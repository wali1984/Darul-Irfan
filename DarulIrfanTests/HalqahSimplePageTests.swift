import Foundation
import XCTest
@testable import DarulIrfan

/// The simple Halqah page (owner 2026-11-19: "remove everything including
/// stage, all buttons except for People, Add a zikr time"): only a Halqah the
/// server marks `simplePage` has it; every other Halqah keeps the full page.
final class HalqahSimplePageTests: XCTestCase {
    private let decoder = JSONDecoder.darulIrfanServer()

    private func detail(group: String) throws -> GroupDetail {
        let json = #"{"group":"# + group + #","canManage":true,"zikrSessions":[],"meetings":[]}"#
        return try decoder.decode(GroupDetail.self, from: Data(json.utf8))
    }

    func testSimplePageDecodes() throws {
        let simple = try detail(group: #"{"id":"na-evening","name":"North America - Evening Zikr","videoClips":true,"simplePage":true}"#)
        XCTAssertEqual(simple.group.simplePage, true)
        XCTAssertTrue(simple.hasSimplePage)
        XCTAssertTrue(HalqahPageLayout(simple).isSimple)

        let ordinary = try detail(group: #"{"id":"usa","name":"USA"}"#)
        XCTAssertNil(ordinary.group.simplePage, "absent for every other Halqah")
        XCTAssertFalse(ordinary.hasSimplePage)
        XCTAssertFalse(HalqahPageLayout(ordinary).isSimple)

        let titled = try detail(group: #"{"id":"na-evening","name":"NA","simplePage":true,"startTitle":"Start Daily North America Nightly Zikr"}"#)
        XCTAssertEqual(titled.group.startTitle, "Start Daily North America Nightly Zikr")
        XCTAssertNil(ordinary.group.startTitle)

        let off = try detail(group: #"{"id":"uk","name":"UK","simplePage":false}"#)
        XCTAssertFalse(off.hasSimplePage)
        XCTAssertFalse(HalqahPageLayout(nil).isSimple, "the full page until the Halqah has loaded")
    }

    func testSimplePageShowsOnlyThePlayerZikrTimesAndTwoTiles() {
        let simple = HalqahPageLayout(simplePage: true)
        XCTAssertFalse(simple.showsStage, "no stage: not by itself, not from a button, a Join or a notification")
        XCTAssertFalse(simple.showsSessionCard, "only the session's player")
        XCTAssertFalse(simple.showsMethodOfZikr)
        XCTAssertFalse(simple.showsSheikhLive)
        XCTAssertFalse(simple.showsNextZikr)
        XCTAssertFalse(simple.showsMeetings)
        XCTAssertFalse(simple.showsPosts)
        XCTAssertFalse(simple.showsRoomResume)
        XCTAssertFalse(simple.showsGoLive)
        XCTAssertFalse(simple.showsAdminExtras)
        XCTAssertTrue(simple.showsAdminTile("people"))
        XCTAssertTrue(simple.showsAdminTile("zikr"))
        for tile in ["post", "meeting", "duas", "history"] {
            XCTAssertFalse(simple.showsAdminTile(tile), tile)
        }
        // Addendum 2: the one start tile; addendum 3: admins end by hand.
        XCTAssertTrue(simple.showsStartTile(isLive: false))
        XCTAssertFalse(simple.showsStartTile(isLive: true), "while a session is live, End session is the admins' control")
        XCTAssertTrue(simple.showsPageEndSession(canManage: true))
        XCTAssertFalse(simple.showsPageEndSession(canManage: false), "members never see End session")
    }

    func testSimpleStartSheet() {
        let form = HalqahStartForm(simple: true, startTitle: "Start Daily North America Nightly Zikr")
        XCTAssertEqual(form.heading, "Start Daily North America Nightly Zikr")
        XCTAssertEqual(form.sessionTitle, "Daily North America Nightly Zikr", "the leading Start is dropped")
        XCTAssertFalse(form.showsKindChoice, "always a Halqah Zikr")
        XCTAssertFalse(form.offersLeadLive, "YouTube and Recording only: no room, record or live link")
        XCTAssertFalse(form.showsTitleField, "the start title names the session")

        XCTAssertEqual(HalqahStartForm(simple: true, startTitle: "Evening Zikr").sessionTitle, "Evening Zikr")
        XCTAssertEqual(HalqahStartForm(simple: true, startTitle: "  Start Evening Zikr ").sessionTitle, "Evening Zikr")

        // No start title: Go live's heading and the title field, as today.
        let untitled = HalqahStartForm(simple: true, startTitle: nil)
        XCTAssertNil(untitled.heading)
        XCTAssertNil(untitled.sessionTitle)
        XCTAssertTrue(untitled.showsTitleField)
        XCTAssertFalse(untitled.offersLeadLive)
        XCTAssertNil(HalqahStartForm(simple: true, startTitle: "   ").heading)
    }

    func testEveryOtherHalqahKeepsTheFullStartSheet() {
        let full = HalqahStartForm()
        XCTAssertFalse(full.isSimple)
        XCTAssertNil(full.heading)
        XCTAssertNil(full.sessionTitle)
        XCTAssertTrue(full.showsKindChoice)
        XCTAssertTrue(full.offersLeadLive)
        XCTAssertTrue(full.showsTitleField)
        XCTAssertNil(HalqahStartForm(simple: false, startTitle: "Start Something").heading, "only a simple page uses it")
    }

    func testWithoutRoomsTheStartSheetOffersNoMeetingAndNoLeadLive() {
        let form = HalqahStartForm(meetingsReady: false)
        XCTAssertFalse(form.isSimple, "still the full page's sheet")
        XCTAssertFalse(form.showsKindChoice, "no Meeting to choose")
        XCTAssertFalse(form.offersLeadLive, "YouTube and Recording only")
        XCTAssertTrue(form.showsTitleField)
        XCTAssertNil(form.heading)
    }

    func testEveryOtherHalqahKeepsTheFullPage() {
        let full = HalqahPageLayout(simplePage: false)
        XCTAssertTrue(full.showsStage)
        XCTAssertTrue(full.showsSessionCard)
        XCTAssertTrue(full.showsMethodOfZikr)
        XCTAssertTrue(full.showsSheikhLive)
        XCTAssertTrue(full.showsNextZikr)
        XCTAssertTrue(full.showsMeetings)
        XCTAssertTrue(full.showsPosts)
        XCTAssertTrue(full.showsRoomResume)
        XCTAssertTrue(full.showsGoLive)
        XCTAssertTrue(full.showsAdminExtras)
        for tile in ["people", "post", "meeting", "zikr", "duas", "history"] {
            XCTAssertTrue(full.showsAdminTile(tile), tile)
        }
        XCTAssertFalse(full.showsStartTile(isLive: false), "Go live stays")
        XCTAssertFalse(full.showsStartTile(isLive: true))
        XCTAssertFalse(full.showsPageEndSession(canManage: true), "End session stays on the session card")
    }
}
