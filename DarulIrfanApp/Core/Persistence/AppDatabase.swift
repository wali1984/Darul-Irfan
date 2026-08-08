import Foundation

/// Owns the app's single SQLite store: location, schema migrations, and the
/// connection used by all repositories.
final class AppDatabase: Sendable {
    let connection: SQLiteDatabase

    /// Current schema version. Bump alongside a new migration script.
    static let schemaVersion = 4

    /// User-owned tables that no content migration may ever disturb. Migration
    /// v4 asserts their row counts are identical before and after it runs; a
    /// test checks this list and that migration's SQL name the same tables, so
    /// adding one here without covering it there fails the build.
    static let userDataTables = [
        "key_value",              // settings, prayer preferences, sync state
        "quran_bookmarks",
        "quran_reading_progress",
        "content_reading_progress",
        "playback_progress",
        "media_bookmarks",
        "playlists",
        "downloaded_assets",
        "favorites",
        "prayer_log",
        "fasting_log",
        "tasbih_counters",
        "zikr_habit",
    ]

    /// Production store, in Application Support (backed up, not user-visible).
    static func liveURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("DarulIrfan", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("darul-irfan.sqlite")
    }

    /// Opens the store at `url` and migrates it to the current schema.
    /// Pass nil for an in-memory database (unit tests).
    init(url: URL?) async throws {
        connection = try SQLiteDatabase(url: url)
        try await migrate()
    }

    static func live() async throws -> AppDatabase {
        try await AppDatabase(url: liveURL())
    }

    static func inMemory() async throws -> AppDatabase {
        try await AppDatabase(url: nil)
    }

    private func migrate() async throws {
        let version = try await connection.schemaVersion()
        if version < 1 {
            try await connection.executeScript(Self.migrationV1)
            try await connection.setSchemaVersion(1)
        }
        if version < 2 {
            try await connection.executeScript(Self.migrationV2)
            try await connection.setSchemaVersion(2)
        }
        if version < 3 {
            try await connection.executeScript(Self.migrationV3)
            try await connection.setSchemaVersion(3)
        }
        if version < 4 {
            try await connection.migrate(
                to: 4,
                script: Self.migrationV4,
                checks: Self.migrationV4Checks,
                cleanup: "DROP TABLE IF EXISTS _migration_v4_counts;"
            )
        }
    }

    // MARK: - Schema v4 (hadith identifiers)

    /// Re-keys `hadith_entries` on a textual canonical identifier.
    ///
    /// v3 keyed the table `(book_id, hadith_number INTEGER)`. Upstream prints
    /// sub-numbered narrations such as `402.2`, which truncated to `402` and
    /// collided with the real hadith 402 — the insert's `ON CONFLICT DO UPDATE`
    /// then overwrote one narration with the other. That silently destroyed 103
    /// narrations across 86 collision groups.
    ///
    /// `402.2` is an identifier, not a quantity, so the fix is textual: no
    /// `REAL`, no `Double`. The old rows are dropped rather than converted —
    /// the narrations they lost exist only in the regenerated seed packs, which
    /// re-import on the same launch via the manifest bump. Nothing user-owned
    /// lives in this table, and the checks below prove nothing else moved.
    static let migrationV4 = """
    -- Dropped first as well as last so a retry after a rolled-back attempt
    -- cannot trip over a leftover scratch table.
    DROP TABLE IF EXISTS _migration_v4_counts;

    -- Row counts for every user-owned table, captured before the drop.
    CREATE TEMP TABLE _migration_v4_counts AS
        SELECT 'key_value' AS table_name, COUNT(*) AS row_count FROM key_value
        UNION ALL SELECT 'quran_bookmarks', COUNT(*) FROM quran_bookmarks
        UNION ALL SELECT 'quran_reading_progress', COUNT(*) FROM quran_reading_progress
        UNION ALL SELECT 'content_reading_progress', COUNT(*) FROM content_reading_progress
        UNION ALL SELECT 'playback_progress', COUNT(*) FROM playback_progress
        UNION ALL SELECT 'media_bookmarks', COUNT(*) FROM media_bookmarks
        UNION ALL SELECT 'playlists', COUNT(*) FROM playlists
        UNION ALL SELECT 'downloaded_assets', COUNT(*) FROM downloaded_assets
        UNION ALL SELECT 'favorites', COUNT(*) FROM favorites
        UNION ALL SELECT 'prayer_log', COUNT(*) FROM prayer_log
        UNION ALL SELECT 'fasting_log', COUNT(*) FROM fasting_log
        UNION ALL SELECT 'tasbih_counters', COUNT(*) FROM tasbih_counters
        UNION ALL SELECT 'zikr_habit', COUNT(*) FROM zikr_habit;

    DROP INDEX IF EXISTS idx_hadith_entries_book;
    DROP TABLE IF EXISTS hadith_entries;

    CREATE TABLE hadith_entries (
        canonical_id TEXT PRIMARY KEY,     -- "bukhari|402.2|403"
        book_id TEXT NOT NULL,
        display_number TEXT NOT NULL,      -- exactly as the source prints it
        number_major INTEGER NOT NULL,
        number_minor INTEGER,              -- lookup only, never a sort key
        source_sequence INTEGER NOT NULL,  -- position in the source edition
        text_ar TEXT,
        text_en TEXT,
        text_ur TEXT,
        grades TEXT,
        source_book INTEGER,
        source_hadith INTEGER
    );

    -- Reading order is the source's own order: Tirmidhi prints 3604.02…3604.09
    -- then 3604.1 (meaning ten), and Malik uses .25/.5/.75 as insertion points,
    -- so neither the minor part nor a decimal reading sorts them correctly.
    CREATE INDEX IF NOT EXISTS idx_hadith_entries_reading_order
        ON hadith_entries (book_id, source_sequence);

    -- Deep links and cross-references resolve by printed number.
    CREATE UNIQUE INDEX IF NOT EXISTS idx_hadith_entries_display_number
        ON hadith_entries (book_id, display_number);

    -- Review state travels with each edition so the model round-trips through
    -- the store intact. Internal metadata only — never rendered in the reader.
    ALTER TABLE quran_editions ADD COLUMN review_state TEXT;
    """

    /// Each query selects violations; the migration commits only if all are empty.
    static let migrationV4Checks: [SQLiteDatabase.MigrationCheck] = [
        .init(
            sql: """
            SELECT table_name FROM _migration_v4_counts c
            WHERE c.row_count <> (
                CASE c.table_name
                    WHEN 'key_value' THEN (SELECT COUNT(*) FROM key_value)
                    WHEN 'quran_bookmarks' THEN (SELECT COUNT(*) FROM quran_bookmarks)
                    WHEN 'quran_reading_progress' THEN (SELECT COUNT(*) FROM quran_reading_progress)
                    WHEN 'content_reading_progress' THEN (SELECT COUNT(*) FROM content_reading_progress)
                    WHEN 'playback_progress' THEN (SELECT COUNT(*) FROM playback_progress)
                    WHEN 'media_bookmarks' THEN (SELECT COUNT(*) FROM media_bookmarks)
                    WHEN 'playlists' THEN (SELECT COUNT(*) FROM playlists)
                    WHEN 'downloaded_assets' THEN (SELECT COUNT(*) FROM downloaded_assets)
                    WHEN 'favorites' THEN (SELECT COUNT(*) FROM favorites)
                    WHEN 'prayer_log' THEN (SELECT COUNT(*) FROM prayer_log)
                    WHEN 'fasting_log' THEN (SELECT COUNT(*) FROM fasting_log)
                    WHEN 'tasbih_counters' THEN (SELECT COUNT(*) FROM tasbih_counters)
                    WHEN 'zikr_habit' THEN (SELECT COUNT(*) FROM zikr_habit)
                END
            )
            """,
            failure: "a user-data table lost or gained rows during the migration"
        ),
        .init(
            sql: """
            SELECT 1 WHERE NOT EXISTS (
                SELECT 1 FROM pragma_table_info('hadith_entries')
                WHERE name = 'canonical_id' AND pk = 1
            )
            """,
            failure: "hadith_entries.canonical_id is not the primary key"
        ),
        .init(
            sql: """
            SELECT name FROM pragma_table_info('hadith_entries')
            WHERE name = 'hadith_number'
            """,
            failure: "the old integer hadith_number column survived the migration"
        ),
        .init(
            sql: """
            SELECT canonical_id FROM hadith_entries
            GROUP BY canonical_id HAVING COUNT(*) > 1
            """,
            failure: "duplicate canonical IDs in hadith_entries"
        ),
    ]

    // MARK: - Schema v3 (hadith)

    /// Hadith collections and their entries. Each script lives in its own
    /// column so the reader can show one, two or all three.
    static let migrationV3 = """
    CREATE TABLE IF NOT EXISTS hadith_books (
        id TEXT PRIMARY KEY,
        title_english TEXT NOT NULL,
        title_urdu TEXT NOT NULL,
        hadith_count INTEGER NOT NULL DEFAULT 0,
        has_arabic INTEGER NOT NULL DEFAULT 0,
        has_english INTEGER NOT NULL DEFAULT 0,
        has_urdu INTEGER NOT NULL DEFAULT 0,
        section_count INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS hadith_entries (
        book_id TEXT NOT NULL,
        hadith_number INTEGER NOT NULL,
        text_ar TEXT,
        text_en TEXT,
        text_ur TEXT,
        grades TEXT,
        ref_book INTEGER,
        ref_hadith INTEGER,
        PRIMARY KEY (book_id, hadith_number)
    );

    CREATE INDEX IF NOT EXISTS idx_hadith_entries_book
        ON hadith_entries (book_id, hadith_number);
    """

    // MARK: - Schema v1

    // Dates are stored as REAL (Unix seconds). Booleans as INTEGER 0/1.
    // JSON columns hold Codable payloads whose shape can evolve without
    // schema churn (settings, string arrays).
    static let migrationV1 = """
    -- Quran ------------------------------------------------------------
    CREATE TABLE IF NOT EXISTS quran_surahs (
        number INTEGER PRIMARY KEY,
        name_arabic TEXT NOT NULL,
        name_transliterated TEXT NOT NULL,
        name_english TEXT NOT NULL,
        name_urdu TEXT,
        ayah_count INTEGER NOT NULL,
        revelation_place TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS quran_ayahs (
        surah_number INTEGER NOT NULL,
        ayah_number INTEGER NOT NULL,
        text_arabic TEXT NOT NULL,
        PRIMARY KEY (surah_number, ayah_number)
    );

    CREATE TABLE IF NOT EXISTS quran_editions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        kind TEXT NOT NULL,
        language TEXT NOT NULL,
        author TEXT,
        source_url TEXT,
        rights_status TEXT NOT NULL,
        is_available_offline INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS quran_translations (
        edition_id TEXT NOT NULL,
        surah_number INTEGER NOT NULL,
        ayah_number INTEGER NOT NULL,
        text TEXT NOT NULL,
        PRIMARY KEY (edition_id, surah_number, ayah_number)
    );

    CREATE TABLE IF NOT EXISTS quran_tafsir (
        edition_id TEXT NOT NULL,
        surah_number INTEGER NOT NULL,
        ayah_start INTEGER NOT NULL,
        ayah_end INTEGER NOT NULL,
        text TEXT NOT NULL,
        source_url TEXT,
        PRIMARY KEY (edition_id, surah_number, ayah_start)
    );

    CREATE TABLE IF NOT EXISTS quran_bookmarks (
        id TEXT PRIMARY KEY,
        surah_number INTEGER NOT NULL,
        ayah_number INTEGER NOT NULL,
        note TEXT,
        created_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS quran_reading_progress (
        surah_number INTEGER PRIMARY KEY,
        ayah_number INTEGER NOT NULL,
        updated_at REAL NOT NULL
    );

    -- Library content ----------------------------------------------------
    CREATE TABLE IF NOT EXISTS content_items (
        id TEXT PRIMARY KEY,
        source_url TEXT NOT NULL,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        title_urdu TEXT,
        language TEXT NOT NULL,
        author TEXT,
        category TEXT NOT NULL,
        body_html TEXT,
        body_plain_text TEXT,
        excerpt TEXT,
        published_at REAL,
        updated_at REAL,
        media_urls_json TEXT NOT NULL DEFAULT '[]',
        download_urls_json TEXT NOT NULL DEFAULT '[]',
        checksum TEXT,
        rights_status TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_content_items_category ON content_items (category);
    CREATE INDEX IF NOT EXISTS idx_content_items_language ON content_items (language);

    CREATE TABLE IF NOT EXISTS content_collections (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        item_ids_json TEXT NOT NULL DEFAULT '[]'
    );

    CREATE TABLE IF NOT EXISTS content_reading_progress (
        content_item_id TEXT PRIMARY KEY,
        fraction REAL NOT NULL,
        updated_at REAL NOT NULL
    );

    -- Media ----------------------------------------------------------------
    CREATE TABLE IF NOT EXISTS media_items (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        language TEXT NOT NULL,
        speaker TEXT,
        date REAL,
        duration_seconds REAL,
        media_type TEXT NOT NULL,
        source_url TEXT NOT NULL,
        stream_url TEXT,
        download_url TEXT,
        youtube_id TEXT,
        year INTEGER,
        month INTEGER,
        category TEXT NOT NULL,
        transcript_url TEXT,
        rights_status TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_media_items_year_month ON media_items (year, month);
    CREATE INDEX IF NOT EXISTS idx_media_items_category ON media_items (category);

    CREATE TABLE IF NOT EXISTS playback_progress (
        media_item_id TEXT PRIMARY KEY,
        position_seconds REAL NOT NULL,
        duration_seconds REAL NOT NULL,
        updated_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS media_bookmarks (
        id TEXT PRIMARY KEY,
        media_item_id TEXT NOT NULL,
        position_seconds REAL NOT NULL,
        note TEXT,
        created_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS playlists (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        media_item_ids_json TEXT NOT NULL DEFAULT '[]',
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL
    );

    -- Downloads & favorites -------------------------------------------------
    CREATE TABLE IF NOT EXISTS downloaded_assets (
        id TEXT PRIMARY KEY,
        remote_url TEXT NOT NULL,
        relative_file_path TEXT NOT NULL,
        byte_size INTEGER NOT NULL,
        content_item_id TEXT,
        media_item_id TEXT,
        downloaded_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS favorites (
        id TEXT PRIMARY KEY,
        content_item_id TEXT,
        media_item_id TEXT,
        created_at REAL NOT NULL
    );

    -- Trackers ---------------------------------------------------------------
    CREATE TABLE IF NOT EXISTS prayer_log (
        day_key TEXT NOT NULL,
        prayer TEXT NOT NULL,
        completion TEXT NOT NULL,
        updated_at REAL NOT NULL,
        PRIMARY KEY (day_key, prayer)
    );

    CREATE TABLE IF NOT EXISTS fasting_log (
        day_key TEXT PRIMARY KEY,
        fasted INTEGER NOT NULL,
        updated_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS tasbih_counters (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        target INTEGER,
        count INTEGER NOT NULL DEFAULT 0,
        lifetime_count INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS zikr_habit (
        day_key TEXT PRIMARY KEY,
        completed_count INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL
    );

    -- Events -------------------------------------------------------------
    CREATE TABLE IF NOT EXISTS events (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        title_urdu TEXT,
        details TEXT,
        start_date REAL,
        end_date REAL,
        dates_are_approximate INTEGER NOT NULL DEFAULT 0,
        venue TEXT,
        source_url TEXT,
        updated_at REAL
    );

    CREATE TABLE IF NOT EXISTS announcements (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        body TEXT,
        published_at REAL,
        source_url TEXT
    );

    -- Key-value store (settings, sync state) --------------------------------
    CREATE TABLE IF NOT EXISTS key_value (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at REAL NOT NULL
    );

    -- Full-text search --------------------------------------------------------
    -- External-content-free FTS tables kept in sync by SearchIndexService.
    CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
        domain,           -- 'quran' | 'library' | 'media' | 'events'
        item_id UNINDEXED,
        title,
        body,
        author,
        language UNINDEXED,
        tokenize = 'unicode61 remove_diacritics 2'
    );
    """

    // MARK: - Schema v2: official platform cache

    static let migrationV2 = """
    CREATE TABLE IF NOT EXISTS platform_cache (
        key TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        etag TEXT,
        updated_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS official_feed_cache (
        id TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        published_at REAL NOT NULL,
        is_featured INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_official_feed_cache_date
        ON official_feed_cache (is_featured DESC, published_at DESC);

    CREATE TABLE IF NOT EXISTS remote_zikr_schedule_cache (
        id TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        updated_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS push_registration_state (
        installation_id TEXT PRIMARY KEY,
        token_hash TEXT,
        topics_json TEXT NOT NULL DEFAULT '[]',
        updated_at REAL NOT NULL
    );
    """
}
