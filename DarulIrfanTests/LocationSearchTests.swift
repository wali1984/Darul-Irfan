import XCTest
@testable import DarulIrfan

@MainActor
final class LocationSearchTests: XCTestCase {
    private let place = PlaceCoordinate(latitude: 31.55, longitude: 74.34, name: "Lahore", timeZoneIdentifier: "Asia/Karachi")

    func testOlderResponseCannotReplaceNewerResults() async {
        let service = ControlledLocationSearch()
        let model = LocationSettingsViewModel(location: service)
        model.query = "old"
        let old = Task { await model.search() }
        await service.waitForRequest("old")
        model.query = "new"
        let new = Task { await model.search() }
        await service.waitForRequest("new")
        await service.finish("new", with: .success([place]))
        await new.value
        await service.finish("old", with: .failure(SearchTestError.failed))
        await old.value
        XCTAssertEqual(model.results, [place])
        XCTAssertTrue(model.hasSearched)
        XCTAssertFalse(model.searchFailed)
        XCTAssertFalse(model.isSearching)
    }

    func testClearingQueryInvalidatesPendingResponse() async {
        let service = ControlledLocationSearch()
        let model = LocationSettingsViewModel(location: service)
        model.query = "old"
        let old = Task { await model.search() }
        await service.waitForRequest("old")
        model.query = ""
        await model.search()
        await service.finish("old", with: .success([place]))
        await old.value
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertFalse(model.hasSearched)
        XCTAssertFalse(model.searchFailed)
        XCTAssertFalse(model.isSearching)
    }

    func testFailureCanBeRetriedAndEditingClearsStaleResults() async {
        let service = ControlledLocationSearch()
        let model = LocationSettingsViewModel(location: service)
        model.query = "Lahore"
        let first = Task { await model.search() }
        await service.waitForRequest("Lahore")
        await service.finish("Lahore", with: .failure(SearchTestError.failed))
        await first.value
        XCTAssertTrue(model.searchFailed)
        let retry = Task { await model.search() }
        await service.waitForRequest("Lahore")
        await service.finish("Lahore", with: .success([place]))
        await retry.value
        XCTAssertEqual(model.results, [place])
        XCTAssertFalse(model.searchFailed)
        model.query = "Karachi"
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertFalse(model.hasSearched)
    }
}

private enum SearchTestError: Error { case failed }
private actor ControlledLocationSearch: LocationServicing {
    var authorizationStatus: LocationAuthorizationStatus { .denied }
    func requestPermission() async -> LocationAuthorizationStatus { .denied }
    func currentPlace() async throws -> PlaceCoordinate { throw SearchTestError.failed }
    private var requests: [String: CheckedContinuation<[PlaceCoordinate], Error>] = [:]
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    func searchPlaces(matching query: String) async throws -> [PlaceCoordinate] {
        try await withCheckedThrowingContinuation { continuation in
            requests[query] = continuation
            waiters.removeValue(forKey: query)?.resume()
        }
    }
    func waitForRequest(_ query: String) async {
        if requests[query] != nil { return }
        await withCheckedContinuation { waiters[query] = $0 }
    }
    func finish(_ query: String, with result: Result<[PlaceCoordinate], Error>) {
        requests.removeValue(forKey: query)?.resume(with: result)
    }
}
