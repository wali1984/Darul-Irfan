import Foundation

/// Keeps the library and media tables to exactly what the bundled seed
/// carries, and moves the reader's own records off any row it removes.
///
/// The import used to only add and update. Rows the seed later dropped stayed
/// on upgraded phones: 21 books listed twice (the copy with no text, crediting
/// the wrong author), the website's downloads page, 14 old announcements and a
/// retired live-TV entry. On top of those, every fresh install applied the
/// abandoned GitHub content feed, which added 23 more (duplicate books,
/// magazine issues, the Shajra and three lectures under old ids). Nothing but
/// the seed import writes these two tables now, so a row the seed does not
/// carry is stale by construction.
///
/// The reader's own records are never simply orphaned. When the seed carries
/// the same publication under its current id (same PDF, same page, same
/// recording) favourites, downloads, bookmarks and listening positions move
/// to it. Otherwise a favourite or bookmark of a row that can no longer be
/// opened is dropped, and a download keeps its file (still listed under
/// storage) but forgets the row. Article reading positions are dropped either
/// way: they measure a body of text that is gone.
struct SeedHousekeeping {
    let database: AppDatabase

    // MARK: Library

    /// Deletes every content item whose id `seed` does not carry. Returns the
    /// ids removed. Never called with an empty seed: an import that read no
    /// items must not empty the library.
    @discardableResult
    func pruneLibrary(keeping seed: [ContentItem]) async throws -> [String] {
        guard !seed.isEmpty else { return [] }
        let seedIDs = Set(seed.map(\.id))
        let rows = try await database.connection.query(
            "SELECT id, type, source_url, download_urls_json FROM content_items"
        )
        let stale = rows.compactMap { row -> StaleLibraryRow? in
            guard let id = row.text("id"), !seedIDs.contains(id) else { return nil }
            return StaleLibraryRow(
                id: id,
                type: row.text("type") ?? "",
                sourceUrl: row.text("source_url") ?? "",
                downloadUrls: Self.decodeStringArray(row.text("download_urls_json"))
            )
        }
        guard !stale.isEmpty else { return [] }

        let twins = LibraryTwins(seed: seed)
        var statements: [(sql: String, parameters: [SQLValue])] = []
        for row in stale {
            if let twin = twins.twin(of: row), twin != row.id {
                statements += Self.moveFavorites(column: "content_item_id", from: row.id, to: twin)
                statements.append((
                    "UPDATE downloaded_assets SET content_item_id = ? WHERE content_item_id = ?",
                    [.text(twin), .text(row.id)]
                ))
            } else {
                statements.append(("DELETE FROM favorites WHERE content_item_id = ?", [.text(row.id)]))
                statements.append((
                    "UPDATE downloaded_assets SET content_item_id = NULL WHERE content_item_id = ?",
                    [.text(row.id)]
                ))
            }
            statements.append(("DELETE FROM content_reading_progress WHERE content_item_id = ?", [.text(row.id)]))
            statements.append(("DELETE FROM content_items WHERE id = ?", [.text(row.id)]))
        }
        try await database.connection.executeBatch(statements)
        let removed = stale.map(\.id)
        AppLog.content("Removed \(removed.count) library rows the seed no longer carries: \(removed.joined(separator: ", "))")
        return removed
    }

    // MARK: Media

    /// Deletes every media item whose id `seed` does not carry. Returns the
    /// ids removed. Never called with an empty seed.
    @discardableResult
    func pruneMedia(keeping seed: [MediaItem]) async throws -> [String] {
        guard !seed.isEmpty else { return [] }
        let seedIDs = Set(seed.map(\.id))
        let rows = try await database.connection.query(
            "SELECT id, source_url, stream_url, download_url FROM media_items"
        )
        let stale = rows.compactMap { row -> StaleMediaRow? in
            guard let id = row.text("id"), !seedIDs.contains(id) else { return nil }
            return StaleMediaRow(
                id: id,
                sourceUrl: row.text("source_url") ?? "",
                fileUrls: [row.text("stream_url"), row.text("download_url")].compactMap { $0 }
            )
        }
        guard !stale.isEmpty else { return [] }

        let twins = MediaTwins(seed: seed)
        var replacements: [String: String] = [:]
        var statements: [(sql: String, parameters: [SQLValue])] = []
        for row in stale {
            if let twin = twins.twin(of: row), twin != row.id {
                replacements[row.id] = twin
                statements += Self.moveFavorites(column: "media_item_id", from: row.id, to: twin)
                // One listening position per recording: keep the more recent.
                statements.append((
                    """
                    DELETE FROM playback_progress WHERE media_item_id = ? AND updated_at <
                        (SELECT updated_at FROM playback_progress WHERE media_item_id = ?)
                    """,
                    [.text(twin), .text(row.id)]
                ))
                statements.append((
                    "UPDATE OR IGNORE playback_progress SET media_item_id = ? WHERE media_item_id = ?",
                    [.text(twin), .text(row.id)]
                ))
                statements.append((
                    "UPDATE media_bookmarks SET media_item_id = ? WHERE media_item_id = ?",
                    [.text(twin), .text(row.id)]
                ))
                statements.append((
                    "UPDATE downloaded_assets SET media_item_id = ? WHERE media_item_id = ?",
                    [.text(twin), .text(row.id)]
                ))
            } else {
                statements.append(("DELETE FROM favorites WHERE media_item_id = ?", [.text(row.id)]))
                statements.append(("DELETE FROM media_bookmarks WHERE media_item_id = ?", [.text(row.id)]))
                statements.append((
                    "UPDATE downloaded_assets SET media_item_id = NULL WHERE media_item_id = ?",
                    [.text(row.id)]
                ))
            }
            // Whatever was not moved above belongs to a row that is going.
            statements.append(("DELETE FROM playback_progress WHERE media_item_id = ?", [.text(row.id)]))
            statements.append(("DELETE FROM media_items WHERE id = ?", [.text(row.id)]))
        }
        statements += try await playlistUpdates(removing: Set(stale.map(\.id)), replacing: replacements)
        try await database.connection.executeBatch(statements)
        let removed = stale.map(\.id)
        AppLog.content("Removed \(removed.count) media rows the seed no longer carries: \(removed.joined(separator: ", "))")
        return removed
    }

    /// Playlists keep their recordings in a JSON array: each removed id is
    /// swapped for its twin (once per playlist) or dropped.
    private func playlistUpdates(
        removing removed: Set<String>,
        replacing replacements: [String: String]
    ) async throws -> [(sql: String, parameters: [SQLValue])] {
        let rows = try await database.connection.query("SELECT id, media_item_ids_json FROM playlists")
        var statements: [(sql: String, parameters: [SQLValue])] = []
        for row in rows {
            guard let id = row.text("id") else { continue }
            let ids = Self.decodeStringArray(row.text("media_item_ids_json"))
            guard ids.contains(where: removed.contains) else { continue }
            var updated: [String] = []
            for itemID in ids {
                guard removed.contains(itemID) else {
                    updated.append(itemID)
                    continue
                }
                // The twin goes in the removed row's place unless the
                // playlist already holds it.
                if let twin = replacements[itemID], !ids.contains(twin), !updated.contains(twin) {
                    updated.append(twin)
                }
            }
            statements.append((
                "UPDATE playlists SET media_item_ids_json = ? WHERE id = ?",
                [.text(Self.encodeStringArray(updated)), .text(id)]
            ))
        }
        return statements
    }

    // MARK: Shared

    /// Moves favourites from one item to another without leaving the item
    /// favourited twice (removing a favourite deletes a single row).
    private static func moveFavorites(
        column: String,
        from staleID: String,
        to twinID: String
    ) -> [(sql: String, parameters: [SQLValue])] {
        [
            (
                "DELETE FROM favorites WHERE \(column) = ? AND EXISTS (SELECT 1 FROM favorites WHERE \(column) = ?)",
                [.text(staleID), .text(twinID)]
            ),
            (
                "UPDATE favorites SET \(column) = ? WHERE \(column) = ?",
                [.text(twinID), .text(staleID)]
            ),
        ]
    }

    private static func decodeStringArray(_ text: String?) -> [String] {
        guard let data = text?.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return values
    }

    private static func encodeStringArray(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }
}

// MARK: - Finding the seed's copy of a removed row

private struct StaleLibraryRow {
    let id: String
    let type: String
    let sourceUrl: String
    let downloadUrls: [String]
}

private struct StaleMediaRow {
    let id: String
    let sourceUrl: String
    let fileUrls: [String]
}

/// Address of a file or page, compared with percent-escapes undone (the
/// feed wrote "06-02-2026 s.mp3" where the seed has "06-02-2026%20s.mp3").
private func normalizedURL(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.removingPercentEncoding ?? trimmed
}

/// Several seed rows can share a file (the seed still lists one book under
/// two ids). Any of them is the same publication, so the choice only has to
/// be stable: the slug-style id over a file-name id, then the shorter one.
private func preferredID(_ ids: [String]) -> String? {
    ids.min { lhs, rhs in
        let lhsFile = lhs.lowercased().hasSuffix(".pdf")
        let rhsFile = rhs.lowercased().hasSuffix(".pdf")
        if lhsFile != rhsFile { return !lhsFile }
        if lhs.count != rhs.count { return lhs.count < rhs.count }
        return lhs < rhs
    }
}

/// A library row's twin is the seed item of the same type that offers the
/// same PDF. Without a shared file, a seed item at the same page counts only
/// when it is the only one there of that type, or, when none there has that
/// type, the only one there at all: many listing pages
/// (books-on-tasawwuf.html) are shared by dozens of unrelated books, while
/// the three About pages that were "article" rows are "page" rows now.
/// An empty address matches nothing.
private struct LibraryTwins {
    private var byFile: [String: [ContentItem]] = [:]
    private var byPage: [String: [ContentItem]] = [:]

    init(seed: [ContentItem]) {
        for item in seed {
            for url in item.downloadUrls {
                let file = normalizedURL(url)
                if !file.isEmpty { byFile[file, default: []].append(item) }
            }
            let page = normalizedURL(item.sourceUrl)
            if !page.isEmpty { byPage[page, default: []].append(item) }
        }
    }

    func twin(of row: StaleLibraryRow) -> String? {
        var sharingFile: [ContentItem] = []
        for url in row.downloadUrls {
            for item in byFile[normalizedURL(url)] ?? [] where item.type.rawValue == row.type {
                if !sharingFile.contains(where: { $0.id == item.id }) { sharingFile.append(item) }
            }
        }
        if !sharingFile.isEmpty {
            let samePage = sharingFile.filter { normalizedURL($0.sourceUrl) == normalizedURL(row.sourceUrl) }
            return preferredID((samePage.isEmpty ? sharingFile : samePage).map(\.id))
        }
        let onPage = byPage[normalizedURL(row.sourceUrl)] ?? []
        let samePage = onPage.filter { $0.type.rawValue == row.type }
        if samePage.count == 1 { return samePage[0].id }
        // The same page filed under another type.
        if samePage.isEmpty, onPage.count == 1 { return onPage[0].id }
        return nil
    }
}

/// A recording's twin is the seed item at the same lecture page; without
/// one, the seed item that streams the same file.
private struct MediaTwins {
    private var byPage: [String: [String]] = [:]
    private var byFile: [String: [String]] = [:]

    init(seed: [MediaItem]) {
        // An empty address is no address: it must not pair unrelated rows.
        for item in seed {
            let page = normalizedURL(item.sourceUrl)
            if !page.isEmpty { byPage[page, default: []].append(item.id) }
            for url in [item.streamUrl, item.downloadUrl].compactMap({ $0 }) {
                let file = normalizedURL(url)
                if !file.isEmpty { byFile[file, default: []].append(item.id) }
            }
        }
    }

    func twin(of row: StaleMediaRow) -> String? {
        let samePage = byPage[normalizedURL(row.sourceUrl)] ?? []
        if samePage.count == 1 { return samePage[0] }
        var sameFile: [String] = []
        for url in row.fileUrls {
            for id in byFile[normalizedURL(url)] ?? [] where !sameFile.contains(id) {
                sameFile.append(id)
            }
        }
        if !samePage.isEmpty {
            // Several seed rows at one page: the one that also has the file.
            let both = samePage.filter(sameFile.contains)
            return preferredID(both.isEmpty ? samePage : both)
        }
        return preferredID(sameFile)
    }
}
