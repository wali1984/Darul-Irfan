import Foundation

/// SQLite-backed store for the hadith collections and their entries.
struct HadithRepository: HadithRepositoryProtocol {
    let database: AppDatabase

    /// Every column the row mapper needs, in one place.
    private static let entryColumns = """
    canonical_id, book_id, display_number, number_major, number_minor,
    source_sequence, text_ar, text_en, text_ur, grades, source_book, source_hadith,
    arabic_segments_json, quran_refs_json, urdu_sanad, urdu_text,
    chapter_number, chapter_title_en, chapter_title_ar, chapter_title_ur
    """

    /// The source edition's own order. See `HadithEntry` for why neither the
    /// display number nor `number_minor` can be used to sort.
    private static let readingOrder = "ORDER BY book_id, source_sequence"

    // MARK: - Reads

    func books() async throws -> [HadithBook] {
        let rows = try await database.connection.query(
            """
            SELECT id, title_english, title_urdu, hadith_count,
                   has_arabic, has_english, has_urdu, section_count, sections_json
            FROM hadith_books
            ORDER BY hadith_count DESC
            """,
            []
        )
        return rows.compactMap { row in
            guard let id = row.text("id"),
                  let titleEnglish = row.text("title_english"),
                  let titleUrdu = row.text("title_urdu") else { return nil }
            return HadithBook(
                id: id,
                titleEnglish: titleEnglish,
                titleUrdu: titleUrdu,
                hadithCount: row.int("hadith_count") ?? 0,
                hasArabic: (row.int("has_arabic") ?? 0) == 1,
                hasEnglish: (row.int("has_english") ?? 0) == 1,
                hasUrdu: (row.int("has_urdu") ?? 0) == 1,
                sectionCount: row.int("section_count") ?? 0,
                sections: Self.decodeSections(row.text("sections_json"))
            )
        }
    }

    /// The book (kitab) list is stored as JSON on the catalogue row. A missing
    /// or unreadable value is treated as "no sourced structure" (nil) rather
    /// than an error, so a reader still lists the collection.
    private static func decodeSections(_ json: String?) -> [HadithSection]? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([HadithSection].self, from: data)
    }

    private static func encodeSections(_ sections: [HadithSection]?) -> String? {
        guard let sections, !sections.isEmpty,
              let data = try? JSONEncoder().encode(sections) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // Small JSON helpers for the enriched columns (schema v6). A missing or
    // unreadable value is treated as absent (nil), never an error, so an older
    // or un-enriched pack still reads back cleanly.
    private static func decode<T: Decodable>(_ type: [T].Type, _ json: String?) -> [T]? {
        guard let json, let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode([T].self, from: data),
              !value.isEmpty else { return nil }
        return value
    }

    private static func encode<T: Encodable>(_ value: [T]?) -> String? {
        guard let value, !value.isEmpty,
              let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Narrators

    /// One narrator's bundled biography, or nil if not present. Backs the
    /// reader's tap-to-open bio; never calls out to any site.
    func narrator(id: Int) async throws -> HadithNarrator? {
        let rows = try await database.connection.query(
            "SELECT payload_json FROM hadith_narrators WHERE id = ?",
            [.int(id)]
        )
        guard let json = rows.first?.text("payload_json"),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HadithNarrator.self, from: data)
    }

    func upsertNarrators(_ narrators: [HadithNarrator]) async throws {
        guard !narrators.isEmpty else { return }
        let encoder = JSONEncoder()
        let statements: [(sql: String, parameters: [SQLValue])] = narrators.compactMap { n in
            guard let data = try? encoder.encode(n),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return (
                sql: """
                INSERT INTO hadith_narrators (id, payload_json) VALUES (?, ?)
                ON CONFLICT(id) DO UPDATE SET payload_json = excluded.payload_json
                """,
                parameters: [.int(n.id), .text(json)]
            )
        }
        try await database.connection.executeBatch(statements)
    }

    /// A page of hadith from one collection, in the source's printed order.
    func entries(bookID: String, limit: Int, offset: Int) async throws -> [HadithEntry] {
        let rows = try await database.connection.query(
            """
            SELECT \(Self.entryColumns)
            FROM hadith_entries
            WHERE book_id = ?
            \(Self.readingOrder)
            LIMIT ? OFFSET ?
            """,
            [.text(bookID), .int(limit), .int(offset)]
        )
        return rows.compactMap(Self.entry(from:))
    }

    func entryCount(bookID: String) async throws -> Int {
        let rows = try await database.connection.query(
            "SELECT COUNT(*) AS n FROM hadith_entries WHERE book_id = ?",
            [.text(bookID)]
        )
        return rows.first?.int("n") ?? 0
    }

    /// One narration by its printed number, e.g. ("bukhari", "402.2").
    /// Backs deep links and cross-references.
    func entry(bookID: String, displayNumber: String) async throws -> HadithEntry? {
        let rows = try await database.connection.query(
            """
            SELECT \(Self.entryColumns)
            FROM hadith_entries
            WHERE book_id = ? AND display_number = ?
            ORDER BY source_sequence
            LIMIT 1
            """,
            [.text(bookID), .text(displayNumber)]
        )
        return rows.compactMap(Self.entry(from:)).first
    }

    /// 0-based position of a narration in its collection's reading order.
    ///
    /// Counts narrations that sort before it by `source_sequence` — the same
    /// order the reader pages in — so the caller can turn a hadith into a page
    /// offset and open directly to it. Nil when the number is not in the book.
    func readingIndex(bookID: String, displayNumber: String) async throws -> Int? {
        let rows = try await database.connection.query(
            """
            SELECT COUNT(*) AS n FROM hadith_entries
            WHERE book_id = ? AND source_sequence < (
                SELECT MIN(source_sequence) FROM hadith_entries
                WHERE book_id = ? AND display_number = ?
            )
            """,
            [.text(bookID), .text(bookID), .text(displayNumber)]
        )
        // The subquery is empty when the display number is absent; COUNT then
        // returns 0 spuriously, so confirm the row actually exists first.
        guard try await entry(bookID: bookID, displayNumber: displayNumber) != nil else {
            return nil
        }
        return rows.first?.int("n") ?? 0
    }

    /// Substring search across whichever scripts are stored.
    func search(_ term: String, bookID: String?, limit: Int) async throws -> [HadithEntry] {
        let needle = "%\(term)%"
        var sql = """
        SELECT \(Self.entryColumns)
        FROM hadith_entries
        WHERE (text_en LIKE ? OR text_ur LIKE ? OR text_ar LIKE ?)
        """
        var params: [SQLValue] = [.text(needle), .text(needle), .text(needle)]
        if let bookID {
            sql += " AND book_id = ?"
            params.append(.text(bookID))
        }
        sql += " \(Self.readingOrder) LIMIT ?"
        params.append(.int(limit))
        let rows = try await database.connection.query(sql, params)
        return rows.compactMap(Self.entry(from:))
    }

    // MARK: - Import

    func upsertBooks(_ books: [HadithBook]) async throws {
        guard !books.isEmpty else { return }
        let statements: [(sql: String, parameters: [SQLValue])] = books.map { book in
            (
                sql: """
                INSERT INTO hadith_books (id, title_english, title_urdu, hadith_count,
                    has_arabic, has_english, has_urdu, section_count, sections_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title_english = excluded.title_english,
                    title_urdu = excluded.title_urdu,
                    hadith_count = excluded.hadith_count,
                    has_arabic = excluded.has_arabic,
                    has_english = excluded.has_english,
                    has_urdu = excluded.has_urdu,
                    section_count = excluded.section_count,
                    sections_json = excluded.sections_json
                """,
                parameters: [
                    .text(book.id),
                    .text(book.titleEnglish),
                    .text(book.titleUrdu),
                    .int(book.hadithCount),
                    .int(book.hasArabic ? 1 : 0),
                    .int(book.hasEnglish ? 1 : 0),
                    .int(book.hasUrdu ? 1 : 0),
                    .int(book.sectionCount),
                    .optionalText(Self.encodeSections(book.sections)),
                ]
            )
        }
        try await database.connection.executeBatch(statements)
    }

    /// Removes one collection's narrations.
    ///
    /// Import does delete-then-insert per collection so a narration dropped
    /// upstream truly disappears instead of lingering as an orphan. Without it
    /// the stored count would drift above the pack's and the integrity check
    /// after import would fail every launch.
    func deleteEntries(bookID: String) async throws {
        try await database.connection.execute(
            "DELETE FROM hadith_entries WHERE book_id = ?",
            [.text(bookID)]
        )
    }

    /// Inserts one collection's narrations.
    ///
    /// The conflict target is `canonical_id`, which identifies exactly one
    /// narration, so a re-import replaces a record only with the newer revision
    /// of *itself* — two different narrations can no longer land on one key and
    /// overwrite each other, which is how the integer schema lost 103 of them.
    /// A collision inside the batch itself would mean a corrupt pack, so the
    /// caller checks the resulting row count.
    func upsertEntries(_ entries: [HadithEntry]) async throws {
        guard !entries.isEmpty else { return }
        let statements: [(sql: String, parameters: [SQLValue])] = entries.map { entry in
            (
                sql: """
                INSERT INTO hadith_entries (canonical_id, book_id, display_number,
                    number_major, number_minor, source_sequence,
                    text_ar, text_en, text_ur, grades, source_book, source_hadith,
                    arabic_segments_json, quran_refs_json, urdu_sanad, urdu_text,
                    chapter_number, chapter_title_en, chapter_title_ar, chapter_title_ur)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(canonical_id) DO UPDATE SET
                    book_id = excluded.book_id,
                    display_number = excluded.display_number,
                    number_major = excluded.number_major,
                    number_minor = excluded.number_minor,
                    source_sequence = excluded.source_sequence,
                    text_ar = excluded.text_ar,
                    text_en = excluded.text_en,
                    text_ur = excluded.text_ur,
                    grades = excluded.grades,
                    source_book = excluded.source_book,
                    source_hadith = excluded.source_hadith,
                    arabic_segments_json = excluded.arabic_segments_json,
                    quran_refs_json = excluded.quran_refs_json,
                    urdu_sanad = excluded.urdu_sanad,
                    urdu_text = excluded.urdu_text,
                    chapter_number = excluded.chapter_number,
                    chapter_title_en = excluded.chapter_title_en,
                    chapter_title_ar = excluded.chapter_title_ar,
                    chapter_title_ur = excluded.chapter_title_ur
                """,
                parameters: [
                    .text(entry.canonicalID),
                    .text(entry.bookID),
                    .text(entry.displayNumber),
                    .int(entry.numberMajor),
                    .optionalInt(entry.numberMinor),
                    .int(entry.sourceSequence),
                    .optionalText(entry.textArabic),
                    .optionalText(entry.textEnglish),
                    .optionalText(entry.textUrdu),
                    .optionalText(entry.grades?.joined(separator: " | ")),
                    .optionalInt(entry.sourceBook),
                    .optionalInt(entry.sourceHadith),
                    .optionalText(Self.encode(entry.arabicSegments)),
                    .optionalText(Self.encode(entry.quranRefs)),
                    .optionalText(entry.urduSanad),
                    .optionalText(entry.urduText),
                    .optionalInt(entry.chapterNumber),
                    .optionalText(entry.chapterTitleEnglish),
                    .optionalText(entry.chapterTitleArabic),
                    .optionalText(entry.chapterTitleUrdu),
                ]
            )
        }
        try await database.connection.executeBatch(statements)
    }

    // MARK: - Row mapping

    private static func entry(from row: SQLRow) -> HadithEntry? {
        guard let canonicalID = row.text("canonical_id"),
              let bookID = row.text("book_id"),
              let displayNumber = row.text("display_number"),
              let numberMajor = row.int("number_major"),
              let sourceSequence = row.int("source_sequence") else { return nil }
        let grades = row.text("grades")?
            .components(separatedBy: " | ")
            .filter { !$0.isEmpty }
        return HadithEntry(
            canonicalID: canonicalID,
            bookID: bookID,
            displayNumber: displayNumber,
            numberMajor: numberMajor,
            numberMinor: row.int("number_minor"),
            sourceSequence: sourceSequence,
            textArabic: row.text("text_ar"),
            textEnglish: row.text("text_en"),
            textUrdu: row.text("text_ur"),
            grades: (grades?.isEmpty ?? true) ? nil : grades,
            sourceBook: row.int("source_book"),
            sourceHadith: row.int("source_hadith"),
            arabicSegments: decode([HadithSegment].self, row.text("arabic_segments_json")),
            quranRefs: decode([QuranRef].self, row.text("quran_refs_json")),
            urduSanad: row.text("urdu_sanad"),
            urduText: row.text("urdu_text"),
            chapterNumber: row.int("chapter_number"),
            chapterTitleEnglish: row.text("chapter_title_en"),
            chapterTitleArabic: row.text("chapter_title_ar"),
            chapterTitleUrdu: row.text("chapter_title_ur")
        )
    }
}
