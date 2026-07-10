import Foundation
import XCTest
@testable import DarulIrfan

/// Tests for `SettingsStore`: full round-trip persistence and the
/// corruption-tolerant load contract (any unreadable blob → `.default`).
final class SettingsStoreTests: XCTestCase {

    private var database: AppDatabase!
    private var store: SettingsStore!

    override func setUp() async throws {
        database = try await AppDatabase.inMemory()
        store = SettingsStore(database: database)
    }

    override func tearDown() {
        store = nil
        database = nil
    }

    func testLoadWithoutSavedSettingsReturnsDefault() async {
        let settings = await store.load()
        XCTAssertEqual(settings, AppSettings.default)
    }

    func testSaveThenLoadRoundtripsEveryField() async {
        var settings = AppSettings()
        settings.language = .urdu
        settings.theme = .dark
        settings.readerFontScale = .large
        settings.locationMode = .manual
        settings.manualPlace = TestPlaces.karachi
        settings.lastKnownPlace = TestPlaces.karachi
        settings.calculation.method = .muslimWorldLeague
        settings.calculation.asrMethod = .shafi
        settings.calculation.highLatitudeRule = .twilightAngle
        settings.calculation.adjustments.fajr = 10
        settings.calculation.adjustments.isha = -5
        settings.calculation.customAngles.fajrAngle = 15.0
        settings.prayerNotifications.styles[.fajr] = .silent
        settings.prayerNotifications.preReminders[.fajr] = .fifteenMinutes
        settings.hijri.dayOffset = -1
        settings.hasCompletedOnboarding = true
        settings.autoDownloadOnWifi = true

        await store.save(settings)
        let loaded = await store.load()
        XCTAssertEqual(loaded, settings)
    }

    func testSaveTwiceKeepsOnlyLatestSettings() async {
        var first = AppSettings()
        first.theme = .light
        await store.save(first)

        var second = AppSettings()
        second.theme = .dark
        second.hijri.dayOffset = 2
        await store.save(second)

        let loaded = await store.load()
        XCTAssertEqual(loaded, second)
        XCTAssertNotEqual(loaded.theme, first.theme)
    }

    func testCorruptStoredJSONFallsBackToDefault() async throws {
        // Simulate a corrupted (or future-format) settings blob under the
        // store's key in key_value. Loading must never throw or crash — it
        // returns the defaults so launch always succeeds.
        try await database.connection.execute(
            "INSERT INTO key_value (key, value, updated_at) VALUES (?, ?, ?)",
            [
                .text("app.settings"),
                .text("{ this is not valid JSON"),
                .date(Date()),
            ]
        )

        let loaded = await store.load()
        XCTAssertEqual(loaded, AppSettings.default)
    }

    func testValidJSONWithWrongShapeFallsBackToDefault() async throws {
        // Parseable JSON that does not decode as AppSettings (e.g. written by
        // an incompatible future version) must also fall back to defaults.
        try await database.connection.execute(
            "INSERT INTO key_value (key, value, updated_at) VALUES (?, ?, ?)",
            [
                .text("app.settings"),
                .text("{\"someFutureKey\": 42}"),
                .date(Date()),
            ]
        )

        let loaded = await store.load()
        XCTAssertEqual(loaded, AppSettings.default)
    }

    func testCorruptBlobIsRecoverableBySaving() async throws {
        try await database.connection.execute(
            "INSERT INTO key_value (key, value, updated_at) VALUES (?, ?, ?)",
            [
                .text("app.settings"),
                .text("not json at all"),
                .date(Date()),
            ]
        )

        var settings = AppSettings()
        settings.hasCompletedOnboarding = true
        await store.save(settings)

        let loaded = await store.load()
        XCTAssertEqual(loaded, settings, "A save must overwrite a corrupt blob")
    }
}
