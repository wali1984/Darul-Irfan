import XCTest
@testable import DarulIrfan

final class TodayNoorLocalizationTests: XCTestCase {
    func testGreetingWaitsUntilNoonInTheSelectedCity() {
        let zone = TimeZone(identifier: "Asia/Karachi")!
        let parser = ISO8601DateFormatter()
        for (instant, expected) in [("2026-10-31T05:00:00Z", "Good morning"),
                                    ("2026-10-31T06:59:00Z", "Good morning"),
                                    ("2026-10-31T07:00:00Z", "Good afternoon")] {
            XCTAssertEqual(DIGradient.greeting(for: parser.date(from: instant)!, timeZone: zone), expected)
        }
        XCTAssertEqual(DIGradient.greeting(for: parser.date(from: "2026-10-31T07:00:00Z")!,
                                           timeZone: TimeZone(identifier: "America/New_York")!), "Peaceful night")
    }

    func testUrduInterfaceKeepsWesternDigits() {
        let locale = LanguageManager.locale(for: .urdu)
        XCTAssertEqual(locale.numberingSystem.identifier, "latn")
        let format = NumberFormatter(); format.locale = locale
        XCTAssertEqual(format.string(from: 1448), "1448")
    }

    func testEveryBundledNameAndDuaTitleHasAnUrduLabel() {
        let keys = SeedBundle.namesOfAllah().map(\.meaningEnglish) + SeedBundle.duas().map(\.title)
        XCTAssertEqual(keys.count, 139)
        for key in keys {
            let text = DailyNoorText.localized(key, urdu: true)
            XCTAssertNotEqual(text, key, key)
            XCTAssertNotNil(text.range(of: "\\p{Arabic}", options: .regularExpression), key)
        }
        for dhikr in DailyDhikr.all {
            XCTAssertNotEqual(DailyNoorText.localized(dhikr.meaning, urdu: true), dhikr.meaning)
        }
    }

    func testUrduSayingsCarryOfficialSourcesAndUrduText() {
        let quotes = SeedBundle.aqwalESheikh(urdu: true)
        XCTAssertEqual(quotes.count, 6)
        XCTAssertEqual(Set(quotes.map(\.id)).count, quotes.count)
        for quote in quotes {
            XCTAssertTrue(quote.sourceUrl?.hasPrefix("https://www.naqshbandiaowaisiah.org/aqwal-e-sheikh/") == true)
            XCTAssertNotNil(quote.text.range(of: "\\p{Arabic}", options: .regularExpression))
            XCTAssertFalse(quote.attribution.isEmpty)
        }
    }

    func testMissingUrduDoesNotSilentlyBecomeEnglish() {
        XCTAssertNil(DailyNoorText.translation(urdu: " ", english: "English", readsUrdu: true))
        XCTAssertEqual(DailyNoorText.translation(urdu: "اردو", english: "English", readsUrdu: true), "اردو")
        XCTAssertEqual(DailyNoorText.reference("Quran 2:201", urdu: true), "قرآن 2:201")
        XCTAssertEqual(DailyNoorText.reference("Sahih al-Bukhari 843", urdu: true), "صحیح بخاری 843")
    }
}
