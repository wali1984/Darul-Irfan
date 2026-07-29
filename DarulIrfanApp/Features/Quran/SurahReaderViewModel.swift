import Foundation
import Observation

/// Reader state for a single surah: ayah text, the chosen offline translation
/// edition, and native tafsir entries or availability placeholders,
/// per-ayah bookmarks, and throttled last-read persistence.
@Observable
@MainActor
final class SurahReaderViewModel {
    enum LoadPhase: Equatable {
        case loading
        /// Structural metadata exists but the Arabic text pack is not on device.
        case textUnavailable
        case ready
        case failed
    }

    let surah: QuranSurah

    // MARK: - Published state

    private(set) var phase: LoadPhase = .loading
    private(set) var ayahs: [QuranAyah] = []
    /// The chosen translation edition readable offline, when one exists.
    private(set) var translationEdition: QuranEdition?
    /// All offline translation editions the reader can switch between.
    private(set) var availableTranslationEditions: [QuranEdition] = []
    /// Stored tafsir entries for this surah across all tafsir editions.
    private(set) var tafsirEntries: [QuranTafsir] = []
    /// Tafsir editions whose verified native pages have not yet been imported.
    /// Their placeholders remain visible so future content can arrive without
    /// changing the reader's structure.
    private(set) var tafsirEditionPointers: [QuranEdition] = []

    /// Which edition drives what's shown under each ayah. Defaults to the
    /// Akram-ut-Tarajum translation; the two tafsir modes reveal commentary.
    var contentMode: QuranContentMode = .tarajum
    /// Word-by-word recitation (audio + timings) for this surah, when bundled.
    private(set) var recitation: SurahRecitation?

    private let repository: any QuranRepositoryProtocol
    /// Preferred translation language ("en"/"ur"); the reader defaults to the
    /// matching offline edition when one exists.
    private let preferredLanguageCode: String

    @ObservationIgnored private var translationsByAyah: [Int: QuranTranslation] = [:]
    @ObservationIgnored private var editionsByID: [String: QuranEdition] = [:]
    private(set) var bookmarksByAyah: [Int: QuranBookmark] = [:]

    // Last-read throttling
    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?
    @ObservationIgnored private var visibleAyahNumber: Int?
    @ObservationIgnored private var lastPersistedAyahNumber: Int?

    init(surah: QuranSurah, repository: any QuranRepositoryProtocol, preferredLanguageCode: String = "en") {
        self.surah = surah
        self.repository = repository
        self.preferredLanguageCode = preferredLanguageCode
    }

    // MARK: - Loading

    func load() async {
        phase = .loading
        do {
            let loadedAyahs = try await repository.ayahs(inSurah: surah.id)
            guard !loadedAyahs.isEmpty else {
                phase = .textUnavailable
                return
            }
            ayahs = loadedAyahs.sorted { $0.ayahNumber < $1.ayahNumber }

            let allEditions = (try? await repository.editions()) ?? []
            editionsByID = Dictionary(
                allEditions.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            availableTranslationEditions = allEditions.filter { $0.kind == .translation && $0.isAvailableOffline }
            // Default translation follows the app language using the Silsila's
            // own complete Akram-ut-Tarajum Urdu or English edition. The reader's
            // edition picker can still switch to the other bundled translations.
            let preferred: QuranEdition?
            if preferredLanguageCode == "ur" {
                preferred = availableTranslationEditions.first(where: { $0.id == "akram-ut-tarajum-ur" })
                    ?? availableTranslationEditions.first(where: { $0.language == "ur" })
                    ?? availableTranslationEditions.first
            } else {
                preferred = availableTranslationEditions.first(where: { $0.id == "akram-ut-tarajum-en" })
                    ?? availableTranslationEditions.first(where: { $0.language == "en" })
                    ?? availableTranslationEditions.first(where: { $0.language == preferredLanguageCode })
                    ?? availableTranslationEditions.first
            }
            if let preferred {
                await loadTranslations(edition: preferred)
            }
            recitation = RecitationProvider.shared.recitation(forSurah: surah.id)

            var entries: [QuranTafsir] = []
            var pointers: [QuranEdition] = []
            for edition in allEditions where edition.kind == .tafsir {
                let rows = (try? await repository.tafsir(editionID: edition.id, surahNumber: surah.id)) ?? []
                if rows.isEmpty {
                    if edition.sourceUrl != nil {
                        pointers.append(edition)
                    }
                } else {
                    entries.append(contentsOf: rows)
                }
            }
            tafsirEntries = entries.sorted { $0.ayahStart < $1.ayahStart }
            tafsirEditionPointers = pointers

            await refreshBookmarks()
            phase = .ready
        } catch {
            phase = .failed
        }
    }

    /// Loads (or switches to) a translation edition's rows for this surah.
    private func loadTranslations(edition: QuranEdition) async {
        translationEdition = edition
        let rows = (try? await repository.translations(editionID: edition.id, surahNumber: surah.id)) ?? []
        translationsByAyah = Dictionary(
            rows.map { ($0.ayahNumber, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Switches the visible translation to another offline edition.
    func selectEdition(_ id: String) async {
        guard let edition = availableTranslationEditions.first(where: { $0.id == id }),
              edition.id != translationEdition?.id else { return }
        await loadTranslations(edition: edition)
    }

    // MARK: - Per-ayah lookups

    func edition(id: String) -> QuranEdition? {
        editionsByID[id]
    }

    /// Translation for an ayah in the chosen edition; nil (hidden gracefully)
    /// when the edition has no text for this ayah.
    func translation(for ayahNumber: Int) -> QuranTranslation? {
        guard let translation = translationsByAyah[ayahNumber],
              !translation.text.isEmpty else { return nil }
        return translation
    }

    /// Stored tafsir entries whose ayah range covers `ayahNumber`.
    func tafsir(for ayahNumber: Int) -> [QuranTafsir] {
        tafsirEntries.filter { $0.ayahStart <= ayahNumber && ayahNumber <= $0.ayahEnd }
    }

    var hasAnyTafsir: Bool {
        !tafsirEntries.isEmpty || !tafsirEditionPointers.isEmpty
    }

    /// Recitation words for an ayah (nil when this surah has no bundled audio).
    func words(forAyah ayahNumber: Int) -> [RecitationWord]? {
        recitation?.verse(ayahNumber)?.words
    }

    /// The tafsir entry to show under `ayahNumber` for the current mode, if any.
    /// A range entry is shown once, under its first ayah.
    func tafsirEntry(startingAt ayahNumber: Int) -> QuranTafsir? {
        guard let prefix = contentMode.tafsirEditionPrefix else { return nil }
        // Only show a tafsir in the reader's own language — never fall back
        // across languages (e.g. an Urdu tafsir must not appear in English UI).
        return tafsirEntries.first {
            $0.ayahStart == ayahNumber
                && $0.editionID.hasPrefix(prefix)
                && edition(id: $0.editionID)?.language == preferredLanguageCode
        }
    }

    /// Whether tafsir text in the reader's language exists for the current mode
    /// anywhere in this surah.
    var hasTafsirForMode: Bool {
        guard let prefix = contentMode.tafsirEditionPrefix else { return false }
        return tafsirEntries.contains {
            $0.editionID.hasPrefix(prefix)
                && edition(id: $0.editionID)?.language == preferredLanguageCode
        }
    }

    /// Share text: the reference only, never the copyrighted body text.
    /// Example: "Surah Al-Fatihah, Ayah 5 — Quran 1:5".
    func shareReference(for ayahNumber: Int) -> String {
        String(localized: "Surah \(surah.nameTransliterated), Ayah \(ayahNumber) — Quran \(surah.id):\(ayahNumber)")
    }

    // MARK: - Bookmarks

    func isBookmarked(_ ayahNumber: Int) -> Bool {
        bookmarksByAyah[ayahNumber] != nil
    }

    func toggleBookmark(ayahNumber: Int) async {
        if let existing = bookmarksByAyah[ayahNumber] {
            do {
                try await repository.removeBookmark(id: existing.id)
                bookmarksByAyah[ayahNumber] = nil
            } catch {
                // Leave the bookmark in place; the user can try again.
            }
        } else {
            let bookmark = QuranBookmark(
                id: UUID(),
                surahNumber: surah.id,
                ayahNumber: ayahNumber,
                note: nil,
                createdAt: Date()
            )
            do {
                try await repository.addBookmark(bookmark)
                bookmarksByAyah[ayahNumber] = bookmark
            } catch {
                // Not saved; the icon simply stays un-filled.
            }
        }
    }

    private func refreshBookmarks() async {
        let all = (try? await repository.bookmarks()) ?? []
        var map: [Int: QuranBookmark] = [:]
        for bookmark in all where bookmark.surahNumber == surah.id {
            map[bookmark.ayahNumber] = bookmark
        }
        bookmarksByAyah = map
    }

    // MARK: - Last-read persistence (throttled)

    /// Called from each ayah card's `onAppear` while scrolling. Saves are
    /// debounced so fast scrolling does not hammer the database.
    func ayahBecameVisible(_ ayahNumber: Int) {
        guard phase == .ready else { return }
        visibleAyahNumber = ayahNumber
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return
            }
            await self?.persistLastRead()
        }
    }

    /// Immediate save; called when the reader disappears.
    func flushLastRead() async {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        await persistLastRead()
    }

    private func persistLastRead() async {
        guard phase == .ready, let ayahNumber = visibleAyahNumber else { return }
        guard ayahNumber != lastPersistedAyahNumber else { return }
        lastPersistedAyahNumber = ayahNumber
        let progress = ReadingProgress(
            surahNumber: surah.id,
            ayahNumber: ayahNumber,
            updatedAt: Date()
        )
        try? await repository.saveLastReadPosition(progress)
    }
}
