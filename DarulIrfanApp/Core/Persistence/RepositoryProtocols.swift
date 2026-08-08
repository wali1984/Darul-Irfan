import Foundation

// Repository layer: typed persistence over AppDatabase. Live implementations
// live in Core/Persistence/Repositories/. ViewModels never touch SQL.

// MARK: - Quran

protocol QuranRepositoryProtocol: Sendable {
    func allSurahs() async throws -> [QuranSurah]
    func ayahs(inSurah surahNumber: Int) async throws -> [QuranAyah]
    /// Surahs that actually have bundled/downloaded Arabic text.
    func surahNumbersWithText() async throws -> [Int]

    func editions() async throws -> [QuranEdition]
    func translations(editionID: String, surahNumber: Int) async throws -> [QuranTranslation]
    func tafsir(editionID: String, surahNumber: Int) async throws -> [QuranTafsir]

    func bookmarks() async throws -> [QuranBookmark]
    func addBookmark(_ bookmark: QuranBookmark) async throws
    func removeBookmark(id: UUID) async throws

    func lastReadPosition() async throws -> ReadingProgress?
    func saveLastReadPosition(_ progress: ReadingProgress) async throws

    // Import (seed/content packs)
    func upsertSurahs(_ surahs: [QuranSurah]) async throws
    func upsertAyahs(_ ayahs: [QuranAyah]) async throws
    func upsertEditions(_ editions: [QuranEdition]) async throws
    func upsertTranslations(_ translations: [QuranTranslation]) async throws
    func upsertTafsir(_ tafsir: [QuranTafsir]) async throws
    /// Removes every tafsir row for an edition (used when the seed drops one).
    func deleteTafsir(editionID: String) async throws
    /// Removes every translation row for an edition (used when re-authored).
    func deleteTranslations(editionID: String) async throws
}

// MARK: - Hadith

protocol HadithRepositoryProtocol: Sendable {
    func books() async throws -> [HadithBook]
    func entries(bookID: String, limit: Int, offset: Int) async throws -> [HadithEntry]
    func entryCount(bookID: String) async throws -> Int
    /// One narration by its printed number ("402.2"); backs deep links.
    func entry(bookID: String, displayNumber: String) async throws -> HadithEntry?
    /// 0-based position of a narration within its collection's reading order,
    /// or nil if it is not present. Lets the reader open straight to a hadith
    /// (e.g. a tapped search result) by computing which page holds it.
    func readingIndex(bookID: String, displayNumber: String) async throws -> Int?
    func search(_ term: String, bookID: String?, limit: Int) async throws -> [HadithEntry]
    /// A narrator's bundled biography for the reader's tap-to-open bio sheet.
    func narrator(id: Int) async throws -> HadithNarrator?

    // Import (seed)
    func upsertBooks(_ books: [HadithBook]) async throws
    func upsertEntries(_ entries: [HadithEntry]) async throws
    /// Clears a collection before re-import, so narrations dropped upstream go.
    func deleteEntries(bookID: String) async throws
    func upsertNarrators(_ narrators: [HadithNarrator]) async throws
}

// MARK: - Library content

protocol ContentRepositoryProtocol: Sendable {
    func items(
        category: ContentCategory?,
        type: ContentType?,
        language: String?,
        limit: Int
    ) async throws -> [ContentItem]
    func item(id: String) async throws -> ContentItem?
    func collections() async throws -> [ContentCollection]

    func favorites() async throws -> [Favorite]
    func addFavorite(_ favorite: Favorite) async throws
    func removeFavorite(id: UUID) async throws

    func readingProgress(contentItemID: String) async throws -> ContentReadingProgress?
    func saveReadingProgress(_ progress: ContentReadingProgress) async throws

    func upsertItems(_ items: [ContentItem]) async throws
    func upsertCollections(_ collections: [ContentCollection]) async throws
}

// MARK: - Media

protocol MediaRepositoryProtocol: Sendable {
    func items(
        category: MediaCategory?,
        year: Int?,
        month: Int?,
        limit: Int
    ) async throws -> [MediaItem]
    func item(id: String) async throws -> MediaItem?
    /// Distinct years available for a category, newest first (archive browser).
    func availableYears(category: MediaCategory?) async throws -> [Int]

    func playbackProgress(mediaItemID: String) async throws -> PlaybackProgress?
    func savePlaybackProgress(_ progress: PlaybackProgress) async throws
    /// Items with saved progress, most recent first ("continue listening").
    func recentlyPlayed(limit: Int) async throws -> [(item: MediaItem, progress: PlaybackProgress)]

    func mediaBookmarks(mediaItemID: String?) async throws -> [MediaBookmark]
    func addMediaBookmark(_ bookmark: MediaBookmark) async throws
    func removeMediaBookmark(id: UUID) async throws

    func playlists() async throws -> [Playlist]
    func savePlaylist(_ playlist: Playlist) async throws
    func deletePlaylist(id: UUID) async throws

    func upsertItems(_ items: [MediaItem]) async throws
}

// MARK: - Downloads

protocol DownloadsRepositoryProtocol: Sendable {
    func allAssets() async throws -> [DownloadedAsset]
    func asset(remoteUrl: String) async throws -> DownloadedAsset?
    func saveAsset(_ asset: DownloadedAsset) async throws
    func deleteAsset(id: String) async throws
}

// MARK: - Trackers (prayer, fasting, zikr, tasbih)

protocol TrackerRepositoryProtocol: Sendable {
    func prayerLog(dayKeys: [String]) async throws -> [PrayerLogEntry]
    func savePrayerLog(_ entry: PrayerLogEntry) async throws
    /// Summary over the trailing `windowDays` ending at `endDayKey`.
    func streakSummary(endingAt endDayKey: String, windowDays: Int) async throws -> PrayerStreakSummary

    func fastingLog(dayKeys: [String]) async throws -> [FastingLogEntry]
    func saveFastingLog(_ entry: FastingLogEntry) async throws

    func tasbihCounters() async throws -> [TasbihCounter]
    func saveTasbihCounter(_ counter: TasbihCounter) async throws
    func deleteTasbihCounter(id: UUID) async throws

    func zikrHabit(dayKeys: [String]) async throws -> [ZikrHabitEntry]
    func saveZikrHabit(_ entry: ZikrHabitEntry) async throws
}

// MARK: - Events

protocol EventsRepositoryProtocol: Sendable {
    func events() async throws -> [CommunityEvent]
    func announcements(limit: Int) async throws -> [Announcement]
    func upsertEvents(_ events: [CommunityEvent]) async throws
    func upsertAnnouncements(_ announcements: [Announcement]) async throws
}

// MARK: - Day keys

enum DayKey {
    /// Civil-day key "yyyy-MM-dd" in the given timezone, used by all trackers.
    static func make(from date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Keys for the trailing `count` days ending at `date`, oldest first.
    static func trailing(_ count: Int, endingAt date: Date, timeZone: TimeZone = .current) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: date).map {
                make(from: $0, timeZone: timeZone)
            }
        }
    }
}
