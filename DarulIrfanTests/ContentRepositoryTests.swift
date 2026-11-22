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

    func testCategoryCountsMatchItemsWithoutLoadingBodies() async throws {
        _ = try await seedThreeItems()
        let counts = try await repository.categoryCounts()
        XCTAssertEqual(counts[.books], 2)
        XCTAssertEqual(counts[.articles], 1)
        XCTAssertEqual(counts.values.reduce(0, +), 3)
    }

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

    // MARK: - Book pages

    /// A page's layout is stored and read back with it; a page can have none,
    /// and a page imported again without one loses it.
    func testBookPageLayoutRoundtrip() async throws {
        let laidOut = BookPage(bookID: "book-ur", page: 3, text: "باب اول\n\nانسان جو چیز بناتا ہے۔", blocks: 2,
                               unresolvedBlocks: 0, layout: "hp")
        let plain = BookPage(bookID: "book-ur", page: 4, text: "انسان جو چیز بناتا ہے۔", blocks: 1,
                             unresolvedBlocks: 0)
        try await repository.upsertBookPages([laidOut, plain])
        let pages = try await repository.bookPages(bookID: "book-ur")
        XCTAssertEqual(pages, [laidOut, plain])
        XCTAssertEqual(pages.first?.layout, "hp")
        XCTAssertNil(pages.last?.layout)

        var withoutLayout = laidOut
        withoutLayout.layout = nil
        try await repository.upsertBookPages([withoutLayout])
        let updated = try await repository.bookPages(bookID: "book-ur")
        XCTAssertNil(updated.first?.layout)
        XCTAssertEqual(updated.first?.text, laidOut.text)
    }

    /// Schema v10 gives the book pages table its layout column.
    func testBookPagesTableHasALayoutColumn() async throws {
        let columns = try await database.connection.query("SELECT name FROM pragma_table_info('book_pages')")
        XCTAssertTrue(columns.compactMap { $0.text("name") }.contains("layout"))
    }

    /// The retired keys are optional in the seed: a page decodes with them
    /// and without them.
    func testBookPageDecodesWithAndWithoutTheRetiredKeys() throws {
        let json = """
        [{"bookID":"b","page":1,"text":"t","blocks":1,"unresolvedBlocks":0,"reviewState":"final","validator":""},
         {"bookID":"b","page":2,"text":"t","blocks":1,"unresolvedBlocks":0}]
        """
        let pages = try JSONDecoder().decode([BookPage].self, from: Data(json.utf8))
        XCTAssertEqual(pages.map(\.page), [1, 2])
    }

    /// An import writes the retired page columns empty.
    func testImportLeavesTheRetiredPageColumnsEmpty() async throws {
        let page = BookPage(bookID: "book-ur", page: 1, text: "page", blocks: 1, unresolvedBlocks: 0)
        try await repository.upsertBookPages([page])
        let rows = try await database.connection.query("SELECT review_state, validator FROM book_pages")
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.text("review_state"), "")
        XCTAssertNil(row.text("validator"))
    }

    /// Schema v11 clears what earlier builds stored in the retired columns
    /// and keeps the text.
    func testSchemaV11ClearsTheRetiredColumns() async throws {
        try await database.connection.execute(
            "INSERT INTO book_pages (book_id, page, text, review_state, validator) VALUES ('b', 1, 'page', 'old', 'old')"
        )
        try await database.connection.execute(
            """
            INSERT INTO hadith_entries (canonical_id, book_id, display_number, number_major, source_sequence,
                text_ur, english_review_state, urdu_review_state, urdu_source)
            VALUES ('b|1|1', 'b', '1', 1, 1, 'narration', 'old', 'old', 'old')
            """
        )
        try await database.connection.executeScript(AppDatabase.migrationV11)

        let pages = try await database.connection.query("SELECT text, review_state, validator FROM book_pages")
        let page = try XCTUnwrap(pages.first)
        XCTAssertEqual(page.text("text"), "page")
        XCTAssertEqual(page.text("review_state"), "")
        XCTAssertNil(page.text("validator"))

        let entries = try await database.connection.query(
            "SELECT text_ur, english_review_state, urdu_review_state, urdu_source FROM hadith_entries"
        )
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.text("text_ur"), "narration")
        for column in ["english_review_state", "urdu_review_state", "urdu_source"] {
            XCTAssertNil(entry.text(column), column)
        }
    }
}
