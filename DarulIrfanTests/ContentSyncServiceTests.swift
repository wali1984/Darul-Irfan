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
/// No network is touched: only `importSeedDataIfNeeded()` is exercised;
/// `refreshFromRemoteManifest()` is deliberately not called from tests.
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
        // Pre-stamp a seed version far above anything the bundle can carry;
        // the guard must short-circuit before touching any seed files.
        try await database.connection.execute(
            "INSERT INTO key_value (key, value, updated_at) VALUES (?, ?, ?)",
            [.text("seed.version"), .text("999999"), .date(Date())]
        )

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

        // Import triggers a full reindex, so the FTS table must have rows
        // whenever anything was imported.
        let indexRows = try await database.connection.query(
            "SELECT COUNT(*) AS row_count FROM search_index"
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
}
