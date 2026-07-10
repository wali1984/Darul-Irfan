import Foundation
import XCTest
@testable import DarulIrfan

/// Tests for `SearchIndexService` over the FTS5 `search_index` table, using
/// real repositories on an in-memory store: seed rows → reindex → query.
final class SearchIndexServiceTests: XCTestCase {

    private var database: AppDatabase!
    private var quranRepository: QuranRepository!
    private var contentRepository: ContentRepository!
    private var mediaRepository: MediaRepository!
    private var eventsRepository: EventsRepository!
    private var service: SearchIndexService!

    override func setUp() async throws {
        database = try await AppDatabase.inMemory()
        quranRepository = QuranRepository(database: database)
        contentRepository = ContentRepository(database: database)
        mediaRepository = MediaRepository(database: database)
        eventsRepository = EventsRepository(database: database)
        service = SearchIndexService(
            database: database,
            quranRepository: quranRepository,
            contentRepository: contentRepository,
            mediaRepository: mediaRepository,
            eventsRepository: eventsRepository
        )
    }

    override func tearDown() {
        service = nil
        eventsRepository = nil
        mediaRepository = nil
        contentRepository = nil
        quranRepository = nil
        database = nil
    }

    // MARK: - Seeding

    /// Seeds one row per domain:
    /// - Quran: Surah Al-Fatihah 1:1 (the basmalah, public-domain Arabic).
    /// - Library: "Method of Zikr" page whose body uses verified wording from
    ///   Docs/RESEARCH_NOTES.md ("Pas Anfas — guarding every breath").
    /// - Media: verified sample lecture title «دعوت و تبلیغ کے اصول».
    /// - Events: "Monthly Ijtema".
    private func seedAllDomains() async throws {
        try await quranRepository.upsertSurahs([
            QuranSurah(
                id: 1,
                nameArabic: "الفاتحة",
                nameTransliterated: "Al-Fatihah",
                nameEnglish: "The Opening",
                nameUrdu: nil,
                ayahCount: 7,
                revelationPlace: .makkah
            )
        ])
        try await quranRepository.upsertAyahs([
            QuranAyah(surahNumber: 1, ayahNumber: 1, textArabic: "بسم الله الرحمن الرحيم")
        ])

        try await contentRepository.upsertItems([
            ContentItem(
                id: "method-of-zikr",
                sourceUrl: "https://www.naqshbandiaowaisiah.org/method-of-zikr.html",
                type: .page,
                title: "Method of Zikr",
                titleUrdu: nil,
                language: "en",
                author: nil,
                category: .methodOfZikr,
                bodyHtml: nil,
                bodyPlainText: "Zikr-e Khafi Qalbi with Pas Anfas, guarding every breath.",
                excerpt: nil,
                publishedAt: nil,
                updatedAt: nil,
                mediaUrls: [],
                downloadUrls: [],
                checksum: nil,
                rightsStatus: .publicDomain
            )
        ])

        try await mediaRepository.upsertItems([
            MediaItem(
                id: "lecture-3725",
                title: "دعوت و تبلیغ کے اصول",
                language: "ur",
                speaker: "Hazrat Ameer Abdul Qadeer Awan (MZA)",
                date: nil,
                durationSeconds: nil,
                mediaType: .audio,
                sourceUrl: "https://www.naqshbandiaowaisiah.org/lecture/3725/2026-01-02-dawat-o-tabligh-ke-usool.html",
                streamUrl: "https://www.naqshbandiaowaisiah.org/uploads/3725/02-01-2026.mp3",
                downloadUrl: nil,
                youtubeId: nil,
                year: 2026,
                month: 1,
                category: .audioLectures,
                transcriptUrl: nil,
                rightsStatus: .linkOnly
            )
        ])

        try await eventsRepository.upsertEvents([
            CommunityEvent(
                id: "monthly-ijtema",
                kind: .monthlyIjtema,
                title: "Monthly Ijtema",
                titleUrdu: nil,
                details: "Monthly gathering at Dar ul Irfan, Munara.",
                startDate: nil,
                endDate: nil,
                datesAreApproximate: true,
                venue: "Dar ul Irfan, Munara",
                sourceUrl: nil,
                updatedAt: nil
            )
        ])

        try await service.reindex(domains: SearchDomain.allCases)
    }

    // MARK: - Queries

    func testArabicTermMatchesQuranDomain() async throws {
        try await seedAllDomains()

        let results = try await service.search("الرحمن", domains: [.quran], limit: 20)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.domain, .quran)
        XCTAssertEqual(results.first?.itemID, "1:1", "Ayah rows are keyed surah:ayah")
    }

    func testEnglishTermMatchesLibraryBody() async throws {
        try await seedAllDomains()

        let results = try await service.search("breath", domains: [.library], limit: 20)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.itemID, "method-of-zikr")
        XCTAssertEqual(results.first?.title, "Method of Zikr")
    }

    func testUrduTermMatchesMediaTitle() async throws {
        try await seedAllDomains()

        let results = try await service.search("تبلیغ", domains: [.media], limit: 20)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.itemID, "lecture-3725")
    }

    func testEmptyAndWhitespaceQueriesReturnNothing() async throws {
        try await seedAllDomains()

        let empty = try await service.search("", domains: SearchDomain.allCases, limit: 20)
        XCTAssertTrue(empty.isEmpty)

        let whitespace = try await service.search("   \n", domains: SearchDomain.allCases, limit: 20)
        XCTAssertTrue(whitespace.isEmpty)
    }

    func testDomainFilterExcludesOtherDomains() async throws {
        try await seedAllDomains()

        // "breath" only exists in the library row; restricting the search to
        // media/events must therefore return nothing.
        let filtered = try await service.search("breath", domains: [.media, .events], limit: 20)
        XCTAssertTrue(filtered.isEmpty)

        // And an empty domain list returns nothing by contract.
        let noDomains = try await service.search("breath", domains: [], limit: 20)
        XCTAssertTrue(noDomains.isEmpty)
    }

    func testEventsDomainIsSearchable() async throws {
        try await seedAllDomains()

        let results = try await service.search("Ijtema", domains: [.events], limit: 20)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.itemID, "monthly-ijtema")
    }

    func testPrefixMatchingFindsPartialTerms() async throws {
        try await seedAllDomains()

        // Terms get a trailing '*' → "guard" matches "guarding".
        let results = try await service.search("guard", domains: [.library], limit: 20)
        XCTAssertEqual(results.map { $0.itemID }, ["method-of-zikr"])
    }

    func testReindexIsIdempotentNoDuplicateRows() async throws {
        try await seedAllDomains()
        // Second full rebuild must replace, not append.
        try await service.reindex(domains: SearchDomain.allCases)

        let results = try await service.search("breath", domains: [.library], limit: 20)
        XCTAssertEqual(results.count, 1, "Reindexing twice must not duplicate index rows")
    }

    func testQuoteInjectionInQueryIsNeutralized() async throws {
        try await seedAllDomains()

        // A query full of FTS5 operators/quotes must be treated as literal
        // terms — "no results", never a thrown syntax error.
        let hostile = try await service.search(
            "\"breath\" OR NEAR( AND",
            domains: SearchDomain.allCases,
            limit: 20
        )
        // The stripped terms still include "breath", "OR", "NEAR(", "AND" —
        // all quoted as literals and ANDed, so nothing matches; the essential
        // assertion is that this call returns instead of throwing.
        XCTAssertTrue(hostile.isEmpty)
    }
}
