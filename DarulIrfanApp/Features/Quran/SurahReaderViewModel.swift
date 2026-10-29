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
    /// Where each recited word sits in each ayah's mushaf text, for the ayat
    /// whose timings spell that text exactly (see `MushafWordMap`). Set with
    /// `recitation`, before the reader shows.
    @ObservationIgnored private var wordMaps: [Int: MushafWordMap] = [:]
    /// Urdu tafsir laid out once per entry, mostly off the main thread, rather
    /// than on every redraw of its card: the sounding card redraws with each
    /// word, and an Akram-ut-Tafaseer entry runs to 23 KB.
    @ObservationIgnored private var formattedTafsirByID: [String: BookPageFormatter.Page] = [:]
    @ObservationIgnored private var tafsirLayoutTask: Task<Void, Never>?
    /// The Basmala, read from the bundled mushaf (Al-Fatihah 1:1) rather than
    /// hardcoded, so it always matches the shipped orthography. Nil when the
    /// Arabic pack is unavailable, in which case the header is simply omitted.
    private(set) var bismillahText: String?

    private let repository: any QuranRepositoryProtocol
    private let devotionalMetrics: DevotionalMetricsSyncService
    /// The language the reader is currently showing translation and tafsir in.
    ///
    /// Mutable on purpose. It starts from the app language, but a reader must be
    /// able to change it in the middle of a surah without leaving the page, so
    /// this is state rather than a constructor constant.
    private(set) var readingLanguage: String

    // These three are deliberately *observed*. The ayah cards read them, and
    // they change when the reader switches language: ignored, the cards kept
    // drawing the old language's translation while the commentary had already
    // moved, which is how Urdu came to show English and English Urdu.
    private var translationsByAyah: [Int: QuranTranslation] = [:]
    /// Asrar-at-Tanzil's OWN per-ayah translation (its dedicated tab shows this,
    /// not Akram-ut-Tarajum; blank where the source has no verse).
    private var asrarTranslationsByAyah: [Int: QuranTranslation] = [:]
    private var editionsByID: [String: QuranEdition] = [:]
    private(set) var bookmarksByAyah: [Int: QuranBookmark] = [:]

    // Last-read throttling
    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?
    /// The ayah at the top of the screen, which is where a reader is.
    @ObservationIgnored private var topAyahNumber: Int?
    @ObservationIgnored private var lastPersistedAyahNumber: Int?

    init(
        surah: QuranSurah,
        repository: any QuranRepositoryProtocol,
        devotionalMetrics: DevotionalMetricsSyncService,
        preferredLanguageCode: String = "en"
    ) {
        self.surah = surah
        self.repository = repository
        self.devotionalMetrics = devotionalMetrics
        self.readingLanguage = preferredLanguageCode
    }

    // MARK: - Reading language across surahs

    /// The reader's own language choice, kept for the rest of the session so
    /// moving to the next surah does not throw it away. It is tied to the app
    /// language it was made under: changing the app language starts afresh
    /// from the new one rather than holding on to an older choice.
    private static var sessionChoice: (appLanguage: String, reading: String)?
    private static var currentAppLanguage = "en"

    static func initialReadingLanguage(appLanguage: String) -> String {
        currentAppLanguage = appLanguage
        if let choice = sessionChoice, choice.appLanguage == appLanguage { return choice.reading }
        return appLanguage
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

            // Al-Fatihah 1:1 IS the Basmala, so it doubles as the source for the
            // header shown above every other surah (except at-Tawbah). Reading it
            // from the mushaf keeps the header in the same orthography as the
            // text; a surah showing its own ayah 1 needs no lookup.
            if surah.id != 1 && surah.id != 9 {
                bismillahText = (try? await repository.ayahs(inSurah: 1))?
                    .first { $0.ayahNumber == 1 }?
                    .textArabic
            }

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
            if readingLanguage == "ur" {
                preferred = availableTranslationEditions.first(where: { $0.id == "akram-ut-tarajum-ur" })
                    ?? availableTranslationEditions.first(where: { $0.language == "ur" })
                    ?? availableTranslationEditions.first
            } else {
                preferred = availableTranslationEditions.first(where: { $0.id == "akram-ut-tarajum-en" })
                    ?? availableTranslationEditions.first(where: { $0.language == "en" })
                    ?? availableTranslationEditions.first(where: { $0.language == readingLanguage })
                    ?? availableTranslationEditions.first
            }
            if let preferred {
                await loadTranslations(edition: preferred)
            }

            // Asrar's own translation for its dedicated tab, in the reader's
            // language (blank where the source has none — never backfilled).
            let asrarRows = (try? await repository.translations(
                editionID: "asrar-at-tanzil-\(readingLanguage)", surahNumber: surah.id)) ?? []
            asrarTranslationsByAyah = Dictionary(
                asrarRows.map { ($0.ayahNumber, $0) }, uniquingKeysWith: { first, _ in first }
            )

            // The timings file is large; it is decoded and matched against the
            // mushaf away from the main thread.
            let surahID = surah.id
            let texts = Dictionary(ayahs.map { ($0.ayahNumber, $0.textArabic) }, uniquingKeysWith: { first, _ in first })
            let (loadedRecitation, maps) = await Task.detached(priority: .userInitiated) {
                () -> (SurahRecitation?, [Int: MushafWordMap]) in
                // The tafsir cards check their quotations against the mushaf;
                // its index is built here rather than on the first card.
                QuranQuotation.warmUp()
                guard let recitation = RecitationProvider.shared.recitation(forSurah: surahID) else { return (nil, [:]) }
                var maps: [Int: MushafWordMap] = [:]
                for verse in recitation.verses {
                    if let text = texts[verse.ayah], let map = MushafWordMap(text: text, words: verse.words) {
                        maps[verse.ayah] = map
                    }
                }
                return (recitation, maps)
            }.value
            recitation = loadedRecitation
            wordMaps = maps

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
            layOutUrduTafsir()
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

    /// The sheikh's bayans on this surah, each labelled with the verses it
    /// expounds. Empty for most surahs: only part of the lecture catalogue is
    /// verse-addressed, and a lecture is never attached to a verse by guesswork.
    var bayans: [AyahBayanLink] {
        AyahBayanLinkProvider.shared.links(surah: surah.id)
    }

    /// Bayans covering one ayah, narrowest range first.
    func bayans(forAyah ayahNumber: Int) -> [AyahBayanLink] {
        AyahBayanLinkProvider.shared.links(surah: surah.id, ayah: ayahNumber)
    }

    /// Languages this surah can actually be read in, worked out from the
    /// editions that have text rather than from a fixed list, so a language
    /// never appears for a surah that has nothing in it.
    var availableReadingLanguages: [String] {
        var codes = Set(availableTranslationEditions.map(\.language))
        for entry in tafsirEntries {
            if let language = editionsByID[entry.editionID]?.language { codes.insert(language) }
        }
        // A settled order rather than whichever edition happened to load first.
        let known = ["en", "ur"].filter { codes.contains($0) }
        return known + codes.subtracting(known).sorted()
    }

    /// Languages in which the current mode's commentary exists for this surah.
    ///
    /// This is what lets an empty tafsir offer the language that does have it,
    /// rather than silently substituting the other language or showing nothing
    /// and leaving the reader to guess.
    var readingLanguagesWithTafsirForMode: [String] {
        guard let prefix = contentMode.tafsirEditionPrefix else { return [] }
        var codes = Set<String>()
        for entry in tafsirEntries where entry.editionID.hasPrefix(prefix) {
            if let language = editionsByID[entry.editionID]?.language { codes.insert(language) }
        }
        let known = ["en", "ur"].filter { codes.contains($0) }
        return known + codes.subtracting(known).sorted()
    }

    /// Moves the whole reading surface — translation and commentary — into
    /// another language, without leaving the surah or losing the scroll.
    func setReadingLanguage(_ code: String) async {
        guard code != readingLanguage else { return }
        readingLanguage = code
        Self.sessionChoice = (appLanguage: Self.currentAppLanguage, reading: code)
        // Follow the Silsila's own complete translation where it exists, then
        // any edition in the chosen language.
        if let preferred = availableTranslationEditions.first(where: { $0.id == "akram-ut-tarajum-\(code)" })
            ?? availableTranslationEditions.first(where: { $0.language == code }) {
            await loadTranslations(edition: preferred)
        }
        // Asrar's own per-ayah translation is a separate edition per language,
        // and stays blank where that language's source has no verse.
        let asrarRows = (try? await repository.translations(
            editionID: "asrar-at-tanzil-\(code)", surahNumber: surah.id)) ?? []
        asrarTranslationsByAyah = Dictionary(
            asrarRows.map { ($0.ayahNumber, $0) }, uniquingKeysWith: { first, _ in first }
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
        if contentMode == .asrarTanzil {
            // Asrar tab is its own edition: show the book's own translation and
            // stay blank where the source has none — never Akram-ut-Tarajum.
            guard let t = asrarTranslationsByAyah[ayahNumber], !t.text.isEmpty else { return nil }
            return t
        }
        guard let translation = translationsByAyah[ayahNumber],
              !translation.text.isEmpty else { return nil }
        return translation
    }

    /// Stored tafsir entries whose ayah range covers `ayahNumber`, in the
    /// language being read.
    ///
    /// Language-strict, as the rest of the reader is: a reader who asked for
    /// Urdu is never handed English commentary, and vice versa. Where the
    /// chosen language has nothing, the reader says so and offers the language
    /// that does — it does not quietly substitute the other one.
    func tafsir(for ayahNumber: Int) -> [QuranTafsir] {
        tafsirEntries.filter { entry in
            guard entry.ayahStart <= ayahNumber, ayahNumber <= entry.ayahEnd else { return false }
            // An entry whose edition is unknown is not shown: its language
            // cannot be confirmed, and guessing is what mixed the two.
            return editionsByID[entry.editionID]?.language == readingLanguage
        }
    }

    /// Every stored commentary covering `ayahNumber`, in both works and both
    /// languages: the ayah's own tafsir sheet lets the reader choose.
    func allTafsir(for ayahNumber: Int) -> [QuranTafsir] {
        tafsirEntries.filter { $0.ayahStart <= ayahNumber && ayahNumber <= $0.ayahEnd }
    }

    /// The full printed volumes of the current mode's tafsir in the language
    /// being read, where this surah's commentary begins in each.
    var fullVolumes: [TafsirVolume] {
        fullVolumes(for: contentMode)
    }

    /// The printed volumes of one work in the language being read.
    func fullVolumes(for mode: QuranContentMode) -> [TafsirVolume] {
        guard let prefix = mode.tafsirEditionPrefix else { return [] }
        return TafsirVolumeProvider.shared.volumes(surah: surah.id, editionPrefix: prefix, language: readingLanguage)
    }

    /// Whether one work has verse-by-verse commentary on this surah in the
    /// language being read.
    func hasTafsir(for mode: QuranContentMode) -> Bool {
        guard let prefix = mode.tafsirEditionPrefix else { return false }
        return tafsirEntries.contains {
            $0.editionID.hasPrefix(prefix) && edition(id: $0.editionID)?.language == readingLanguage
        }
    }

    /// True for an ayah the Asrar tab leaves blank on purpose although the
    /// surah has Asrar's translation in this language: the two ayat whose
    /// source text was wrong (23:38, 80:41) are withheld until checked. The
    /// reader says so instead of showing an unexplained gap.
    func isAsrarTranslationWithheld(_ ayahNumber: Int) -> Bool {
        contentMode == .asrarTanzil
            && !asrarTranslationsByAyah.isEmpty
            && translation(for: ayahNumber) == nil
    }

    var hasAnyTafsir: Bool {
        !tafsirEntries.isEmpty || !tafsirEditionPointers.isEmpty
    }

    /// Where the recited words sit in this ayah's mushaf text, for tinting the
    /// word that is sounding. Nil when the surah has no timings or this ayah's
    /// timings do not spell the mushaf text; the ayah is then drawn untinted.
    func wordMap(forAyah ayahNumber: Int) -> MushafWordMap? {
        wordMaps[ayahNumber]
    }

    /// An Urdu tafsir entry laid out into headings, paragraphs and verified
    /// Qur'an quotations, checked against the mushaf as its source calls for
    /// (`quranCheck(forTafsirEdition:)`).
    func formattedTafsir(_ entry: QuranTafsir) -> BookPageFormatter.Page {
        if let cached = formattedTafsirByID[entry.id] { return cached }
        let page = BookPageFormatter.format(entry.text, quranCheck: Self.quranCheck(forTafsirEdition: entry.editionID))
        formattedTafsirByID[entry.id] = page
        return page
    }

    /// How closely an Urdu tafsir's Arabic must follow the mushaf to be set
    /// as Qur'an, as `BookPageFormatter.quranCheck(for:)` decides for a book
    /// page. Asrar-at-Tanzil's Urdu rows are cut from pages Claude re-read
    /// from the scan, so a quotation is matched by its letters. Akram-ut-
    /// Tafaseer's come from the original OCR of the printed volumes, so a
    /// quotation must match exactly, vowel marks included.
    nonisolated static func quranCheck(forTafsirEdition editionID: String) -> QuranQuotation.Check {
        editionID == "asrar-at-tanzil-ur" ? .letters : .exact
    }

    private func layOutUrduTafsir() {
        let urduEntries = tafsirEntries.filter {
            editionsByID[$0.editionID]?.language == "ur" && formattedTafsirByID[$0.id] == nil
        }
        guard !urduEntries.isEmpty else { return }
        tafsirLayoutTask?.cancel()
        tafsirLayoutTask = Task { [weak self] in
            let pages = await Task.detached(priority: .utility) { () -> [String: BookPageFormatter.Page] in
                var pages: [String: BookPageFormatter.Page] = [:]
                for entry in urduEntries {
                    pages[entry.id] = BookPageFormatter.format(
                        entry.text,
                        quranCheck: SurahReaderViewModel.quranCheck(forTafsirEdition: entry.editionID)
                    )
                }
                return pages
            }.value
            guard !Task.isCancelled, let self else { return }
            self.formattedTafsirByID.merge(pages) { existing, _ in existing }
        }
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
                && edition(id: $0.editionID)?.language == readingLanguage
        }
    }

    /// The commentary of the current mode that takes in this ayah from an
    /// earlier one (ayat 13-32, seen from ayah 20), in the reader's language:
    /// the book explains some passages as a whole.
    func tafsirEntry(covering ayahNumber: Int) -> QuranTafsir? {
        guard let prefix = contentMode.tafsirEditionPrefix else { return nil }
        return tafsirEntries.first {
            $0.ayahStart < ayahNumber && ayahNumber <= $0.ayahEnd
                && $0.editionID.hasPrefix(prefix)
                && edition(id: $0.editionID)?.language == readingLanguage
        }
    }

    /// Whether tafsir text in the reader's language exists for the current mode
    /// anywhere in this surah.
    var hasTafsirForMode: Bool {
        guard let prefix = contentMode.tafsirEditionPrefix else { return false }
        return tafsirEntries.contains {
            $0.editionID.hasPrefix(prefix)
                && edition(id: $0.editionID)?.language == readingLanguage
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

    /// Called when the ayah at the top of the screen changes. That ayah, not
    /// the last card laid out below the screen, is where the reader is, so
    /// "Continue reading" returns to it. Saves are debounced so fast scrolling
    /// does not hammer the database.
    func topAyahChanged(_ ayahNumber: Int) {
        guard phase == .ready else { return }
        topAyahNumber = ayahNumber
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
        guard phase == .ready, let ayahNumber = topAyahNumber else { return }
        guard ayahNumber != lastPersistedAyahNumber else { return }
        lastPersistedAyahNumber = ayahNumber
        let progress = ReadingProgress(
            surahNumber: surah.id,
            ayahNumber: ayahNumber,
            updatedAt: Date()
        )
        try? await repository.saveLastReadPosition(progress)
        await devotionalMetrics.refresh(reference: progress.updatedAt)
    }
}
