import XCTest
@testable import DarulIrfan

final class PlaceSelectionTests: XCTestCase {
    private let saved = PlaceCoordinate(latitude: 31.55, longitude: 74.34, name: "Lahore", timeZoneIdentifier: "Asia/Karachi")

    func testTranslatedNameAndCountryMetadataRetainSelection() {
        var translated = saved
        translated.name = "\u{0644}\u{0627}\u{06c1}\u{0648}\u{0631}"
        translated.countryCode = "PK"
        XCTAssertTrue(saved.isSameLocation(as: translated))
        XCTAssertTrue(translated.isSameLocation(as: saved))
        // Ordinary equality must still detect display-name changes.
        XCTAssertNotEqual(saved, translated)
    }

    func testSerializationNoiseRetainsSelection() {
        var other = saved
        other.latitude = 31.550000000000004
        other.longitude = 74.34000000000002
        XCTAssertTrue(saved.isSameLocation(as: other))
    }

    func testDistinctCoordinatesAndTimeZonesRemainDistinct() {
        var other = saved
        other.latitude = 31.5501
        XCTAssertFalse(saved.isSameLocation(as: other))
        other = saved; other.longitude = 74.3401
        XCTAssertFalse(saved.isSameLocation(as: other))
        other = saved; other.timeZoneIdentifier = "Asia/Kolkata"
        XCTAssertFalse(saved.isSameLocation(as: other))
        other = saved; other.latitude = -31.55
        XCTAssertFalse(saved.isSameLocation(as: other))
    }
}
