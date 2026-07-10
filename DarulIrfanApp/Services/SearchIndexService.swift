import Foundation

/// Maintains and queries the `search_index` FTS5 table (see AppDatabase
/// schema v1). Each domain's rows are rebuilt atomically — delete + inserts
/// run inside one transaction — so the index is never left half-populated.
///
/// FTS columns: domain(0), item_id(1), title(2), body(3), author(4),
/// language(5); item_id and language are UNINDEXED.
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
    INSERT INTO search_index (domain, item_id, title, body, author, language)
    VALUES (?, ?, ?, ?, ?, ?)
    """

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
            }

            var statements: [(sql: String, parameters: [SQLValue])] = [
                ("DELETE FROM search_index WHERE domain = ?", [.text(domain.rawValue)])
            ]
            statements.append(contentsOf: inserts)
            try await database.connection.executeBatch(statements)
        }
    }

    private func insertStatement(
        domain: SearchDomain,
        itemID: String,
        title: String,
        body: String,
        author: String?,
        language: String?
    ) -> (sql: String, parameters: [SQLValue]) {
        (
            Self.insertSQL,
            [
                .text(domain.rawValue),
                .text(itemID),
                .text(title),
                .text(body),
                .optionalText(author),
                .optionalText(language)
            ]
        )
    }

    /// One row per ayah that has bundled/downloaded Arabic text. Body holds
    /// the Arabic plus every available translation so English/Urdu queries
    /// match too.
    private func quranRows() async throws -> [(sql: String, parameters: [SQLValue])] {
        let surahs = try await quranRepository.allSurahs()
        let surahsByNumber = Dictionary(
            surahs.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let translationEditions = try await quranRepository.editions()
            .filter { $0.kind == .translation }
        let surahNumbers = try await quranRepository.surahNumbersWithText()

        var rows: [(sql: String, parameters: [SQLValue])] = []
        for surahNumber in surahNumbers {
            let ayahs = try await quranRepository.ayahs(inSurah: surahNumber)
            guard !ayahs.isEmpty else { continue }

            var translationsByAyah: [Int: [String]] = [:]
            for edition in translationEditions {
                let translations = try await quranRepository.translations(
                    editionID: edition.id,
                    surahNumber: surahNumber
                )
                for translation in translations {
                    translationsByAyah[translation.ayahNumber, default: []].append(translation.text)
                }
            }

            let surahName = surahsByNumber[surahNumber]?.nameTransliterated ?? "\(surahNumber)"
            for ayah in ayahs {
                var bodyParts: [String] = [ayah.textArabic]
                if let extra = translationsByAyah[ayah.ayahNumber] {
                    bodyParts.append(contentsOf: extra)
                }
                rows.append(insertStatement(
                    domain: .quran,
                    itemID: ayah.id,
                    title: "Surah \(surahName) \(ayah.surahNumber):\(ayah.ayahNumber)",
                    body: bodyParts.joined(separator: "\n"),
                    author: nil,
                    language: "ar"
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

    // MARK: - Search

    func search(
        _ query: String,
        domains: [SearchDomain],
        limit: Int
    ) async throws -> [SearchResult] {
        let matchExpression = Self.ftsMatchExpression(from: query)
        guard !matchExpression.isEmpty, !domains.isEmpty else { return [] }

        let domainPlaceholders = Array(repeating: "?", count: domains.count)
            .joined(separator: ", ")
        // snippet() column index 3 = body; matches wrapped in single angle
        // quotation marks for highlight rendering, 12 tokens of context.
        let sql = """
        SELECT domain, item_id, title, language,
               snippet(search_index, 3, '‹', '›', '…', 12) AS snippet
        FROM search_index
        WHERE search_index MATCH ?
          AND domain IN (\(domainPlaceholders))
        ORDER BY rank
        LIMIT ?
        """

        var parameters: [SQLValue] = [.text(matchExpression)]
        parameters.append(contentsOf: domains.map { .text($0.rawValue) })
        parameters.append(.int(max(1, limit)))

        let rows: [SQLRow]
        do {
            rows = try await database.connection.query(sql, parameters)
        } catch {
            // A query the FTS parser rejects should read as "no results",
            // never as a failure surfaced to the person searching.
            print("SearchIndexService: search failed — \(error)")
            return []
        }

        return rows.compactMap { row in
            guard
                let domainRaw = row.text("domain"),
                let domain = SearchDomain(rawValue: domainRaw),
                let itemID = row.text("item_id"),
                let title = row.text("title")
            else { return nil }
            return SearchResult(
                domain: domain,
                itemID: itemID,
                title: title,
                snippet: row.text("snippet"),
                language: row.text("language")
            )
        }
    }

    /// Turns free text into a safe FTS5 expression: each whitespace-separated
    /// term is stripped of double quotes, wrapped in double quotes (which
    /// neutralizes every FTS5 operator), and given a trailing `*` for prefix
    /// matching. Terms are implicitly ANDed. Empty input yields "".
    private static func ftsMatchExpression(from query: String) -> String {
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
        return terms.map { "\"\($0)\"*" }.joined(separator: " ")
    }
}
