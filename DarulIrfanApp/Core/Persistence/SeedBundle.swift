import Foundation

// MARK: - Seed manifest

/// Version marker for the bundled seed data set, read from
/// `Resources/SeedData/manifest.json`. `ContentSyncService` compares
/// `version` against the `seed.version` row in `key_value` to decide
/// whether an import is needed.
struct SeedManifest: Codable, Sendable, Equatable {
    var version: Int
    var generatedAt: Date?
}

// MARK: - Seed bundle loaders

/// Namespace for reading the bundled seed JSON files in
/// `Resources/SeedData/` (schema v1, camelCase keys matching the Codable
/// models, ISO-8601 date strings without fractional seconds).
///
/// Every loader is tolerant of a missing or corrupt file: it logs the
/// problem via `print` and returns an empty array (or `nil`), so a
/// packaging mistake degrades gracefully instead of crashing the app.
enum SeedBundle {

    // MARK: Manifest

    static func manifest() -> SeedManifest? {
        decodeObject(SeedManifest.self, fromFile: "manifest")
    }

    // MARK: Quran

    static func quranSurahs() -> [QuranSurah] {
        decodeArray(QuranSurah.self, fromFile: "quran_surahs")
    }

    static func quranAyahs() -> [QuranAyah] {
        decodeArray(QuranAyah.self, fromFile: "quran_ayahs")
    }

    static func quranEditions() -> [QuranEdition] {
        decodeArray(QuranEdition.self, fromFile: "quran_editions")
    }

    static func quranTranslations() -> [QuranTranslation] {
        decodeArray(QuranTranslation.self, fromFile: "quran_translations")
    }

    static func quranTafsir() -> [QuranTafsir] {
        decodeArray(QuranTafsir.self, fromFile: "quran_tafsir")
    }

    // MARK: Library, media, community

    static func libraryItems() -> [ContentItem] {
        decodeArray(ContentItem.self, fromFile: "library_items")
    }

    static func mediaItems() -> [MediaItem] {
        decodeArray(MediaItem.self, fromFile: "media_items")
    }

    static func events() -> [CommunityEvent] {
        decodeArray(CommunityEvent.self, fromFile: "events")
    }

    static func announcements() -> [Announcement] {
        decodeArray(Announcement.self, fromFile: "announcements")
    }

    // MARK: Zikr & companion content (read directly from the bundle by features)

    static func zikrSessions() -> [ZikrSession] {
        decodeArray(ZikrSession.self, fromFile: "zikr_sessions")
    }

    static func namesOfAllah() -> [NameOfAllah] {
        decodeArray(NameOfAllah.self, fromFile: "names_of_allah")
    }

    static func duas() -> [Dua] {
        decodeArray(Dua.self, fromFile: "duas")
    }

    static func dailyAyat() -> [DailyAyah] {
        decodeArray(DailyAyah.self, fromFile: "daily_ayat")
    }

    static func aqwalESheikh() -> [DailyInspiration] {
        decodeArray(DailyInspiration.self, fromFile: "aqwal_e_sheikh")
    }

    static func islamicDays() -> [IslamicDay] {
        decodeArray(IslamicDay.self, fromFile: "islamic_days")
    }

    static func darulIrfanPlace() -> DarulIrfanPlace? {
        decodeObject(DarulIrfanPlace.self, fromFile: "darul_irfan_place")
    }

    // MARK: - Internals

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Locates a seed file whether the SeedData folder was copied as a
    /// folder reference (subdirectory preserved) or flattened into the
    /// bundle root by the project generator.
    private static func url(forFile fileName: String) -> URL? {
        let bundle = Bundle.main
        if let url = bundle.url(forResource: fileName, withExtension: "json", subdirectory: "SeedData") {
            return url
        }
        if let url = bundle.url(forResource: fileName, withExtension: "json", subdirectory: "Resources/SeedData") {
            return url
        }
        return bundle.url(forResource: fileName, withExtension: "json")
    }

    private static func data(forFile fileName: String) -> Data? {
        guard let url = url(forFile: fileName) else {
            print("SeedBundle: \(fileName).json is not present in the app bundle.")
            return nil
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            print("SeedBundle: could not read \(fileName).json — \(error)")
            return nil
        }
    }

    /// Decodes a JSON array of `element`; returns [] when the file is
    /// missing or does not decode.
    private static func decodeArray<Element: Decodable>(
        _ element: Element.Type,
        fromFile fileName: String
    ) -> [Element] {
        guard let data = data(forFile: fileName) else { return [] }
        do {
            return try makeDecoder().decode([Element].self, from: data)
        } catch {
            print("SeedBundle: could not decode \(fileName).json — \(error)")
            return []
        }
    }

    /// Decodes a single JSON object; returns nil when the file is missing
    /// or does not decode.
    private static func decodeObject<Value: Decodable>(
        _ value: Value.Type,
        fromFile fileName: String
    ) -> Value? {
        guard let data = data(forFile: fileName) else { return nil }
        do {
            return try makeDecoder().decode(Value.self, from: data)
        } catch {
            print("SeedBundle: could not decode \(fileName).json — \(error)")
            return nil
        }
    }
}
