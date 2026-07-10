import Foundation
import Observation

/// Reader state for a single surah: ayah text, the chosen offline translation
/// edition, tafsir entries (including link-only pointers to the website),
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
    /// The first translation edition readable offline, when one exists.
    private(set) var translationEdition: QuranEdition?
    /// Stored tafsir entries for this surah across all tafsir editions.
    private(set) var tafsirEntries: [QuranTafsir] = []
    /// Tafsir editions with no stored text for this surah but a website link
    /// (the tafsir text is not machine-readable on naqshbandiaowaisiah.org —
    /// only image-scan PDF booklets — so the app points to the source pages).
    private(set) var tafsirEditionPointers: [QuranEdition] = []

    var showTranslation = true
    var showTafsir = false

    private let repository: any QuranRepositoryProtocol

    @ObservationIgnored private var translationsByAyah: [Int: QuranTranslation] = [:]
    @ObservationIgnored private var editionsByID: [String: QuranEdition] = [:]
    private(set) var bookmarksByAyah: [Int: QuranBookmark] = [:]

    // Last-read throttling
    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?
    @ObservationIgnored private var visibleAyahNumber: Int?
    @ObservationIgnored private var lastPersistedAyahNumber: Int?

    init(surah: QuranSurah, repository: any QuranRepositoryProtocol) {
        self.surah = surah
        self.repository = repository
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

            if let edition = allEditions.first(where: { $0.kind == .translation && $0.isAvailableOffline }) {
                translationEdition = edition
                let rows = (try? await repository.translations(editionID: edition.id, surahNumber: surah.id)) ?? []
                translationsByAyah = Dictionary(
                    rows.map { ($0.ayahNumber, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            }

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
