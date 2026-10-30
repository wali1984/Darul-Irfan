import XCTest
@testable import DarulIrfan

/// The Read tab's redesign: the hadith collections in three groups, a Books
/// shelf of one item opening that item, turning printed pages that skip
/// blank ones, and search in a book's text.
final class ReadRedesignTests: XCTestCase {

    // MARK: - Hadith groups

    private func collection(_ id: String, english: Bool = true, urdu: Bool = true) -> HadithBook {
        HadithBook(
            id: id,
            titleEnglish: id,
            titleUrdu: id,
            hadithCount: 100,
            hasArabic: true,
            hasEnglish: english,
            hasUrdu: urdu,
            sectionCount: 0,
            sections: nil
        )
    }

    func testHadithCollectionsFallIntoThreeGroups() {
        // In the repository's reading order (HadithRepository.collectionOrder).
        let books = [
            collection("bukhari"), collection("muslim"), collection("abudawud"),
            collection("tirmidhi"), collection("nasai"), collection("ibnmajah"),
            collection("malik"), collection("ahmad", urdu: false),
            collection("darimi", english: false, urdu: false),
            collection("riyadussalihin", urdu: false), collection("mishkat"),
            collection("ibnabishayba", english: false, urdu: false),
        ]
        let groups = HadithCollectionGroup.groups(from: books)
        XCTAssertEqual(groups.map(\.kind), [.sahihainAndSunan, .more, .arabicOnly])
        XCTAssertEqual(groups[0].books.map(\.id), ["bukhari", "muslim", "abudawud", "tirmidhi", "nasai", "ibnmajah"])
        XCTAssertEqual(groups[1].books.map(\.id), ["malik", "ahmad", "riyadussalihin", "mishkat"])
        XCTAssertEqual(groups[2].books.map(\.id), ["darimi", "ibnabishayba"])
    }

    func testTheSixKeepTheirOrderWhereverTheyArrive() {
        let books = [collection("ibnmajah"), collection("malik"), collection("muslim"), collection("bukhari")]
        let groups = HadithCollectionGroup.groups(from: books)
        XCTAssertEqual(groups.first?.books.map(\.id), ["bukhari", "muslim", "ibnmajah"])
    }

    func testMoreCollectionsAndArabicOnlyFoldBeyondTheirFirstFew() {
        let books = [
            collection("bukhari"),
            collection("malik"), collection("ahmad"), collection("riyadussalihin"), collection("mishkat"),
            collection("darimi", english: false, urdu: false), collection("bayhaqi", english: false, urdu: false),
        ]
        let groups = HadithCollectionGroup.groups(from: books)
        let six = groups[0], more = groups[1], arabic = groups[2]

        XCTAssertFalse(six.isFoldable)
        XCTAssertEqual(six.visibleBooks(expanded: false).count, 1)

        XCTAssertTrue(more.isFoldable)
        XCTAssertEqual(more.visibleBooks(expanded: false).map(\.id), ["malik", "ahmad", "riyadussalihin"])
        XCTAssertEqual(more.visibleBooks(expanded: true).count, 4)

        XCTAssertTrue(arabic.isFoldable)
        XCTAssertEqual(arabic.visibleBooks(expanded: false).map(\.id), ["darimi"])
        XCTAssertEqual(arabic.visibleBooks(expanded: true).count, 2)
    }

    func testAGroupWithNothingInItIsLeftOut() {
        let groups = HadithCollectionGroup.groups(from: [collection("bukhari"), collection("malik")])
        XCTAssertEqual(groups.map(\.kind), [.sahihainAndSunan, .more])
        XCTAssertFalse(groups[1].isFoldable, "Three or fewer show without Show all")
        XCTAssertTrue(HadithCollectionGroup.groups(from: []).isEmpty)
    }

    // MARK: - Books shelves

    private func libraryItem(_ id: String, category: ContentCategory, type: ContentType = .book) -> ContentItem {
        ContentItem(
            id: id, sourceUrl: "", type: type, title: id, titleUrdu: nil, language: "ur",
            author: nil, category: category, bodyHtml: nil, bodyPlainText: nil, excerpt: nil,
            publishedAt: nil, updatedAt: nil, mediaUrls: [], downloadUrls: [], checksum: nil,
            rightsStatus: .permissionConfirmed
        )
    }

    private func shelf(_ id: String) throws -> LibraryShelf {
        let all = LibraryShelf.publications + LibraryShelf.quranVolumes
        return try XCTUnwrap(all.first { $0.id == id })
    }

    @MainActor
    func testAShelfOfOneItemOpensThatItem() async throws {
        let database = try await AppDatabase.inMemory()
        let repository = ContentRepository(database: database)
        try await repository.upsertItems([
            libraryItem("book-only", category: .books),
            libraryItem("booklet-1", category: .booklets, type: .booklet),
            libraryItem("booklet-2", category: .booklets, type: .booklet),
            libraryItem("course-1", category: .trainingCourses),
        ])
        let viewModel = LibraryViewModel(contentRepository: repository)
        await viewModel.reloadHome()

        XCTAssertEqual(viewModel.target(for: try shelf("books")), .item(id: "book-only"))
        XCTAssertEqual(viewModel.soleItem(for: [.books])?.id, "book-only")
        XCTAssertEqual(viewModel.target(for: try shelf("booklets")), .category(.booklets))
        XCTAssertNil(viewModel.soleItem(for: [.booklets]))
        // Courses and documents: one course, no documents yet - the one item.
        XCTAssertEqual(viewModel.count(for: try shelf("courses")), 1)
        XCTAssertEqual(viewModel.target(for: try shelf("courses")), .item(id: "course-1"))
    }

    @MainActor
    func testAShelfOfTwoCategoriesListsBothOnceItHoldsMore() async throws {
        let database = try await AppDatabase.inMemory()
        let repository = ContentRepository(database: database)
        try await repository.upsertItems([
            libraryItem("course-1", category: .trainingCourses),
            libraryItem("document-1", category: .importantDocuments, type: .document),
        ])
        let viewModel = LibraryViewModel(contentRepository: repository)
        await viewModel.reloadHome()

        let courses = try shelf("courses")
        XCTAssertEqual(viewModel.count(for: courses), 2)
        XCTAssertEqual(viewModel.target(for: courses), .shelf, "Each category has one, but the shelf has two")
        let listed = await viewModel.items(in: courses.categories)
        XCTAssertEqual(Set(listed.map(\.id)), ["course-1", "document-1"])
    }

    func testTheBooksShelvesLeaveAboutTeachingsAndNewsToHalqahAndDiscover() {
        let listed = Set((LibraryShelf.publications + LibraryShelf.quranVolumes).flatMap(\.categories))
        let moved: [ContentCategory] = [
            .aboutSilsila, .sheikhAbdulQadeerAwan, .sheikhMuhammadAkramAwan, .shajra,
            .tasawwuf, .tazkiyahNafs, .zikrAllah, .methodOfZikr, .baiat,
            .announcements, .pressReleases, .featureArticles, .aqwalESheikh,
        ]
        for category in moved {
            XCTAssertFalse(listed.contains(category), "\(category) is not a Books shelf")
        }
        let kept: [ContentCategory] = [
            .books, .alMurshidMagazine, .booklets, .articles, .sufiPoetry,
            .trainingCourses, .importantDocuments, .quranTafsir, .quranTranslation,
        ]
        for category in kept {
            XCTAssertTrue(listed.contains(category), "\(category) has a Books shelf")
        }
    }

    // MARK: - Turning pages

    func testTurningPagesSkipsTheOnesAScanLeftOut() {
        let pages = [1, 2, 3, 5, 6]
        XCTAssertEqual(BookPageNavigator.page(after: 3, in: pages), 5)
        XCTAssertEqual(BookPageNavigator.page(before: 5, in: pages), 3)
        XCTAssertNil(BookPageNavigator.page(after: 6, in: pages))
        XCTAssertNil(BookPageNavigator.page(before: 1, in: pages))
        // A page between two that exist.
        XCTAssertEqual(BookPageNavigator.page(after: 4, in: pages), 5)
        XCTAssertEqual(BookPageNavigator.page(before: 4, in: pages), 3)
        XCTAssertEqual(BookPageNavigator.index(of: 4, in: pages), 2)
        // Before the first page.
        XCTAssertEqual(BookPageNavigator.page(after: 0, in: pages), 1)
        // The scrubber.
        XCTAssertEqual(BookPageNavigator.page(atPosition: 2.4, in: pages), 3)
        XCTAssertEqual(BookPageNavigator.page(atPosition: 9, in: pages), 6)
        XCTAssertEqual(BookPageNavigator.page(atPosition: -3, in: pages), 1)
        XCTAssertNil(BookPageNavigator.page(atPosition: 1, in: []))
    }

    // MARK: - Search in the book

    func testSearchInABookFindsWordsAsTheAppSearchDoes() {
        let pages = [
            BookPage(bookID: "b", page: 4, text: "ذکرِ الٰہی دل کی زندگی ہے", blocks: 1, unresolvedBlocks: 0,
                     reviewState: "claudeTranscribed", validator: "test"),
            BookPage(bookID: "b", page: 7, text: "بِسْمِ اللّٰهِ الرَّحْمٰنِ الرَّحِيْمِ", blocks: 1, unresolvedBlocks: 0,
                     reviewState: "machineProvisional", validator: "test"),
            BookPage(bookID: "b", page: 9, text: "The Method of Zikr", blocks: 1, unresolvedBlocks: 0,
                     reviewState: "claudeTranscribed", validator: "test"),
        ]
        let index = BookTextSearch.index(pages)
        XCTAssertEqual(BookTextSearch.pages(matching: "زندگی", in: index), [4])
        // Vowel marks are ignored, as in the app's search.
        XCTAssertEqual(BookTextSearch.pages(matching: "بسم", in: index), [7])
        XCTAssertEqual(BookTextSearch.pages(matching: "zikr", in: index), [9])
        XCTAssertTrue(BookTextSearch.pages(matching: "  ", in: index).isEmpty)

        // The passage is the page as written, marks and all.
        let passage = BookTextSearch.passage(for: "بسم", in: pages[1].text)
        XCTAssertEqual(passage, pages[1].text)
        XCTAssertNil(BookTextSearch.passage(for: "صلوٰۃ", in: pages[1].text))
    }

    func testAPassageKeepsWholeWordsAroundTheMatch() throws {
        let words = (1...60).map { "word\($0)" }.joined(separator: " ")
        let passage = try XCTUnwrap(BookTextSearch.passage(for: "word30", in: words, radius: 20))
        XCTAssertTrue(passage.contains("word30"))
        XCTAssertTrue(passage.hasPrefix("…"))
        XCTAssertTrue(passage.hasSuffix("…"))
        let inner = passage.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        for word in inner.split(separator: " ") {
            XCTAssertTrue(word.hasPrefix("word") && Int(word.dropFirst(4)) != nil, "\(word) is a whole word")
        }
    }
}
