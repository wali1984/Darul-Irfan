import Foundation

/// Live SQLite-backed implementation of `DownloadsRepositoryProtocol`.
/// Column names follow schema v1 in `AppDatabase.migrationV1` exactly.
struct DownloadsRepository: DownloadsRepositoryProtocol {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func allAssets() async throws -> [DownloadedAsset] {
        let rows = try await database.connection.query(
            """
            SELECT id, remote_url, relative_file_path, byte_size,
                   content_item_id, media_item_id, downloaded_at
            FROM downloaded_assets
            ORDER BY downloaded_at DESC
            """
        )
        return rows.compactMap { Self.asset(from: $0) }
    }

    func asset(remoteUrl: String) async throws -> DownloadedAsset? {
        let rows = try await database.connection.query(
            """
            SELECT id, remote_url, relative_file_path, byte_size,
                   content_item_id, media_item_id, downloaded_at
            FROM downloaded_assets
            WHERE remote_url = ?
            ORDER BY downloaded_at DESC
            LIMIT 1
            """,
            [.text(remoteUrl)]
        )
        guard let row = rows.first else { return nil }
        return Self.asset(from: row)
    }

    func saveAsset(_ asset: DownloadedAsset) async throws {
        try await database.connection.execute(
            """
            INSERT INTO downloaded_assets (id, remote_url, relative_file_path,
                byte_size, content_item_id, media_item_id, downloaded_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                remote_url = excluded.remote_url,
                relative_file_path = excluded.relative_file_path,
                byte_size = excluded.byte_size,
                content_item_id = excluded.content_item_id,
                media_item_id = excluded.media_item_id,
                downloaded_at = excluded.downloaded_at
            """,
            [
                .text(asset.id),
                .text(asset.remoteUrl),
                .text(asset.relativeFilePath),
                .integer(asset.byteSize),
                .optionalText(asset.contentItemID),
                .optionalText(asset.mediaItemID),
                .date(asset.downloadedAt),
            ]
        )
    }

    func deleteAsset(id: String) async throws {
        try await database.connection.execute(
            "DELETE FROM downloaded_assets WHERE id = ?",
            [.text(id)]
        )
    }

    // MARK: - Row mapping

    private static func asset(from row: SQLRow) -> DownloadedAsset? {
        guard
            let id = row.text("id"),
            let remoteUrl = row.text("remote_url"),
            let relativeFilePath = row.text("relative_file_path"),
            let downloadedAt = row.date("downloaded_at")
        else { return nil }
        let byteSize: Int64 = row.int64("byte_size") ?? 0
        return DownloadedAsset(
            id: id,
            remoteUrl: remoteUrl,
            relativeFilePath: relativeFilePath,
            byteSize: byteSize,
            contentItemID: row.text("content_item_id"),
            mediaItemID: row.text("media_item_id"),
            downloadedAt: downloadedAt
        )
    }
}
