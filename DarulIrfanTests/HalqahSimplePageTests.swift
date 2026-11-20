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
    }
}
