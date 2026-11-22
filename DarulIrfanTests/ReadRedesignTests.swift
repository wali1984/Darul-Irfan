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
    func testSilsilaReadFailureIsNotAnEmptyCategoryAndCanRetry() async throws {
        let database = try await AppDatabase.inMemory()
        let repository = ContentRepository(database: database)
        try await repository.upsertItems([libraryItem("silsila-test", category: .aboutSilsila)])
        let model = LibraryViewModel(contentRepository: repository)
        // A filter chosen in Books must not hide Silsila navigation content.
        model.languageFilter = "ar"
        model.typeFilter = .document
        try await database.connection.execute("ALTER TABLE content_items RENAME TO unavailable_content_items")
        do {
            _ = try await model.silsilaItems(in: .aboutSilsila)
            XCTFail("A catalogue failure must reach the screen's Retry state")
        } catch {
            // Expected database failure, distinct from a legitimate empty result.
        }
        try await database.connection.execute("ALTER TABLE unavailable_content_items RENAME TO content_items")
        let recovered = try await model.silsilaItems(in: .aboutSilsila)
        XCTAssertEqual(recovered.map(\.id), ["silsila-test"])
        let empty = try await model.silsilaItems(in: .tasawwuf)
        XCTAssertTrue(empty.isEmpty)
    }

    @MainActor
    func testCancelledDownloadCannotReplaceImmediateRetryState() async throws {
        let database = try await AppDatabase.inMemory()
        let repository = ContentRepository(database: database)
        let downloads = DownloadsRepository(database: database)
        let manager = ControlledArticleDownloadManager()
        try await repository.upsertItems([libraryItem("download-race", category: .books)])
        let model = ContentItemDetailViewModel(itemID: "download-race", contentRepository: repository,
            downloadsRepository: downloads, downloadManager: manager)
        await model.load()
        let address = "https://example.com/book.pdf"
        let first = Task { await model.download(urlString: address) }
        while manager.pending.count < 1 { await Task.yield() }
        model.cancelDownload(urlString: address)
        let second = Task { await model.download(urlString: address) }
        while manager.pending.count < 2 { await Task.yield() }
        manager.pending[0].resume(throwing: CancellationError())
        await first.value
        XCTAssertEqual(model.downloadStates[address], .downloading)
        manager.pending[1].resume(throwing: URLError(.notConnectedToInternet))
        await second.value
        XCTAssertEqual(model.downloadStates[address], .failed)
    }

    @MainActor
    func testReturningToArticleKeepsLoadedContentButExplicitReloadStillWorks() async throws {
        let database = try await AppDatabase.inMemory()
        let repository = ContentRepository(database: database)
        let downloads = DownloadsRepository(database: database)
        try await repository.upsertItems([libraryItem("article-return", category: .tasawwuf)])
        let model = ContentItemDetailViewModel(itemID: "article-return", contentRepository: repository,
            downloadsRepository: downloads, downloadManager: DownloadManager(downloadsRepository: downloads))
        await model.loadIfNeeded()
        XCTAssertEqual(model.item?.id, "article-return")
        try await repository.deleteItems(ids: ["article-return"])
        await model.loadIfNeeded()
        XCTAssertEqual(model.item?.id, "article-return", "Navigation return must retain the current article")
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.loadFailed)
        await model.load()
        XCTAssertNil(model.item, "Explicit reload must still read current catalogue state")
    }

    @MainActor
    func testArticleReadFailureCanRetryAndMissingItemRemainsDistinct() async throws {
        let database = try await AppDatabase.inMemory()
        let repository = ContentRepository(database: database)
        let downloads = DownloadsRepository(database: database)
        try await repository.upsertItems([libraryItem("article-test", category: .tasawwuf)])
        let model = ContentItemDetailViewModel(itemID: "article-test", contentRepository: repository,
            downloadsRepository: downloads, downloadManager: DownloadManager(downloadsRepository: downloads))
        try await database.connection.execute("ALTER TABLE content_items RENAME TO unavailable_content_items")
        await model.load()
        XCTAssertTrue(model.loadFailed)
        XCTAssertFalse(model.isLoading)
        try await database.connection.execute("ALTER TABLE unavailable_content_items RENAME TO content_items")
        await model.load()
        XCTAssertFalse(model.loadFailed)
        XCTAssertEqual(model.item?.id, "article-test")
        try await repository.deleteItems(ids: ["article-test"])
        await model.load()
        XCTAssertFalse(model.loadFailed)
        XCTAssertNil(model.item)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testCategoryReadFailureIsDistinctFromFilterEmptyAndRetries() async throws {
        let database = try await AppDatabase.inMemory()
        let repository = ContentRepository(database: database)
        try await repository.upsertItems([libraryItem("category-test", category: .books)])
        let model = LibraryViewModel(contentRepository: repository)
        try await database.connection.execute("ALTER TABLE content_items RENAME TO unavailable_content_items")
        do {
            _ = try await model.items(in: [.books, .importantDocuments])
            XCTFail("A failed category read must expose Retry")
        } catch { }
        try await database.connection.execute("ALTER TABLE unavailable_content_items RENAME TO content_items")
        let recovered = try await model.items(in: [.books, .importantDocuments])
        XCTAssertEqual(recovered.map(\.id), ["category-test"])
        model.languageFilter = "ar"
        let filtered = try await model.items(in: .books)
        XCTAssertTrue(filtered.isEmpty)
    }

    @MainActor
    func testFavoriteListFailuresAreNotEmptyAndCanRetry() async throws {
        let database = try await AppDatabase.inMemory()
        let repository = ContentRepository(database: database)
        try await repository.upsertItems([libraryItem("favorite-list-test", category: .books)])
        let model = LibraryViewModel(contentRepository: repository)
        let added = await model.toggleFavorite(contentItemID: "favorite-list-test")
        XCTAssertTrue(added)
        for table in ["favorites", "content_items"] {
            try await database.connection.execute("ALTER TABLE \(table) RENAME TO unavailable_\(table)")
            do {
                _ = try await model.favoriteItems()
                XCTFail("A failed favorite list read must expose Retry, not an empty list")
            } catch { }
            XCTAssertTrue(model.isFavorite("favorite-list-test"))
            try await database.connection.execute("ALTER TABLE unavailable_\(table) RENAME TO \(table)")
            let recovered = try await model.favoriteItems()
            XCTAssertEqual(recovered.map(\.id), ["favorite-list-test"])
        }
        let removed = await model.toggleFavorite(contentItemID: "favorite-list-test")
        XCTAssertTrue(removed)
        let empty = try await model.favoriteItems()
        XCTAssertTrue(empty.isEmpty)
    }

    @MainActor
    func testSavedFavoriteCountReportsReadFailureAndRecovers() async throws {
        let database = try await AppDatabase.inMemory()
        let repository = ContentRepository(database: database)
        try await repository.upsertItems([libraryItem("saved-count", category: .books)])
        let model = LibraryViewModel(contentRepository: repository)
        XCTAssertTrue(model.favoritesLoading)
        await model.loadFavorites()
        XCTAssertFalse(model.favoritesLoading)
        XCTAssertFalse(model.favoritesFailed)
        XCTAssertEqual(model.favoritesCount, 0)
        let added = await model.toggleFavorite(contentItemID: "saved-count")
        XCTAssertTrue(added)
        try await database.connection.execute("ALTER TABLE favorites RENAME TO unavailable_favorites")
        await model.loadFavorites()
        XCTAssertTrue(model.favoritesFailed)
        XCTAssertFalse(model.favoritesLoading)
        XCTAssertEqual(model.favoritesCount, 1, "A failed read preserves the confirmed count")
        try await database.connection.execute("ALTER TABLE unavailable_favorites RENAME TO favorites")
        _ = try await model.favoriteItems()
        XCTAssertFalse(model.favoritesFailed, "Opening Favorites can recover the Saved summary")
        XCTAssertEqual(model.favoritesCount, 1)
        await model.loadFavorites()
        XCTAssertFalse(model.favoritesFailed)
        XCTAssertFalse(model.favoritesLoading)
    }

    @MainActor
    func testFailedFavoriteRemovalPreservesConfirmedStateAndRetries() async throws {
        let database = try await AppDatabase.inMemory()
        let repository = ContentRepository(database: database)
        try await repository.upsertItems([libraryItem("favorite-test", category: .books)])
        let model = LibraryViewModel(contentRepository: repository)
        let added = await model.toggleFavorite(contentItemID: "favorite-test")
        XCTAssertTrue(added)
        try await database.connection.execute("ALTER TABLE favorites RENAME TO unavailable_favorites")
        let removed = await model.toggleFavorite(contentItemID: "favorite-test")
        XCTAssertFalse(removed)
        XCTAssertTrue(model.favoriteChangeFailed)
        XCTAssertTrue(model.isFavorite("favorite-test"))
        await model.loadFavorites()
        XCTAssertTrue(model.isFavorite("favorite-test"), "Failed refresh must not erase confirmed stars")
        try await database.connection.execute("ALTER TABLE unavailable_favorites RENAME TO favorites")
        let retried = await model.toggleFavorite(contentItemID: "favorite-test")
        XCTAssertTrue(retried)
        XCTAssertFalse(model.isFavorite("favorite-test"))
        let stored = try await repository.favorites()
        XCTAssertTrue(stored.isEmpty)
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
        let listed = try await viewModel.items(in: courses.categories)
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

    // MARK: - Text first

    func testAWorkWithTextOpensAsTextAndOneWithoutAsItsPrintedPages() {
        // Never opened: the text when the work has text (it may have a PDF
        // as well), the printed pages only when it has none.
        XCTAssertEqual(BookReadingHistory.startMode(resume: nil, hasText: true), .text)
        XCTAssertEqual(BookReadingHistory.startMode(resume: nil, hasText: false), .pages)
        // Left in the printed pages: Keep reading goes back to them.
        let leftInPages = BookResume(mode: .pages, page: 12, pageCount: 300)
        XCTAssertEqual(BookReadingHistory.startMode(resume: leftInPages, hasText: true), .pages)
        let leftInText = BookResume(mode: .text, page: 7, pageCount: nil)
        XCTAssertEqual(BookReadingHistory.startMode(resume: leftInText, hasText: true), .text)
    }

    func testTheReaderSwitchReadsTextThenPages() {
        XCTAssertEqual(BookReaderMode.allCases, [.text, .pages])
        // What is kept on the device does not change with the order.
        XCTAssertEqual(BookReaderMode.text.rawValue, "text")
        XCTAssertEqual(BookReaderMode.pages.rawValue, "pages")
    }

    func testKeepReadingReturnsToTheTextUnlessTheReaderChoseThePrintedPages() {
        let defaults = UserDefaults.standard
        let id = "text-first-\(UUID().uuidString)"
        let lastBook = defaults.string(forKey: "library.lastBook")
        defer {
            for key in [
                "bookPDF.page.\(id)", "bookText.page.\(id)",
                "library.book.mode.\(id)", "library.book.choice.\(id)",
            ] {
                defaults.removeObject(forKey: key)
            }
            if let lastBook {
                defaults.set(lastBook, forKey: "library.lastBook")
            } else {
                defaults.removeObject(forKey: "library.lastBook")
            }
        }
        XCTAssertNil(BookReadingHistory.resume(itemID: id, hasPDF: true, hasText: true))

        // A place kept in both and no choice made: the text.
        PDFReadingPosition.save(page: 9, itemID: id)
        BookReadingPosition.save(page: 4, bookID: id)
        var resume = BookReadingHistory.resume(itemID: id, hasPDF: true, hasText: true)
        XCTAssertEqual(resume?.mode, .text)
        XCTAssertEqual(resume?.page, 4)

        // Opening a work is not choosing how to read it, and the note older
        // builds kept at every opening is not read: still the text.
        defaults.set("pages", forKey: "library.book.mode.\(id)")
        BookReadingHistory.recordOpened(itemID: id)
        XCTAssertEqual(BookReadingHistory.lastItemID(), id)
        XCTAssertNil(BookReadingHistory.choice(itemID: id))
        resume = BookReadingHistory.resume(itemID: id, hasPDF: true, hasText: true)
        XCTAssertEqual(resume?.mode, .text)
        XCTAssertEqual(resume?.page, 4)

        // The reader chose the printed pages: back to them, at their page.
        BookReadingHistory.recordChoice(itemID: id, mode: .pages)
        XCTAssertEqual(defaults.string(forKey: "library.book.choice.\(id)"), "pages")
        XCTAssertEqual(BookReadingHistory.choice(itemID: id), .pages)
        resume = BookReadingHistory.resume(itemID: id, hasPDF: true, hasText: true)
        XCTAssertEqual(resume?.mode, .pages)
        XCTAssertEqual(resume?.page, 9)

        // And the text again, with the switch.
        BookReadingHistory.recordChoice(itemID: id, mode: .text)
        resume = BookReadingHistory.resume(itemID: id, hasPDF: true, hasText: true)
        XCTAssertEqual(resume?.mode, .text)
        XCTAssertEqual(resume?.page, 4)

        // A work with no text has only its printed pages to go back to.
        resume = BookReadingHistory.resume(itemID: id, hasPDF: true, hasText: false)
        XCTAssertEqual(resume?.mode, .pages)
        XCTAssertEqual(resume?.page, 9)

        // The printed pages chosen, but the work no longer has its PDF: the text.
        BookReadingHistory.recordChoice(itemID: id, mode: .pages)
        resume = BookReadingHistory.resume(itemID: id, hasPDF: false, hasText: true)
        XCTAssertEqual(resume?.mode, .text)
        XCTAssertEqual(resume?.page, 4)
    }

    private func textPage(_ bookID: String, _ page: Int) -> BookPage {
        BookPage(bookID: bookID, page: page, text: "متن", blocks: 1, unresolvedBlocks: 0)
    }

    /// Before works opened as text, the gold button opened the PDF and every
    /// opening noted "pages". A device that read that way keeps its place:
    /// the PDF's page becomes the place in the text.
    func testAPlaceKeptInThePrintedPagesBecomesThePlaceInTheText() async throws {
        let defaults = UserDefaults.standard
        let suffix = UUID().uuidString
        let readInPages = "carried-pages-\(suffix)"
        let readInBoth = "carried-both-\(suffix)"
        let noText = "carried-no-text-\(suffix)"
        let ids = [readInPages, readInBoth, noText]
        defer {
            for id in ids {
                for prefix in ["bookPDF.page.", "bookText.page.", "library.book.mode.", "library.book.choice."] {
                    defaults.removeObject(forKey: prefix + id)
                }
            }
        }
        let database = try await AppDatabase.inMemory()
        let repository = ContentRepository(database: database)
        try await repository.upsertBookPages([
            textPage(readInPages, 3), textPage(readInPages, 40), textPage(readInPages, 41),
            textPage(readInBoth, 2), textPage(readInBoth, 7),
        ])
        // As an older build left them: the PDF's page, and "pages" noted.
        PDFReadingPosition.save(page: 40, itemID: readInPages)
        PDFReadingPosition.save(page: 12, itemID: readInBoth)
        BookReadingPosition.save(page: 7, bookID: readInBoth)
        PDFReadingPosition.save(page: 5, itemID: noText)
        for id in ids {
            defaults.set("pages", forKey: "library.book.mode.\(id)")
        }
        XCTAssertTrue(Set(PDFReadingPosition.itemIDs()).isSuperset(of: ids))

        let carried = await BookReadingHistory.carryPrintedPlacesToText(contentRepository: repository)
        XCTAssertTrue(carried)

        // Read only in its printed pages: the text, at that page.
        var resume = BookReadingHistory.resume(itemID: readInPages, hasPDF: true, hasText: true)
        XCTAssertEqual(resume?.mode, .text)
        XCTAssertEqual(resume?.page, 40)
        XCTAssertEqual(PDFReadingPosition.page(itemID: readInPages), 40, "The PDF keeps its own place")

        // A place already kept in the text is not written over.
        resume = BookReadingHistory.resume(itemID: readInBoth, hasPDF: true, hasText: true)
        XCTAssertEqual(resume?.mode, .text)
        XCTAssertEqual(resume?.page, 7)

        // A work with no text is left with its printed pages.
        XCTAssertNil(BookReadingPosition.page(bookID: noText))
        resume = BookReadingHistory.resume(itemID: noText, hasPDF: true, hasText: false)
        XCTAssertEqual(resume?.mode, .pages)
        XCTAssertEqual(resume?.page, 5)

        // The older note is gone, and nothing was taken for a choice.
        for id in ids {
            XCTAssertNil(defaults.object(forKey: "library.book.mode.\(id)"))
            XCTAssertNil(BookReadingHistory.choice(itemID: id))
        }
    }

    /// When the works that have text cannot be told, nothing is settled, and
    /// the next launch tries again.
    func testCarryingPlacesWaitsWhenTheTextCannotBeLookedUp() async throws {
        let defaults = UserDefaults.standard
        let id = "carried-later-\(UUID().uuidString)"
        defer {
            for prefix in ["bookPDF.page.", "bookText.page.", "library.book.mode."] {
                defaults.removeObject(forKey: prefix + id)
            }
        }
        let database = try await AppDatabase.inMemory()
        let repository = ContentRepository(database: database)
        try await repository.upsertBookPages([textPage(id, 6)])
        PDFReadingPosition.save(page: 6, itemID: id)
        defaults.set("pages", forKey: "library.book.mode.\(id)")

        try await database.connection.execute("ALTER TABLE book_pages RENAME TO unavailable_book_pages")
        let failed = await BookReadingHistory.carryPrintedPlacesToText(contentRepository: repository)
        XCTAssertFalse(failed)
        XCTAssertNil(BookReadingPosition.page(bookID: id))

        try await database.connection.execute("ALTER TABLE unavailable_book_pages RENAME TO book_pages")
        let carried = await BookReadingHistory.carryPrintedPlacesToText(contentRepository: repository)
        XCTAssertTrue(carried)
        XCTAssertEqual(BookReadingPosition.page(bookID: id), 6)
        XCTAssertNil(defaults.object(forKey: "library.book.mode.\(id)"))
    }

    /// The step is taken once: a device that has taken it keeps what the
    /// reader has done since.
    func testCarryingPlacesIsDoneOnce() async throws {
        let defaults = UserDefaults.standard
        let id = "carried-once-\(UUID().uuidString)"
        let done = defaults.object(forKey: "library.book.textFirst")
        defer {
            for prefix in ["bookPDF.page.", "bookText.page."] {
                defaults.removeObject(forKey: prefix + id)
            }
            if let done {
                defaults.set(done, forKey: "library.book.textFirst")
            } else {
                defaults.removeObject(forKey: "library.book.textFirst")
            }
        }
        let database = try await AppDatabase.inMemory()
        let repository = ContentRepository(database: database)
        try await repository.upsertBookPages([textPage(id, 8)])
        PDFReadingPosition.save(page: 8, itemID: id)

        defaults.set(true, forKey: "library.book.textFirst")
        await BookReadingHistory.moveToTextFirstIfNeeded(contentRepository: repository)
        XCTAssertNil(BookReadingPosition.page(bookID: id), "Already done on this device")
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
            BookPage(bookID: "b", page: 4, text: "ذکرِ الٰہی دل کی زندگی ہے", blocks: 1, unresolvedBlocks: 0),
            BookPage(bookID: "b", page: 7, text: "بِسْمِ اللّٰهِ الرَّحْمٰنِ الرَّحِيْمِ", blocks: 1, unresolvedBlocks: 0),
            BookPage(bookID: "b", page: 9, text: "The Method of Zikr", blocks: 1, unresolvedBlocks: 0),
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

@MainActor
private final class ControlledArticleDownloadManager: DownloadManaging {
    var activeDownloads: [String: Double] { [:] }
    var pending: [CheckedContinuation<DownloadedAsset, Error>] = []
    func download(url: URL, forContentItem contentItemID: String?, mediaItemID: String?) async throws -> DownloadedAsset {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func cancelDownload(url: URL) {}
    func deleteAsset(_ asset: DownloadedAsset) async throws {}
    func localURL(for asset: DownloadedAsset) -> URL? { nil }
    func totalBytesUsed() async -> Int64 { 0 }
}
