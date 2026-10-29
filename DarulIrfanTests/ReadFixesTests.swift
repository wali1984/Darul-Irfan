import XCTest
@testable import DarulIrfan

/// Smaller reading fixes from the audit: surah search spellings, typed ayah
/// references, the order of the Qur'an volumes in the library, topic ayah
/// references, and one favourite per item.
final class ReadFixesTests: XCTestCase {

    @MainActor
    func testSurahSearchFindsTheUsualSpellings() async throws {
        let surahs = SeedBundle.quranSurahs()
        try XCTSkipIf(surahs.isEmpty, "surah index not bundled in this configuration")
        let database = try await AppDatabase.inMemory()
        let repository = QuranRepository(database: database)
        try await repository.upsertSurahs(surahs)
        let viewModel = QuranViewModel(repository: repository)
        await viewModel.load()
        let expectations: [(String, Int)] = [
            ("fatiha", 1), ("Fatihah", 1), ("baqarah", 2), ("imran", 3), ("yasin", 36), ("rahman", 55),
            ("waqiah", 56), ("muzammil", 73), ("ikhlas", 112), ("البقرة", 2), ("الرحمن", 55), ("بقرہ", 2),
            ("فاتحہ", 1), ("یسین", 36), ("کہف", 18), ("bani israil", 17),
        ]
        for (query, surah) in expectations {
            viewModel.searchText = query
            XCTAssertTrue(viewModel.filteredSurahs.contains { $0.id == surah }, "\(query) should find surah \(surah)")
        }
        viewModel.searchText = "2:255"
        XCTAssertEqual(viewModel.typedAyah?.surah.id, 2)
        XCTAssertEqual(viewModel.typedAyah?.ayah, 255)
        viewModel.searchText = "2:300"
        XCTAssertNil(viewModel.typedAyah)
    }

    @MainActor
    func testQuranVolumesSortInQuranOrder() {
        func item(_ id: String) -> ContentItem {
            ContentItem(
                id: id, sourceUrl: "", type: .book, title: id, titleUrdu: nil, language: "ur",
                author: nil, category: .quranTafsir, bodyHtml: nil, bodyPlainText: nil, excerpt: nil,
                publishedAt: nil, updatedAt: nil, mediaUrls: [], downloadUrls: [], checksum: nil,
                rightsStatus: .permissionConfirmed
            )
        }
        let ids = ["asrar-10-ur", "tafaseer-parah-10", "asrar-2-en", "tafaseer-parah-2", "asrar-2-ur"]
        let sorted = ids.map(item).sorted {
            LibraryViewModel.quranOrder($0).lexicographicallyPrecedes(LibraryViewModel.quranOrder($1))
        }
        XCTAssertEqual(sorted.map(\.id), ["tafaseer-parah-2", "tafaseer-parah-10", "asrar-2-ur", "asrar-2-en", "asrar-10-ur"])

        let tarajum = ["tarajum-Akram-ut-Tarajum-Parah-1-to-30.pdf", "tarajum-Akram-ut-Tarajum-Parah10.pdf",
                       "tarajum-Akram-ut-Tarajum-Parah-16-to-30.pdf", "tarajum-Akram-ut-Tarajum-Parah02.pdf",
                       "tarajum-Akram-ut-Tarajum-Parah-1-to-15.pdf"]
        let sortedTarajum = tarajum.map(item).sorted {
            LibraryViewModel.quranOrder($0).lexicographicallyPrecedes(LibraryViewModel.quranOrder($1))
        }
        XCTAssertEqual(sortedTarajum.map(\.id), [
            "tarajum-Akram-ut-Tarajum-Parah02.pdf", "tarajum-Akram-ut-Tarajum-Parah10.pdf",
            "tarajum-Akram-ut-Tarajum-Parah-1-to-15.pdf", "tarajum-Akram-ut-Tarajum-Parah-16-to-30.pdf",
            "tarajum-Akram-ut-Tarajum-Parah-1-to-30.pdf",
        ])
    }

    /// A reference that cannot name real ayat is refused instead of building
    /// a range that stops the app.
    func testTopicAyahReferencesRejectImpossibleRanges() {
        XCTAssertNil(AyahRef("2:257-255"))
        XCTAssertNil(AyahRef("2:0"))
        XCTAssertNil(AyahRef("115:1"))
        XCTAssertEqual(AyahRef("33:41-42")?.end, 42)
        XCTAssertEqual(AyahRef("13:28")?.start, 28)
    }

    func testAnItemIsFavouritedOnce() async throws {
        let database = try await AppDatabase.inMemory()
        let repository = ContentRepository(database: database)
        let first = Favorite(id: UUID(), contentItemID: "book-1", mediaItemID: nil, createdAt: Date())
        let second = Favorite(id: UUID(), contentItemID: "book-1", mediaItemID: nil, createdAt: Date())
        try await repository.addFavorite(first)
        try await repository.addFavorite(second)
        let favourites = try await repository.favorites()
        XCTAssertEqual(favourites.count, 1)
        try await repository.removeFavorite(id: first.id)
        let afterRemoval = try await repository.favorites()
        XCTAssertTrue(afterRemoval.isEmpty)
    }
}
