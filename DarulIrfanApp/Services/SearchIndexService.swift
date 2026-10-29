import Foundation

// MARK: - Folding

/// Folds Arabic and Urdu text to the form the search index holds, so a word
/// matches however it was typed: with or without harakat, on an Arabic or an
/// Urdu keyboard.
///
/// Drops the harakat, the Qur'anic annotation and pause signs, tatweel, soft
/// hyphens and the invisible joiners and direction marks, and folds the
/// Arabic and Urdu forms of one letter together (أ إ آ ٱ → ا; ى ي ئ → ی;
/// ك → ک; ة ۃ ه ھ → ہ; ؤ → و) and Arabic-Indic digits to 0-9. Latin text is
/// left as it is: the index's tokenizer already ignores its case and accents.
/// Used only for matching; nothing folded is ever shown.
enum SearchNormalizer {
    static func normalize(_ text: String) -> String {
        var view = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !isDropped(scalar.value) {
            view.append(foldedLetter(scalar))
        }
        return String(view)
    }

    /// The one form of a letter that Arabic and Urdu write in several ways.
    static func foldedLetter(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        folds[scalar.value] ?? scalar
    }

    private static func isDropped(_ value: UInt32) -> Bool {
        switch value {
        case 0x0610...0x061A, 0x064B...0x065F, 0x0670, 0x0640,
             0x06D6...0x06ED, 0x08D3...0x08FF,
             0x200B...0x200F, 0x202A...0x202E, 0x2066...0x2069, 0xFEFF, 0x00AD:
            return true
        default:
            return false
        }
    }

    private static let folds: [UInt32: Unicode.Scalar] = {
        var map: [UInt32: Unicode.Scalar] = [:]
        let groups: [(String, Unicode.Scalar)] = [
            ("\u{0623}\u{0625}\u{0622}\u{0671}\u{0672}\u{0673}", "\u{0627}"),
            ("\u{0649}\u{064A}\u{0626}\u{06D0}\u{06CD}", "\u{06CC}"),
            ("\u{0643}\u{06AA}", "\u{06A9}"),
            ("\u{0629}\u{06C3}\u{0647}\u{06BE}\u{06C0}", "\u{06C1}"),
            ("\u{0624}", "\u{0648}"),
        ]
        for (variants, letter) in groups {
            for scalar in variants.unicodeScalars { map[scalar.value] = letter }
        }
        for digit in 0..<10 {
            guard let ascii = Unicode.Scalar(UInt32(0x30 + digit)) else { continue }
            map[UInt32(0x0660 + digit)] = ascii
            map[UInt32(0x06F0 + digit)] = ascii
        }
        return map
    }()
}

// MARK: - Snippets

/// The few words shown under a search result. Taken from the original text,
/// never the folded form the index holds, so the Qur'an keeps its harakat;
/// the matched words are marked ‹ › for `SearchSnippetFormatter`.
enum SearchSnippet {
    static func make(from text: String, terms: [String], radius: Int = 7) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        let needles = terms.map(fold).filter { !$0.isEmpty }
        func matches(_ word: Substring) -> Bool {
            let folded = fold(SearchNormalizer.normalize(String(word)))
                .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            return !folded.isEmpty && needles.contains { folded.hasPrefix($0) }
        }
        let hit = words.firstIndex(where: matches) ?? 0
        let start = max(0, hit - radius)
        let end = min(words.count, hit + radius + 1)
        var snippet = words[start..<end]
            .map { matches($0) ? "\u{2039}\($0)\u{203A}" : String($0) }
            .joined(separator: " ")
        if start > 0 { snippet = "\u{2026} " + snippet }
        if end < words.count { snippet += " \u{2026}" }
        return snippet
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

// MARK: - Index state

/// The large index-only tables (schema v9) and the key_value rows that say
/// whether each is in step with the content it indexes.
enum SearchIndexState {
    enum Table: String, CaseIterable, Sendable {
        case hadith = "hadith_fts"
        case bookPages = "book_page_fts"
        case tafsir = "tafsir_fts"
    }

    static func key(_ table: Table) -> String { "search.fts.\(table.rawValue)" }

    /// Added to every batch that changes a table's content, so its index is
    /// rebuilt from the new rows. A fresh value each time lets a build that
    /// started before the change see that it is out of date.
    static func markStale(_ table: Table) -> (sql: String, parameters: [SQLValue]) {
        (
            """
            INSERT INTO key_value (key, value, updated_at) VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """,
            [.text(key(table)), .text("stale:" + UUID().uuidString), .date(Date())]
        )
    }

    static func isReady(_ table: Table, database: AppDatabase) async -> Bool {
        let rows = (try? await database.connection.query(
            "SELECT value FROM key_value WHERE key = ?", [.text(key(table))]
        )) ?? []
        return rows.first?.text("value") == "ready"
    }
}

// MARK: - Background builds

/// Builds the large index-only tables (hadith, book pages, per-ayah tafsir)
/// in the background whenever their content has changed, a chunk at a time
/// so other database work runs in between. Building them takes tens of
/// seconds on a phone; until a table is ready, the search that needs it says
/// what it does instead where it is queried.
actor LargeSearchIndexBuilder {
    static let shared = LargeSearchIndexBuilder()

    /// The build under way for each database, and the databases asked for
    /// again while theirs ran (their content may have changed meanwhile).
    private var running: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var requestedAgain: Set<ObjectIdentifier> = []
    private static let chunkSize = 800

    /// Builds every large index of `database` that is out of step with its
    /// content, and returns once they are built. Asked while a build runs,
    /// it waits for that one, which then goes round once more.
    func buildStaleIndexes(database: AppDatabase) async {
        let key = ObjectIdentifier(database)
        if let current = running[key] {
            requestedAgain.insert(key)
            await current.value
            return
        }
        let task = Task { await self.run(database: database, key: key) }
        running[key] = task
        await task.value
    }

    private func run(database: AppDatabase, key: ObjectIdentifier) async {
        repeat {
            requestedAgain.remove(key)
            for table in SearchIndexState.Table.allCases {
                await build(table, database: database)
            }
        } while requestedAgain.contains(key)
        running[key] = nil
    }

    private func build(_ table: SearchIndexState.Table, database: AppDatabase) async {
        let key = SearchIndexState.key(table)
        let connection = database.connection
        do {
            let state = try await connection.query(
                "SELECT value FROM key_value WHERE key = ?", [.text(key)]
            ).first?.text("value")
            if state == "ready" { return }
            try await connection.execute("INSERT INTO \(table.rawValue)(\(table.rawValue)) VALUES('delete-all')")
            var lastRowID: Int64 = 0
            while true {
                let rows = try await connection.query(Self.sourceSQL(table), [.integer(lastRowID), .int(Self.chunkSize)])
                guard !rows.isEmpty else { break }
                var inserts: [(sql: String, parameters: [SQLValue])] = []
                for row in rows {
                    guard let rowID = row.int64("rid") else { continue }
                    lastRowID = max(lastRowID, rowID)
                    let body = SearchNormalizer.normalize(Self.text(of: row, in: table))
                    guard !body.isEmpty else { continue }
                    inserts.append((
                        sql: "INSERT INTO \(table.rawValue)(rowid, body) VALUES (?, ?)",
                        parameters: [.integer(rowID), .text(body)]
                    ))
                }
                if !inserts.isEmpty { try await connection.executeBatch(inserts) }
            }
            // Ready only if no write changed the content while this ran;
            // otherwise the next round builds it again.
            if let state {
                try await connection.execute(
                    "UPDATE key_value SET value = 'ready', updated_at = ? WHERE key = ? AND value = ?",
                    [.date(Date()), .text(key), .text(state)]
                )
            } else {
                try await connection.execute(
                    """
                    INSERT INTO key_value (key, value, updated_at) VALUES (?, 'ready', ?)
                    ON CONFLICT(key) DO NOTHING
                    """,
                    [.text(key), .date(Date())]
                )
            }
        } catch {
            AppLog.search("Building \(table.rawValue) failed: \(error.localizedDescription)")
        }
    }

    private static func sourceSQL(_ table: SearchIndexState.Table) -> String {
        switch table {
        case .hadith:
            return """
            SELECT rowid AS rid, text_ar, text_en, text_ur, urdu_sanad, urdu_text
            FROM hadith_entries WHERE rowid > ? ORDER BY rowid LIMIT ?
            """
        case .bookPages:
            return "SELECT rowid AS rid, text FROM book_pages WHERE rowid > ? ORDER BY rowid LIMIT ?"
        case .tafsir:
            return "SELECT rowid AS rid, text FROM quran_tafsir WHERE rowid > ? ORDER BY rowid LIMIT ?"
        }
    }

    private static func text(of row: SQLRow, in table: SearchIndexState.Table) -> String {
        switch table {
        case .hadith:
            return ["text_ar", "text_en", "text_ur", "urdu_sanad", "urdu_text"]
                .compactMap { row.text($0) }
                .joined(separator: "\n")
        case .bookPages, .tafsir:
            return row.text("text") ?? ""
        }
    }
}

// MARK: - Result locators

extension SearchResult {
    /// A hit on one page of a book's text: which book, which page.
    var bookPage: (bookID: String, page: Int)? {
        let parts = itemID.split(separator: "|", omittingEmptySubsequences: false)
        guard domain == .library, parts.count == 3, parts[0] == "bookpage",
              let page = Int(parts[2]) else { return nil }
        return (String(parts[1]), page)
    }

    /// The ayah a Qur'an hit opens at: the ayah itself, or the first ayah of
    /// the tafsir passage that matched.
    var ayahReference: (surah: Int, ayah: Int)? {
        guard domain == .quran else { return nil }
        let reference = itemID.split(separator: "|").last.map(String.init) ?? itemID
        let numbers = reference.split(separator: ":").compactMap { Int($0) }
        guard numbers.count == 2 else { return nil }
        return (numbers[0], numbers[1])
    }
}

// MARK: - Service

/// Maintains and queries the search tables (AppDatabase schema v9).
///
/// `search_fts` holds the Qur'an (each ayah with every translation, the
/// Silsila's Asrar-at-Tanzil English included), the library catalogue, the
/// media and the events, as folded text plus the original for display. Each
/// section is rebuilt atomically - delete and inserts in one transaction - so
/// it is never left half-populated. The per-ayah tafsir, the book pages and
/// the hadith have their own index-only tables, built in the background by
/// `LargeSearchIndexBuilder`; the hadith section is answered from its table
/// alone, by the query the Hadith tab runs.
///
/// Every section is searched with its own limit, so a common word's Qur'an
/// hits cannot crowd the books and lectures out of "All".
struct SearchIndexService: SearchIndexServicing {

    // MARK: Stored dependencies (order matches AppDependencies.live())

    let database: AppDatabase
    let quranRepository: any QuranRepositoryProtocol
    let contentRepository: any ContentRepositoryProtocol
    let mediaRepository: any MediaRepositoryProtocol
    let eventsRepository: any EventsRepositoryProtocol

    init(
        database: AppDatabase,
        quranRepository: any QuranRepositoryProtocol,
        contentRepository: any ContentRepositoryProtocol,
        mediaRepository: any MediaRepositoryProtocol,
        eventsRepository: any EventsRepositoryProtocol
    ) {
        self.database = database
        self.quranRepository = quranRepository
        self.contentRepository = contentRepository
        self.mediaRepository = mediaRepository
        self.eventsRepository = eventsRepository
    }

    /// Practical upper bound when reading whole catalogs for indexing.
    private static let fetchLimit = 100_000

    private static let insertSQL = """
    INSERT INTO search_fts (domain, item_id, title, body, author, language, display_title, display_body)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """

    private static let readyKeyPrefix = "search.fts.domain."

    /// The sections `search_fts` holds: all but the hadith.
    private static let tableDomains = SearchDomain.allCases.filter { $0 != .hadith }

    // MARK: - Reindex

    func reindex(domains: [SearchDomain]) async throws {
        for domain in domains {
            let inserts: [(sql: String, parameters: [SQLValue])]
            switch domain {
            case .quran:
                inserts = try await quranRows()
            case .library:
                inserts = try await libraryRows()
            case .media:
                inserts = try await mediaRows()
            case .events:
                inserts = try await eventRows()
            case .hadith:
                // Its index is `hadith_fts`, built by LargeSearchIndexBuilder
                // (scheduled below), not rows of `search_fts`.
                continue
            }

            var statements: [(sql: String, parameters: [SQLValue])] = [
                ("DELETE FROM search_fts WHERE domain = ?", [.text(domain.rawValue)])
            ]
            statements.append(contentsOf: inserts)
            statements.append((
                """
                INSERT INTO key_value (key, value, updated_at) VALUES (?, 'ready', ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
                """,
                [.text(Self.readyKeyPrefix + domain.rawValue), .date(Date())]
            ))
            try await database.connection.executeBatch(statements)
        }
        await dropLegacyIndexIfSuperseded()
        Self.scheduleLargeIndexBuild(database: database)
    }

    /// Starts (or queues) the background build of whichever large index is
    /// out of step with its content. Returns at once.
    static func scheduleLargeIndexBuild(database: AppDatabase) {
        Task.detached(priority: .utility) {
            await LargeSearchIndexBuilder.shared.buildStaleIndexes(database: database)
        }
    }

    /// - Parameter matchOnly: more text to match that is not shown - another
    ///   spelling of the body's words.
    private func insertStatement(
        domain: SearchDomain,
        itemID: String,
        title: String,
        body: String,
        author: String?,
        language: String?,
        matchOnly: String? = nil
    ) -> (sql: String, parameters: [SQLValue]) {
        var folded = SearchNormalizer.normalize(body)
        if let matchOnly { folded += "\n" + SearchNormalizer.normalize(matchOnly) }
        return (
            Self.insertSQL,
            [
                .text(domain.rawValue),
                .text(itemID),
                .text(SearchNormalizer.normalize(title)),
                .text(folded),
                .optionalText(author.map(SearchNormalizer.normalize)),
                .optionalText(language),
                .text(title),
                .text(body)
            ]
        )
    }

    /// The mushaf writes some long "a" sounds as a waw under a standing alef
    /// (الصلوٰة, الزكوٰة, الحيوٰة) where ordinary Arabic writes an alef (الصلاة).
    /// Indexing that spelling as well lets the ordinary one find the ayah.
    private static func ordinarySpelling(of mushaf: String) -> String {
        mushaf.replacingOccurrences(of: "\u{0670}\u{0648}", with: "\u{0627}", options: .literal)
    }

    /// One row per ayah that has bundled/downloaded Arabic text. Body holds
    /// the Arabic plus every stored translation - Akram-ut-Tarajum in both
    /// languages and Asrar-at-Tanzil's own English, which is stored under its
    /// tafsir edition - so English and Urdu queries match too.
    private func quranRows() async throws -> [(sql: String, parameters: [SQLValue])] {
        let surahs = try await quranRepository.allSurahs()
        let surahsByNumber = Dictionary(
            surahs.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let editions = try await quranRepository.editions()
        let surahNumbers = try await quranRepository.surahNumbersWithText()

        var rows: [(sql: String, parameters: [SQLValue])] = []
        for surahNumber in surahNumbers {
            let ayahs = try await quranRepository.ayahs(inSurah: surahNumber)
            guard !ayahs.isEmpty else { continue }

            var translationsByAyah: [Int: [String]] = [:]
            for edition in editions {
                let translations = try await quranRepository.translations(
                    editionID: edition.id,
                    surahNumber: surahNumber
                )
                for translation in translations where !translation.text.isEmpty {
                    translationsByAyah[translation.ayahNumber, default: []].append(translation.text)
                }
            }

            let surahName = surahsByNumber[surahNumber]?.nameTransliterated ?? "\(surahNumber)"
            for ayah in ayahs {
                var bodyParts: [String] = [ayah.textArabic]
                if let extra = translationsByAyah[ayah.ayahNumber] {
                    bodyParts.append(contentsOf: extra)
                }
                let ordinary = Self.ordinarySpelling(of: ayah.textArabic)
                rows.append(insertStatement(
                    domain: .quran,
                    itemID: ayah.id,
                    title: "Surah \(surahName) \(ayah.surahNumber):\(ayah.ayahNumber)",
                    body: bodyParts.joined(separator: "\n"),
                    author: nil,
                    language: "ar",
                    matchOnly: ordinary == ayah.textArabic ? nil : ordinary
                ))
            }
        }
        return rows
    }

    private func libraryRows() async throws -> [(sql: String, parameters: [SQLValue])] {
        let items = try await contentRepository.items(
            category: nil,
            type: nil,
            language: nil,
            limit: Self.fetchLimit
        )
        return items.map { item in
            var bodyParts: [String] = []
            if let titleUrdu = item.titleUrdu, !titleUrdu.isEmpty {
                bodyParts.append(titleUrdu)
            }
            if let body = item.bodyPlainText, !body.isEmpty {
                bodyParts.append(body)
            }
            if let excerpt = item.excerpt, !excerpt.isEmpty {
                bodyParts.append(excerpt)
            }
            return insertStatement(
                domain: .library,
                itemID: item.id,
                title: item.title,
                body: bodyParts.joined(separator: "\n"),
                author: item.author,
                language: item.language
            )
        }
    }

    private func mediaRows() async throws -> [(sql: String, parameters: [SQLValue])] {
        let items = try await mediaRepository.items(
            category: nil,
            year: nil,
            month: nil,
            limit: Self.fetchLimit
        )
        return items.map { item in
            insertStatement(
                domain: .media,
                itemID: item.id,
                title: item.title,
                body: "",
                author: item.speaker,
                language: item.language
            )
        }
    }

    private func eventRows() async throws -> [(sql: String, parameters: [SQLValue])] {
        let events = try await eventsRepository.events()
        return events.map { event in
            var bodyParts: [String] = []
            if let titleUrdu = event.titleUrdu, !titleUrdu.isEmpty {
                bodyParts.append(titleUrdu)
            }
            if let details = event.details, !details.isEmpty {
                bodyParts.append(details)
            }
            return insertStatement(
                domain: .events,
                itemID: event.id,
                title: event.title,
                body: bodyParts.joined(separator: "\n"),
                author: nil,
                language: nil
            )
        }
    }

    /// The v1 table answers only until `search_fts` holds every section.
    private func dropLegacyIndexIfSuperseded() async {
        let ready = await readyDomains()
        guard Self.tableDomains.allSatisfy({ ready.contains($0) }) else { return }
        try? await database.connection.execute("DROP TABLE IF EXISTS search_index")
    }

    private func readyDomains() async -> Set<SearchDomain> {
        let rows = (try? await database.connection.query(
            "SELECT key FROM key_value WHERE key LIKE 'search.fts.domain.%' AND value = 'ready'"
        )) ?? []
        return Set(rows.compactMap { row in
            row.text("key").flatMap { SearchDomain(rawValue: String($0.dropFirst(Self.readyKeyPrefix.count))) }
        })
    }

    // MARK: - Search

    /// Searches each domain with its own `limit`. The Qur'an also returns
    /// matching tafsir passages, and the library matching pages of the books'
    /// text, after the domain's own rows. The hadith come from their own
    /// index.
    func search(
        _ query: String,
        domains: [SearchDomain],
        limit: Int
    ) async throws -> [SearchResult] {
        let terms = Self.searchTerms(from: query)
        let expression = Self.matchExpression(for: terms)
        guard !expression.isEmpty, !domains.isEmpty else { return [] }

        let perDomain = max(1, limit)
        let extra = max(1, perDomain / 2)
        let highlight = Self.allSpellings(of: terms)
        let ready = await readyDomains()
        var results: [SearchResult] = []
        var unbuilt: [SearchDomain] = []
        for domain in domains {
            var hits: [SearchResult]
            if domain == .hadith {
                hits = await hadithHits(matching: query, limit: perDomain, highlight: highlight)
            } else if ready.contains(domain) {
                hits = await rows(matching: expression, domain: domain, limit: perDomain, highlight: highlight)
            } else {
                // Built at the next content import; until then the v1 table
                // still answers, and the section is built now in the
                // background.
                unbuilt.append(domain)
                hits = await legacyRows(matching: query, domain: domain, limit: perDomain)
            }
            switch domain {
            case .quran:
                hits += await tafsirHits(matching: expression, limit: extra, highlight: highlight)
            case .library:
                hits += await bookPageHits(matching: expression, limit: extra, highlight: highlight)
            case .hadith, .media, .events:
                break
            }
            results += hits
        }
        if !unbuilt.isEmpty {
            let service = self
            let pending = unbuilt
            Task.detached(priority: .utility) { try? await service.reindex(domains: pending) }
        }
        return results
    }

    private func rows(
        matching expression: String,
        domain: SearchDomain,
        limit: Int,
        highlight: [String]
    ) async -> [SearchResult] {
        let found: [SQLRow]
        do {
            found = try await database.connection.query(
                """
                SELECT item_id, display_title, display_body, language
                FROM search_fts
                WHERE search_fts MATCH ? AND domain = ?
                ORDER BY rank
                LIMIT ?
                """,
                [.text(expression), .text(domain.rawValue), .int(limit)]
            )
        } catch {
            // A query the FTS parser rejects should read as "no results",
            // never as a failure surfaced to the person searching.
            AppLog.search("Search query failed: \(error.localizedDescription)")
            return []
        }
        return found.compactMap { row in
            guard let itemID = row.text("item_id"), let title = row.text("display_title") else { return nil }
            return SearchResult(
                domain: domain,
                itemID: itemID,
                title: title,
                snippet: row.text("display_body").flatMap { SearchSnippet.make(from: $0, terms: highlight) },
                language: row.text("language")
            )
        }
    }

    /// Per-ayah tafsir passages (Akram-ut-Tafaseer, Asrar-at-Tanzil English).
    private func tafsirHits(matching expression: String, limit: Int, highlight: [String]) async -> [SearchResult] {
        guard await isLargeIndexReady(.tafsir) else { return [] }
        let rows = (try? await database.connection.query(
            """
            SELECT t.edition_id, t.surah_number, t.ayah_start, t.text,
                   e.title AS edition_title, e.language AS language,
                   s.name_transliterated AS surah_name
            FROM (SELECT rowid AS rid, rank AS score FROM tafsir_fts
                  WHERE tafsir_fts MATCH ? ORDER BY rank LIMIT ?) AS hit
            JOIN quran_tafsir t ON t.rowid = hit.rid
            LEFT JOIN quran_editions e ON e.id = t.edition_id
            LEFT JOIN quran_surahs s ON s.number = t.surah_number
            ORDER BY hit.score
            """,
            [.text(expression), .int(limit)]
        )) ?? []
        return rows.compactMap { row in
            guard let edition = row.text("edition_id"),
                  let surah = row.int("surah_number"),
                  let ayah = row.int("ayah_start") else { return nil }
            let work = row.text("edition_title") ?? edition
            let name = row.text("surah_name") ?? "\(surah)"
            return SearchResult(
                domain: .quran,
                itemID: "tafsir|\(edition)|\(surah):\(ayah)",
                title: "\(work) — Surah \(name) \(surah):\(ayah)",
                snippet: row.text("text").flatMap { SearchSnippet.make(from: $0, terms: highlight) },
                language: row.text("language")
            )
        }
    }

    /// Pages of the books' and tafsir volumes' text (book_pages).
    private func bookPageHits(matching expression: String, limit: Int, highlight: [String]) async -> [SearchResult] {
        guard await isLargeIndexReady(.bookPages) else { return [] }
        let rows = (try? await database.connection.query(
            """
            SELECT p.book_id, p.page, p.text, c.title AS title, c.language AS language
            FROM (SELECT rowid AS rid, rank AS score FROM book_page_fts
                  WHERE book_page_fts MATCH ? ORDER BY rank LIMIT ?) AS hit
            JOIN book_pages p ON p.rowid = hit.rid
            LEFT JOIN content_items c ON c.id = p.book_id
            ORDER BY hit.score
            """,
            [.text(expression), .int(limit)]
        )) ?? []
        return rows.compactMap { row in
            guard let bookID = row.text("book_id"), let page = row.int("page") else { return nil }
            let title = row.text("title") ?? bookID
            return SearchResult(
                domain: .library,
                itemID: "bookpage|\(bookID)|\(page)",
                title: "\(title) — " + String(localized: "Page \(page)"),
                snippet: row.text("text").flatMap { SearchSnippet.make(from: $0, terms: highlight) },
                language: row.text("language") ?? "ur"
            )
        }
    }

    /// Narrations from every collection, by the same query the Hadith tab
    /// runs (`HadithRepository.search`: `hadith_fts`, a few per collection,
    /// the two Sahihs first). A row shows the words found, in whichever
    /// script they are, under the collection's name in that script.
    private func hadithHits(matching query: String, limit: Int, highlight: [String]) async -> [SearchResult] {
        let repository = HadithRepository(database: database)
        let entries = (try? await repository.search(query, bookID: nil, limit: limit)) ?? []
        guard !entries.isEmpty else { return [] }
        let books = Dictionary(
            ((try? await repository.books()) ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return entries.map { entry in
            let snippets = Self.hadithTexts(of: entry).compactMap { text -> (snippet: String, language: String)? in
                SearchSnippet.make(from: text.text, terms: highlight).map { (snippet: $0, language: text.language) }
            }
            // The text the words were found in; the first there is otherwise.
            let shown = snippets.first { $0.snippet.contains("\u{2039}") } ?? snippets.first
            var collection = entry.bookID
            if let book = books[entry.bookID] {
                let inUrdu = shown.map { $0.language != "en" } ?? false
                collection = inUrdu && !book.titleUrdu.isEmpty ? book.titleUrdu : book.titleEnglish
            }
            return SearchResult(
                domain: .hadith,
                itemID: entry.canonicalID,
                title: "\(collection) \(entry.displayNumber)",
                snippet: shown?.snippet,
                language: shown?.language
            )
        }
    }

    /// A narration's English, Urdu and Arabic, each that it has.
    private static func hadithTexts(of entry: HadithEntry) -> [(text: String, language: String)] {
        let wholeUrdu: String? = entry.textUrdu.flatMap { $0.isEmpty ? nil : $0 }
        let urdu: String = wholeUrdu ?? [entry.urduSanad, entry.urduText].compactMap { $0 }.joined(separator: " ")
        let candidates: [(text: String?, language: String)] = [
            (entry.textEnglish, "en"),
            (urdu, "ur"),
            (entry.textArabic, "ar"),
        ]
        return candidates.compactMap { candidate -> (text: String, language: String)? in
            guard let text = candidate.text, !text.isEmpty else { return nil }
            return (text: text, language: candidate.language)
        }
    }

    private func isLargeIndexReady(_ table: SearchIndexState.Table) async -> Bool {
        if await SearchIndexState.isReady(table, database: database) { return true }
        Self.scheduleLargeIndexBuild(database: database)
        return false
    }

    /// The v1 `search_index`, read the way it always was, for a section
    /// `search_fts` does not hold yet.
    private func legacyRows(matching query: String, domain: SearchDomain, limit: Int) async -> [SearchResult] {
        let expression = Self.legacyMatchExpression(from: query)
        guard !expression.isEmpty else { return [] }
        let rows = (try? await database.connection.query(
            """
            SELECT item_id, title, language,
                   snippet(search_index, 3, '‹', '›', '…', 12) AS snippet
            FROM search_index
            WHERE search_index MATCH ? AND domain = ?
            ORDER BY rank
            LIMIT ?
            """,
            [.text(expression), .text(domain.rawValue), .int(limit)]
        )) ?? []
        return rows.compactMap { row in
            guard let itemID = row.text("item_id"), let title = row.text("title") else { return nil }
            return SearchResult(
                domain: domain,
                itemID: itemID,
                title: title,
                snippet: row.text("snippet"),
                language: row.text("language")
            )
        }
    }

    // MARK: - Query building

    /// The query's words as the index holds them: double quotes and control
    /// characters removed, Arabic and Urdu folded (`SearchNormalizer`).
    static func searchTerms(from query: String) -> [String] {
        query
            .components(separatedBy: .whitespacesAndNewlines)
            .map { term -> String in
                SearchNormalizer.normalize(term.filter { character in
                    character != "\"" && !character.unicodeScalars.contains { scalar in
                        CharacterSet.controlCharacters.contains(scalar)
                    }
                })
            }
            .filter { !$0.isEmpty }
    }

    /// Turns free text into a safe FTS5 expression: each whitespace-separated
    /// term is stripped of double quotes, folded, wrapped in double quotes
    /// (which neutralizes every FTS5 operator), and given a trailing `*` for
    /// prefix matching. Terms are implicitly ANDed. Empty input yields "". A
    /// word typed in Roman Urdu also matches its Urdu spellings: "namaz"
    /// searches ("namaz"* OR "نماز"* OR "صلوہ"*).
    static func ftsMatchExpression(from query: String) -> String {
        matchExpression(for: searchTerms(from: query))
    }

    private static func matchExpression(for terms: [String]) -> String {
        guard !terms.isEmpty else { return "" }
        return terms.map { term in
            let variants = spellings(of: term)
            guard variants.count > 1 else { return "\"\(term)\"*" }
            return "(" + variants.map { "\"\($0)\"*" }.joined(separator: " OR ") + ")"
        }
        // Explicit AND: FTS5 rejects a bracketed group followed by a bare term.
        .joined(separator: " AND ")
    }

    /// A term and, when it is Roman Urdu, its folded Urdu spellings.
    private static func spellings(of term: String) -> [String] {
        var result = [term]
        for spelling in RomanUrdu.spellings(for: term) {
            let folded = SearchNormalizer.normalize(spelling)
            if !folded.isEmpty, !result.contains(folded) { result.append(folded) }
        }
        return result
    }

    /// Every spelling a result's snippet should mark as matched.
    static func allSpellings(of terms: [String]) -> [String] {
        terms.flatMap { spellings(of: $0) }
    }

    /// The expression the v1 table was queried with: unfolded terms.
    private static func legacyMatchExpression(from query: String) -> String {
        let terms = query
            .components(separatedBy: .whitespacesAndNewlines)
            .map { term -> String in
                term.filter { character in
                    character != "\"" && !character.unicodeScalars.contains { scalar in
                        CharacterSet.controlCharacters.contains(scalar)
                    }
                }
            }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return "" }
        return terms.map { term in
            let spellings = RomanUrdu.spellings(for: term)
            guard !spellings.isEmpty else { return "\"\(term)\"*" }
            return "(" + ([term] + spellings).map { "\"\($0)\"*" }.joined(separator: " OR ") + ")"
        }
        .joined(separator: " AND ")
    }
}
