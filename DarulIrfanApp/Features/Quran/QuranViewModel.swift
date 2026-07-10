import Foundation
import Observation

/// Drives the Quran tab root: the surah index, which surahs have offline
/// Arabic text, the global continue-reading position, and the user's
/// bookmarks. The reader screen has its own view model
/// (`SurahReaderViewModel`); this one owns everything list-level.
@Observable
@MainActor
final class QuranViewModel {
    enum LoadPhase: Equatable {
        case loading
        case loaded
        case failed
    }

    // MARK: - Published state

    private(set) var phase: LoadPhase = .loading
    /// All 114 surahs, ascending by number. Structural metadata is always bundled.
    private(set) var surahs: [QuranSurah] = []
    /// Surah numbers whose Arabic text is bundled/downloaded and readable offline.
    private(set) var offlineSurahNumbers: Set<Int> = []
    /// Global continue-reading position, if the user has read before.
    private(set) var lastRead: ReadingProgress?
    private(set) var bookmarks: [QuranBookmark] = []

    /// Local filter applied to the surah list (name or number).
    var searchText: String = ""

    private let repository: any QuranRepositoryProtocol
    @ObservationIgnored private var hasLoadedOnce = false

    init(repository: any QuranRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Loading

    /// Full load of the surah index plus reader state. Safe to call again.
    func load() async {
        if !hasLoadedOnce {
            phase = .loading
        }
        do {
            let allSurahs = try await repository.allSurahs()
            let numbersWithText = try await repository.surahNumbersWithText()
            surahs = allSurahs.sorted { $0.id < $1.id }
            offlineSurahNumbers = Set(numbersWithText)
            lastRead = try? await repository.lastReadPosition()
            bookmarks = (try? await repository.bookmarks()) ?? []
            hasLoadedOnce = true
            phase = .loaded
        } catch {
            if !hasLoadedOnce {
                phase = .failed
            }
        }
    }

    /// Lightweight refresh of the state the reader screen can change
    /// (last-read position and bookmarks). Called when list screens reappear.
    func refreshReaderState() async {
        guard hasLoadedOnce else { return }
        if let position = try? await repository.lastReadPosition() {
            lastRead = position
        }
        if let latest = try? await repository.bookmarks() {
            bookmarks = latest
        }
    }

    // MARK: - Derived list state

    /// Surahs matching `searchText`; the full list when the query is empty.
    var filteredSurahs: [QuranSurah] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return surahs }
        if let number = Int(query), (1...114).contains(number) {
            return surahs.filter { $0.id == number }
        }
        return surahs.filter { matches($0, query: query) }
    }

    private func matches(_ surah: QuranSurah, query: String) -> Bool {
        if surah.nameTransliterated.localizedCaseInsensitiveContains(query) { return true }
        if surah.nameEnglish.localizedCaseInsensitiveContains(query) { return true }
        if surah.nameArabic.contains(query) { return true }
        if let urdu = surah.nameUrdu, urdu.contains(query) { return true }
        return String(surah.id) == query
    }

    func surah(number: Int) -> QuranSurah? {
        surahs.first { $0.id == number }
    }

    /// The surah the continue-reading card points at, when one exists.
    var continueReadingSurah: QuranSurah? {
        guard let lastRead else { return nil }
        return surah(number: lastRead.surahNumber)
    }

    func hasOfflineText(_ surah: QuranSurah) -> Bool {
        offlineSurahNumbers.contains(surah.id)
    }

    // MARK: - Bookmarks

    /// Bookmarks for one surah, for the grouped bookmarks screen.
    struct BookmarkGroup: Identifiable, Equatable {
        var surah: QuranSurah
        var bookmarks: [QuranBookmark]
        var id: Int { surah.id }
    }

    /// Bookmarks grouped by surah, ascending by surah number then ayah number.
    var bookmarksBySurah: [BookmarkGroup] {
        let grouped = Dictionary(grouping: bookmarks) { $0.surahNumber }
        return grouped.keys.sorted().compactMap { number -> BookmarkGroup? in
            guard let surah = surah(number: number) else { return nil }
            let items = (grouped[number] ?? []).sorted { $0.ayahNumber < $1.ayahNumber }
            return BookmarkGroup(surah: surah, bookmarks: items)
        }
    }

    func removeBookmark(_ bookmark: QuranBookmark) async {
        do {
            try await repository.removeBookmark(id: bookmark.id)
            bookmarks.removeAll { $0.id == bookmark.id }
        } catch {
            // Keep the list unchanged; the row simply stays until a retry.
        }
    }
}
