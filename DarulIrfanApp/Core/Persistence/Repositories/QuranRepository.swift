import Foundation

/// Live SQLite-backed implementation of `QuranRepositoryProtocol`.
/// Column names follow schema v1 in `AppDatabase.migrationV1` exactly.
///
/// Enum handling on read: an unknown `revelation_place` falls back to
/// `.makkah` (so a surah row is never dropped from the index); a
/// `quran_editions` row with an unknown `kind` is skipped (the reader cannot
/// use it); an unknown `rights_status` falls back to `.linkOnly`, the most
/// restrictive option.
struct QuranRepository: QuranRepositoryProtocol {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Surahs & ayahs

    func allSurahs() async throws -> [QuranSurah] {
        let rows = try await database.connection.query(
            """
            SELECT number, name_arabic, name_transliterated, name_english,
                   name_urdu, ayah_count, revelation_place
            FROM quran_surahs
            ORDER BY number ASC
            """
        )
        return rows.compactMap { Self.surah(from: $0) }
    }

    func ayahs(inSurah surahNumber: Int) async throws -> [QuranAyah] {
        let rows = try await database.connection.query(
            """
            SELECT surah_number, ayah_number, text_arabic
            FROM quran_ayahs
            WHERE surah_number = ?
            ORDER BY ayah_number ASC
            """,
            [.int(surahNumber)]
        )
        return rows.compactMap { row in
            guard
                let surah = row.int("surah_number"),
                let ayah = row.int("ayah_number"),
                let text = row.text("text_arabic")
            else { return nil }
            return QuranAyah(surahNumber: surah, ayahNumber: ayah, textArabic: text)
        }
    }

    func surahNumbersWithText() async throws -> [Int] {
        let rows = try await database.connection.query(
            """
            SELECT DISTINCT surah_number
            FROM quran_ayahs
            ORDER BY surah_number ASC
            """
        )
        return rows.compactMap { $0.int("surah_number") }
    }

    // MARK: - Editions, translations, tafsir

    func editions() async throws -> [QuranEdition] {
        let rows = try await database.connection.query(
            """
            SELECT id, title, kind, language, author, source_url,
                   rights_status, is_available_offline
            FROM quran_editions
            ORDER BY title ASC
            """
        )
        return rows.compactMap { Self.edition(from: $0) }
    }

    func translations(editionID: String, surahNumber: Int) async throws -> [QuranTranslation] {
        let rows = try await database.connection.query(
            """
            SELECT edition_id, surah_number, ayah_number, text
            FROM quran_translations
            WHERE edition_id = ? AND surah_number = ?
            ORDER BY ayah_number ASC
            """,
            [.text(editionID), .int(surahNumber)]
        )
        return rows.compactMap { row in
            guard
                let edition = row.text("edition_id"),
                let surah = row.int("surah_number"),
                let ayah = row.int("ayah_number"),
                let text = row.text("text")
            else { return nil }
            return QuranTranslation(
                editionID: edition,
                surahNumber: surah,
                ayahNumber: ayah,
                text: text
            )
        }
    }

    func tafsir(editionID: String, surahNumber: Int) async throws -> [QuranTafsir] {
        let rows = try await database.connection.query(
            """
            SELECT edition_id, surah_number, ayah_start, ayah_end, text, source_url
            FROM quran_tafsir
            WHERE edition_id = ? AND surah_number = ?
            ORDER BY ayah_start ASC
            """,
            [.text(editionID), .int(surahNumber)]
        )
        return rows.compactMap { row in
            guard
                let edition = row.text("edition_id"),
                let surah = row.int("surah_number"),
                let ayahStart = row.int("ayah_start"),
                let ayahEnd = row.int("ayah_end"),
                let text = row.text("text")
            else { return nil }
            return QuranTafsir(
                editionID: edition,
                surahNumber: surah,
                ayahStart: ayahStart,
                ayahEnd: ayahEnd,
                text: text,
                sourceUrl: row.text("source_url")
            )
        }
    }

    // MARK: - Bookmarks

    func bookmarks() async throws -> [QuranBookmark] {
        let rows = try await database.connection.query(
            """
            SELECT id, surah_number, ayah_number, note, created_at
            FROM quran_bookmarks
            ORDER BY created_at DESC
            """
        )
        return rows.compactMap { row in
            guard
                let idText = row.text("id"),
                let id = UUID(uuidString: idText),
                let surah = row.int("surah_number"),
                let ayah = row.int("ayah_number"),
                let createdAt = row.date("created_at")
            else { return nil }
            return QuranBookmark(
                id: id,
                surahNumber: surah,
                ayahNumber: ayah,
                note: row.text("note"),
                createdAt: createdAt
            )
        }
    }

    func addBookmark(_ bookmark: QuranBookmark) async throws {
        try await database.connection.execute(
            """
            INSERT INTO quran_bookmarks (id, surah_number, ayah_number, note, created_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                surah_number = excluded.surah_number,
                ayah_number = excluded.ayah_number,
                note = excluded.note,
                created_at = excluded.created_at
            """,
            [
                .text(bookmark.id.uuidString),
                .int(bookmark.surahNumber),
                .int(bookmark.ayahNumber),
                .optionalText(bookmark.note),
                .date(bookmark.createdAt),
            ]
        )
    }

    func removeBookmark(id: UUID) async throws {
        try await database.connection.execute(
            "DELETE FROM quran_bookmarks WHERE id = ?",
            [.text(id.uuidString)]
        )
    }

    // MARK: - Reading progress

    func lastReadPosition() async throws -> ReadingProgress? {
        let rows = try await database.connection.query(
            """
            SELECT surah_number, ayah_number, updated_at
            FROM quran_reading_progress
            ORDER BY updated_at DESC
            LIMIT 1
            """
        )
        guard
            let row = rows.first,
            let surah = row.int("surah_number"),
            let ayah = row.int("ayah_number"),
            let updatedAt = row.date("updated_at")
        else { return nil }
        return ReadingProgress(surahNumber: surah, ayahNumber: ayah, updatedAt: updatedAt)
    }

    func saveLastReadPosition(_ progress: ReadingProgress) async throws {
        try await database.connection.execute(
            """
            INSERT INTO quran_reading_progress (surah_number, ayah_number, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(surah_number) DO UPDATE SET
                ayah_number = excluded.ayah_number,
                updated_at = excluded.updated_at
            """,
            [
                .int(progress.surahNumber),
                .int(progress.ayahNumber),
                .date(progress.updatedAt),
            ]
        )
    }

    // MARK: - Import (seed / content packs)

    func upsertSurahs(_ surahs: [QuranSurah]) async throws {
        guard !surahs.isEmpty else { return }
        let statements: [(sql: String, parameters: [SQLValue])] = surahs.map { surah in
            (
                sql: """
                INSERT INTO quran_surahs (number, name_arabic, name_transliterated,
                    name_english, name_urdu, ayah_count, revelation_place)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(number) DO UPDATE SET
                    name_arabic = excluded.name_arabic,
                    name_transliterated = excluded.name_transliterated,
                    name_english = excluded.name_english,
                    name_urdu = excluded.name_urdu,
                    ayah_count = excluded.ayah_count,
                    revelation_place = excluded.revelation_place
                """,
                parameters: [
                    .int(surah.id),
                    .text(surah.nameArabic),
                    .text(surah.nameTransliterated),
                    .text(surah.nameEnglish),
                    .optionalText(surah.nameUrdu),
                    .int(surah.ayahCount),
                    .text(surah.revelationPlace.rawValue),
                ]
            )
        }
        try await database.connection.executeBatch(statements)
    }

    func upsertAyahs(_ ayahs: [QuranAyah]) async throws {
        guard !ayahs.isEmpty else { return }
        let statements: [(sql: String, parameters: [SQLValue])] = ayahs.map { ayah in
            (
                sql: """
                INSERT INTO quran_ayahs (surah_number, ayah_number, text_arabic)
                VALUES (?, ?, ?)
                ON CONFLICT(surah_number, ayah_number) DO UPDATE SET
                    text_arabic = excluded.text_arabic
                """,
                parameters: [
                    .int(ayah.surahNumber),
                    .int(ayah.ayahNumber),
                    .text(ayah.textArabic),
                ]
            )
        }
        try await database.connection.executeBatch(statements)
    }

    func upsertEditions(_ editions: [QuranEdition]) async throws {
        guard !editions.isEmpty else { return }
        let statements: [(sql: String, parameters: [SQLValue])] = editions.map { edition in
            (
                sql: """
                INSERT INTO quran_editions (id, title, kind, language, author,
                    source_url, rights_status, is_available_offline)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    kind = excluded.kind,
                    language = excluded.language,
                    author = excluded.author,
                    source_url = excluded.source_url,
                    rights_status = excluded.rights_status,
                    is_available_offline = excluded.is_available_offline
                """,
                parameters: [
                    .text(edition.id),
                    .text(edition.title),
                    .text(edition.kind.rawValue),
                    .text(edition.language),
                    .optionalText(edition.author),
                    .optionalText(edition.sourceUrl),
                    .text(edition.rightsStatus.rawValue),
                    .bool(edition.isAvailableOffline),
                ]
            )
        }
        try await database.connection.executeBatch(statements)
    }

    func upsertTranslations(_ translations: [QuranTranslation]) async throws {
        guard !translations.isEmpty else { return }
        let statements: [(sql: String, parameters: [SQLValue])] = translations.map { translation in
            (
                sql: """
                INSERT INTO quran_translations (edition_id, surah_number, ayah_number, text)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(edition_id, surah_number, ayah_number) DO UPDATE SET
                    text = excluded.text
                """,
                parameters: [
                    .text(translation.editionID),
                    .int(translation.surahNumber),
                    .int(translation.ayahNumber),
                    .text(translation.text),
                ]
            )
        }
        try await database.connection.executeBatch(statements)
    }

    func upsertTafsir(_ tafsir: [QuranTafsir]) async throws {
        guard !tafsir.isEmpty else { return }
        let statements: [(sql: String, parameters: [SQLValue])] = tafsir.map { entry in
            (
                sql: """
                INSERT INTO quran_tafsir (edition_id, surah_number, ayah_start,
                    ayah_end, text, source_url)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(edition_id, surah_number, ayah_start) DO UPDATE SET
                    ayah_end = excluded.ayah_end,
                    text = excluded.text,
                    source_url = excluded.source_url
                """,
                parameters: [
                    .text(entry.editionID),
                    .int(entry.surahNumber),
                    .int(entry.ayahStart),
                    .int(entry.ayahEnd),
                    .text(entry.text),
                    .optionalText(entry.sourceUrl),
                ]
            )
        }
        try await database.connection.executeBatch(statements)
    }

    // MARK: - Row mapping

    private static func surah(from row: SQLRow) -> QuranSurah? {
        guard
            let number = row.int("number"),
            let nameArabic = row.text("name_arabic"),
            let nameTransliterated = row.text("name_transliterated"),
            let nameEnglish = row.text("name_english"),
            let ayahCount = row.int("ayah_count")
        else { return nil }
        let placeRaw = row.text("revelation_place") ?? ""
        let place = QuranSurah.RevelationPlace(rawValue: placeRaw) ?? .makkah
        return QuranSurah(
            id: number,
            nameArabic: nameArabic,
            nameTransliterated: nameTransliterated,
            nameEnglish: nameEnglish,
            nameUrdu: row.text("name_urdu"),
            ayahCount: ayahCount,
            revelationPlace: place
        )
    }

    private static func edition(from row: SQLRow) -> QuranEdition? {
        guard
            let id = row.text("id"),
            let title = row.text("title"),
            let kindRaw = row.text("kind"),
            let kind = QuranEdition.Kind(rawValue: kindRaw),
            let language = row.text("language")
        else { return nil }
        let rightsRaw = row.text("rights_status") ?? ""
        let rights = RightsStatus(rawValue: rightsRaw) ?? .linkOnly
        return QuranEdition(
            id: id,
            title: title,
            kind: kind,
            language: language,
            author: row.text("author"),
            sourceUrl: row.text("source_url"),
            rightsStatus: rights,
            isAvailableOffline: row.bool("is_available_offline")
        )
    }
}
