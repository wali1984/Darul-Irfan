import Foundation

/// Live implementation of `SettingsStoring`, persisting `AppSettings` as a
/// single JSON document (ISO-8601 dates) in the `key_value` table under the
/// key `app.settings`.
///
/// `load()` returns `AppSettings.default` on any read or decode failure —
/// including blobs written by a newer app version this build cannot decode —
/// so settings corruption can never prevent launch. `save(_:)` is
/// intentionally non-throwing per the protocol; a failed write leaves the
/// previously stored settings in place.
struct SettingsStore: SettingsStoring {
    private let database: AppDatabase

    private static let settingsKey = "app.settings"

    init(database: AppDatabase) {
        self.database = database
    }

    func load() async -> AppSettings {
        do {
            let rows = try await database.connection.query(
                "SELECT value FROM key_value WHERE key = ? LIMIT 1",
                [.text(Self.settingsKey)]
            )
            guard
                let json = rows.first?.text("value"),
                let data = json.data(using: .utf8)
            else { return .default }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            return .default
        }
    }

    func save(_ settings: AppSettings) async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard
            let data = try? encoder.encode(settings),
            let json = String(data: data, encoding: .utf8)
        else { return }
        try? await database.connection.execute(
            """
            INSERT INTO key_value (key, value, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
                value = excluded.value,
                updated_at = excluded.updated_at
            """,
            [
                .text(Self.settingsKey),
                .text(json),
                .date(Date()),
            ]
        )
    }
}
