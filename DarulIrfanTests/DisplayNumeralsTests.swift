import XCTest
@testable import DarulIrfan

final class DisplayNumeralsTests: XCTestCase {
    private let urdu = Locale(identifier: "ur_PK")

    func testConvertsEveryDigitWithoutChangingTimeOrderOrUnits() {
        XCTAssertEqual(DisplayNumerals.text("0123456789 · 06:45 · −18°F", locale: urdu), "۰۱۲۳۴۵۶۷۸۹ · ۰۶:۴۵ · −۱۸°F")
        XCTAssertEqual(DisplayNumerals.text("۰۱:۰۰", locale: urdu), "۰۱:۰۰")
        XCTAssertEqual(DisplayNumerals.text("2026-10-31|65°F", locale: Locale(identifier: "en_US")), "2026-10-31|65°F")
    }
    func testCountdownKeepsItsMeaningAtHourAndZeroBoundaries() {
        XCTAssertEqual(DisplayNumerals.countdown(3661, locale: urdu), "۱:۰۱:۰۱")
        XCTAssertEqual(DisplayNumerals.countdown(61, locale: urdu), "۱:۰۱")
        XCTAssertEqual(DisplayNumerals.countdown(-1, locale: urdu), "۰:۰۰")
    }
    func testNumberingOverridePreservesPhoneTemperaturePreference() {
        let locale = DisplayNumerals.locale(Locale(identifier: "ur-PK-u-mu-fahrenhe"))
        XCTAssertEqual(locale.numberingSystem.identifier, "arabext")
        XCTAssertEqual(CityWeatherSnapshot.deviceUnit(locale: locale), "F")
    }
    func testNumberAndDateFormattersUseUrduDigits() {
        let locale = DisplayNumerals.locale(urdu)
        let number = NumberFormatter(); number.locale = locale
        XCTAssertEqual(number.string(from: 1448), "۱۴۴۸")
        let date = Date(timeIntervalSince1970: 1793404800)
        let formatted = date.formatted(Date.FormatStyle(timeZone: TimeZone(secondsFromGMT: 0)!).year().locale(locale))
        XCTAssertTrue(formatted.contains("۲۰۲۶"))
    }
}
