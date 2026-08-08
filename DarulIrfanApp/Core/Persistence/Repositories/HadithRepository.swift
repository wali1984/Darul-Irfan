import Foundation

/// SQLite-backed store for the hadith collections and their entries.
struct HadithRepository: HadithRepositoryProtocol {
    let database: AppDatabase

    /// Every column the row mapper needs, in one place.
    private static let entryColumns = """
    canonical_id, book_id, display_number, number_major, number_minor,
    source_sequence, text_ar, text_en, text_ur, grades, source_book, source_hadith
    """

    /// The source edition's own order. See `HadithEntry` for why neither the
    /// display number nor `number_minor` can be used to sort.
    private static let readingOrder = "ORDER BY book_id, source_sequence"

    // MARK: - Reads

    func books() async throws -> [HadithBook] {
        let rows = try await database.connection.query(
            """
            SELECT id, title_english, title_urdu, hadith_count,
                   has_arabic, has_english, has_urdu, section_count
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
                sectionCount: row.int("section_count") ?? 0
            )
        }
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
            """,
            [.text(bookID), .text(displayNumber)]
        )
        return rows.compactMap(Self.entry(from:)).first
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
                    has_arabic, has_english, has_urdu, section_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title_english = excluded.title_english,
                    title_urdu = excluded.title_urdu,
                    hadith_count = excluded.hadith_count,
                    has_arabic = excluded.has_arabic,
                    has_english = excluded.has_english,
                    has_urdu = excluded.has_urdu,
                    section_count = excluded.section_count
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
                    text_ar, text_en, text_ur, grades, source_book, source_hadith)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                    source_hadith = excluded.source_hadith
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
            sourceHadith: row.int("source_hadith")
        )
    }
}
