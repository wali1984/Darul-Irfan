import Foundation
import XCTest
@testable import DarulIrfan

final class OfficialPlatformTests: XCTestCase {
    func testDecodesBootstrapContract() throws {
        let json = """
        {
          "schemaVersion":1,
          "generatedAt":"2026-07-23T20:00:00Z",
          "minimumSupportedVersion":"1.2.1",
          "featureFlags":{"officialFeed":true,"liveHub":true,"pushRegistration":true,"diagnostics":false},
          "officialLinks":{"website":"https://www.naqshbandiaowaisiah.org/"},
          "schedules":[{"id":"evening","title":"Online Zikr","weekdays":[1,2,3,4,5,6,7],"startHour":21,"startMinute":15,"durationMinutes":30,"timeZoneIdentifier":"Asia/Karachi"}],
          "live":{"id":"official-live","state":"live","title":"Live Zikr","sources":[{"kind":"youtube","url":"https://www.youtube.com/watch?v=abc123","videoID":"abc123","supportsBackgroundAudio":false}],"updatedAt":"2026-07-23T20:00:00Z"},
          "contentVersions":{"officialFeed":1}
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(AppBootstrap.self, from: Data(json.utf8))
        XCTAssertTrue(value.featureFlags.officialFeed)
        XCTAssertEqual(value.schedules.first?.timeZoneIdentifier, "Asia/Karachi")
        XCTAssertEqual(value.live.preferredSource?.kind, .youtube)
        XCTAssertFalse(value.live.preferredSource?.supportsBackgroundAudio ?? true)
    }

    func testDecodesSharedWorkerBootstrapFixture() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "bootstrap", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(AppBootstrap.self, from: Data(contentsOf: url))
        XCTAssertEqual(value.schemaVersion, 1)
        XCTAssertEqual(value.live.preferredSource?.kind, .youtube)
        XCTAssertEqual(value.schedules.first?.timeZoneIdentifier, "Asia/Karachi")
    }

    func testOwnedStreamTakesPriorityOverYouTubeAndPaltalk() {
        let https = URL(string: "https://example.com/live.mp3") ?? URL(fileURLWithPath: "/")
        var live = LiveBroadcast.offline
        live.sources = [
            LiveSource(kind: .paltalk, url: https, supportsBackgroundAudio: false),
            LiveSource(kind: .youtube, url: https, videoID: "video", supportsBackgroundAudio: false),
            LiveSource(kind: .ownedStream, url: https, supportsBackgroundAudio: true),
        ]
        XCTAssertEqual(live.preferredSource?.kind, .ownedStream)
        XCTAssertTrue(live.preferredSource?.supportsBackgroundAudio ?? false)
    }

    func testSchemaV2CreatesOfficialPlatformTables() async throws {
        let database = try await AppDatabase.inMemory()
        let version = try await database.connection.schemaVersion()
        XCTAssertEqual(version, 2)
        let tables = try await database.connection.query(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('platform_cache','official_feed_cache','remote_zikr_schedule_cache','push_registration_state')"
        )
        XCTAssertEqual(Set(tables.compactMap { $0.text("name") }).count, 4)
    }

    func testV2MigrationPreservesExistingUserData() async throws {
        let connection = try SQLiteDatabase(url: nil)
        try await connection.executeScript(AppDatabase.migrationV1)
        try await connection.execute(
            "INSERT INTO key_value(key,value,updated_at) VALUES('settings','{\"language\":\"ur\"}',1)"
        )
        try await connection.execute(
            "INSERT INTO quran_bookmarks(id,surah_number,ayah_number,note,created_at) VALUES('bookmark',2,255,'note',1)"
        )
        try await connection.execute(
            "INSERT INTO content_reading_progress(content_item_id,fraction,updated_at) VALUES('book',0.5,1)"
        )

        try await connection.executeScript(AppDatabase.migrationV2)

        let settings = try await connection.query("SELECT key FROM key_value WHERE key='settings'")
        let bookmarks = try await connection.query("SELECT id FROM quran_bookmarks WHERE id='bookmark'")
        let progress = try await connection.query("SELECT content_item_id FROM content_reading_progress WHERE content_item_id='book'")
        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(bookmarks.count, 1)
        XCTAssertEqual(progress.count, 1)
    }

    func testOldSettingsJSONKeepsValuesAndUsesNewDefaults() throws {
        let json = """
        {"language":"ur","theme":"dark","hasCompletedOnboarding":true,"autoDownloadOnWifi":true}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.language, .urdu)
        XCTAssertEqual(settings.theme, .dark)
        XCTAssertTrue(settings.hasCompletedOnboarding)
        XCTAssertFalse(settings.push.isEnabled)
        XCTAssertEqual(settings.push.consentVersion, 0)
        XCTAssertEqual(settings.diagnosticsConsent, .notAsked)
        XCTAssertFalse(settings.liveActivitiesEnabled)
        XCTAssertEqual(settings.quranReaderDisplayMode, .arabicAndTranslation)
        XCTAssertFalse(settings.quranAutoAdvanceSurah)
    }

    func testLegacyImplicitPushValueRequiresFreshConsent() throws {
        let json = """
        {"isEnabled":true,"topics":["liveZikr","announcements"]}
        """
        let preferences = try JSONDecoder().decode(PushPreferences.self, from: Data(json.utf8))
        XCTAssertFalse(preferences.isEnabled)
        XCTAssertEqual(preferences.consentVersion, 0)
        XCTAssertEqual(preferences.topics, [.liveZikr, .announcements])
    }

    func testExplicitPushConsentRoundTrips() throws {
        let original = PushPreferences(
            isEnabled: true,
            topics: [.liveZikr, .events],
            consentVersion: PushPreferences.currentConsentVersion
        )
        let decoded = try JSONDecoder().decode(PushPreferences.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }
}
