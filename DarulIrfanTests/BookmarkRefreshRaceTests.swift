import Foundation
import XCTest
@testable import DarulIrfan

final class BookmarkRefreshRaceTests: XCTestCase {
    @MainActor
    func testDeletionDuringHeldReadCannotRestoreDeletedBookmark() async {
        await verifyDeletionDuringRead(entry: .bookmarks)
    }

    @MainActor
    func testDeletionDuringInitialLoadCannotRestoreDeletedBookmark() async {
        await verifyDeletionDuringRead(entry: .initialLoad)
    }

    @MainActor
    func testDeletionDuringReaderRefreshCannotRestoreDeletedBookmark() async {
        await verifyDeletionDuringRead(entry: .readerRefresh)
    }

    private enum Entry { case bookmarks, initialLoad, readerRefresh }

    @MainActor
    private func verifyDeletionDuringRead(entry: Entry) async {
        let began = expectation(description: "First bookmark snapshot captured")
        let bookmark = QuranBookmark(id: UUID(), surahNumber: 1, ayahNumber: 1,
                                     note: nil, createdAt: Date())
        let heldRead = entry == .readerRefresh ? 2 : 1
        let repository = HeldBookmarkRepository(bookmark: bookmark, heldRead: heldRead) { began.fulfill() }
        let model = QuranViewModel(repository: repository)
        if entry == .readerRefresh { await model.load() }
        let read = Task {
            switch entry {
            case .bookmarks: await model.refreshBookmarks()
            case .initialLoad: await model.load()
            case .readerRefresh: await model.refreshReaderState()
            }
        }
        await fulfillment(of: [began], timeout: 5)
        await model.removeBookmark(bookmark)
        await repository.releaseRead()
        await read.value
        XCTAssertTrue(model.bookmarks.isEmpty, "An older read must not resurrect a deleted bookmark")
        XCTAssertFalse(model.bookmarksLoading)
        XCTAssertFalse(model.bookmarksFailed)
        let reads = await repository.readCount
        XCTAssertEqual(reads, heldRead + 1, "Deletion must retain a fresh read after the in-flight snapshot")
    }
}

private actor HeldBookmarkRepository: QuranRepositoryProtocol {
    private var saved: [QuranBookmark]
    private var held: CheckedContinuation<Void, Never>?
    private let began: @Sendable () -> Void
    private let heldRead: Int
    private(set) var readCount = 0
    init(bookmark: QuranBookmark, heldRead: Int, began: @escaping @Sendable () -> Void) {
        saved = [bookmark]
        self.heldRead = heldRead
        self.began = began
    }
    func bookmarks() async throws -> [QuranBookmark] {
        readCount += 1
        let snapshot = saved
        if readCount == heldRead {
            await withCheckedContinuation { continuation in
                held = continuation
                began()
            }
        }
        return snapshot
    }
    func releaseRead() { held?.resume(); held = nil }
    func removeBookmark(id: UUID) async throws { saved.removeAll { $0.id == id } }
    func addBookmark(_ bookmark: QuranBookmark) async throws { saved.append(bookmark) }
    func allSurahs() async throws -> [QuranSurah] { [] }
    func ayahs(inSurah surahNumber: Int) async throws -> [QuranAyah] { [] }
    func surahNumbersWithText() async throws -> [Int] { [] }
    func editions() async throws -> [QuranEdition] { [] }
    func translations(editionID: String, surahNumber: Int) async throws -> [QuranTranslation] { [] }
    func tafsir(editionID: String, surahNumber: Int) async throws -> [QuranTafsir] { [] }
    func lastReadPosition() async throws -> ReadingProgress? { nil }
    func saveLastReadPosition(_ progress: ReadingProgress) async throws { }
    func upsertSurahs(_ surahs: [QuranSurah]) async throws { }
    func upsertAyahs(_ ayahs: [QuranAyah]) async throws { }
    func upsertEditions(_ editions: [QuranEdition]) async throws { }
    func upsertTranslations(_ translations: [QuranTranslation]) async throws { }
    func upsertTafsir(_ tafsir: [QuranTafsir]) async throws { }
    func deleteTafsir(editionID: String) async throws { }
    func deleteTranslations(editionID: String) async throws { }
    func deleteEdition(id: String) async throws { }
}
