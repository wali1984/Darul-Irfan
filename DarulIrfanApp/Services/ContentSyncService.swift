import Foundation

// MARK: - Remote manifest shape

/// Shape of the remote content manifest the app polls for updates.
///
/// `files` maps a payload name (currently understood: "media_items",
/// "events") to the URL of a JSON file containing an array of the matching
/// model — absolute, or relative to the manifest's own location. The server
/// side of this endpoint is future work; until it exists every fetch simply
/// resolves to "nothing new".
struct RemoteManifest: Codable, Sendable, Equatable {
    var version: Int
    var files: [String: String]
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
    let contentRepository: any ContentRepositoryProtocol
    let mediaRepository: any MediaRepositoryProtocol
    let eventsRepository: any EventsRepositoryProtocol
    let database: AppDatabase
    let searchIndex: any SearchIndexServicing

    init(
        quranRepository: any QuranRepositoryProtocol,
        contentRepository: any ContentRepositoryProtocol,
        mediaRepository: any MediaRepositoryProtocol,
        eventsRepository: any EventsRepositoryProtocol,
        database: AppDatabase,
        searchIndex: any SearchIndexServicing
    ) {
        self.quranRepository = quranRepository
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
    }

    /// Documented future endpoint for content updates. Not live yet —
    /// failures are always treated as "no update available".
    private static let remoteManifestURLString =
        "https://www.naqshbandiaowaisiah.org/app/content_manifest.json"

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
        if !translations.isEmpty {
            try await quranRepository.upsertTranslations(translations)
            imported += translations.count
        }
        if !tafsir.isEmpty {
            try await quranRepository.upsertTafsir(tafsir)
            imported += tafsir.count
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
            print("ContentSyncService: seed bundle contained no records; skipping version stamp.")
            return 0
        }

        try await writeValue(String(targetVersion), forKey: Keys.seedVersion)
        try await searchIndex.reindex(domains: SearchDomain.allCases)
        return imported
    }

    // MARK: - Remote refresh

    func refreshFromRemoteManifest() async throws {
        guard let manifestURL = URL(string: Self.remoteManifestURLString) else { return }

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

        let appliedVersion = try await readIntValue(forKey: Keys.remoteVersion) ?? 0
        guard manifest.version > appliedVersion else { return }

        var updatedDomains: [SearchDomain] = []

        if let mediaPath = manifest.files["media_items"],
           let mediaURL = Self.resolve(mediaPath, against: manifestURL) {
            let items = await Self.fetchArray(MediaItem.self, from: mediaURL)
                .filter { !$0.id.isEmpty && !$0.title.isEmpty }
            if !items.isEmpty {
                try await mediaRepository.upsertItems(items)
                updatedDomains.append(.media)
            }
        }

        if let eventsPath = manifest.files["events"],
           let eventsURL = Self.resolve(eventsPath, against: manifestURL) {
            let events = await Self.fetchArray(CommunityEvent.self, from: eventsURL)
                .filter { !$0.id.isEmpty && !$0.title.isEmpty }
            if !events.isEmpty {
                try await eventsRepository.upsertEvents(events)
                updatedDomains.append(.events)
            }
        }

        guard !updatedDomains.isEmpty else { return }
        try await writeValue(String(manifest.version), forKey: Keys.remoteVersion)
        try await searchIndex.reindex(domains: updatedDomains)
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
            print("ContentSyncService: could not fetch \(url.absoluteString) — \(error)")
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
