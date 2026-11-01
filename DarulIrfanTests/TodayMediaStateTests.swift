import XCTest
@testable import DarulIrfan

@MainActor
final class TodayMediaStateTests: XCTestCase {
    private func item(_ id: String) throws -> DailyMediaItem {
        try JSONDecoder().decode(DailyMediaItem.self, from: Data("{\"id\":\"\(id)\",\"slot\":\"ayah\"}".utf8))
    }

    func testSameDayFailureRetainsPicturesAndEmptySuccessClearsThem() async throws {
        let state = TodayMediaState()
        let picture = try item("published")
        await state.load(day: "today") { _ in [picture] }
        await state.load(day: "today") { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertEqual(state.items.map(\.id), ["published"])
        XCTAssertTrue(state.failed)
        XCTAssertFalse(state.loading)
        await state.load(day: "today") { _ in [] }
        XCTAssertTrue(state.items.isEmpty)
        XCTAssertFalse(state.failed)
    }

    func testRolloverDoesNotShowYesterdaysPicturesOnFailure() async throws {
        let state = TodayMediaState()
        let picture = try item("old")
        await state.load(day: "yesterday") { _ in [picture] }
        await state.load(day: "today") { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertTrue(state.items.isEmpty)
        XCTAssertTrue(state.failed)
    }

    func testLateOlderRequestCannotOverwriteNewDay() async throws {
        let state = TodayMediaState()
        let old = try item("old")
        let new = try item("new")
        await state.load(day: "yesterday") { _ in
            await state.load(day: "today") { _ in [new] }
            return [old]
        }
        XCTAssertEqual(state.items.map(\.id), ["new"])
        XCTAssertFalse(state.failed)
        XCTAssertFalse(state.loading)
    }

    func testCancellationKeepsSnapshotWithoutFailure() async throws {
        let state = TodayMediaState()
        let picture = try item("kept")
        await state.load(day: "today") { _ in [picture] }
        await state.load(day: "today") { _ in throw CancellationError() }
        XCTAssertEqual(state.items.map(\.id), ["kept"])
        XCTAssertFalse(state.failed)
        XCTAssertFalse(state.loading)
    }
}
