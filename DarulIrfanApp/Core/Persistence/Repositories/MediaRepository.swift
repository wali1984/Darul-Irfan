import Foundation

/// Live SQLite-backed implementation of `MediaRepositoryProtocol`.
/// Column names follow schema v1 in `AppDatabase.migrationV1` exactly.
///
/// Enum handling on read: rows whose `media_type` or `category` raw value is
/// unknown are skipped (this build cannot present them); an unknown
/// `rights_status` falls back to `.linkOnly`, the most restrictive option.
struct MediaRepository: MediaRepositoryProtocol {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Catalog

    func items(
        category: MediaCategory?,
        year: Int?,
        month: Int?,
        limit: Int
    ) async throws -> [MediaItem] {
        var conditions: [String] = []
        var parameters: [SQLValue] = []
        if let category {
            conditions.append("category = ?")
            parameters.append(.text(category.rawValue))
        }
        if let year {
            conditions.append("year = ?")
            parameters.append(.int(year))
        }
        if let month {
            conditions.append("month = ?")
            parameters.append(.int(month))
        }

        var sql = """
        SELECT id, title, language, speaker, date, duration_seconds, media_type,
               source_url, stream_url, download_url, youtube_id, year, month,
               category, transcript_url, rights_status
        FROM media_items
        """
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }
        // SQLite sorts NULLs last in DESC order, so undated items trail.
        sql += " ORDER BY date DESC, title ASC LIMIT ?"
        parameters.append(.int(limit))

        let rows = try await database.connection.query(sql, parameters)
        return rows.compactMap { Self.mediaItem(from: $0) }
    }

    func item(id: String) async throws -> MediaItem? {
        let rows = try await database.connection.query(
            """
            SELECT id, title, language, speaker, date, duration_seconds, media_type,
                   source_url, stream_url, download_url, youtube_id, year, month,
                   category, transcript_url, rights_status
            FROM media_items
            WHERE id = ?
            LIMIT 1
            """,
            [.text(id)]
        )
        guard let row = rows.first else { return nil }
        return Self.mediaItem(from: row)
    }

    func availableYears(category: MediaCategory?) async throws -> [Int] {
        var sql = "SELECT DISTINCT year FROM media_items WHERE year IS NOT NULL"
        var parameters: [SQLValue] = []
        if let category {
            sql += " AND category = ?"
            parameters.append(.text(category.rawValue))
        }
        sql += " ORDER BY year DESC"
        let rows = try await database.connection.query(sql, parameters)
        return rows.compactMap { $0.int("year") }
    }

    // MARK: - Playback progress

    func playbackProgress(mediaItemID: String) async throws -> PlaybackProgress? {
        let rows = try await database.connection.query(
            """
            SELECT media_item_id, position_seconds, duration_seconds, updated_at
            FROM playback_progress
            WHERE media_item_id = ?
            LIMIT 1
            """,
            [.text(mediaItemID)]
        )
        guard let row = rows.first else { return nil }
        return Self.playbackProgress(
            from: row,
            itemColumn: "media_item_id",
            positionColumn: "position_seconds",
            durationColumn: "duration_seconds",
            updatedColumn: "updated_at"
        )
    }

    func savePlaybackProgress(_ progress: PlaybackProgress) async throws {
        try await database.connection.execute(
            """
            INSERT INTO playback_progress (media_item_id, position_seconds,
                duration_seconds, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(media_item_id) DO UPDATE SET
                position_seconds = excluded.position_seconds,
                duration_seconds = excluded.duration_seconds,
                updated_at = excluded.updated_at
            """,
            [
                .text(progress.mediaItemID),
                .real(progress.positionSeconds),
                .real(progress.durationSeconds),
                .date(progress.updatedAt),
            ]
        )
    }

    func recentlyPlayed(limit: Int) async throws -> [(item: MediaItem, progress: PlaybackProgress)] {
        // Progress columns are aliased so they cannot collide with the media
        // item's own duration column in the joined row.
        let rows = try await database.connection.query(
            """
            SELECT m.id AS id, m.title AS title, m.language AS language,
                   m.speaker AS speaker, m.date AS date,
                   m.duration_seconds AS duration_seconds,
                   m.media_type AS media_type, m.source_url AS source_url,
                   m.stream_url AS stream_url, m.download_url AS download_url,
                   m.youtube_id AS youtube_id, m.year AS year, m.month AS month,
                   m.category AS category, m.transcript_url AS transcript_url,
                   m.rights_status AS rights_status,
                   p.media_item_id AS progress_media_item_id,
                   p.position_seconds AS progress_position_seconds,
                   p.duration_seconds AS progress_duration_seconds,
                   p.updated_at AS progress_updated_at
            FROM playback_progress AS p
            JOIN media_items AS m ON m.id = p.media_item_id
            ORDER BY p.updated_at DESC
            LIMIT ?
            """,
            [.int(limit)]
        )
        var results: [(item: MediaItem, progress: PlaybackProgress)] = []
        for row in rows {
            guard
                let item = Self.mediaItem(from: row),
                let progress = Self.playbackProgress(
                    from: row,
                    itemColumn: "progress_media_item_id",
                    positionColumn: "progress_position_seconds",
                    durationColumn: "progress_duration_seconds",
                    updatedColumn: "progress_updated_at"
                )
            else { continue }
            results.append((item: item, progress: progress))
        }
        return results
    }

    // MARK: - Media bookmarks

    func mediaBookmarks(mediaItemID: String?) async throws -> [MediaBookmark] {
        let rows: [SQLRow]
        if let mediaItemID {
            rows = try await database.connection.query(
                """
                SELECT id, media_item_id, position_seconds, note, created_at
                FROM media_bookmarks
                WHERE media_item_id = ?
                ORDER BY position_seconds ASC
                """,
                [.text(mediaItemID)]
            )
        } else {
            rows = try await database.connection.query(
                """
                SELECT id, media_item_id, position_seconds, note, created_at
                FROM media_bookmarks
                ORDER BY created_at DESC
                """
            )
        }
        return rows.compactMap { row in
            guard
                let idText = row.text("id"),
                let id = UUID(uuidString: idText),
                let itemID = row.text("media_item_id"),
                let position = row.double("position_seconds"),
                let createdAt = row.date("created_at")
            else { return nil }
            return MediaBookmark(
                id: id,
                mediaItemID: itemID,
                positionSeconds: position,
                note: row.text("note"),
                createdAt: createdAt
            )
        }
    }

    func addMediaBookmark(_ bookmark: MediaBookmark) async throws {
        try await database.connection.execute(
            """
            INSERT INTO media_bookmarks (id, media_item_id, position_seconds,
                note, created_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                media_item_id = excluded.media_item_id,
                position_seconds = excluded.position_seconds,
                note = excluded.note,
                created_at = excluded.created_at
            """,
            [
                .text(bookmark.id.uuidString),
                .text(bookmark.mediaItemID),
                .real(bookmark.positionSeconds),
                .optionalText(bookmark.note),
                .date(bookmark.createdAt),
            ]
        )
    }

    func removeMediaBookmark(id: UUID) async throws {
        try await database.connection.execute(
            "DELETE FROM media_bookmarks WHERE id = ?",
            [.text(id.uuidString)]
        )
    }

    // MARK: - Playlists

    func playlists() async throws -> [Playlist] {
        let rows = try await database.connection.query(
            """
            SELECT id, title, media_item_ids_json, created_at, updated_at
            FROM playlists
            ORDER BY updated_at DESC
            """
        )
        return rows.compactMap { row in
            guard
                let idText = row.text("id"),
                let id = UUID(uuidString: idText),
                let title = row.text("title"),
                let createdAt = row.date("created_at"),
                let updatedAt = row.date("updated_at")
            else { return nil }
            return Playlist(
                id: id,
                title: title,
                mediaItemIDs: decodeStringArray(row.text("media_item_ids_json")),
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    func savePlaylist(_ playlist: Playlist) async throws {
        try await database.connection.execute(
            """
            INSERT INTO playlists (id, title, media_item_ids_json, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                media_item_ids_json = excluded.media_item_ids_json,
                updated_at = excluded.updated_at
            """,
            [
                .text(playlist.id.uuidString),
                .text(playlist.title),
                .text(encodeStringArray(playlist.mediaItemIDs)),
                .date(playlist.createdAt),
                .date(playlist.updatedAt),
            ]
        )
    }

    func deletePlaylist(id: UUID) async throws {
        try await database.connection.execute(
            "DELETE FROM playlists WHERE id = ?",
            [.text(id.uuidString)]
        )
    }

    // MARK: - Import (seed / manifest sync)

    func upsertItems(_ items: [MediaItem]) async throws {
        guard !items.isEmpty else { return }
        let statements: [(sql: String, parameters: [SQLValue])] = items.map { item in
            (
                sql: """
                INSERT INTO media_items (id, title, language, speaker, date,
                    duration_seconds, media_type, source_url, stream_url,
                    download_url, youtube_id, year, month, category,
                    transcript_url, rights_status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    language = excluded.language,
                    speaker = excluded.speaker,
                    date = excluded.date,
                    duration_seconds = excluded.duration_seconds,
                    media_type = excluded.media_type,
                    source_url = excluded.source_url,
                    stream_url = excluded.stream_url,
                    download_url = excluded.download_url,
                    youtube_id = excluded.youtube_id,
                    year = excluded.year,
                    month = excluded.month,
                    category = excluded.category,
                    transcript_url = excluded.transcript_url,
                    rights_status = excluded.rights_status
                """,
                parameters: [
                    .text(item.id),
                    .text(item.title),
                    .text(item.language),
                    .optionalText(item.speaker),
                    .optionalDate(item.date),
                    .optionalReal(item.durationSeconds),
                    .text(item.mediaType.rawValue),
                    .text(item.sourceUrl),
                    .optionalText(item.streamUrl),
                    .optionalText(item.downloadUrl),
                    .optionalText(item.youtubeId),
                    .optionalInt(item.year),
                    .optionalInt(item.month),
                    .text(item.category.rawValue),
                    .optionalText(item.transcriptUrl),
                    .text(item.rightsStatus.rawValue),
                ]
            )
        }
        try await database.connection.executeBatch(statements)
    }

    // MARK: - Row mapping

    private static func mediaItem(from row: SQLRow) -> MediaItem? {
        guard
            let id = row.text("id"),
            let title = row.text("title"),
            let language = row.text("language"),
            let typeRaw = row.text("media_type"),
            let mediaType = MediaType(rawValue: typeRaw),
            let sourceUrl = row.text("source_url"),
            let categoryRaw = row.text("category"),
            let category = MediaCategory(rawValue: categoryRaw)
        else { return nil }
        let rightsRaw = row.text("rights_status") ?? ""
        let rights = RightsStatus(rawValue: rightsRaw) ?? .linkOnly
        return MediaItem(
            id: id,
            title: title,
            language: language,
            speaker: row.text("speaker"),
            date: row.date("date"),
            durationSeconds: row.double("duration_seconds"),
            mediaType: mediaType,
            sourceUrl: sourceUrl,
            streamUrl: row.text("stream_url"),
            downloadUrl: row.text("download_url"),
            youtubeId: row.text("youtube_id"),
            year: row.int("year"),
            month: row.int("month"),
            category: category,
            transcriptUrl: row.text("transcript_url"),
            rightsStatus: rights
        )
    }

    private static func playbackProgress(
        from row: SQLRow,
        itemColumn: String,
        positionColumn: String,
        durationColumn: String,
        updatedColumn: String
    ) -> PlaybackProgress? {
        guard
            let itemID = row.text(itemColumn),
            let position = row.double(positionColumn),
            let duration = row.double(durationColumn),
            let updatedAt = row.date(updatedColumn)
        else { return nil }
        return PlaybackProgress(
            mediaItemID: itemID,
            positionSeconds: position,
            durationSeconds: duration,
            updatedAt: updatedAt
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
