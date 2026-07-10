import Foundation
import XCTest
@testable import DarulIrfan

/// Tests for `ContentRepository`: filtering, favorites, and reading progress
/// against an in-memory store.
final class ContentRepositoryTests: XCTestCase {

    private var database: AppDatabase!
    private var repository: ContentRepository!

    override func setUp() async throws {
        database = try await AppDatabase.inMemory()
        repository = ContentRepository(database: database)
    }

    override func tearDown() {
        repository = nil
        database = nil
    }

    // MARK: - Fixtures

    private func makeItem(
        id: String,
        title: String,
        type: ContentType,
        category: ContentCategory,
        language: String,
        publishedAt: Date?,
        bodyPlainText: String? = nil
    ) -> ContentItem {
        ContentItem(
            id: id,
            sourceUrl: "https://www.naqshbandiaowaisiah.org/\(id).html",
            type: type,
            title: title,
            titleUrdu: nil,
            language: language,
            author: nil,
            category: category,
            bodyHtml: nil,
            bodyPlainText: bodyPlainText,
            excerpt: nil,
            publishedAt: publishedAt,
            updatedAt: nil,
            mediaUrls: [],
            downloadUrls: ["https://www.naqshbandiaowaisiah.org/uploads/books/\(id).pdf"],
            checksum: nil,
            rightsStatus: .linkOnly
        )
    }

    private func seedThreeItems() async throws -> (ContentItem, ContentItem, ContentItem) {
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_800_000_000)
        let bookEnglish = makeItem(
            id: "book-en", title: "Book in English", type: .book,
            category: .books, language: "en", publishedAt: older
        )
        let articleUrdu = makeItem(
            id: "article-ur", title: "Article in Urdu", type: .article,
            category: .articles, language: "ur", publishedAt: newer
        )
        let bookUrduUndated = makeItem(
            id: "book-ur", title: "Book in Urdu", type: .book,
            category: .books, language: "ur", publishedAt: nil
        )
        try await repository.upsertItems([bookEnglish, articleUrdu, bookUrduUndated])
        return (bookEnglish, articleUrdu, bookUrduUndated)
    }

    // MARK: - Filtering

    func testItemsFilterByCategory() async throws {
        let (bookEnglish, _, bookUrduUndated) = try await seedThreeItems()

        let books = try await repository.items(
            category: .books, type: nil, language: nil, limit: 50
        )
        // Dated first (published DESC), undated trail.
        XCTAssertEqual(books.map { $0.id }, [bookEnglish.id, bookUrduUndated.id])
    }

    func testItemsFilterByLanguageAndType() async throws {
        let (_, articleUrdu, bookUrduUndated) = try await seedThreeItems()

        let urdu = try await repository.items(
            category: nil, type: nil, language: "ur", limit: 50
        )
        XCTAssertEqual(urdu.map { $0.id }, [articleUrdu.id, bookUrduUndated.id])

        let articles = try await repository.items(
            category: nil, type: .article, language: nil, limit: 50
        )
        XCTAssertEqual(articles.map { $0.id }, [articleUrdu.id])

        // Combined filters intersect.
        let urduBooks = try await repository.items(
            category: .books, type: nil, language: "ur", limit: 50
        )
        XCTAssertEqual(urduBooks.map { $0.id }, [bookUrduUndated.id])
    }

    func testItemsRespectLimitAndOrderNewestFirst() async throws {
        let (_, articleUrdu, _) = try await seedThreeItems()

        let firstOnly = try await repository.items(
            category: nil, type: nil, language: nil, limit: 1
        )
        // The single newest-dated item wins the limit-1 query.
        XCTAssertEqual(firstOnly.map { $0.id }, [articleUrdu.id])
    }

    func testItemByIDRoundtripIncludingJSONArrayColumns() async throws {
        let (bookEnglish, _, _) = try await seedThreeItems()

        let fetched = try await repository.item(id: bookEnglish.id)
        XCTAssertEqual(fetched, bookEnglish)
        XCTAssertEqual(
            fetched?.downloadUrls,
            ["https://www.naqshbandiaowaisiah.org/uploads/books/book-en.pdf"]
        )

        let missing = try await repository.item(id: "does-not-exist")
        XCTAssertNil(missing)
    }

    // MARK: - Favorites

    func testFavoritesAddListNewestFirstAndRemove() async throws {
        let older = Favorite(
            id: UUID(),
            contentItemID: "book-en",
            mediaItemID: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let newer = Favorite(
            id: UUID(),
            contentItemID: nil,
            mediaItemID: "lecture-3725",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try await repository.addFavorite(older)
        try await repository.addFavorite(newer)

        let favorites = try await repository.favorites()
        XCTAssertEqual(favorites.map { $0.id }, [newer.id, older.id])
        XCTAssertEqual(favorites[0].mediaItemID, "lecture-3725")
        XCTAssertNil(favorites[0].contentItemID)

        try await repository.removeFavorite(id: older.id)
        let remaining = try await repository.favorites()
        XCTAssertEqual(remaining.map { $0.id }, [newer.id])
    }

    // MARK: - Reading progress

    func testReadingProgressSaveOverwriteAndRead() async throws {
        let none = try await repository.readingProgress(contentItemID: "book-en")
        XCTAssertNil(none)

        let initial = ContentReadingProgress(
            contentItemID: "book-en",
            fraction: 0.25,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await repository.saveReadingProgress(initial)
        let saved = try await repository.readingProgress(contentItemID: "book-en")
        XCTAssertEqual(saved, initial)

        // Saving again for the same item overwrites (primary-keyed upsert).
        let updated = ContentReadingProgress(
            contentItemID: "book-en",
            fraction: 0.8,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        try await repository.saveReadingProgress(updated)
        let latest = try await repository.readingProgress(contentItemID: "book-en")
        XCTAssertEqual(latest?.fraction ?? 0, 0.8, accuracy: 0.000001)
    }

    // MARK: - Collections

    func testCollectionsRoundtrip() async throws {
        let collection = ContentCollection(
            id: "almurshid-1981",
            title: "Al-Murshid 1981",
            category: .alMurshidMagazine,
            itemIDs: ["magazine-feb-mar-1981", "magazine-may-1983"]
        )
        try await repository.upsertCollections([collection])

        let collections = try await repository.collections()
        XCTAssertEqual(collections, [collection])
    }
}
