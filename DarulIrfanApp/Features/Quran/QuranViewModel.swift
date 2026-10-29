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
    /// Each surah's names reduced for matching (see `romanKey`, `scriptKey`).
    @ObservationIgnored private var searchKeys: [Int: (roman: [String], script: [String])] = [:]

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
            searchKeys = Dictionary(surahs.map { ($0.id, Self.keys(for: $0)) }, uniquingKeysWith: { first, _ in first })
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
    ///
    /// Names are compared the way people type them: a transliteration with
    /// or without "Al-", doubled vowels or a final "h" (fatiha, Faatiha,
    /// Fatihah; yasin, Yaseen), an Arabic name without harakat, and the Urdu
    /// names the IndoPak mushaf uses where they differ (یسین, بنی اسرائیل).
    var filteredSurahs: [QuranSurah] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return surahs }
        if let number = Int(SearchNormalizer.normalize(query)), (1...114).contains(number) {
            return surahs.filter { $0.id == number }
        }
        let roman = Self.romanKey(query)
        let script = Self.scriptKey(query)
        return surahs.filter { surah in
            let keys = searchKeys[surah.id] ?? Self.keys(for: surah)
            if !roman.isEmpty { return keys.roman.contains { $0.contains(roman) } }
            guard !script.isEmpty else { return false }
            return keys.script.contains { $0.contains(script) }
        }
    }

    /// An ayah typed into the search field as "2:255" (or "2 255", in any
    /// digits), when that surah has that ayah.
    var typedAyah: (surah: QuranSurah, ayah: Int)? {
        let folded = SearchNormalizer.normalize(searchText)
        let numbers = folded.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count == 2, let found = surah(number: numbers[0]),
              (1...found.ayahCount).contains(numbers[1]) else { return nil }
        return (found, numbers[1])
    }

    private static func keys(for surah: QuranSurah) -> (roman: [String], script: [String]) {
        var roman = [romanKey(surah.nameTransliterated), romanKey(surah.nameEnglish)]
        var script = [scriptKey(surah.nameArabic)]
        if let urdu = surah.nameUrdu { script.append(scriptKey(urdu)) }
        for alias in nameAliases[surah.id] ?? [] {
            if alias.unicodeScalars.contains(where: { (0x0600...0x06FF).contains($0.value) }) {
                script.append(scriptKey(alias))
            } else {
                roman.append(romanKey(alias))
            }
        }
        return (roman.filter { !$0.isEmpty }, script.filter { !$0.isEmpty })
    }

    /// A transliteration reduced to its letters: lower case, no accents,
    /// hyphens or apostrophes, "ee"/"oo" read as i/u, doubled letters once,
    /// and no final "h" after a vowel.
    static func romanKey(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var letters = String(String.UnicodeScalarView(folded.unicodeScalars.filter { (0x61...0x7A).contains($0.value) }))
        for (spelling, sound) in [("ee", "i"), ("oo", "u"), ("ou", "u"), ("au", "aw")] {
            letters = letters.replacingOccurrences(of: spelling, with: sound)
        }
        var key = ""
        for character in letters where character != key.last { key.append(character) }
        if key.count > 2, key.hasSuffix("h"), let beforeLast = key.dropLast().last, "aeiou".contains(beforeLast) {
            key.removeLast()
        }
        return key
    }

    /// An Arabic or Urdu name without harakat, with the two scripts' letter
    /// forms folded together and the spaces taken out.
    static func scriptKey(_ text: String) -> String {
        SearchNormalizer.normalize(text).filter { !$0.isWhitespace }
    }

    /// Names a reader may search by that the catalogue does not carry: the
    /// IndoPak surah names that differ from the Arabic heading, and common
    /// Urdu spellings.
    private static let nameAliases: [Int: [String]] = [
        17: ["بنی اسرائیل", "bani israil", "bani israeel"],
        36: ["یسین", "یاسین"],
        40: ["مومن", "mumin", "momin"],
        41: ["حم السجدہ", "ha mim sajdah", "hamim sajdah"],
        55: ["رحمان"],
        76: ["دہر", "dahr"],
        94: ["الم نشرح", "alam nashrah", "inshirah"],
        111: ["لہب", "lahab"],
    ]

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
