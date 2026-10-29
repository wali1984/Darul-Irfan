import Foundation

// MARK: - Content integrity

/// Raised when what the seed shipped and what the database holds disagree.
///
/// The caller at launch uses `try?`, so this does not block startup: the
/// stage's fingerprint stays unrecorded and the stage is retried next launch
/// rather than a short corpus being accepted as correct. Tests and the content
/// build treat it as fatal, which is where a bad pack is meant to be caught.
enum ContentIntegrityError: Error, CustomStringConvertible {
    case hadithRowCountMismatch(bookID: String, expected: Int, stored: Int)
    case hadithCatalogCountMismatch(bookID: String, claimed: Int, stored: Int)
    case hadithPackMissing(bookID: String, claimed: Int)

    var description: String {
        switch self {
        case .hadithRowCountMismatch(let bookID, let expected, let stored):
            return "Hadith '\(bookID)': seed has \(expected) records, database stored \(stored)."
        case .hadithCatalogCountMismatch(let bookID, let claimed, let stored):
            return "Hadith '\(bookID)': catalogue claims \(claimed), database stored \(stored)."
        case .hadithPackMissing(let bookID, let claimed):
            return "Hadith '\(bookID)': catalogue claims \(claimed), but the bundle has no records for it."
        }
    }
}

// MARK: - Import stages

/// The independent parts of the bundled seed import, in the order they run.
///
/// A stage imports only when the fingerprint of the files it reads (and of
/// its import logic, `revision`) differs from the one recorded when it last
/// imported. Every seed change used to re-import all of them - about 590 MB
/// of JSON and 205,000 rows behind the launch screen - although most changes
/// touch one file.
enum SeedStage: String, CaseIterable, Sendable {
    case quran
    case quranTranslations
    case quranTafsir
    case library
    case media
    case events
    case bookPages
    case hadith

    /// Bump when what a stage stores changes while its files do not, so each
    /// device imports that stage once more.
    var revision: Int {
        switch self {
        // 2: schema v9 stores each narration's translation provenance
        // (english/urdu review state, Urdu source), so every collection
        // imports once more to fill it, changed file or not.
        case .hadith: return 2
        default: return 1
        }
    }

    /// The per-stage version key earlier builds recorded (`seed.version.<name>`).
    /// The three Qur'an stages were a single stage then.
    var earlierStampName: String {
        switch self {
        case .quran, .quranTranslations, .quranTafsir: return "quran"
        default: return rawValue
        }
    }

    var step: SeedImportStep {
        switch self {
        case .quran, .quranTranslations, .quranTafsir: return .quran
        case .library: return .library
        case .media: return .media
        case .events: return .events
        case .bookPages: return .books
        case .hadith: return .hadith
        }
    }
}

/// What the launch screen says while bundled content is being prepared.
/// Reported only for work that actually runs.
enum SeedImportStep: Sendable, Equatable {
    case quran
    case library
    case media
    case events
    case books
    case hadith
    case search
}

// MARK: - Content sync service

/// Imports the bundled seed JSON into the database on first launch and after
/// seed changes. All writes go through the repositories, whose upserts run
/// inside transactions, so a malformed or partial file can never corrupt
/// local data.
///
/// The app no longer applies the GitHub-hosted content feed: it was last
/// published on 2026-10-02 (the sync job stopped), and applying it on a fresh
/// install replaced curated seed fields with older ones - article bodies,
/// categories, authors - and added duplicate rows under old ids. The bundled
/// seed is the library's only source.
struct ContentSyncService: ContentSyncServicing {

    // MARK: Stored dependencies (order matches AppDependencies.live())

    let quranRepository: any QuranRepositoryProtocol
    let hadithRepository: any HadithRepositoryProtocol
    let contentRepository: any ContentRepositoryProtocol
    let mediaRepository: any MediaRepositoryProtocol
    let eventsRepository: any EventsRepositoryProtocol
    let database: AppDatabase
    let searchIndex: any SearchIndexServicing

    init(
        quranRepository: any QuranRepositoryProtocol,
        hadithRepository: any HadithRepositoryProtocol,
        contentRepository: any ContentRepositoryProtocol,
        mediaRepository: any MediaRepositoryProtocol,
        eventsRepository: any EventsRepositoryProtocol,
        database: AppDatabase,
        searchIndex: any SearchIndexServicing
    ) {
        self.quranRepository = quranRepository
        self.hadithRepository = hadithRepository
        self.contentRepository = contentRepository
        self.mediaRepository = mediaRepository
        self.eventsRepository = eventsRepository
        self.database = database
        self.searchIndex = searchIndex
    }

    // MARK: Constants

    enum Keys {
        /// Manifest version of the seed last imported in full.
        static let seedVersion = "seed.version"
        /// `stageRevisionsStamp` of the build that last imported in full.
        static let stageRevisions = "seed.stageRevisions"
        /// Build whose search code last rebuilt the index.
        static let searchIndexBuild = "search.indexedBuild"
        /// Fingerprint of a stage's files when it last imported.
        static func stageFingerprint(_ stage: SeedStage) -> String { "seed.hash.\(stage.rawValue)" }
        /// Fingerprint of one hadith pack, so a change to one collection
        /// re-imports that collection only.
        static func hadithPack(_ bookID: String) -> String { "seed.hash.hadith.pack.\(bookID)" }
        static let hadithNarrators = "seed.hash.hadith.narrators"
    }

    /// Stage names with their revisions. A build whose stages or revisions
    /// differ from the last full import checks every stage again, even when
    /// the manifest version did not move.
    static var stageRevisionsStamp: String {
        SeedStage.allCases.map { "\($0.rawValue)=\($0.revision)" }.joined(separator: ",")
    }

    /// The running app's version and build, e.g. "1.11.1 (45)".
    private static var appBuild: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    // MARK: - Seed import

    @discardableResult
    func importSeedDataIfNeeded(progress: @escaping @Sendable (SeedImportStep) async -> Void) async throws -> Int {
        let targetVersion = SeedBundle.manifest()?.version ?? 1
        let installedVersion = try await readIntValue(forKey: Keys.seedVersion) ?? 0
        let installedRevisions = try await readValue(forKey: Keys.stageRevisions)

        var imported = 0
        var stagesRan = false
        var firstError: Error?

        // Files can differ from what was imported only when the manifest
        // version or the import logic moved, so the fingerprints (which read
        // every seed file) are taken only then.
        if installedVersion < targetVersion || installedRevisions != Self.stageRevisionsStamp {
            let outcome = await importChangedStages(progress: progress)
            imported = outcome.imported
            stagesRan = outcome.ran
            firstError = outcome.firstError
            if firstError == nil {
                try await writeValue(String(targetVersion), forKey: Keys.seedVersion)
                try await writeValue(Self.stageRevisionsStamp, forKey: Keys.stageRevisions)
            }
        }

        // Search covers whatever did land, so a failed stage never hides the
        // content that imported. The index is also rebuilt once per app
        // build, so a change in how it is built reaches every device without
        // waiting for a seed change.
        let build = Self.appBuild
        let indexedBuild = try await readValue(forKey: Keys.searchIndexBuild)
        if stagesRan || indexedBuild != build {
            await progress(.search)
            try await searchIndex.reindex(domains: SearchDomain.allCases)
            try await writeValue(build, forKey: Keys.searchIndexBuild)
        }

        if let firstError {
            // The full-import stamps stay absent, so the next launch checks
            // the stages again and retries the ones that failed.
            throw firstError
        }
        return imported
    }

    /// Runs every stage whose fingerprint changed. A failed stage is logged
    /// and leaves its fingerprint unrecorded; the others still run.
    private func importChangedStages(
        progress: @escaping @Sendable (SeedImportStep) async -> Void
    ) async -> (imported: Int, ran: Bool, firstError: Error?) {
        // The hadith stage's file list comes from its catalogue. If that does
        // not decode, the stage still runs (its catalogue fingerprint
        // differs) and fails with the decoding error.
        let catalog = try? SeedBundle.strictObject(HadithCatalog.self, fromFile: "hadith_books")
        let hadithBookIDs = catalog?.books.map(\.id) ?? []
        var imported = 0
        var ran = false
        var firstError: Error?
        var failedStages: [String] = []

        for stage in SeedStage.allCases {
            do {
                let digests = Self.files(for: stage, hadithBookIDs: hadithBookIDs).map { name in
                    (name: name, digest: SeedBundle.digest(ofFile: name))
                }
                let fingerprint = SeedBundle.stageFingerprint(
                    stage: stage.rawValue,
                    revision: stage.revision,
                    files: digests
                )
                if let recorded = try await readValue(forKey: Keys.stageFingerprint(stage)) {
                    if recorded == fingerprint { continue }
                } else if try await adoptEarlierImport(of: stage, fingerprint: fingerprint) {
                    continue
                }

                await progress(stage.step)
                ran = true
                let digestsByFile = Dictionary(digests.map { ($0.name, $0.digest) }, uniquingKeysWith: { first, _ in first })
                imported += try await run(stage, digests: digestsByFile)
                try await writeValue(fingerprint, forKey: Keys.stageFingerprint(stage))
            } catch {
                AppLog.content("Seed stage '\(stage.rawValue)' failed: \(error)")
                failedStages.append(stage.rawValue)
                if firstError == nil { firstError = error }
            }
        }

        if !failedStages.isEmpty {
            AppLog.content("Seed import incomplete; will retry: \(failedStages.joined(separator: ", "))")
        }
        return (imported, ran, firstError)
    }

    /// The bundled files each stage reads, in the order they are fingerprinted.
    static func files(for stage: SeedStage, hadithBookIDs: [String]) -> [String] {
        switch stage {
        case .quran: return ["quran_surahs", "quran_ayahs", "quran_editions"]
        case .quranTranslations: return ["quran_translations"]
        case .quranTafsir: return ["quran_tafsir"]
        case .library: return ["library_items"]
        case .media: return ["media_items"]
        case .events: return ["events", "announcements"]
        case .bookPages: return ["book_pages"]
        case .hadith: return ["hadith_books"] + hadithBookIDs.map { "hadith_\($0)" } + ["hadith_narrators"]
        }
    }

    private func run(_ stage: SeedStage, digests: [String: String]) async throws -> Int {
        switch stage {
        case .quran: return try await importQuranText()
        case .quranTranslations: return try await importQuranTranslations()
        case .quranTafsir: return try await importQuranTafsir()
        case .library: return try await importLibrarySeed()
        case .media: return try await importMediaSeed()
        case .events: return try await importEventsSeed()
        case .bookPages: return try await importBookPagesSeed()
        case .hadith: return try await importHadithSeed(digests: digests)
        }
    }

    // MARK: - Imports made before fingerprints

    /// Builds before 1.12 recorded only a manifest version per stage, so
    /// without this the first launch after the update would import every
    /// stage again, although most of their files have not changed in weeks.
    ///
    /// Each entry is the fingerprint the stage's files had when this was
    /// written, and the first manifest version that shipped exactly those
    /// files (from git history). A stage whose recorded version is at least
    /// that, and whose files still match, already holds them. If the files
    /// change, the fingerprint no longer matches and the stage imports.
    ///
    /// Library and media are absent on purpose: they import once more to
    /// drop the rows the seed no longer carries. Translations and tafsir
    /// delete rows before re-inserting them, so an earlier import cut short
    /// by a force-quit could leave them incomplete under an older stamp; they
    /// qualify only from 44, the last manifest earlier builds shipped, which
    /// none of them ever re-ran. Hadith is absent too: schema v9 stores
    /// each narration's translation provenance, which earlier imports never
    /// wrote, so every collection must import once more.
    static let earlierImports: [SeedStage: (fromVersion: Int, fingerprint: String)] = [
        .quran: (42, "e474028b8d940217ac453be2e8e48727ae16c524d6ea9d6e02c36e291edc771d"),
        .quranTranslations: (44, "370584fed3ef084fa1d0ff703f0c6252f8acd13e92f2adde1145a03a9895d41a"),
        .quranTafsir: (44, "3a18e565b205268688eac7f376d62294616228f71033f9727423d51f4e8b8a8b"),
        .bookPages: (41, "c611bd7f899c4cfa32012a2e4f1f37237333acc0f143450180c06d0b24437593"),
    ]

    private func adoptEarlierImport(of stage: SeedStage, fingerprint: String) async throws -> Bool {
        guard let earlier = Self.earlierImports[stage], earlier.fingerprint == fingerprint else { return false }
        let stamped = try await earlierStamp(of: stage)
        guard stamped >= earlier.fromVersion else { return false }
        try await writeValue(fingerprint, forKey: Keys.stageFingerprint(stage))
        AppLog.content("Seed stage '\(stage.rawValue)' already holds these files (imported at v\(stamped)).")
        return true
    }

    /// The manifest version an earlier build recorded for a stage: its own
    /// stamp, or the full-import stamp of builds before stages had one.
    private func earlierStamp(of stage: SeedStage) async throws -> Int {
        let stageStamp = try await readIntValue(forKey: Keys.seedVersion + "." + stage.earlierStampName) ?? 0
        let fullStamp = try await readIntValue(forKey: Keys.seedVersion) ?? 0
        return max(stageStamp, fullStamp)
    }

    // MARK: - Qur'an

    private func importQuranText() async throws -> Int {
        let surahs = try SeedBundle.strictArray(QuranSurah.self, fromFile: "quran_surahs")
        let ayahs = try SeedBundle.strictArray(QuranAyah.self, fromFile: "quran_ayahs")
        let editions = try SeedBundle.strictArray(QuranEdition.self, fromFile: "quran_editions")
        var imported = 0
        if !surahs.isEmpty {
            try await quranRepository.upsertSurahs(surahs)
            imported += surahs.count
        }
        if !ayahs.isEmpty {
            try await quranRepository.upsertAyahs(ayahs)
            imported += ayahs.count
        }
        if !editions.isEmpty {
            try await quranRepository.upsertEditions(editions)
            imported += editions.count
            // Only the Silsila's own translations are offered. Pickthall and
            // Jalandhry shipped in the first builds; an upsert alone would
            // leave them on devices that already imported them.
            let current = Set(editions.map(\.id))
            for stale in ((try? await quranRepository.editions()) ?? []) where !current.contains(stale.id) {
                try await quranRepository.deleteEdition(id: stale.id)
            }
        }
        return imported
    }

    /// Editions whose rows have been re-authored across versions are deleted
    /// wholesale BEFORE re-importing, so (a) no stale range can orphan under
    /// an ayah - a leftover 662 KB full-surah block once crashed large surahs
    /// - and (b) ayat dropped from the source truly go blank. Akram-ut-Tafaseer
    /// joins them now that it is segmented per ayah: the single draft row of
    /// earlier builds must not survive beside the new ones.
    ///
    /// The Urdu Asrar edition relies on the "stays gone" half: its tafsir
    /// records were withdrawn because the OCR behind them is corrupt (see
    /// Docs/ASRAR_URDU_TRANSLATION_STATUS.md), and this purge is what removes
    /// them from devices that imported them. Its edition row is kept, so the
    /// reader offers the full printed volume instead.
    private static let reauthoredEditionIDs = ["asrar-at-tanzil-en", "asrar-at-tanzil-ur", "akram-ut-tafaseer-ur"]

    private func importQuranTranslations() async throws -> Int {
        // Decoded before anything is deleted, so a damaged file leaves the
        // current rows in place.
        let translations = try SeedBundle.strictArray(QuranTranslation.self, fromFile: "quran_translations")
        for editionID in Self.reauthoredEditionIDs {
            try await quranRepository.deleteTranslations(editionID: editionID)
        }
        guard !translations.isEmpty else { return 0 }
        try await quranRepository.upsertTranslations(translations)
        return translations.count
    }

    private func importQuranTafsir() async throws -> Int {
        let tafsir = try SeedBundle.strictArray(QuranTafsir.self, fromFile: "quran_tafsir")
        for editionID in Self.reauthoredEditionIDs {
            try await quranRepository.deleteTafsir(editionID: editionID)
        }
        guard !tafsir.isEmpty else { return 0 }
        try await quranRepository.upsertTafsir(tafsir)
        return tafsir.count
    }

    // MARK: - Library, media, events

    /// Upserts the seed's library items over whatever an earlier build or
    /// the GitHub feed wrote (every column, so overwritten bodies, categories
    /// and authors come back), then removes the rows the seed no longer
    /// carries - see `SeedHousekeeping`.
    private func importLibrarySeed() async throws -> Int {
        let libraryItems = try SeedBundle.strictArray(ContentItem.self, fromFile: "library_items")
        guard !libraryItems.isEmpty else { return 0 }
        try await contentRepository.upsertItems(libraryItems)
        try await SeedHousekeeping(database: database).pruneLibrary(keeping: libraryItems)
        return libraryItems.count
    }

    private func importMediaSeed() async throws -> Int {
        let mediaItems = try SeedBundle.strictArray(MediaItem.self, fromFile: "media_items")
        guard !mediaItems.isEmpty else { return 0 }
        try await mediaRepository.upsertItems(mediaItems)
        try await SeedHousekeeping(database: database).pruneMedia(keeping: mediaItems)
        return mediaItems.count
    }

    private func importEventsSeed() async throws -> Int {
        let events = try SeedBundle.strictArray(CommunityEvent.self, fromFile: "events")
        let announcements = try SeedBundle.strictArray(Announcement.self, fromFile: "announcements")
        var imported = 0
        if !events.isEmpty {
            try await eventsRepository.upsertEvents(events)
            imported += events.count
        }
        if !announcements.isEmpty {
            try await eventsRepository.upsertAnnouncements(announcements)
            imported += announcements.count
        }
        return imported
    }

    /// Book text: ~19,000 pages across the books and both tafsirs, inserted in
    /// chunks rather than one transaction holding the whole corpus. Keyed on
    /// (book_id, page), which the generator verifies unique, so a re-import
    /// updates in place instead of dropping pages on a collision.
    private func importBookPagesSeed() async throws -> Int {
        let bookPages = try SeedBundle.strictArray(BookPage.self, fromFile: "book_pages")
        guard !bookPages.isEmpty else { return 0 }
        var offset = 0
        while offset < bookPages.count {
            let end = min(offset + 500, bookPages.count)
            try await contentRepository.upsertBookPages(Array(bookPages[offset..<end]))
            offset = end
        }
        return bookPages.count
    }

    // MARK: - Hadith

    /// The catalogue plus one pack per collection. Packs are loaded and
    /// inserted one book at a time so a large corpus never has to be held in
    /// memory all at once, and a pack whose file is unchanged and whose rows
    /// are all present is skipped.
    ///
    /// Every insert is counted back out of the database afterwards. Sacred
    /// text must never go missing quietly: the previous integer-keyed schema
    /// let sub-numbered narrations such as 402.2 collide with 402 and
    /// overwrite each other on insert, and nothing noticed because nobody
    /// compared what went in with what landed.
    private func importHadithSeed(digests: [String: String]) async throws -> Int {
        guard let catalog = try SeedBundle.strictObject(HadithCatalog.self, fromFile: "hadith_books"),
              !catalog.books.isEmpty else { return 0 }
        var imported = 0
        try await hadithRepository.upsertBooks(catalog.books)
        imported += catalog.books.count

        for book in catalog.books {
            let file = "hadith_\(book.id)"
            let packFingerprint = Self.packFingerprint(digests[file] ?? SeedBundle.digest(ofFile: file))
            // A collection whose file is unchanged and whose rows are all
            // there is not imported again.
            if try await readValue(forKey: Keys.hadithPack(book.id)) == packFingerprint,
               try await hadithRepository.entryCount(bookID: book.id) == book.hadithCount {
                continue
            }

            let rows = try SeedBundle.strictArray(HadithEntry.self, fromFile: file)
            guard !rows.isEmpty else {
                // A catalogue that promises narrations the bundle does not
                // carry is a packaging error, not an empty collection.
                if book.hadithCount > 0 {
                    throw ContentIntegrityError.hadithPackMissing(bookID: book.id, claimed: book.hadithCount)
                }
                continue
            }
            // Delete-then-insert: a narration dropped upstream must go, not
            // linger as an orphan the pack no longer accounts for.
            try await hadithRepository.deleteEntries(bookID: book.id)
            try await hadithRepository.upsertEntries(rows)
            imported += rows.count

            let stored = try await hadithRepository.entryCount(bookID: book.id)
            if stored != rows.count {
                AppLog.content(
                    "Hadith pack '\(book.id)': \(rows.count) records in the seed "
                    + "but \(stored) rows stored — narrations were lost on insert."
                )
                throw ContentIntegrityError.hadithRowCountMismatch(
                    bookID: book.id, expected: rows.count, stored: stored
                )
            }
            if book.hadithCount != stored {
                AppLog.content(
                    "Hadith catalogue claims \(book.hadithCount) for '\(book.id)' "
                    + "but \(stored) rows shipped."
                )
                throw ContentIntegrityError.hadithCatalogCountMismatch(
                    bookID: book.id, claimed: book.hadithCount, stored: stored
                )
            }
            try await writeValue(packFingerprint, forKey: Keys.hadithPack(book.id))
        }

        // Narrator biographies referenced by the chains, bundled natively so
        // the reader's tap-to-open bio never calls out.
        let narratorsFingerprint = Self.packFingerprint(
            digests["hadith_narrators"] ?? SeedBundle.digest(ofFile: "hadith_narrators")
        )
        if try await readValue(forKey: Keys.hadithNarrators) != narratorsFingerprint {
            let narrators = try SeedBundle.strictArray(HadithNarrator.self, fromFile: "hadith_narrators")
            if !narrators.isEmpty {
                try await hadithRepository.upsertNarrators(narrators)
                imported += narrators.count
            }
            try await writeValue(narratorsFingerprint, forKey: Keys.hadithNarrators)
        }
        return imported
    }

    /// A pack's recorded fingerprint: the hadith stage revision and the
    /// pack file's digest.
    private static func packFingerprint(_ digest: String) -> String {
        "\(SeedStage.hadith.revision):\(digest)"
    }

    // MARK: - key_value helpers

    private func readValue(forKey key: String) async throws -> String? {
        let rows = try await database.connection.query(
            "SELECT value FROM key_value WHERE key = ?",
            [.text(key)]
        )
        return rows.first?.text("value")
    }

    private func readIntValue(forKey key: String) async throws -> Int? {
        guard let text = try await readValue(forKey: key) else { return nil }
        return Int(text)
    }

    private func writeValue(_ value: String, forKey key: String) async throws {
        try await database.connection.execute(
            """
            INSERT INTO key_value (key, value, updated_at) VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """,
            [.text(key), .text(value), .date(Date())]
        )
    }
}
