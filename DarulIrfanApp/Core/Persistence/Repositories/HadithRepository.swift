import Foundation

/// SQLite-backed store for the hadith collections and their entries.
struct HadithRepository: HadithRepositoryProtocol {
    let database: AppDatabase

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

    /// A page of hadith from one collection, ordered by hadith number.
    func entries(bookID: String, limit: Int, offset: Int) async throws -> [HadithEntry] {
        let rows = try await database.connection.query(
            """
            SELECT book_id, hadith_number, text_ar, text_en, text_ur,
                   grades, ref_book, ref_hadith
            FROM hadith_entries
            WHERE book_id = ?
            ORDER BY hadith_number
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

    /// Substring search across whichever scripts are stored.
    func search(_ term: String, bookID: String?, limit: Int) async throws -> [HadithEntry] {
        let needle = "%\(term)%"
        var sql = """
        SELECT book_id, hadith_number, text_ar, text_en, text_ur,
               grades, ref_book, ref_hadith
        FROM hadith_entries
        WHERE (text_en LIKE ? OR text_ur LIKE ? OR text_ar LIKE ?)
        """
        var params: [SQLValue] = [.text(needle), .text(needle), .text(needle)]
        if let bookID {
            sql += " AND book_id = ?"
            params.append(.text(bookID))
        }
        sql += " ORDER BY book_id, hadith_number LIMIT ?"
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

    func upsertEntries(_ entries: [HadithEntry]) async throws {
        guard !entries.isEmpty else { return }
        let statements: [(sql: String, parameters: [SQLValue])] = entries.map { entry in
            (
                sql: """
                INSERT INTO hadith_entries (book_id, hadith_number, text_ar, text_en,
                    text_ur, grades, ref_book, ref_hadith)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(book_id, hadith_number) DO UPDATE SET
                    text_ar = excluded.text_ar,
                    text_en = excluded.text_en,
                    text_ur = excluded.text_ur,
                    grades = excluded.grades,
                    ref_book = excluded.ref_book,
                    ref_hadith = excluded.ref_hadith
                """,
                parameters: [
                    .text(entry.bookID),
                    .int(entry.hadithNumber),
                    .optionalText(entry.textArabic),
                    .optionalText(entry.textEnglish),
                    .optionalText(entry.textUrdu),
                    .optionalText(entry.grades?.joined(separator: " | ")),
                    entry.refBook.map { SQLValue.int($0) } ?? .null,
                    entry.refHadith.map { SQLValue.int($0) } ?? .null,
                ]
            )
        }
        try await database.connection.executeBatch(statements)
    }

    // MARK: - Row mapping

    private static func entry(from row: SQLRow) -> HadithEntry? {
        guard let bookID = row.text("book_id"),
              let number = row.int("hadith_number") else { return nil }
        let grades = row.text("grades")?
            .components(separatedBy: " | ")
            .filter { !$0.isEmpty }
        return HadithEntry(
            bookID: bookID,
            hadithNumber: number,
            textArabic: row.text("text_ar"),
            textEnglish: row.text("text_en"),
            textUrdu: row.text("text_ur"),
            grades: (grades?.isEmpty ?? true) ? nil : grades,
            refBook: row.int("ref_book"),
            refHadith: row.int("ref_hadith")
        )
    }
}
