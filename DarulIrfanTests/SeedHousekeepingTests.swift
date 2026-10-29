import Foundation
import XCTest
@testable import DarulIrfan

/// Tests for `SeedHousekeeping`: rows the bundled seed no longer carries leave
/// the library and media tables, and the reader's own records move to the
/// seed's copy of the same publication or recording instead of dangling.
final class SeedHousekeepingTests: XCTestCase {

    private var database: AppDatabase!
    private var contentRepository: ContentRepository!
    private var mediaRepository: MediaRepository!
    private var downloadsRepository: DownloadsRepository!
    private var housekeeping: SeedHousekeeping!

    override func setUp() async throws {
        database = try await AppDatabase.inMemory()
        contentRepository = ContentRepository(database: database)
        mediaRepository = MediaRepository(database: database)
        downloadsRepository = DownloadsRepository(database: database)
        housekeeping = SeedHousekeeping(database: database)
    }

    override func tearDown() {
        housekeeping = nil
        downloadsRepository = nil
        mediaRepository = nil
        contentRepository = nil
        database = nil
    }

    // MARK: - Fixtures

    private let site = "https://www.naqshbandiaowaisiah.org"

    private func libraryItem(
        id: String,
        type: ContentType,
        category: ContentCategory,
        page: String,
        files: [String] = []
    ) -> ContentItem {
        ContentItem(
            id: id,
            sourceUrl: "\(site)/\(page)",
            type: type,
            title: id,
            titleUrdu: nil,
            language: "ur",
            author: nil,
            category: category,
            bodyHtml: nil,
            bodyPlainText: "Text of \(id)",
            excerpt: nil,
            publishedAt: nil,
            updatedAt: nil,
            mediaUrls: [],
            downloadUrls: files.map { "\(site)/uploads/books/\($0)" },
            checksum: nil,
            rightsStatus: .permissionConfirmed
        )
    }

    private func lecture(id: String, page: String, file: String) -> MediaItem {
        MediaItem(
            id: id,
            title: id,
            language: "ur",
            speaker: nil,
            date: nil,
            durationSeconds: nil,
            mediaType: .audio,
            sourceUrl: "\(site)/lecture/\(page)",
            streamUrl: "\(site)/uploads/\(file)",
            downloadUrl: nil,
            youtubeId: nil,
            year: 2026,
            month: nil,
            category: .audioLectures,
            transcriptUrl: nil,
            rightsStatus: .permissionConfirmed
        )
    }

    private func libraryIDs() async throws -> Set<String> {
        let rows = try await database.connection.query("SELECT id FROM content_items")
        return Set(rows.compactMap { $0.text("id") })
    }

    private func mediaIDs() async throws -> Set<String> {
        let rows = try await database.connection.query("SELECT id FROM media_items")
        return Set(rows.compactMap { $0.text("id") })
    }

    private func asset(id: String, url: String, contentItemID: String? = nil, mediaItemID: String? = nil) -> DownloadedAsset {
        DownloadedAsset(
            id: id,
            remoteUrl: url,
            relativeFilePath: "Downloads/\(id)",
            byteSize: 1_024,
            contentItemID: contentItemID,
            mediaItemID: mediaItemID,
            downloadedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    // MARK: - Library

    func testLibraryRowsTheSeedDroppedLeaveAndFavouritesMoveToTheSameBook() async throws {
        let book = libraryItem(
            id: "book-hayyat-e-tayyabah-i", type: .book, category: .books,
            page: "books-on-tasawwuf.html", files: ["Hayyat-e-Tayyabah-I.pdf"]
        )
        let otherBook = libraryItem(
            id: "book-islah-e-qalb", type: .book, category: .books,
            page: "books-on-tasawwuf.html", files: ["Islah-e-Qalb.pdf"]
        )
        let shajra = libraryItem(
            id: "page-shajra-silsila-naqshbandia-owaisiah", type: .page, category: .shajra,
            page: "shajra-silsila-naqshbandia-owaisiah.html"
        )
        let seed = [book, otherBook, shajra]

        // An earlier seed's PDF-named twin, the GitHub feed's copy of the
        // Shajra, an old announcement and the website's downloads page.
        let bookTwin = libraryItem(
            id: "book-Hayyat-e-Tayyabah-I.pdf", type: .book, category: .books,
            page: "books-on-tasawwuf.html", files: ["Hayyat-e-Tayyabah-I.pdf"]
        )
        let shajraTwin = libraryItem(
            id: "shajra-silsila-naqshbandia-owaisiah", type: .page, category: .shajra,
            page: "shajra-silsila-naqshbandia-owaisiah.html"
        )
        let announcement = libraryItem(
            id: "announcement-2433-2024-05-05-mahana-ijtima", type: .announcement, category: .announcements,
            page: "announcement/2433.html"
        )
        let downloadsPage = libraryItem(
            id: "page-downloads-index", type: .page, category: .importantDocuments,
            page: "downloads.html"
        )
        try await contentRepository.upsertItems(seed + [bookTwin, shajraTwin, announcement, downloadsPage])

        let created = Date(timeIntervalSince1970: 1_800_000_000)
        try await contentRepository.addFavorite(Favorite(id: UUID(), contentItemID: bookTwin.id, mediaItemID: nil, createdAt: created))
        try await contentRepository.addFavorite(Favorite(id: UUID(), contentItemID: shajraTwin.id, mediaItemID: nil, createdAt: created))
        try await contentRepository.addFavorite(Favorite(id: UUID(), contentItemID: shajra.id, mediaItemID: nil, createdAt: created))
        try await contentRepository.addFavorite(Favorite(id: UUID(), contentItemID: announcement.id, mediaItemID: nil, createdAt: created))
        try await contentRepository.saveReadingProgress(ContentReadingProgress(contentItemID: announcement.id, fraction: 0.4, updatedAt: created))
        try await downloadsRepository.saveAsset(asset(id: "pdf", url: bookTwin.downloadUrls[0], contentItemID: bookTwin.id))
        try await downloadsRepository.saveAsset(asset(id: "page", url: "\(site)/downloads.pdf", contentItemID: downloadsPage.id))

        let removed = try await housekeeping.pruneLibrary(keeping: seed)

        XCTAssertEqual(Set(removed), [bookTwin.id, shajraTwin.id, announcement.id, downloadsPage.id])
        let remaining = try await libraryIDs()
        XCTAssertEqual(remaining, Set(seed.map(\.id)))

        let favourites = try await contentRepository.favorites().compactMap(\.contentItemID)
        XCTAssertEqual(favourites.filter { $0 == book.id }.count, 1, "The twin's favourite moves to the book")
        XCTAssertEqual(favourites.filter { $0 == shajra.id }.count, 1, "Already a favourite: not listed twice")
        XCTAssertFalse(favourites.contains(announcement.id), "A favourite of a row that cannot open goes")

        let progress = try await contentRepository.readingProgress(contentItemID: announcement.id)
        XCTAssertNil(progress)

        let assets = try await downloadsRepository.allAssets()
        XCTAssertEqual(assets.first { $0.id == "pdf" }?.contentItemID, book.id, "The download now belongs to the book")
        XCTAssertNotNil(assets.first { $0.id == "page" }, "A download keeps its file")
        XCTAssertNil(assets.first { $0.id == "page" }?.contentItemID)
    }

    func testAListingPageSharedByManyBooksIsNotATwin() async throws {
        let books = ["a", "b"].map {
            libraryItem(id: "book-\($0)", type: .book, category: .books, page: "books-on-tasawwuf.html", files: ["\($0).pdf"])
        }
        let orphan = libraryItem(id: "book-gone", type: .book, category: .books, page: "books-on-tasawwuf.html")
        try await contentRepository.upsertItems(books + [orphan])
        try await contentRepository.addFavorite(Favorite(id: UUID(), contentItemID: orphan.id, mediaItemID: nil, createdAt: Date()))

        try await housekeeping.pruneLibrary(keeping: books)

        let favourites = try await contentRepository.favorites()
        XCTAssertTrue(favourites.isEmpty, "Never moved onto an unrelated book that only shares a listing page")
    }

    func testTheOnlySeedItemAtAPageIsATwinUnderAnotherType() async throws {
        // The About page was an "article" row in an earlier seed and is a
        // "page" row now; a listing page with two documents is no twin.
        let about = libraryItem(
            id: "page-silsila-naqshbandia-owaisiah", type: .page, category: .aboutSilsila,
            page: "silsila-naqshbandia-owaisiah.html"
        )
        let documents = ["en", "ur"].map {
            libraryItem(id: "document-conditions-\($0)", type: .document, category: .importantDocuments, page: "documents.html")
        }
        let seed = [about] + documents
        let oldAbout = libraryItem(
            id: "silsila-naqshbandia-owaisiah", type: .article, category: .aboutSilsila,
            page: "silsila-naqshbandia-owaisiah.html"
        )
        let oldListing = libraryItem(id: "documents", type: .article, category: .articles, page: "documents.html")
        try await contentRepository.upsertItems(seed + [oldAbout, oldListing])
        try await contentRepository.addFavorite(Favorite(id: UUID(), contentItemID: oldAbout.id, mediaItemID: nil, createdAt: Date()))
        try await contentRepository.addFavorite(Favorite(id: UUID(), contentItemID: oldListing.id, mediaItemID: nil, createdAt: Date()))

        let removed = try await housekeeping.pruneLibrary(keeping: seed)

        XCTAssertEqual(Set(removed), [oldAbout.id, oldListing.id])
        let favourites = try await contentRepository.favorites().compactMap(\.contentItemID)
        XCTAssertEqual(favourites, [about.id], "The About favourite moves; the listing page has no single twin")
    }

    func testAnEmptySeedNeverEmptiesTheLibrary() async throws {
        let book = libraryItem(id: "book-a", type: .book, category: .books, page: "a.html")
        try await contentRepository.upsertItems([book])

        let removed = try await housekeeping.pruneLibrary(keeping: [])

        XCTAssertTrue(removed.isEmpty)
        let remaining = try await libraryIDs()
        XCTAssertEqual(remaining, [book.id])
    }

    // MARK: - Media

    func testMediaRowsTheSeedDroppedLeaveAndListeningRecordsMoveToTheSameRecording() async throws {
        let seedLecture = lecture(
            id: "lecture-3835-azmat-mohammad-rasool-ul-allah",
            page: "3835/2026-02-06-azmat-mohammad-rasool-ul-allah.html",
            file: "3835/06-02-2026%20s.mp3"
        )
        let other = lecture(id: "lecture-4000-other", page: "4000/other.html", file: "4000/other.mp3")
        // The feed's copy writes the same file with a literal space.
        let feedCopy = lecture(
            id: "lecture-3835-2026-02-06-azmat-mohammad-rasool-ul-allah",
            page: "3835/2026-02-06-azmat-mohammad-rasool-ul-allah.html",
            file: "3835/06-02-2026 s.mp3"
        )
        let retired = lecture(id: "almurshid-tv-live", page: "tv.html", file: "tv.m3u8")
        try await mediaRepository.upsertItems([seedLecture, other, feedCopy, retired])

        let older = Date(timeIntervalSince1970: 1_800_000_000)
        let newer = older.addingTimeInterval(3_600)
        try await mediaRepository.savePlaybackProgress(PlaybackProgress(mediaItemID: seedLecture.id, positionSeconds: 30, durationSeconds: 3_000, updatedAt: older))
        try await mediaRepository.savePlaybackProgress(PlaybackProgress(mediaItemID: feedCopy.id, positionSeconds: 1_200, durationSeconds: 3_000, updatedAt: newer))
        try await mediaRepository.savePlaybackProgress(PlaybackProgress(mediaItemID: retired.id, positionSeconds: 5, durationSeconds: 60, updatedAt: newer))
        try await mediaRepository.addMediaBookmark(MediaBookmark(id: UUID(), mediaItemID: feedCopy.id, positionSeconds: 600, note: nil, createdAt: older))
        try await mediaRepository.addMediaBookmark(MediaBookmark(id: UUID(), mediaItemID: retired.id, positionSeconds: 1, note: nil, createdAt: older))
        try await downloadsRepository.saveAsset(asset(id: "mp3", url: feedCopy.streamUrl ?? "", mediaItemID: feedCopy.id))
        let playlist = Playlist(id: UUID(), title: "Mine", mediaItemIDs: [feedCopy.id, other.id, retired.id], createdAt: older, updatedAt: older)
        try await mediaRepository.savePlaylist(playlist)

        let removed = try await housekeeping.pruneMedia(keeping: [seedLecture, other])

        XCTAssertEqual(Set(removed), [feedCopy.id, retired.id])
        let remaining = try await mediaIDs()
        XCTAssertEqual(remaining, [seedLecture.id, other.id])

        let progress = try await mediaRepository.playbackProgress(mediaItemID: seedLecture.id)
        XCTAssertEqual(progress?.positionSeconds, 1_200, "The more recent listening position wins")
        let retiredProgress = try await mediaRepository.playbackProgress(mediaItemID: retired.id)
        XCTAssertNil(retiredProgress)

        let bookmarks = try await mediaRepository.mediaBookmarks(mediaItemID: nil)
        XCTAssertEqual(bookmarks.map(\.mediaItemID), [seedLecture.id])

        let assets = try await downloadsRepository.allAssets()
        XCTAssertEqual(assets.first?.mediaItemID, seedLecture.id, "The lecture still shows as downloaded")

        let playlists = try await mediaRepository.playlists()
        XCTAssertEqual(playlists.first?.mediaItemIDs, [seedLecture.id, other.id])
    }

    func testTheNewerListeningPositionStaysWhenTheSeedCopyWasPlayedLast() async throws {
        let seedLecture = lecture(id: "lecture-1", page: "1.html", file: "1.mp3")
        let feedCopy = lecture(id: "lecture-1-old", page: "1.html", file: "1.mp3")
        try await mediaRepository.upsertItems([seedLecture, feedCopy])
        let older = Date(timeIntervalSince1970: 1_800_000_000)
        try await mediaRepository.savePlaybackProgress(PlaybackProgress(mediaItemID: feedCopy.id, positionSeconds: 10, durationSeconds: 100, updatedAt: older))
        try await mediaRepository.savePlaybackProgress(PlaybackProgress(mediaItemID: seedLecture.id, positionSeconds: 70, durationSeconds: 100, updatedAt: older.addingTimeInterval(60)))

        try await housekeeping.pruneMedia(keeping: [seedLecture])

        let progress = try await mediaRepository.playbackProgress(mediaItemID: seedLecture.id)
        XCTAssertEqual(progress?.positionSeconds, 70)
        let stale = try await mediaRepository.playbackProgress(mediaItemID: feedCopy.id)
        XCTAssertNil(stale)
    }
}
