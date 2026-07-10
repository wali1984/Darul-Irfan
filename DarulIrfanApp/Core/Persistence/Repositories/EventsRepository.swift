import Foundation

/// Live SQLite-backed implementation of `EventsRepositoryProtocol`.
/// Column names follow schema v1 in `AppDatabase.migrationV1` exactly.
///
/// Enum handling on read: an unknown event `kind` falls back to `.other`
/// so newly introduced kinds still appear in the events list.
struct EventsRepository: EventsRepositoryProtocol {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Reads

    func events() async throws -> [CommunityEvent] {
        // Dated events first (soonest start date first), undated events last.
        let rows = try await database.connection.query(
            """
            SELECT id, kind, title, title_urdu, details, start_date, end_date,
                   dates_are_approximate, venue, source_url, updated_at
            FROM events
            ORDER BY (start_date IS NULL) ASC, start_date ASC, title ASC
            """
        )
        return rows.compactMap { row in
            guard
                let id = row.text("id"),
                let title = row.text("title")
            else { return nil }
            let kindRaw = row.text("kind") ?? ""
            let kind = EventKind(rawValue: kindRaw) ?? .other
            return CommunityEvent(
                id: id,
                kind: kind,
                title: title,
                titleUrdu: row.text("title_urdu"),
                details: row.text("details"),
                startDate: row.date("start_date"),
                endDate: row.date("end_date"),
                datesAreApproximate: row.bool("dates_are_approximate"),
                venue: row.text("venue"),
                sourceUrl: row.text("source_url"),
                updatedAt: row.date("updated_at")
            )
        }
    }

    func announcements(limit: Int) async throws -> [Announcement] {
        // SQLite sorts NULLs last in DESC order, so undated announcements trail.
        let rows = try await database.connection.query(
            """
            SELECT id, title, body, published_at, source_url
            FROM announcements
            ORDER BY published_at DESC, title ASC
            LIMIT ?
            """,
            [.int(limit)]
        )
        return rows.compactMap { row in
            guard
                let id = row.text("id"),
                let title = row.text("title")
            else { return nil }
            return Announcement(
                id: id,
                title: title,
                body: row.text("body"),
                publishedAt: row.date("published_at"),
                sourceUrl: row.text("source_url")
            )
        }
    }

    // MARK: - Import (seed / manifest sync)

    func upsertEvents(_ events: [CommunityEvent]) async throws {
        guard !events.isEmpty else { return }
        let statements: [(sql: String, parameters: [SQLValue])] = events.map { event in
            (
                sql: """
                INSERT INTO events (id, kind, title, title_urdu, details,
                    start_date, end_date, dates_are_approximate, venue,
                    source_url, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    kind = excluded.kind,
                    title = excluded.title,
                    title_urdu = excluded.title_urdu,
                    details = excluded.details,
                    start_date = excluded.start_date,
                    end_date = excluded.end_date,
                    dates_are_approximate = excluded.dates_are_approximate,
                    venue = excluded.venue,
                    source_url = excluded.source_url,
                    updated_at = excluded.updated_at
                """,
                parameters: [
                    .text(event.id),
                    .text(event.kind.rawValue),
                    .text(event.title),
                    .optionalText(event.titleUrdu),
                    .optionalText(event.details),
                    .optionalDate(event.startDate),
                    .optionalDate(event.endDate),
                    .bool(event.datesAreApproximate),
                    .optionalText(event.venue),
                    .optionalText(event.sourceUrl),
                    .optionalDate(event.updatedAt),
                ]
            )
        }
        try await database.connection.executeBatch(statements)
    }

    func upsertAnnouncements(_ announcements: [Announcement]) async throws {
        guard !announcements.isEmpty else { return }
        let statements: [(sql: String, parameters: [SQLValue])] = announcements.map { announcement in
            (
                sql: """
                INSERT INTO announcements (id, title, body, published_at, source_url)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    body = excluded.body,
                    published_at = excluded.published_at,
                    source_url = excluded.source_url
                """,
                parameters: [
                    .text(announcement.id),
                    .text(announcement.title),
                    .optionalText(announcement.body),
                    .optionalDate(announcement.publishedAt),
                    .optionalText(announcement.sourceUrl),
                ]
            )
        }
        try await database.connection.executeBatch(statements)
    }
}
