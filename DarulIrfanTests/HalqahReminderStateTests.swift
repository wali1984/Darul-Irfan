import XCTest
@testable import DarulIrfan

@MainActor
final class HalqahReminderStateTests: XCTestCase {
    func testSuccessfulSnapshotRetainsCurrentAndOtherGroupReminders() {
        let state = HalqahReminderState()
        let keys = ["groupZikrReminder.a.keep", "groupZikrReminder.a.gone",
                    "groupZikrReminder.ab.gone", "personal-zikr.daily.0"]
        XCTAssertEqual(state.accept(groupID: "a", sessionIDs: ["keep"], savedKeys: keys), [keys[1]])
        XCTAssertTrue(state.permits(groupID: "a", sessionID: "keep"))
        XCTAssertFalse(state.permits(groupID: "a", sessionID: "gone"))
    }

    func testEmptySuccessfulSnapshotRevokesPendingEnable() {
        let state = HalqahReminderState()
        _ = state.accept(groupID: "a", sessionIDs: ["one"], savedKeys: [])
        XCTAssertTrue(state.permits(groupID: "a", sessionID: "one"))
        XCTAssertEqual(state.accept(groupID: "a", sessionIDs: [], savedKeys: ["groupZikrReminder.a.one"]),
                       ["groupZikrReminder.a.one"])
        XCTAssertFalse(state.permits(groupID: "a", sessionID: "one"))
    }

    func testNoNewSnapshotPreservesStateAndConfirmedRemovalRevokesOnlyTarget() {
        let state = HalqahReminderState()
        XCTAssertTrue(state.permits(groupID: "unknown", sessionID: "one"))
        _ = state.accept(groupID: "a", sessionIDs: ["one", "two"], savedKeys: [])
        // A failed load does not call accept; previous permissions remain.
        XCTAssertTrue(state.permits(groupID: "a", sessionID: "one"))
        state.remove(groupID: "a", sessionID: "one")
        XCTAssertFalse(state.permits(groupID: "a", sessionID: "one"))
        XCTAssertTrue(state.permits(groupID: "a", sessionID: "two"))
    }
}
