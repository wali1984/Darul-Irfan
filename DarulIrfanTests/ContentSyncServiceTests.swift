import Foundation
import XCTest
@testable import DarulIrfan

/// Tests for `ContentSyncService.importSeedDataIfNeeded()`.
///
/// The unit test bundle runs inside the app host (TEST_HOST points at
/// DarulIrfan.app), so `Bundle.main` is the real app bundle and `SeedBundle`
/// reads the shipped `Resources/SeedData/*.json` files. If the seed manifest
/// cannot be located (e.g. resources were not packaged into this particular
/// test host build), the bundle-dependent tests skip with a clear message
/// instead of asserting on data that is not there. The version-guard test is
/// bundle-independent and always runs.
///
/// No network is touched: the import reads the bundle only.
final class ContentSyncServiceTests: XCTestCase {

    private var database: AppDatabase!
    private var quranRepository: QuranRepository!
    private var hadithRepository: HadithRepository!
    private var contentRepository: ContentRepository!
    private var mediaRepository: MediaRepository!
    private var eventsRepository: EventsRepository!
    private var searchIndex: SearchIndexService!
    private var service: ContentSyncService!

    override func setUp() async throws {
        database = try await AppDatabase.inMemory()
        quranRepository = QuranRepository(database: database)
        hadithRepository = HadithRepository(database: database)
        contentRepository = ContentRepository(database: database)
        mediaRepository = MediaRepository(database: database)
        eventsRepository = EventsRepository(database: database)
        searchIndex = SearchIndexService(
            database: database,
            quranRepository: quranRepository,
            contentRepository: contentRepository,
            mediaRepository: mediaRepository,
            eventsRepository: eventsRepository
        )
        service = ContentSyncService(
            quranRepository: quranRepository,
            hadithRepository: hadithRepository,
            contentRepository: contentRepository,
            mediaRepository: mediaRepository,
            eventsRepository: eventsRepository,
            database: database,
            searchIndex: searchIndex
        )
    }

    override func tearDown() {
        service = nil
        searchIndex = nil
        eventsRepository = nil
        mediaRepository = nil
        contentRepository = nil
        hadithRepository = nil
        quranRepository = nil
        database = nil
    }

    // MARK: - Version guard (bundle-independent)

    func testImportSkipsWhenInstalledSeedVersionIsCurrent() async throws {
        // Pre-stamp a seed version far above anything the bundle can carry,
        // imported by this build's stages; the guard must short-circuit
        // before touching any seed files.
        try await setValue("999999", forKey: ContentSyncService.Keys.seedVersion)
        try await setValue(ContentSyncService.stageRevisionsStamp, forKey: ContentSyncService.Keys.stageRevisions)

        let imported = try await service.importSeedDataIfNeeded()
        XCTAssertEqual(imported, 0, "An already-current seed version must import nothing")

        let surahs = try await quranRepository.allSurahs()
        XCTAssertTrue(surahs.isEmpty, "The guard must prevent any writes")
    }

    // MARK: - Seed import (uses the real bundled seed data)

    func testSeedImportIsIdempotent() async throws {
        try XCTSkipIf(
            SeedBundle.manifest() == nil,
            "SeedData resources are not visible to this test host; skipping bundle-dependent seed test"
        )

        let firstRun = try await service.importSeedDataIfNeeded()
        XCTAssertGreaterThan(firstRun, 0, "First import must bring in seed records")

        // Second call sees seed.version already stamped → imports nothing.
        let secondRun = try await service.importSeedDataIfNeeded()
        XCTAssertEqual(secondRun, 0, "Repeated import must be a no-op")

        // The stamp matches the bundled manifest version.
        let manifestVersion = SeedBundle.manifest()?.version ?? -1
        let rows = try await database.connection.query(
            "SELECT value FROM key_value WHERE key = ?",
            [.text("seed.version")]
        )
        XCTAssertEqual(rows.first?.text("value"), String(manifestVersion))
    }

    func testSeedImportPopulatesRepositoriesAndSearchIndex() async throws {
        try XCTSkipIf(
            SeedBundle.manifest() == nil,
            "SeedData resources are not visible to this test host; skipping bundle-dependent seed test"
        )

        let imported = try await service.importSeedDataIfNeeded()
        XCTAssertGreaterThan(imported, 0)

        // The import count is exactly the sum of the bundle's record counts —
        // nothing dropped, nothing double-counted.
        // Hadith imports the catalogue plus one pack per collection.
        let hadithCatalog = SeedBundle.hadithCatalog()
        let hadithTotal = (hadithCatalog?.books.count ?? 0)
            + (hadithCatalog?.books.reduce(0) { partial, book in
                partial + SeedBundle.hadithEntries(bookID: book.id).count
            } ?? 0)

        let expectedTotal = SeedBundle.quranSurahs().count
            + SeedBundle.quranAyahs().count
            + SeedBundle.quranEditions().count
            + SeedBundle.quranTranslations().count
            + SeedBundle.quranTafsir().count
            + hadithTotal
            // The narrator store imports alongside the collections (schema v6)
            // and the importer counts it; omitting it here failed the build by
            // exactly the store's size (194,341 − 181,698 = 12,643 narrators).
            + SeedBundle.hadithNarrators().count
            + SeedBundle.libraryItems().count
            + SeedBundle.bookPages().count
            + SeedBundle.mediaItems().count
            + SeedBundle.events().count
            + SeedBundle.announcements().count
        XCTAssertEqual(imported, expectedTotal)

        // Spot-check the repositories now serve what the bundle declared.
        let surahs = try await quranRepository.allSurahs()
        XCTAssertEqual(surahs.count, SeedBundle.quranSurahs().count)

        let mediaItems = try await mediaRepository.items(
            category: nil, year: nil, month: nil, limit: 100_000
        )
        XCTAssertEqual(mediaItems.count, SeedBundle.mediaItems().count)

        let pageRows = try await database.connection.query(
            "SELECT COUNT(*) AS row_count FROM book_pages"
        )
        XCTAssertEqual(pageRows.first?.int("row_count"), SeedBundle.bookPages().count,
                       "Every bundled book page must survive import")

        // Import triggers a full reindex, so the FTS table must have rows
        // whenever anything was imported. (search_fts, schema v9, replaced
        // v1's search_index, which the first full reindex drops.)
        let indexRows = try await database.connection.query(
            "SELECT COUNT(*) AS row_count FROM search_fts"
        )
        let rowCount = indexRows.first?.int("row_count") ?? 0
        XCTAssertGreaterThan(rowCount, 0, "Seed import must build the search index")
    }

    func testBundledAkramUtTarajumIsCompleteInBothLanguages() throws {
        try XCTSkipIf(
            SeedBundle.manifest() == nil,
            "SeedData resources are not visible to this test host; skipping bundle-dependent seed test"
        )

        let translations = SeedBundle.quranTranslations()
        let surahs = SeedBundle.quranSurahs()
        XCTAssertEqual(surahs.count, 114)
        XCTAssertEqual(surahs.reduce(0) { $0 + $1.ayahCount }, 6_236)

        for editionID in ["akram-ut-tarajum-ur", "akram-ut-tarajum-en"] {
            let rows = translations.filter { $0.editionID == editionID }
            XCTAssertEqual(rows.count, 6_236, "\(editionID) must contain every Quran ayah")
            XCTAssertEqual(Set(rows.map(\.id)).count, 6_236, "\(editionID) must not contain duplicate ayahs")
            XCTAssertTrue(rows.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            for surah in surahs {
                XCTAssertEqual(
                    rows.filter { $0.surahNumber == surah.id }.count,
                    surah.ayahCount,
                    "\(editionID) has the wrong count for surah \(surah.id)"
                )
            }
        }
    }

    func testSeedImportedDataSurvivesReimportUnchanged() async throws {
        try XCTSkipIf(
            SeedBundle.manifest() == nil,
            "SeedData resources are not visible to this test host; skipping bundle-dependent seed test"
        )

        _ = try await service.importSeedDataIfNeeded()
        let surahsAfterFirst = try await quranRepository.allSurahs()

        _ = try await service.importSeedDataIfNeeded()
        let surahsAfterSecond = try await quranRepository.allSurahs()

        XCTAssertEqual(
            surahsAfterFirst, surahsAfterSecond,
            "A repeated import must leave the data byte-for-byte identical"
        )
    }

    // MARK: - Fingerprints

    /// The fingerprint's input is plain text so it can be computed outside
    /// the app (the earlier-imports table was). This pins the format.
    func testStageFingerprintFormatIsStable() {
        let fingerprint = SeedBundle.stageFingerprint(
            stage: "test",
            revision: 3,
            files: [
                (name: "a", digest: "missing"),
                (name: "b", digest: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"),
            ]
        )
        XCTAssertEqual(fingerprint, "31d273d517d1cfc9797597888e8085f76cdb043b691a23013cbcb7bf8a6625b3")
    }

    func testOnlyStagesWhoseFilesChangedImportAgain() async throws {
        try XCTSkipIf(
            SeedBundle.manifest() == nil,
            "SeedData resources are not visible to this test host; skipping bundle-dependent seed test"
        )
        _ = try await service.importSeedDataIfNeeded()

        // A manifest bump that left these files alone imports nothing.
        try await deleteKey(ContentSyncService.Keys.seedVersion)
        let unchanged = try await service.importSeedDataIfNeeded()
        XCTAssertEqual(unchanged, 0)

        // A changed stage imports on its own.
        try await setValue("changed", forKey: ContentSyncService.Keys.stageFingerprint(.library))
        try await deleteKey(ContentSyncService.Keys.seedVersion)
        let libraryOnly = try await service.importSeedDataIfNeeded()
        XCTAssertEqual(libraryOnly, SeedBundle.libraryItems().count)

        // New import logic re-checks every stage without a manifest change,
        // and still imports none whose files are unchanged.
        try await setValue("older stages", forKey: ContentSyncService.Keys.stageRevisions)
        let sameFiles = try await service.importSeedDataIfNeeded()
        XCTAssertEqual(sameFiles, 0)
        let stamp = try await value(forKey: ContentSyncService.Keys.stageRevisions)
        XCTAssertEqual(stamp, ContentSyncService.stageRevisionsStamp)
    }

    /// The hadith stage keeps a fingerprint per collection: when it runs, a
    /// collection whose file is unchanged and whose rows are all there is
    /// left alone, and one with rows missing is imported again.
    func testHadithCollectionsImportAgainOnlyWhenChangedOrIncomplete() async throws {
        try XCTSkipIf(
            SeedBundle.manifest() == nil,
            "SeedData resources are not visible to this test host; skipping bundle-dependent seed test"
        )
        let catalog = try XCTUnwrap(SeedBundle.hadithCatalog())
        let collections = catalog.books.filter { $0.hadithCount > 0 }
        let emptied = try XCTUnwrap(collections.min { $0.hadithCount < $1.hadithCount })
        _ = try await service.importSeedDataIfNeeded()
        try await mark("hadith_entries", column: "grades", oneRowPerGroup: "book_id", in: collections.map(\.id))

        try await database.connection.execute("DELETE FROM hadith_entries WHERE book_id = ?", [.text(emptied.id)])
        try await setValue("changed", forKey: ContentSyncService.Keys.stageFingerprint(.hadith))
        try await deleteKey(ContentSyncService.Keys.seedVersion)
        let imported = try await service.importSeedDataIfNeeded()

        XCTAssertEqual(imported, catalog.books.count + emptied.hadithCount)
        let restored = try await hadithRepository.entryCount(bookID: emptied.id)
        XCTAssertEqual(restored, emptied.hadithCount)
        let untouched = try await marked("hadith_entries", column: "grades", oneRowPerGroup: "book_id", in: collections.map(\.id))
        XCTAssertEqual(untouched, Set(collections.map(\.id)).subtracting([emptied.id]))
    }

    /// A device an earlier build imported has per-stage version stamps and no
    /// fingerprints. A stage whose files are still those earlier builds
    /// shipped is adopted, not imported again; library and media always
    /// import once more, to drop rows the seed no longer carries.
    func testEarlierImportsOfUnchangedFilesAreAdopted() async throws {
        try XCTSkipIf(
            SeedBundle.manifest() == nil,
            "SeedData resources are not visible to this test host; skipping bundle-dependent seed test"
        )
        _ = try await service.importSeedDataIfNeeded()
        // One row each stage would rewrite if it imported again.
        let sentinels: [(stage: SeedStage, table: String, column: String)] = [
            (.quran, "quran_editions", "author"),
            (.quranTranslations, "quran_translations", "text"),
            (.quranTafsir, "quran_tafsir", "source_url"),
            (.bookPages, "book_pages", "validator"),
        ]
        for sentinel in sentinels {
            try await database.connection.execute(
                "UPDATE \(sentinel.table) SET \(sentinel.column) = 'adoption-sentinel' WHERE rowid = (SELECT MIN(rowid) FROM \(sentinel.table))"
            )
        }

        // As an earlier build left it.
        try await database.connection.execute("DELETE FROM key_value WHERE key LIKE 'seed.hash.%'")
        try await deleteKey(ContentSyncService.Keys.seedVersion)
        try await deleteKey(ContentSyncService.Keys.stageRevisions)
        for stage in ["quran", "library", "media", "events", "bookPages", "hadith"] {
            try await setValue("44", forKey: "seed.version.\(stage)")
        }
        let imported = try await service.importSeedDataIfNeeded()
        XCTAssertGreaterThanOrEqual(imported, SeedBundle.libraryItems().count + SeedBundle.mediaItems().count)

        let hadithIDs = SeedBundle.hadithCatalog()?.books.map(\.id) ?? []
        for sentinel in sentinels {
            let files = ContentSyncService.files(for: sentinel.stage, hadithBookIDs: hadithIDs)
            let bundled = SeedBundle.stageFingerprint(
                stage: sentinel.stage.rawValue,
                revision: sentinel.stage.revision,
                files: files.map { (name: $0, digest: SeedBundle.digest(ofFile: $0)) }
            )
            let rows = try await database.connection.query(
                "SELECT COUNT(*) AS n FROM \(sentinel.table) WHERE \(sentinel.column) = 'adoption-sentinel'"
            )
            let kept = (rows.first?.int("n") ?? 0) == 1
            if ContentSyncService.earlierImports[sentinel.stage]?.fingerprint == bundled {
                XCTAssertTrue(kept, "\(sentinel.stage) should have been adopted")
            } else {
                XCTAssertFalse(kept, "\(sentinel.stage) changed since, so it imports")
            }
        }
    }

    // MARK: - Helpers

    private func setValue(_ value: String, forKey key: String) async throws {
        try await database.connection.execute(
            """
            INSERT INTO key_value (key, value, updated_at) VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """,
            [.text(key), .text(value), .date(Date())]
        )
    }

    private func value(forKey key: String) async throws -> String? {
        let rows = try await database.connection.query("SELECT value FROM key_value WHERE key = ?", [.text(key)])
        return rows.first?.text("value")
    }

    private func deleteKey(_ key: String) async throws {
        try await database.connection.execute("DELETE FROM key_value WHERE key = ?", [.text(key)])
    }

    /// Marks one row per group (say per collection) with a value an import
    /// would overwrite, so a group imported again can be told apart.
    private func mark(_ table: String, column: String, oneRowPerGroup group: String, in ids: [String]) async throws {
        for id in ids {
            try await database.connection.execute(
                """
                UPDATE \(table) SET \(column) = 'adoption-sentinel' WHERE rowid =
                    (SELECT MIN(rowid) FROM \(table) WHERE \(group) = ?)
                """,
                [.text(id)]
            )
        }
    }

    private func marked(_ table: String, column: String, oneRowPerGroup group: String, in ids: [String]) async throws -> Set<String> {
        var marked: Set<String> = []
        for id in ids {
            let rows = try await database.connection.query(
                "SELECT COUNT(*) AS n FROM \(table) WHERE \(group) = ? AND \(column) = 'adoption-sentinel'",
                [.text(id)]
            )
            if (rows.first?.int("n") ?? 0) == 1 { marked.insert(id) }
        }
        return marked
    }
}
