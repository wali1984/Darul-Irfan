import Foundation
import XCTest
@testable import DarulIrfan

/// Round-trip tests for `QuranRepository` against an in-memory store.
final class QuranRepositoryTests: XCTestCase {

    private var database: AppDatabase!
    private var repository: QuranRepository!

    override func setUp() async throws {
        database = try await AppDatabase.inMemory()
        repository = QuranRepository(database: database)
    }

    override func tearDown() {
        repository = nil
        database = nil
    }

    // MARK: - Fixtures

    private func fatihah() -> QuranSurah {
        QuranSurah(
            id: 1,
            nameArabic: "الفاتحة",
            nameTransliterated: "Al-Fatihah",
            nameEnglish: "The Opening",
            nameUrdu: "الفاتحہ",
            ayahCount: 7,
            revelationPlace: .makkah
        )
    }

    private func ikhlas() -> QuranSurah {
        QuranSurah(
            id: 112,
            nameArabic: "الإخلاص",
            nameTransliterated: "Al-Ikhlas",
            nameEnglish: "The Sincerity",
            nameUrdu: nil,
            ayahCount: 4,
            revelationPlace: .makkah
        )
    }

    // MARK: - Surahs & ayahs

    @MainActor
    func testReaderRetriesSamePositionAfterFailedSave() async throws {
        let surah = fatihah()
        try await repository.upsertSurahs([surah])
        try await repository.upsertAyahs([
            QuranAyah(surahNumber: 1, ayahNumber: 1, textArabic: "Reader persistence fixture")
        ])
        let metrics = DevotionalMetricsSyncService(quranRepository: repository,
            trackerRepository: TrackerRepository(database: database), watchSync: WatchSyncService())
        let model = SurahReaderViewModel(surah: surah, repository: repository, devotionalMetrics: metrics)
        await model.load()
        XCTAssertEqual(model.phase, .ready)
        model.topAyahChanged(1)
        try await database.connection.executeScript("""
            CREATE TRIGGER reject_reader_save BEFORE INSERT ON quran_reading_progress
            BEGIN SELECT RAISE(ABORT, 'Injected storage failure'); END;
            """)
        await model.flushLastRead()
        let failed = try await repository.lastReadPosition()
        XCTAssertNil(failed)
        try await database.connection.executeScript("DROP TRIGGER reject_reader_save;")
        // No new scroll event: leaving again must retry the exact same ayah.
        await model.flushLastRead()
        let recovered = try await repository.lastReadPosition()
        XCTAssertEqual(recovered?.surahNumber, 1)
        XCTAssertEqual(recovered?.ayahNumber, 1)
    }

    func testSurahUpsertAndFetchRoundtrip() async throws {
        try await repository.upsertSurahs([ikhlas(), fatihah()])

        let surahs = try await repository.allSurahs()
        XCTAssertEqual(surahs.count, 2)
        // ORDER BY number ASC regardless of insert order.
        XCTAssertEqual(surahs.map { $0.id }, [1, 112])
        XCTAssertEqual(surahs[0], fatihah())
        XCTAssertEqual(surahs[1], ikhlas())

        // Upsert with a changed field updates in place — no duplicate row.
        var updated = fatihah()
        updated.nameEnglish = "The Opening Chapter"
        try await repository.upsertSurahs([updated])
        let afterUpdate = try await repository.allSurahs()
        XCTAssertEqual(afterUpdate.count, 2)
        XCTAssertEqual(afterUpdate[0].nameEnglish, "The Opening Chapter")
    }

    func testAyahUpsertFetchAndSurahNumbersWithText() async throws {
        let ayahs = [
            QuranAyah(surahNumber: 1, ayahNumber: 2, textArabic: "Second ayah fixture text"),
            QuranAyah(surahNumber: 1, ayahNumber: 1, textArabic: "بسم الله الرحمن الرحيم"),
        ]
        try await repository.upsertAyahs(ayahs)

        let fetched = try await repository.ayahs(inSurah: 1)
        XCTAssertEqual(fetched.count, 2)
        // ORDER BY ayah_number ASC regardless of insert order.
        XCTAssertEqual(fetched.map { $0.ayahNumber }, [1, 2])
        XCTAssertEqual(fetched[0].textArabic, "بسم الله الرحمن الرحيم")

        // Other surahs have no text yet.
        let empty = try await repository.ayahs(inSurah: 2)
        XCTAssertTrue(empty.isEmpty)

        let withText = try await repository.surahNumbersWithText()
        XCTAssertEqual(withText, [1])
    }

    @MainActor
    func testParahOpeningMissingContentCanRecoverWithoutCachingPartialResults() async throws {
        let entries = [QuranPara(number: 1, surah: fatihah(), ayah: 1)]
        do {
            _ = try await QuranParas.openings(for: entries, repository: repository)
            XCTFail("Missing scripture must not become a successful empty opening")
        } catch QuranParas.OpeningError.missingContent {
            // The UI can offer Retry rather than silently omit the verse.
        }
        let arabic = "??? ???? ?????? ??????"
        try await repository.upsertAyahs([QuranAyah(surahNumber: 1, ayahNumber: 1, textArabic: arabic)])
        let recovered = try await QuranParas.openings(for: entries, repository: repository)
        XCTAssertEqual(recovered, [1: arabic])
    }

    @MainActor
    func testCancelledParahOpeningReadDoesNotReturnSuccessfulEmptyContent() async throws {
        let entries = [QuranPara(number: 1, surah: fatihah(), ayah: 1)]
        let repository = self.repository!
        let task = Task { @MainActor in
            try await QuranParas.openings(for: entries, repository: repository)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancellation must propagate to the screen lifecycle")
        } catch is CancellationError {
        }
    }

    // MARK: - Editions, translations, tafsir

    func testEditionTranslationAndTafsirRoundtrip() async throws {
        let edition = QuranEdition(
            id: "test-translation-en",
            title: "Test Translation",
            kind: .translation,
            language: "en",
            author: "Test Author",
            sourceUrl: "https://www.naqshbandiaowaisiah.org/akram-ut-tarajum",
            rightsStatus: .linkOnly,
            isAvailableOffline: true
        )
        try await repository.upsertEditions([edition])
        let editions = try await repository.editions()
        XCTAssertEqual(editions, [edition])

        let translation = QuranTranslation(
            editionID: edition.id,
            surahNumber: 1,
            ayahNumber: 1,
            text: "Translation fixture text"
        )
        try await repository.upsertTranslations([translation])
        let translations = try await repository.translations(
            editionID: edition.id, surahNumber: 1
        )
        XCTAssertEqual(translations, [translation])
        // Other surah → no rows.
        let none = try await repository.translations(editionID: edition.id, surahNumber: 2)
        XCTAssertTrue(none.isEmpty)

        let tafsir = QuranTafsir(
            editionID: "asrar-at-tanzil-en",
            surahNumber: 1,
            ayahStart: 1,
            ayahEnd: 7,
            text: "Tafsir fixture text",
            sourceUrl: "https://www.naqshbandiaowaisiah.org/asrar-at-tanzil/1229/tafseer-quran-in-english-surah-al-fatihah.html"
        )
        try await repository.upsertTafsir([tafsir])
        let fetchedTafsir = try await repository.tafsir(
            editionID: "asrar-at-tanzil-en", surahNumber: 1
        )
        XCTAssertEqual(fetchedTafsir, [tafsir])
    }

    // MARK: - Bookmarks

    func testBookmarkAddListNewestFirstAndRemove() async throws {
        let older = QuranBookmark(
            id: UUID(),
            surahNumber: 1,
            ayahNumber: 1,
            note: "Reflect on this",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let newer = QuranBookmark(
            id: UUID(),
            surahNumber: 112,
            ayahNumber: 1,
            note: nil,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try await repository.addBookmark(older)
        try await repository.addBookmark(newer)

        let bookmarks = try await repository.bookmarks()
        // ORDER BY created_at DESC → newest first.
        XCTAssertEqual(bookmarks.map { $0.id }, [newer.id, older.id])
        XCTAssertEqual(bookmarks[1].note, "Reflect on this")

        try await repository.removeBookmark(id: newer.id)
        let remaining = try await repository.bookmarks()
        XCTAssertEqual(remaining.map { $0.id }, [older.id])

        // Removing an id that does not exist is a harmless no-op.
        try await repository.removeBookmark(id: UUID())
        let unchanged = try await repository.bookmarks()
        XCTAssertEqual(unchanged.count, 1)
    }

    // MARK: - Last read position

    func testLastReadPositionUpsertKeepsLatest() async throws {
        let initiallyEmpty = try await repository.lastReadPosition()
        XCTAssertNil(initiallyEmpty)

        let first = ReadingProgress(
            surahNumber: 1,
            ayahNumber: 5,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await repository.saveLastReadPosition(first)

        // Same surah saved again → row is replaced, not duplicated.
        let sameSurahLater = ReadingProgress(
            surahNumber: 1,
            ayahNumber: 7,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        try await repository.saveLastReadPosition(sameSurahLater)
        let afterUpsert = try await repository.lastReadPosition()
        XCTAssertEqual(afterUpsert?.surahNumber, 1)
        XCTAssertEqual(afterUpsert?.ayahNumber, 7)

        // A more recent position in another surah wins the global
        // "continue reading" query (ORDER BY updated_at DESC).
        let otherSurahNewest = ReadingProgress(
            surahNumber: 112,
            ayahNumber: 2,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        try await repository.saveLastReadPosition(otherSurahNewest)
        let latest = try await repository.lastReadPosition()
        XCTAssertEqual(latest?.surahNumber, 112)
        XCTAssertEqual(latest?.ayahNumber, 2)
    }
}
