import Foundation

/// Owns the app's single SQLite store: location, schema migrations, and the
/// connection used by all repositories.
final class AppDatabase: Sendable {
    let connection: SQLiteDatabase

    /// Current schema version. Bump alongside a new migration script.
    static let schemaVersion = 2

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
    }

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
