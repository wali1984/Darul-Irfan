import XCTest
@testable import DarulIrfan

final class LocalTimeThemeTests: XCTestCase {
    func testSunriseSunsetAndUnavailablePolarTimes() throws {
        let place = PlaceCoordinate(latitude: 40.7128, longitude: -74.006, name: "New York", timeZoneIdentifier: "America/New_York")
        let parser = ISO8601DateFormatter()
        XCTAssertEqual(PrayerCalculationService.solarNight(at: try XCTUnwrap(parser.date(from: "2026-11-01T17:00:00Z")), place: place), false)
        XCTAssertEqual(PrayerCalculationService.solarNight(at: try XCTUnwrap(parser.date(from: "2026-11-01T06:00:00Z")), place: place), true)
        let pole = PlaceCoordinate(latitude: 89, longitude: 0, name: "Polar", timeZoneIdentifier: "UTC")
        XCTAssertNil(PrayerCalculationService.solarNight(at: try XCTUnwrap(parser.date(from: "2026-06-21T12:00:00Z")), place: pole))
    }

    func testSavedThemeChoicesRoundTrip() throws {
        for theme in AppTheme.allCases {
            XCTAssertEqual(try JSONDecoder().decode(AppTheme.self, from: JSONEncoder().encode(theme)), theme)
        }
        XCTAssertNil(AppTheme.system.colorScheme)
        XCTAssertEqual(AppTheme.light.colorScheme, .light)
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)
    }
    func testUpgradeDefaultAndPermanentOverrides() throws {
        for oldTheme in [AppTheme.system, .light, .dark] {
            var settings = AppSettings()
            settings.theme = oldTheme
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
            object.removeValue(forKey: "themeScheduleVersion")
            let upgraded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(upgraded.theme, oldTheme == .system ? .automatic : oldTheme)
        }
        var explicitSystem = AppSettings()
        explicitSystem.theme = .system
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(explicitSystem)).theme, .system)
        XCTAssertEqual(AppSettings().theme, .automatic)
    }
}
