import Foundation
import XCTest
@testable import DarulIrfan

final class NearbyMasjidResponseTests: XCTestCase {
    private let place = #"{"id":"one","name":"Masjid","address":"Road","latitude":31.52,"longitude":74.35,"attributions":[{"provider":"Source","uri":"https://example.test"}]}"#

    private func payload(_ items: String, attribution: String = "Google Maps") -> Data {
        Data("{\"items\":[\(items)],\"attribution\":\"\(attribution)\"}".utf8)
    }

    func testEmptyAndValidResultsPreserveDetailsAndAttribution() throws {
        XCTAssertTrue(try NearbyMasjidService.decodeResults(payload("")).isEmpty)
        let results = try NearbyMasjidService.decodeResults(payload(place))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Masjid")
        XCTAssertEqual(results.first?.latitude, 31.52)
        XCTAssertEqual(results.first?.attributions.first?.provider, "Source")
        XCTAssertEqual(results.first?.attributions.first?.uri, "https://example.test")
    }

    func testInvalidResultsNeverBecomeAnEmptySuccess() {
        let invalid = [
            payload(place + "," + place),
            payload(place.replacingOccurrences(of: "31.52", with: "91")),
            payload(place.replacingOccurrences(of: "74.35", with: "181")),
            payload(place.replacingOccurrences(of: "Masjid", with: "   ")),
            payload(place.replacingOccurrences(of: "one", with: "")),
            payload(place, attribution: ""),
            payload((1...21).map { place.replacingOccurrences(of: "one", with: "id-\($0)") }.joined(separator: ",")),
            Data(#"{"items":[]}"#.utf8), Data("null".utf8), Data(repeating: 32, count: 512_001)
        ]
        for data in invalid { XCTAssertThrowsError(try NearbyMasjidService.decodeResults(data)) }
    }
}
