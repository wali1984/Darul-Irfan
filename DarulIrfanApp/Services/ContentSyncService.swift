import Foundation

// MARK: - Remote manifest shape

/// Shape of the remote content manifest the app polls for updates.
///
/// `files` maps a payload name (currently understood: "media_items",
/// "events") to the URL of a JSON file containing an array of the matching
/// model — absolute, or relative to the deployed GitHub-hosted manifest.
/// Network failures resolve to cached/bundled content and never block launch.
struct RemoteManifest: Codable, Sendable, Equatable {
    var version: Int
    var files: [String: String]
}

// MARK: - Content integrity

/// Raised when what the seed shipped and what the database holds disagree.
///
/// The caller at launch uses `try?`, so this does not block startup: the seed
/// version stays unstamped and the import is retried next launch rather than a
/// short corpus being accepted as correct. Tests and the content build treat it
/// as fatal, which is where a bad pack is meant to be caught.
enum ContentIntegrityError: Error, CustomStringConvertible {
    case hadithRowCountMismatch(bookID: String, expected: Int, stored: Int)
    case hadithCatalogCountMismatch(bookID: String, claimed: Int, stored: Int)

    var description: String {
        switch self {
        case .hadithRowCountMismatch(let bookID, let expected, let stored):
            return "Hadith '\(bookID)': seed has \(expected) records, database stored \(stored)."
        case .hadithCatalogCountMismatch(let bookID, let claimed, let stored):
            return "Hadith '\(bookID)': catalogue claims \(claimed), database stored \(stored)."
        }
    }
}

// MARK: - Content sync service

/// Imports the bundled seed JSON into the database on first launch (and
/// after seed-version bumps), and applies remote manifest updates when the
/// documented endpoint becomes available. All writes go through the
/// repositories, whose upserts run inside transactions, so a malformed or
/// partial payload can never corrupt local data.
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

    private enum Keys {
        /// Seed data version already imported into the database.
        static let seedVersion = "seed.version"
        /// Remote manifest version already applied.
        static let remoteVersion = "remote.manifest.version"
        /// Epoch seconds of the last successful manifest contact (drives the
        /// 14-day cadence, written even when there was nothing new).
        static let lastCheckedAt = "remote.lastCheckedAt"
    }

    /// Published fortnightly by the content-sync GitHub Action
    /// (.github/workflows/content-sync.yml) and served from the repo via
    /// raw.githubusercontent.com. Offline/first-run failures are always
    /// treated as "no update available".
    private static let remoteManifestURLString =
        "https://raw.githubusercontent.com/wali1984/Darul-Irfan/main/content/content_manifest.json"

    /// The manifest is small; data files download only when its version rises.
    private static let refreshInterval: TimeInterval = 6 * 3_600

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Seed import

    @discardableResult
    func importSeedDataIfNeeded() async throws -> Int {
        let targetVersion = SeedBundle.manifest()?.version ?? 1
        let installedVersion = try await readIntValue(forKey: Keys.seedVersion) ?? 0
        guard installedVersion < targetVersion else { return 0 }

        let surahs = SeedBundle.quranSurahs()
        let ayahs = SeedBundle.quranAyahs()
        let editions = SeedBundle.quranEditions()
        let translations = SeedBundle.quranTranslations()
        let tafsir = SeedBundle.quranTafsir()
        let libraryItems = SeedBundle.libraryItems()
        let mediaItems = SeedBundle.mediaItems()
        let events = SeedBundle.events()
        let announcements = SeedBundle.announcements()

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
        }
        // Both Asrar-at-Tanzil editions have been re-authored across versions.
        // Delete their rows wholesale BEFORE re-importing so: (a) no stale range
        // can orphan under an ayah — a leftover 662 KB full-surah block once
        // crashed large surahs, including when upgrading straight from an old
        // build; (b) ayat dropped from the source truly go blank. Re-inserted
        // just below from the seed when present; stays gone when the seed omits
        // it (upsert adds nothing for a missing edition).
        //
        // The Urdu edition relies on the "stays gone" half. Its 1,118 tafsir
        // records were withdrawn from the seed because the OCR behind them is
        // corrupt — see Docs/ASRAR_URDU_TRANSLATION_STATUS.md — so this purge is
        // what actually removes them from devices that already imported them.
        // The edition row itself is deliberately kept: it carries a sourceUrl,
        // so with no rows the reader falls back to its "not yet imported"
        // placeholder instead of showing damaged scripture commentary.
        for editionID in ["asrar-at-tanzil-en", "asrar-at-tanzil-ur"] {
            try await quranRepository.deleteTranslations(editionID: editionID)
            try await quranRepository.deleteTafsir(editionID: editionID)
        }
        if !translations.isEmpty {
            try await quranRepository.upsertTranslations(translations)
            imported += translations.count
        }
        if !tafsir.isEmpty {
            try await quranRepository.upsertTafsir(tafsir)
            imported += tafsir.count
        }

        // Hadith: the catalogue plus one pack per collection. Packs are loaded
        // and inserted one book at a time so a large corpus never has to be
        // held in memory all at once.
        //
        // Every insert is counted back out of the database afterwards. Sacred
        // text must never go missing quietly: the previous integer-keyed schema
        // let sub-numbered narrations such as 402.2 collide with 402 and
        // overwrite each other on insert, and nothing noticed because nobody
        // compared what went in with what landed.
        if let catalog = SeedBundle.hadithCatalog(), !catalog.books.isEmpty {
            try await hadithRepository.upsertBooks(catalog.books)
            imported += catalog.books.count
            for book in catalog.books {
                let rows = SeedBundle.hadithEntries(bookID: book.id)
                guard !rows.isEmpty else { continue }
                // Delete-then-insert: a narration dropped upstream must go,
                // not linger as an orphan the pack no longer accounts for.
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
            }
            // Narrator biographies referenced by the chains, bundled natively so
            // the reader's tap-to-open bio never calls out. Optional: absent
            // until the corpus is ingested with people data.
            let narrators = SeedBundle.hadithNarrators()
            if !narrators.isEmpty {
                try await hadithRepository.upsertNarrators(narrators)
                imported += narrators.count
            }
        }
        if !libraryItems.isEmpty {
            try await contentRepository.upsertItems(libraryItems)
            imported += libraryItems.count
        }
        if !mediaItems.isEmpty {
            try await mediaRepository.upsertItems(mediaItems)
            imported += mediaItems.count
        }
        if !events.isEmpty {
            try await eventsRepository.upsertEvents(events)
            imported += events.count
        }
        if !announcements.isEmpty {
            try await eventsRepository.upsertAnnouncements(announcements)
            imported += announcements.count
        }

        guard imported > 0 else {
            // A completely empty bundle means the seed files did not ship.
            // Leave seed.version unchanged so a corrected build imports.
            AppLog.content("Seed bundle contained no records; skipping version stamp.")
            return 0
        }

        // Reindex BEFORE stamping the version: if reindexing throws, the
        // stamp stays absent and the next launch retries the whole import
        // (repository upserts are idempotent).
        try await searchIndex.reindex(domains: SearchDomain.allCases)
        try await writeValue(String(targetVersion), forKey: Keys.seedVersion)
        return imported
    }

    // MARK: - Remote refresh

    func refreshFromRemoteManifest() async throws {
        guard let manifestURL = URL(string: Self.remoteManifestURLString) else { return }

        // 14-day cadence gate: skip the network entirely if we checked
        // recently. Cheap enough to call on every launch.
        let now = Date()
        if let lastChecked = try await readDoubleValue(forKey: Keys.lastCheckedAt),
           now.timeIntervalSince1970 - lastChecked < Self.refreshInterval {
            return
        }

        // Offline-first: an unreachable or not-yet-deployed manifest is the
        // normal case, never an error surfaced to the user.
        let manifest: RemoteManifest
        do {
            let (data, response) = try await Self.session.data(from: manifestURL)
            guard
                let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode)
            else { return }
            manifest = try Self.makeDecoder().decode(RemoteManifest.self, from: data)
        } catch {
            return
        }

        // Reaching the manifest counts as a check, even if nothing is new —
        // advance the fortnightly clock so we don't hammer the endpoint.
        try? await writeValue(String(now.timeIntervalSince1970), forKey: Keys.lastCheckedAt)

        let appliedVersion = try await readIntValue(forKey: Keys.remoteVersion) ?? 0
        guard manifest.version > appliedVersion else { return }

        var updatedDomains: [SearchDomain] = []
        var allFilesApplied = true

        // Payload names this app version recognizes. "tafsir" is acknowledged
        // but not applied inline (the tafsir manifest lists PDF page URLs the
        // reader links to, not bundled text). Anything unrecognized blocks the
        // version stamp so a future app version re-attempts it.
        let understoodNames: Set<String> = ["articles", "documents", "media", "events", "tafsir"]
        if !Set(manifest.files.keys).isSubset(of: understoodNames) {
            allFilesApplied = false
        }

        // Library content (articles + documents) -> content repository.
        for name in ["articles", "documents"] {
            guard let path = manifest.files[name] else { continue }
            guard let url = Self.resolve(path, against: manifestURL) else { allFilesApplied = false; continue }
            let items = await Self.fetchArray(ContentItem.self, from: url)
                .filter { !$0.id.isEmpty && !$0.title.isEmpty }
            if items.isEmpty { allFilesApplied = false; continue }
            // Chunk large catalogs so each transaction stays bounded.
            for chunk in stride(from: 0, to: items.count, by: 500) {
                try await contentRepository.upsertItems(Array(items[chunk..<min(chunk + 500, items.count)]))
            }
            if !updatedDomains.contains(.library) { updatedDomains.append(.library) }
        }

        if let mediaPath = manifest.files["media"],
           let mediaURL = Self.resolve(mediaPath, against: manifestURL) {
            let items = await Self.fetchArray(MediaItem.self, from: mediaURL)
                .filter { !$0.id.isEmpty && !$0.title.isEmpty }
            if items.isEmpty {
                allFilesApplied = false
            } else {
                for chunk in stride(from: 0, to: items.count, by: 500) {
                    try await mediaRepository.upsertItems(Array(items[chunk..<min(chunk + 500, items.count)]))
                }
                updatedDomains.append(.media)
            }
        } else if manifest.files["media"] != nil {
            allFilesApplied = false
        }

        if let eventsPath = manifest.files["events"],
           let eventsURL = Self.resolve(eventsPath, against: manifestURL) {
            let events = await Self.fetchArray(CommunityEvent.self, from: eventsURL)
                .filter { !$0.id.isEmpty && !$0.title.isEmpty }
            if events.isEmpty {
                allFilesApplied = false
            } else {
                try await eventsRepository.upsertEvents(events)
                updatedDomains.append(.events)
            }
        } else if manifest.files["events"] != nil {
            allFilesApplied = false
        }

        if !updatedDomains.isEmpty {
            try await searchIndex.reindex(domains: updatedDomains)
        }

        // Stamp the version only when every file listed in the manifest
        // applied successfully; otherwise leave it unstamped so the next
        // refresh retries (upserts and reindexing are idempotent).
        guard allFilesApplied else { return }
        try await writeValue(String(manifest.version), forKey: Keys.remoteVersion)
    }

    /// Downloads and decodes a JSON array; any failure (network, HTTP
    /// status, malformed payload) yields [] so nothing is applied.
    private static func fetchArray<Element: Decodable>(
        _ element: Element.Type,
        from url: URL
    ) async -> [Element] {
        do {
            let (data, response) = try await session.data(from: url)
            guard
                let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode)
            else { return [] }
            return try makeDecoder().decode([Element].self, from: data)
        } catch {
            AppLog.content("Remote content fetch failed for \(url.host ?? "unknown host"): \(error.localizedDescription)")
            return []
        }
    }

    private static func resolve(_ path: String, against base: URL) -> URL? {
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    // MARK: - key_value helpers

    private func readIntValue(forKey key: String) async throws -> Int? {
        let rows = try await database.connection.query(
            "SELECT value FROM key_value WHERE key = ?",
            [.text(key)]
        )
        guard let text = rows.first?.text("value") else { return nil }
        return Int(text)
    }

    private func readDoubleValue(forKey key: String) async throws -> Double? {
        let rows = try await database.connection.query(
            "SELECT value FROM key_value WHERE key = ?",
            [.text(key)]
        )
        guard let text = rows.first?.text("value") else { return nil }
        return Double(text)
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
