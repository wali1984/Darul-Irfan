import Foundation
import CryptoKit

// MARK: - Seed manifest

/// Version marker for the bundled seed data set, read from
/// `Resources/SeedData/manifest.json`. `ContentSyncService` compares
/// `version` against the `seed.version` row in `key_value` to decide
/// whether an import is needed.
struct SeedManifest: Codable, Sendable, Equatable {
    var version: Int
    var generatedAt: Date?
    /// Release the seed was cut for, e.g. "1.9.4". Reporting only.
    var contentVersion: String?
    /// The weakest review state anything in this seed carries, so one field
    /// answers "may this seed ship to this channel?". Internal metadata.
    var reviewState: ReviewState?
}

// MARK: - Seed bundle loaders

/// Namespace for reading the bundled seed JSON files in
/// `Resources/SeedData/` (schema v1, camelCase keys matching the Codable
/// models, ISO-8601 date strings without fractional seconds).
///
/// Every loader below is tolerant of a missing or corrupt file: it logs the
/// problem and returns an empty array (or `nil`), so a packaging mistake
/// degrades gracefully instead of crashing the app. The seed import uses the
/// strict loaders at the end of this type instead.
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

    // MARK: Hadith

    /// The collection index (also carries the corpus licence/provenance).
    static func hadithCatalog() -> HadithCatalog? {
        decodeObject(HadithCatalog.self, fromFile: "hadith_books")
    }

    /// One collection's entries, e.g. `hadith_bukhari`. Packs are split per
    /// book so a single oversized file never has to be parsed at once.
    static func hadithEntries(bookID: String) -> [HadithEntry] {
        decodeArray(HadithEntry.self, fromFile: "hadith_\(bookID)")
    }

    /// Bundled narrator biographies (`hadith_narrators.json`) for the reader's
    /// tap-to-open bio. Absent until the corpus is ingested with people data —
    /// returns [] and the reader shows an unavailable-yet state.
    static func hadithNarrators() -> [HadithNarrator] {
        decodeArray(HadithNarrator.self, fromFile: "hadith_narrators")
    }

    // MARK: Library, media, community

    static func libraryItems() -> [ContentItem] {
        decodeArray(ContentItem.self, fromFile: "library_items")
    }

    /// One library item straight from the bundle, for screens that must never
    /// be empty: the content database is the normal source, but if its import
    /// has not landed (or failed and is waiting to retry) the bundled copy is
    /// the same verified text.
    static func libraryItem(id: String) -> ContentItem? {
        libraryItems().first { $0.id == id }
    }

    /// OCR'd page text for the Silsila's books (`book_pages.json`), one record
    /// per printed page keyed to a `library_items.json` id. Absent until the
    /// books are ingested — returns [] and each book falls back to its PDF.
    static func bookPages() -> [BookPage] {
        decodeArray(BookPage.self, fromFile: "book_pages")
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

    static func topics() -> [Topic] {
        decodeArray(Topic.self, fromFile: "topics")
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
    /// bundle root by the project generator. Internal so the reader-only
    /// lookups (bayan links, tafsir volumes) find files the same way.
    static func url(forFile fileName: String) -> URL? {
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
            AppLog.content("Seed file is missing: \(fileName).json")
            return nil
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            AppLog.content("Could not read seed file \(fileName).json: \(error.localizedDescription)")
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
            AppLog.content("Could not decode seed file \(fileName).json: \(error.localizedDescription)")
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
            AppLog.content("Could not decode seed file \(fileName).json: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Strict loaders (seed import)

    /// Thrown by the strict loaders the seed import uses.
    enum LoadError: Error, CustomStringConvertible {
        case unreadable(file: String, reason: String)
        case undecodable(file: String, reason: String)

        var description: String {
            switch self {
            case .unreadable(let file, let reason): return "Seed file \(file).json could not be read: \(reason)"
            case .undecodable(let file, let reason): return "Seed file \(file).json does not decode: \(reason)"
            }
        }
    }

    /// Like the tolerant loaders, but a file that is present and does not
    /// decode throws instead of reading as empty. The import stamps a stage
    /// once it succeeds, so treating a damaged file as "nothing to import"
    /// would leave that content empty until the next seed change. A missing
    /// file still reads as empty: that is how a seed leaves a file out.
    static func strictArray<Element: Decodable>(
        _ element: Element.Type,
        fromFile fileName: String
    ) throws -> [Element] {
        guard let data = try strictData(forFile: fileName) else { return [] }
        do {
            return try makeDecoder().decode([Element].self, from: data)
        } catch {
            throw LoadError.undecodable(file: fileName, reason: String(describing: error))
        }
    }

    static func strictObject<Value: Decodable>(
        _ value: Value.Type,
        fromFile fileName: String
    ) throws -> Value? {
        guard let data = try strictData(forFile: fileName) else { return nil }
        do {
            return try makeDecoder().decode(Value.self, from: data)
        } catch {
            throw LoadError.undecodable(file: fileName, reason: String(describing: error))
        }
    }

    private static func strictData(forFile fileName: String) throws -> Data? {
        guard let url = url(forFile: fileName) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw LoadError.unreadable(file: fileName, reason: error.localizedDescription)
        }
    }

    // MARK: - Fingerprints (seed import)

    /// SHA-256 of a bundled seed file as lowercase hex, "missing" when the
    /// bundle has no such file, or "unreadable" when reading it failed.
    /// Read in 4 MB pieces: the largest hadith pack is 58 MB.
    static func digest(ofFile fileName: String) -> String {
        guard let url = url(forFile: fileName) else { return "missing" }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "unreadable" }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk: Data?
            do {
                chunk = try autoreleasepool { try handle.read(upToCount: 4 << 20) }
            } catch {
                return "unreadable"
            }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hexString(hasher.finalize())
    }

    /// Identifies what one import stage would write: its name, the revision
    /// of its import logic and the digest of every file it reads, in order.
    /// The input is plain text so the value can be computed outside the app
    /// too; the transition table in `ContentSyncService` was produced that
    /// way, and a test pins the format.
    static func stageFingerprint(stage: String, revision: Int, files: [(name: String, digest: String)]) -> String {
        var text = "darul-irfan-seed-stage\nstage:\(stage)\nrevision:\(revision)\n"
        for file in files {
            text += "file:\(file.name):\(file.digest)\n"
        }
        return hexString(SHA256.hash(data: Data(text.utf8)))
    }

    private static func hexString<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
