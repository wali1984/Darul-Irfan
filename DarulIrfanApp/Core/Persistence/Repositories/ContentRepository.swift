import Foundation

/// Live SQLite-backed implementation of `ContentRepositoryProtocol`.
/// Column names follow schema v1 in `AppDatabase.migrationV1` exactly.
///
/// Enum handling on read: rows whose `type` or `category` raw value is
/// unknown are skipped (they belong to a newer taxonomy this build does not
/// understand); an unknown `rights_status` falls back to `.linkOnly`, the
/// most restrictive option.
struct ContentRepository: ContentRepositoryProtocol {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Items

    func items(
        category: ContentCategory?,
        type: ContentType?,
        language: String?,
        limit: Int
    ) async throws -> [ContentItem] {
        var conditions: [String] = []
        var parameters: [SQLValue] = []
        if let category {
            conditions.append("category = ?")
            parameters.append(.text(category.rawValue))
        }
        if let type {
            conditions.append("type = ?")
            parameters.append(.text(type.rawValue))
        }
        if let language {
            conditions.append("language = ?")
            parameters.append(.text(language))
        }

        var sql = """
        SELECT id, source_url, type, title, title_urdu, language, author,
               category, body_html, body_plain_text, excerpt, published_at,
               updated_at, media_urls_json, download_urls_json, checksum,
               rights_status
        FROM content_items
        """
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }
        // SQLite sorts NULLs last in DESC order, so undated items trail.
        sql += " ORDER BY published_at DESC, title ASC LIMIT ?"
        parameters.append(.int(limit))

        let rows = try await database.connection.query(sql, parameters)
        return rows.compactMap { Self.contentItem(from: $0) }
    }

    func item(id: String) async throws -> ContentItem? {
        let rows = try await database.connection.query(
            """
            SELECT id, source_url, type, title, title_urdu, language, author,
                   category, body_html, body_plain_text, excerpt, published_at,
                   updated_at, media_urls_json, download_urls_json, checksum,
                   rights_status
            FROM content_items
            WHERE id = ?
            LIMIT 1
            """,
            [.text(id)]
        )
        guard let row = rows.first else { return nil }
        return Self.contentItem(from: row)
    }

    // MARK: - Collections

    func collections() async throws -> [ContentCollection] {
        let rows = try await database.connection.query(
            """
            SELECT id, title, category, item_ids_json
            FROM content_collections
            ORDER BY title ASC
            """
        )
        return rows.compactMap { row in
            guard
                let id = row.text("id"),
                let title = row.text("title"),
                let categoryRaw = row.text("category"),
                let category = ContentCategory(rawValue: categoryRaw)
            else { return nil }
            return ContentCollection(
                id: id,
                title: title,
                category: category,
                itemIDs: decodeStringArray(row.text("item_ids_json"))
            )
        }
    }

    // MARK: - Favorites

    func favorites() async throws -> [Favorite] {
        let rows = try await database.connection.query(
            """
            SELECT id, content_item_id, media_item_id, created_at
            FROM favorites
            ORDER BY created_at DESC
            """
        )
        return rows.compactMap { row in
            guard
                let idText = row.text("id"),
                let id = UUID(uuidString: idText),
                let createdAt = row.date("created_at")
            else { return nil }
            return Favorite(
                id: id,
                contentItemID: row.text("content_item_id"),
                mediaItemID: row.text("media_item_id"),
                createdAt: createdAt
            )
        }
    }

    func addFavorite(_ favorite: Favorite) async throws {
        try await database.connection.execute(
            """
            INSERT INTO favorites (id, content_item_id, media_item_id, created_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                content_item_id = excluded.content_item_id,
                media_item_id = excluded.media_item_id,
                created_at = excluded.created_at
            """,
            [
                .text(favorite.id.uuidString),
                .optionalText(favorite.contentItemID),
                .optionalText(favorite.mediaItemID),
                .date(favorite.createdAt),
            ]
        )
    }

    func removeFavorite(id: UUID) async throws {
        try await database.connection.execute(
            "DELETE FROM favorites WHERE id = ?",
            [.text(id.uuidString)]
        )
    }

    // MARK: - Reading progress

    func readingProgress(contentItemID: String) async throws -> ContentReadingProgress? {
        let rows = try await database.connection.query(
            """
            SELECT content_item_id, fraction, updated_at
            FROM content_reading_progress
            WHERE content_item_id = ?
            LIMIT 1
            """,
            [.text(contentItemID)]
        )
        guard
            let row = rows.first,
            let itemID = row.text("content_item_id"),
            let fraction = row.double("fraction"),
            let updatedAt = row.date("updated_at")
        else { return nil }
        return ContentReadingProgress(
            contentItemID: itemID,
            fraction: fraction,
            updatedAt: updatedAt
        )
    }

    func saveReadingProgress(_ progress: ContentReadingProgress) async throws {
        try await database.connection.execute(
            """
            INSERT INTO content_reading_progress (content_item_id, fraction, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(content_item_id) DO UPDATE SET
                fraction = excluded.fraction,
                updated_at = excluded.updated_at
            """,
            [
                .text(progress.contentItemID),
                .real(progress.fraction),
                .date(progress.updatedAt),
            ]
        )
    }

    // MARK: - Import (seed / manifest sync)

    func upsertItems(_ items: [ContentItem]) async throws {
        guard !items.isEmpty else { return }
        let statements: [(sql: String, parameters: [SQLValue])] = items.map { item in
            (
                sql: """
                INSERT INTO content_items (id, source_url, type, title, title_urdu,
                    language, author, category, body_html, body_plain_text, excerpt,
                    published_at, updated_at, media_urls_json, download_urls_json,
                    checksum, rights_status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    source_url = excluded.source_url,
                    type = excluded.type,
                    title = excluded.title,
                    title_urdu = excluded.title_urdu,
                    language = excluded.language,
                    author = excluded.author,
                    category = excluded.category,
                    body_html = excluded.body_html,
                    body_plain_text = excluded.body_plain_text,
                    excerpt = excluded.excerpt,
                    published_at = excluded.published_at,
                    updated_at = excluded.updated_at,
                    media_urls_json = excluded.media_urls_json,
                    download_urls_json = excluded.download_urls_json,
                    checksum = excluded.checksum,
                    rights_status = excluded.rights_status
                """,
                parameters: [
                    .text(item.id),
                    .text(item.sourceUrl),
                    .text(item.type.rawValue),
                    .text(item.title),
                    .optionalText(item.titleUrdu),
                    .text(item.language),
                    .optionalText(item.author),
                    .text(item.category.rawValue),
                    .optionalText(item.bodyHtml),
                    .optionalText(item.bodyPlainText),
                    .optionalText(item.excerpt),
                    .optionalDate(item.publishedAt),
                    .optionalDate(item.updatedAt),
                    .text(encodeStringArray(item.mediaUrls)),
                    .text(encodeStringArray(item.downloadUrls)),
                    .optionalText(item.checksum),
                    .text(item.rightsStatus.rawValue),
                ]
            )
        }
        try await database.connection.executeBatch(statements)
    }

    func upsertCollections(_ collections: [ContentCollection]) async throws {
        guard !collections.isEmpty else { return }
        let statements: [(sql: String, parameters: [SQLValue])] = collections.map { collection in
            (
                sql: """
                INSERT INTO content_collections (id, title, category, item_ids_json)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    category = excluded.category,
                    item_ids_json = excluded.item_ids_json
                """,
                parameters: [
                    .text(collection.id),
                    .text(collection.title),
                    .text(collection.category.rawValue),
                    .text(encodeStringArray(collection.itemIDs)),
                ]
            )
        }
        try await database.connection.executeBatch(statements)
    }

    // MARK: - Row mapping

    private static func contentItem(from row: SQLRow) -> ContentItem? {
        guard
            let id = row.text("id"),
            let sourceUrl = row.text("source_url"),
            let typeRaw = row.text("type"),
            let type = ContentType(rawValue: typeRaw),
            let title = row.text("title"),
            let language = row.text("language"),
            let categoryRaw = row.text("category"),
            let category = ContentCategory(rawValue: categoryRaw)
        else { return nil }
        let rightsRaw = row.text("rights_status") ?? ""
        let rights = RightsStatus(rawValue: rightsRaw) ?? .linkOnly
        return ContentItem(
            id: id,
            sourceUrl: sourceUrl,
            type: type,
            title: title,
            titleUrdu: row.text("title_urdu"),
            language: language,
            author: row.text("author"),
            category: category,
            bodyHtml: row.text("body_html"),
            bodyPlainText: row.text("body_plain_text"),
            excerpt: row.text("excerpt"),
            publishedAt: row.date("published_at"),
            updatedAt: row.date("updated_at"),
            mediaUrls: decodeStringArray(row.text("media_urls_json")),
            downloadUrls: decodeStringArray(row.text("download_urls_json")),
            checksum: row.text("checksum"),
            rightsStatus: rights
        )
    }
}

// MARK: - JSON array columns

private func encodeStringArray(_ values: [String]) -> String {
    guard
        let data = try? JSONEncoder().encode(values),
        let text = String(data: data, encoding: .utf8)
    else { return "[]" }
    return text
}

private func decodeStringArray(_ text: String?) -> [String] {
    guard
        let text,
        let data = text.data(using: .utf8),
        let values = try? JSONDecoder().decode([String].self, from: data)
    else { return [] }
    return values
}
