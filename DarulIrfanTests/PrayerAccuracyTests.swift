import Foundation
import XCTest
@testable import DarulIrfan

/// Prayer times pinned against a high-precision solar ephemeris (pyephem,
/// VSOP87; geometric twilight angles, -0.833 degree sunrise/sunset, Hanafi
/// shadow). See Docs/PRAYER_TIME_ACCURACY.md for the full 16-city grid. The
/// engine agreed within half a minute wherever twilight actually occurs; the
/// tolerance here is two minutes to absorb rounding, not engine error.
final class PrayerAccuracyTests: XCTestCase {

    private let service = PrayerCalculationService()
    private let tolerance: TimeInterval = 120

    private func place(_ name: String, _ lat: Double, _ lon: Double, _ zone: String) -> PlaceCoordinate {
        PlaceCoordinate(latitude: lat, longitude: lon, name: name, timeZoneIdentifier: zone)
    }

    private func preferences(_ method: CalculationMethodChoice) -> PrayerCalculationPreferences {
        var preferences = PrayerCalculationPreferences()
        preferences.method = method
        preferences.asrMethod = .hanafi
        preferences.highLatitudeRule = .automatic
        return preferences
    }

    private func at(_ zone: String, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        TestDates.make(year: y, month: m, day: d, hour: h, minute: min, timeZone: TimeZone(identifier: zone)!)
    }

    private func times(_ place: PlaceCoordinate, _ y: Int, _ m: Int, _ d: Int, _ method: CalculationMethodChoice) throws -> PrayerDaySchedule {
        try XCTUnwrap(service.schedule(for: DateComponents(year: y, month: m, day: d), at: place, preferences: preferences(method)))
    }

    private func assertNear(_ actual: Date?, _ expected: Date, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else { return XCTFail("\(label) missing", file: file, line: line) }
        XCTAssertLessThanOrEqual(abs(actual.timeIntervalSince(expected)), tolerance,
                                 "\(label): \(actual) vs expected \(expected)", file: file, line: line)
    }

    /// Dar-ul-Irfan itself, Karachi method.
    func testDarulIrfanWinterAndSummer() throws {
        let munara = place("Munara", 32.6678, 72.5133, "Asia/Karachi")
        let jan = try times(munara, 2026, 1, 15, .karachi)
        assertNear(jan.time(for: .fajr), at("Asia/Karachi", 2026, 1, 15, 5, 45), "Fajr")
        assertNear(jan.time(for: .sunrise), at("Asia/Karachi", 2026, 1, 15, 7, 12), "Sunrise")
        assertNear(jan.time(for: .asr), at("Asia/Karachi", 2026, 1, 15, 15, 49), "Asr")
        assertNear(jan.time(for: .maghrib), at("Asia/Karachi", 2026, 1, 15, 17, 26), "Maghrib")
        assertNear(jan.time(for: .isha), at("Asia/Karachi", 2026, 1, 15, 18, 53), "Isha")
        let jun = try times(munara, 2026, 6, 21, .karachi)
        assertNear(jun.time(for: .fajr), at("Asia/Karachi", 2026, 6, 21, 3, 20), "Fajr")
        assertNear(jun.time(for: .isha), at("Asia/Karachi", 2026, 6, 21, 21, 2), "Isha")
    }

    /// The day US clocks change: times must be on the new clock.
    func testNewYorkOnDaylightSavingDay() throws {
        let newYork = place("New York", 40.7128, -74.0060, "America/New_York")
        let day = try times(newYork, 2026, 3, 8, .northAmerica)
        assertNear(day.time(for: .fajr), at("America/New_York", 2026, 3, 8, 6, 4), "Fajr")
        assertNear(day.time(for: .maghrib), at("America/New_York", 2026, 3, 8, 18, 55), "Maghrib")
        assertNear(day.time(for: .isha), at("America/New_York", 2026, 3, 8, 20, 10), "Isha")
    }

    /// Southern hemisphere summer.
    func testSydneyInJanuary() throws {
        let sydney = place("Sydney", -33.8688, 151.2093, "Australia/Sydney")
        let day = try times(sydney, 2026, 1, 15, .muslimWorldLeague)
        assertNear(day.time(for: .fajr), at("Australia/Sydney", 2026, 1, 15, 4, 19), "Fajr")
        assertNear(day.time(for: .isha), at("Australia/Sydney", 2026, 1, 15, 21, 42), "Isha")
    }

    /// Real twilight at 49 degrees north in June: the library's high-latitude
    /// limit used to put Fajr at 04:00, 84 minutes after true dawn.
    func testVancouverMidsummerUsesRealTwilight() throws {
        let vancouver = place("Vancouver", 49.2827, -123.1207, "America/Vancouver")
        let day = try times(vancouver, 2026, 6, 21, .northAmerica)
        assertNear(day.time(for: .fajr), at("America/Vancouver", 2026, 6, 21, 2, 36), "Fajr")
        assertNear(day.time(for: .isha), at("America/Vancouver", 2026, 6, 21, 23, 52), "Isha")
    }

    /// Oslo in winter and spring: twilight occurs, so astronomy, not the limit.
    func testOsloUsesRealTwilightWhenItOccurs() throws {
        let oslo = place("Oslo", 59.9139, 10.7522, "Europe/Oslo")
        let january = try times(oslo, 2026, 1, 15, .muslimWorldLeague)
        assertNear(january.time(for: .fajr), at("Europe/Oslo", 2026, 1, 15, 6, 27), "Fajr")
        let march = try times(oslo, 2026, 3, 29, .muslimWorldLeague)
        assertNear(march.time(for: .fajr), at("Europe/Oslo", 2026, 3, 29, 4, 18), "Fajr")
    }

    /// London in June never reaches 18 degrees: the recommended rule decides.
    func testLondonMidsummerFallsBackToTheRule() throws {
        let london = place("London", 51.5074, -0.1278, "Europe/London")
        let day = try times(london, 2026, 6, 21, .muslimWorldLeague)
        assertNear(day.time(for: .fajr), at("Europe/London", 2026, 6, 21, 3, 40), "Fajr (seventh of the night)")
    }

    /// Umm al-Qura: Isha is Maghrib + 90 minutes, + 120 in Ramadan.
    func testUmmAlQuraRamadanIsha() throws {
        let makkah = place("Makkah", 21.3891, 39.8579, "Asia/Riyadh")
        let ramadan = try times(makkah, 2026, 3, 8, .ummAlQura)
        let ordinary = try times(makkah, 2026, 1, 15, .ummAlQura)
        let ramadanGap = try XCTUnwrap(ramadan.time(for: .isha)).timeIntervalSince(try XCTUnwrap(ramadan.time(for: .maghrib)))
        let ordinaryGap = try XCTUnwrap(ordinary.time(for: .isha)).timeIntervalSince(try XCTUnwrap(ordinary.time(for: .maghrib)))
        XCTAssertEqual(ramadanGap, 120 * 60, accuracy: 60)
        XCTAssertEqual(ordinaryGap, 90 * 60, accuracy: 60)
    }

    func testRecommendedMethodByCountry() {
        XCTAssertEqual(CalculationMethodChoice.recommended(forCountryCode: "PK"), .karachi)
        XCTAssertEqual(CalculationMethodChoice.recommended(forCountryCode: "us"), .northAmerica)
        XCTAssertEqual(CalculationMethodChoice.recommended(forCountryCode: "CA"), .northAmerica)
        XCTAssertEqual(CalculationMethodChoice.recommended(forCountryCode: "GB"), .moonsightingCommittee)
        XCTAssertEqual(CalculationMethodChoice.recommended(forCountryCode: "SA"), .ummAlQura)
        XCTAssertEqual(CalculationMethodChoice.recommended(forCountryCode: "FR"), .muslimWorldLeague)
        XCTAssertNil(CalculationMethodChoice.recommended(forCountryCode: nil))
    }

    /// A place saved before countries were recorded still decodes.
    func testLegacyPlaceDecodes() throws {
        let json = #"{"latitude":24.86,"longitude":67.0,"name":"Karachi","timeZoneIdentifier":"Asia/Karachi"}"#
        let decoded = try JSONDecoder().decode(PlaceCoordinate.self, from: Data(json.utf8))
        XCTAssertNil(decoded.countryCode)
    }
}
