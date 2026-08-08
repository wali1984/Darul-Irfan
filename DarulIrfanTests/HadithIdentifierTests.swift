import XCTest
@testable import DarulIrfan

/// Guards the hadith identifier scheme and the v4 migration that introduced it.
///
/// The bug these exist to prevent: hadith numbers used to be stored as `Int`,
/// so the sub-numbered narrations upstream prints as `402.2` truncated to `402`
/// and collided with the real hadith 402. The insert's `ON CONFLICT DO UPDATE`
/// then overwrote one narration with the other — 103 of them across 86 groups,
/// with nothing raised. Numbers like `402.2` are identifiers, not quantities,
/// so they are stored textually and never as `Double`/`REAL`.
final class HadithIdentifierTests: XCTestCase {
    private var database: AppDatabase!
    private var repository: HadithRepository!

    override func setUp() async throws {
        try await super.setUp()
        database = try await AppDatabase.inMemory()
        repository = HadithRepository(database: database)
    }

    override func tearDown() async throws {
        repository = nil
        database = nil
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// Sahih al-Bukhari's 402 / 402.2 pair and the 1390 / 1390.2 / 1390.3 run —
    /// the exact shapes the integer schema collapsed.
    private func bukhariFixture() -> [HadithEntry] {
        [
            makeEntry(book: "bukhari", number: "402", sequence: 402),
            makeEntry(book: "bukhari", number: "402.2", sequence: 403),
            makeEntry(book: "bukhari", number: "1390", sequence: 1396),
            makeEntry(book: "bukhari", number: "1390.2", sequence: 1397),
            makeEntry(book: "bukhari", number: "1390.3", sequence: 1398),
        ]
    }

    private func makeEntry(
        book: String,
        number: String,
        sequence: Int,
        arabic: String? = nil,
        english: String? = nil,
        urdu: String? = nil
    ) -> HadithEntry {
        let parts = number.split(separator: ".", maxSplits: 1)
        return HadithEntry(
            canonicalID: "\(book)|\(number)|\(sequence)",
            bookID: book,
            displayNumber: number,
            numberMajor: Int(parts[0])!,
            numberMinor: parts.count > 1 ? Int(parts[1])! : nil,
            sourceSequence: sequence,
            textArabic: arabic ?? "arabic \(number)",
            textEnglish: english ?? "english \(number)",
            textUrdu: urdu ?? "urdu \(number)"
        )
    }

    // MARK: - Sub-numbered narrations survive

    func testSubNumberedNarrationsAreStoredSeparately() async throws {
        let fixture = bukhariFixture()
        try await repository.upsertEntries(fixture)

        // The whole point: five records in, five records out. Under the integer
        // schema this stored two — 402.2 overwrote 402, and 1390.2/.3 overwrote 1390.
        let stored = try await repository.entryCount(bookID: "bukhari")
        XCTAssertEqual(stored, fixture.count)

        for expected in fixture {
            let found = try await repository.entry(
                bookID: "bukhari", displayNumber: expected.displayNumber
            )
            XCTAssertEqual(found?.canonicalID, expected.canonicalID,
                           "hadith \(expected.displayNumber) is not retrievable by its printed number")
            XCTAssertEqual(found?.textEnglish, expected.textEnglish,
                           "hadith \(expected.displayNumber) holds another narration's text")
        }
    }

    func testHadith402AndItsSubNumberAreDistinctRecords() async throws {
        try await repository.upsertEntries(bukhariFixture())

        let base = try await repository.entry(bookID: "bukhari", displayNumber: "402")
        let sub = try await repository.entry(bookID: "bukhari", displayNumber: "402.2")

        XCTAssertNotNil(base)
        XCTAssertNotNil(sub)
        XCTAssertNotEqual(base?.canonicalID, sub?.canonicalID)
        XCTAssertNotEqual(base?.textEnglish, sub?.textEnglish)
        XCTAssertEqual(base?.numberMajor, 402)
        XCTAssertEqual(sub?.numberMajor, 402)
        XCTAssertNil(base?.numberMinor)
        XCTAssertEqual(sub?.numberMinor, 2)

        // Sahih al-Bukhari prints 402 and 402.2 but no 402.1. A lookup for it
        // must come back empty rather than resolving to either neighbour.
        let absent = try await repository.entry(bookID: "bukhari", displayNumber: "402.1")
        XCTAssertNil(absent, "402.1 does not exist in this collection")
    }

    func testConsecutiveSubNumbersEachKeepTheirOwnText() async throws {
        try await repository.upsertEntries(bukhariFixture())

        for number in ["1390", "1390.2", "1390.3"] {
            let entry = try await repository.entry(bookID: "bukhari", displayNumber: number)
            XCTAssertEqual(entry?.displayNumber, number)
            XCTAssertEqual(entry?.textEnglish, "english \(number)")
            XCTAssertEqual(entry?.textUrdu, "urdu \(number)")
        }
    }

    // MARK: - Printed form and ordering

    func testDisplayNumberKeepsTheSourcesExactTextualForm() async throws {
        // Jami' at-Tirmidhi prints 3604.02 … 3604.09 then 3604.1. Round-tripping
        // any of these through a number loses the printed form: the leading zero
        // in .02 disappears, and .10 comes back as .1. The stored value is the
        // source's characters, untouched by arithmetic.
        let entries = [
            makeEntry(book: "tirmidhi", number: "3604", sequence: 3637),
            makeEntry(book: "tirmidhi", number: "3604.02", sequence: 3638),
            makeEntry(book: "tirmidhi", number: "3604.09", sequence: 3645),
            makeEntry(book: "tirmidhi", number: "3604.1", sequence: 3646),
        ]
        try await repository.upsertEntries(entries)

        let stored = try await repository.entries(bookID: "tirmidhi", limit: 50, offset: 0)
        XCTAssertEqual(stored.map(\.displayNumber), ["3604", "3604.02", "3604.09", "3604.1"])
    }

    func testReadingOrderFollowsTheSourceNotTheMinorNumber() async throws {
        // 3604.1 is sub-number *ten*: it comes last in the collection despite
        // numberMinor == 1. Ordering by the minor part (or by a decimal reading)
        // would put it second. sourceSequence is what makes this come out right.
        let entries = [
            makeEntry(book: "tirmidhi", number: "3604.09", sequence: 3645),
            makeEntry(book: "tirmidhi", number: "3604.1", sequence: 3646),
            makeEntry(book: "tirmidhi", number: "3604.02", sequence: 3638),
        ]
        try await repository.upsertEntries(entries)

        let stored = try await repository.entries(bookID: "tirmidhi", limit: 50, offset: 0)
        XCTAssertEqual(stored.map(\.displayNumber), ["3604.02", "3604.09", "3604.1"])
        XCTAssertEqual(stored.last?.numberMinor, 1, "3604.1's minor part really is 1…")
        XCTAssertEqual(stored.last?.sourceSequence, 3646, "…but it is printed last")
    }

    func testMuwattaMalikFractionalInsertionsKeepTheirOrder() async throws {
        // Muwatta Malik uses .25 / .5 / .75 as insertion points between whole
        // numbers, so the minor part is not a counter: 1167.75 sorts after
        // 1167.5 even though 75 > 5 would be read the other way round by anyone
        // treating the minor part as a sequence.
        let entries = [
            makeEntry(book: "malik", number: "1167", sequence: 1177),
            makeEntry(book: "malik", number: "1167.5", sequence: 1178),
            makeEntry(book: "malik", number: "1167.75", sequence: 1179),
        ]
        try await repository.upsertEntries(entries)

        let stored = try await repository.entries(bookID: "malik", limit: 50, offset: 0)
        XCTAssertEqual(stored.map(\.displayNumber), ["1167", "1167.5", "1167.75"])
    }

    // MARK: - Re-import is idempotent, not destructive

    func testReimportingReplacesOnlyTheSameNarration() async throws {
        try await repository.upsertEntries(bukhariFixture())
        let before = try await repository.entryCount(bookID: "bukhari")

        // A content update revises 402.2's Urdu. It must not touch 402.
        var revised = makeEntry(book: "bukhari", number: "402.2", sequence: 403)
        revised.textUrdu = "revised urdu 402.2"
        try await repository.upsertEntries([revised])

        let after = try await repository.entryCount(bookID: "bukhari")
        XCTAssertEqual(after, before, "a re-import must not add or drop rows")

        let sub = try await repository.entry(bookID: "bukhari", displayNumber: "402.2")
        XCTAssertEqual(sub?.textUrdu, "revised urdu 402.2")

        let base = try await repository.entry(bookID: "bukhari", displayNumber: "402")
        XCTAssertEqual(base?.textUrdu, "urdu 402", "hadith 402 was overwritten by 402.2")
    }

    func testDeleteThenInsertDropsNarrationsRemovedUpstream() async throws {
        try await repository.upsertEntries(bukhariFixture())
        XCTAssertEqual(try await repository.entryCount(bookID: "bukhari"), 5)

        // A later content version drops 1390.2 and 1390.3. Re-importing without
        // clearing first would leave them behind, and the stored count would
        // drift permanently above what the pack accounts for.
        let revised = Array(bukhariFixture().prefix(3))
        try await repository.deleteEntries(bookID: "bukhari")
        try await repository.upsertEntries(revised)

        XCTAssertEqual(try await repository.entryCount(bookID: "bukhari"), revised.count)
        XCTAssertNil(try await repository.entry(bookID: "bukhari", displayNumber: "1390.2"))
        XCTAssertNotNil(try await repository.entry(bookID: "bukhari", displayNumber: "402.2"))
    }

    // MARK: - Honest gaps

    func testMissingTranslationIsReportedAsMissingNotSubstituted() {
        let entry = makeEntry(
            book: "bukhari", number: "402", sequence: 402,
            arabic: "عربی", english: "English narration", urdu: nil
        )

        // No cross-language fallback: English prose returned for "ur" would be
        // set in Nastaliq and laid out right-to-left, reading as if it were the
        // Urdu translation. Arabic returned for "ur" would present the source
        // text as its own translation.
        XCTAssertNil(entry.text(languageCode: "ur"))
        XCTAssertEqual(entry.text(languageCode: "en"), "English narration")
        XCTAssertEqual(entry.text(languageCode: "ar"), "عربی")

        // Where something must be shown, the language comes with it so the view
        // can style the text for the script it actually is.
        let preview = entry.availableText(preferring: "ur")
        XCTAssertEqual(preview?.text, "English narration")
        XCTAssertEqual(preview?.languageCode, "en")
    }

    // MARK: - Schema and migration

    func testSchemaKeysHadithOnTextNotANumber() async throws {
        let columns = try await database.connection.query(
            "SELECT name, type, pk FROM pragma_table_info('hadith_entries')"
        )
        let byName = Dictionary(uniqueKeysWithValues: columns.compactMap { row in
            row.text("name").map { ($0, row) }
        })

        XCTAssertEqual(byName["canonical_id"]?.text("type"), "TEXT")
        XCTAssertEqual(byName["canonical_id"]?.int("pk"), 1)
        XCTAssertEqual(byName["display_number"]?.text("type"), "TEXT")
        XCTAssertNil(byName["hadith_number"], "the old integer column must be gone")

        // No column in this table may be REAL: a float hadith number is exactly
        // the failure mode this schema exists to rule out.
        for (name, row) in byName {
            XCTAssertNotEqual(row.text("type"), "REAL", "\(name) must not be REAL")
        }
    }

    func testMigrationFromV3PreservesUserDataAndRekeysHadith() async throws {
        // Rebuild a v3-era database: old hadith table, and user data in every
        // table the migration promises to leave alone.
        let legacy = try SQLiteDatabase(url: nil)
        try await legacy.executeScript(AppDatabase.migrationV1)
        try await legacy.executeScript(AppDatabase.migrationV2)
        try await legacy.executeScript(AppDatabase.migrationV3)
        try await legacy.setSchemaVersion(3)

        try await legacy.execute(
            "INSERT INTO hadith_entries (book_id, hadith_number, text_en) VALUES (?, ?, ?)",
            [.text("bukhari"), .int(402), .text("legacy 402")]
        )
        try await legacy.execute(
            "INSERT INTO quran_bookmarks (id, surah_number, ayah_number, created_at) VALUES (?, ?, ?, ?)",
            [.text("bm-1"), .int(2), .int(255), .real(1)]
        )
        try await legacy.execute(
            "INSERT INTO key_value (key, value, updated_at) VALUES (?, ?, ?)",
            [.text("settings.calculationMethod"), .text("karachi"), .real(1)]
        )
        try await legacy.execute(
            "INSERT INTO downloaded_assets (id, remote_url, relative_file_path, byte_size, downloaded_at) "
            + "VALUES (?, ?, ?, ?, ?)",
            [.text("dl-1"), .text("https://example.org/a.mp3"), .text("a.mp3"), .int(10), .real(1)]
        )
        try await legacy.execute(
            "INSERT INTO quran_reading_progress (surah_number, ayah_number, updated_at) VALUES (?, ?, ?)",
            [.int(18), .int(10), .real(1)]
        )
        try await legacy.execute(
            "INSERT INTO prayer_log (day_key, prayer, completion, updated_at) VALUES (?, ?, ?, ?)",
            [.text("2026-08-08"), .text("fajr"), .text("jamaat"), .real(1)]
        )

        // Apply v4 exactly as the app does.
        try await legacy.migrate(
            to: 4,
            script: AppDatabase.migrationV4,
            checks: AppDatabase.migrationV4Checks,
            cleanup: "DROP TABLE IF EXISTS _migration_v4_counts;"
        )

        XCTAssertEqual(try await legacy.schemaVersion(), 4)

        // Settings, bookmarks, downloads and progress are all still there.
        for (table, expected) in [
            ("quran_bookmarks", 1), ("key_value", 1), ("downloaded_assets", 1),
            ("quran_reading_progress", 1), ("prayer_log", 1),
        ] {
            let rows = try await legacy.query("SELECT COUNT(*) AS n FROM \(table)")
            XCTAssertEqual(rows.first?.int("n"), expected, "\(table) lost rows in the migration")
        }

        // The scratch table the checks used is gone.
        let scratch = try await legacy.query(
            "SELECT name FROM pragma_table_info('_migration_v4_counts')"
        )
        XCTAssertTrue(scratch.isEmpty)

        // Hadith is re-keyed and empty, ready for the regenerated packs, which
        // re-import on the same launch because the seed manifest version rose.
        let entries = try await legacy.query("SELECT COUNT(*) AS n FROM hadith_entries")
        XCTAssertEqual(entries.first?.int("n"), 0)
    }

    func testEveryUserDataTableIsCoveredByTheMigrationChecks() {
        // The declared list and the migration's SQL must name the same tables:
        // a table added to one but not the other would be silently unprotected.
        for table in AppDatabase.userDataTables {
            XCTAssertTrue(
                AppDatabase.migrationV4.contains("FROM \(table)"),
                "\(table) is declared user data but migration v4 does not count its rows"
            )
            XCTAssertTrue(
                AppDatabase.migrationV4Checks.contains { $0.sql.contains("FROM \(table)") },
                "\(table) is declared user data but no migration check verifies it"
            )
        }
    }

    func testMigrationRollsBackWhenACheckFails() async throws {
        let legacy = try SQLiteDatabase(url: nil)
        try await legacy.executeScript(AppDatabase.migrationV1)
        try await legacy.executeScript(AppDatabase.migrationV2)
        try await legacy.executeScript(AppDatabase.migrationV3)
        try await legacy.setSchemaVersion(3)
        try await legacy.execute(
            "INSERT INTO key_value (key, value, updated_at) VALUES (?, ?, ?)",
            [.text("settings.language"), .text("ur"), .real(1)]
        )

        // A check that always finds a violation stands in for a migration that
        // would have damaged the database.
        let failing = SQLiteDatabase.MigrationCheck(
            sql: "SELECT 1", failure: "deliberate failure"
        )
        do {
            try await legacy.migrate(
                to: 4,
                script: AppDatabase.migrationV4,
                checks: AppDatabase.migrationV4Checks + [failing],
                cleanup: "DROP TABLE IF EXISTS _migration_v4_counts;"
            )
            XCTFail("migration should have thrown")
        } catch {
            // expected
        }

        // Rolled back whole: the old schema and the user's settings are intact,
        // and user_version still says 3 so the next launch retries cleanly.
        XCTAssertEqual(try await legacy.schemaVersion(), 3)
        let columns = try await legacy.query(
            "SELECT name FROM pragma_table_info('hadith_entries') WHERE name = 'hadith_number'"
        )
        XCTAssertEqual(columns.count, 1, "the v3 schema should be untouched")
        let settings = try await legacy.query("SELECT COUNT(*) AS n FROM key_value")
        XCTAssertEqual(settings.first?.int("n"), 1)
    }
}
