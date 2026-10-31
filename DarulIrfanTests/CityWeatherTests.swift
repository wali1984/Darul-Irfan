import XCTest
@testable import DarulIrfan

final class CityWeatherTests: XCTestCase {
    func testFollowsPhoneTemperaturePreferenceIncludingRegionalOverrides() {
        XCTAssertEqual(CityWeatherSnapshot.deviceUnit(locale: Locale(identifier: "en_US")), "F")
        XCTAssertEqual(CityWeatherSnapshot.deviceUnit(locale: Locale(identifier: "ur_PK")), "C")
        XCTAssertEqual(CityWeatherSnapshot.deviceUnit(locale: Locale(identifier: "en-US-u-mu-celsius")), "C")
        XCTAssertEqual(CityWeatherSnapshot.deviceUnit(locale: Locale(identifier: "ur-PK-u-mu-fahrenhe")), "F")
    }
    func testOnlyCityPrecisionLeavesTheDevice() {
        let grid = WeatherCityGrid(latitude: 31.52037, longitude: 74.35874)
        XCTAssertEqual(grid?.latitude, "31.5")
        XCTAssertEqual(grid?.longitude, "74.4")
        XCTAssertEqual(WeatherCityGrid(latitude: -0.04, longitude: 0)?.key, "0.0,0.0")
        XCTAssertNil(WeatherCityGrid(latitude: .nan, longitude: 0))
        XCTAssertNil(WeatherCityGrid(latitude: 91, longitude: 0))
        XCTAssertNil(WeatherCityGrid(latitude: 0, longitude: 181))
    }
    func testWeatherUnitConversionAndFreezingPoint() {
        XCTAssertEqual(CityWeatherSnapshot.temperature(0, unit: "F", locale: Locale(identifier: "en_US")), "32°F")
        XCTAssertEqual(CityWeatherSnapshot.temperature(-40, unit: "F", locale: Locale(identifier: "en_US")), "-40°F")
        XCTAssertEqual(CityWeatherSnapshot.temperature(23, unit: "C", locale: Locale(identifier: "en_US")), "23°C")
    }
    func testMalformedOrStaleWeatherCannotBecomeAZeroDegreeReading() throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = Data(#"{"temperatureCelsius":23,"feelsLikeCelsius":24,"humidity":0.5,"isDaylight":false,"observedAt":"2026-10-31T01:00:00Z","expiresAt":"2026-10-31T01:10:00Z"}"#.utf8)
        let value = try decoder.decode(CityWeatherSnapshot.self, from: data)
        let now = ISO8601DateFormatter().date(from: "2026-10-31T01:00:00Z")!
        XCTAssertTrue(value.usable(at: now))
        XCTAssertFalse(value.usable(at: now.addingTimeInterval(3601)))
        XCTAssertFalse(value.usable(at: now.addingTimeInterval(-301)))
        XCTAssertThrowsError(try decoder.decode(CityWeatherSnapshot.self, from: Data("{}".utf8)))
    }
}
