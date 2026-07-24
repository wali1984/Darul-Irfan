import Foundation
import Security

enum OfficialPlatformError: Error {
    case invalidResponse
    case noCachedContent
}

enum OfficialPlatformConfiguration {
    /// Backend base URL. Read from the Info.plist key `OfficialPlatformBaseURL`
    /// so the POC/staging host can be swapped for production without a code
    /// change; falls back to the production host when the key is absent.
    static let baseURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "OfficialPlatformBaseURL") as? String,
           !raw.isEmpty, let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://api.naqshbandiaowaisiah.us") ?? URL(fileURLWithPath: "/")
    }()
}

actor OfficialPlatformService:
    OfficialFeedServicing,
    LiveBroadcastServicing,
    PushRegistrationServicing,
    DiagnosticsServicing
{
    private let database: AppDatabase
    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder
    private var diagnosticsConsent: DiagnosticsConsent = .notAsked

    init(database: AppDatabase, baseURL: URL = OfficialPlatformConfiguration.baseURL) {
        self.database = database
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        encoder.dateEncodingStrategy = .iso8601
    }

    func bootstrap(forceRefresh: Bool = false) async -> AppBootstrap {
        do {
            let data = try await fetch(path: "/v1/bootstrap", cacheKey: "bootstrap", forceRefresh: forceRefresh)
            let value = try decoder.decode(AppBootstrap.self, from: data)
            try await replaceSchedules(value.schedules)
            return value
        } catch {
            guard let cached = try? await cachedData(for: "bootstrap"),
                  let value = try? decoder.decode(AppBootstrap.self, from: cached.data) else {
                return .offline
            }
            return value
        }
    }

    func feed(after cursor: String?, forceRefresh: Bool = false) async throws -> OfficialFeedPage {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/feed"), resolvingAgainstBaseURL: false)
        var query = [URLQueryItem(name: "limit", value: "20")]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        components?.queryItems = query
        guard let url = components?.url else { throw OfficialPlatformError.invalidResponse }
        let key = cursor == nil ? "feed:first" : "feed:\(cursor ?? "")"
        do {
            let data = try await fetch(url: url, cacheKey: key, forceRefresh: forceRefresh)
            let page = try decoder.decode(OfficialFeedPage.self, from: data)
            try await cacheFeedItems(page.items)
            return page
        } catch {
            if cursor == nil {
                let items = try await cachedFeedItems()
                if !items.isEmpty { return OfficialFeedPage(items: items, nextCursor: nil, isFromCache: true) }
            }
            throw error
        }
    }

    func currentLiveBroadcast(forceRefresh: Bool = false) async -> LiveBroadcast {
        do {
            let data = try await fetch(path: "/v1/live", cacheKey: "live", forceRefresh: forceRefresh)
            return try decoder.decode(LiveBroadcast.self, from: data)
        } catch {
            guard let cached = try? await cachedData(for: "live"),
                  let value = try? decoder.decode(LiveBroadcast.self, from: cached.data) else {
                return (await bootstrap(forceRefresh: false)).live
            }
            return value
        }
    }

    func registerForPush(token: Data, preferences: PushPreferences) async throws {
        guard preferences.isEnabled else {
            await unregisterFromPush()
            return
        }
        let identity = SecureInstallationIdentity.loadOrCreate()
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        SecurePushToken.save(tokenString)
        let registration = DeviceRegistration(
            installationID: identity,
            apnsToken: tokenString,
            locale: Locale.current.identifier,
            timeZone: TimeZone.current.identifier,
            topics: preferences.topics.sorted { $0.rawValue < $1.rawValue },
            environment: Self.pushEnvironment,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        )
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/devices"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(registration)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw OfficialPlatformError.invalidResponse
        }
        try await database.connection.execute(
            """
            INSERT INTO push_registration_state(installation_id,token_hash,topics_json,updated_at)
            VALUES(?,?,?,?)
            ON CONFLICT(installation_id) DO UPDATE SET
              token_hash=excluded.token_hash,
              topics_json=excluded.topics_json,
              updated_at=excluded.updated_at
            """,
            [.text(identity.uuidString), .text("registered"), .text(String(data: try encoder.encode(registration.topics), encoding: .utf8) ?? "[]"), .date(Date())]
        )
    }

    func unregisterFromPush() async {
        guard let identity = SecureInstallationIdentity.load(),
              let token = SecurePushToken.load() else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/devices/\(identity.uuidString)"))
        request.httpMethod = "DELETE"
        request.setValue(token, forHTTPHeaderField: "X-APNS-Token")
        _ = try? await session.data(for: request)
        try? await database.connection.execute(
            "DELETE FROM push_registration_state WHERE installation_id=?",
            [.text(identity.uuidString)]
        )
        SecurePushToken.delete()
    }

    func setConsent(_ consent: DiagnosticsConsent) async {
        diagnosticsConsent = consent
    }

    func uploadMetricPayload(_ data: Data) async {
        await uploadDiagnostics(data: data, kind: "metric")
    }

    func uploadDiagnosticPayload(_ data: Data) async {
        await uploadDiagnostics(data: data, kind: "diagnostic")
    }

    private func uploadDiagnostics(data: Data, kind: String) async {
        guard diagnosticsConsent == .granted, data.count <= 200_000 else { return }
        let identity = SecureInstallationIdentity.loadOrCreate()
        let payload: [String: String] = [
            "installationID": identity.uuidString,
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "kind": kind,
            "metricKitPayload": String(decoding: data, as: UTF8.self),
        ]
        guard let body = try? encoder.encode(payload) else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/diagnostics"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        _ = try? await session.data(for: request)
    }

    private func fetch(path: String, cacheKey: String, forceRefresh: Bool) async throws -> Data {
        try await fetch(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), cacheKey: cacheKey, forceRefresh: forceRefresh)
    }

    private func fetch(url: URL, cacheKey: String, forceRefresh: Bool) async throws -> Data {
        let cached = try? await cachedData(for: cacheKey)
        if !forceRefresh, let cached, Date().timeIntervalSince(cached.updatedAt) < 300 {
            return cached.data
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = cached?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OfficialPlatformError.invalidResponse }
        if http.statusCode == 304, let cached { return cached.data }
        guard (200...299).contains(http.statusCode), !data.isEmpty else { throw OfficialPlatformError.invalidResponse }
        try await saveCache(data, key: cacheKey, etag: http.value(forHTTPHeaderField: "ETag"))
        return data
    }

    private func cachedData(for key: String) async throws -> (data: Data, etag: String?, updatedAt: Date) {
        guard let row = try await database.connection.query(
            "SELECT payload_json,etag,updated_at FROM platform_cache WHERE key=?",
            [.text(key)]
        ).first,
        let json = row.text("payload_json"), let data = json.data(using: .utf8), let date = row.date("updated_at") else {
            throw OfficialPlatformError.noCachedContent
        }
        return (data, row.text("etag"), date)
    }

    private func saveCache(_ data: Data, key: String, etag: String?) async throws {
        guard let string = String(data: data, encoding: .utf8) else { throw OfficialPlatformError.invalidResponse }
        try await database.connection.execute(
            "INSERT INTO platform_cache(key,payload_json,etag,updated_at) VALUES(?,?,?,?) ON CONFLICT(key) DO UPDATE SET payload_json=excluded.payload_json,etag=excluded.etag,updated_at=excluded.updated_at",
            [.text(key), .text(string), .optionalText(etag), .date(Date())]
        )
    }

    private func cacheFeedItems(_ items: [OfficialFeedItem]) async throws {
        let now = Date()
        let statements = try items.map { item in
            let data = try encoder.encode(item)
            return (
                sql: "INSERT INTO official_feed_cache(id,payload_json,published_at,is_featured,updated_at) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET payload_json=excluded.payload_json,published_at=excluded.published_at,is_featured=excluded.is_featured,updated_at=excluded.updated_at",
                parameters: [SQLValue.text(item.id), .text(String(decoding: data, as: UTF8.self)), .date(item.publishedAt), .bool(item.isFeatured), .date(now)]
            )
        }
        try await database.connection.executeBatch(statements)
    }

    private func cachedFeedItems() async throws -> [OfficialFeedItem] {
        let rows = try await database.connection.query("SELECT payload_json FROM official_feed_cache ORDER BY is_featured DESC,published_at DESC LIMIT 50")
        return rows.compactMap { row in
            guard let json = row.text("payload_json"), let data = json.data(using: .utf8) else { return nil }
            return try? decoder.decode(OfficialFeedItem.self, from: data)
        }
    }

    private func replaceSchedules(_ schedules: [RemoteZikrSchedule]) async throws {
        guard !schedules.isEmpty else { return }
        let now = Date()
        var statements: [(sql: String, parameters: [SQLValue])] = [
            ("DELETE FROM remote_zikr_schedule_cache", [])
        ]
        for schedule in schedules {
            let data = try encoder.encode(schedule)
            statements.append((
                "INSERT INTO remote_zikr_schedule_cache(id,payload_json,updated_at) VALUES(?,?,?)",
                [.text(schedule.id), .text(String(decoding: data, as: UTF8.self)), .date(now)]
            ))
        }
        try await database.connection.executeBatch(statements)
    }

    private static var pushEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

}

private enum SecureInstallationIdentity {
    private static let service = "us.naqshbaniaowaisiah.installation"
    private static let account = "anonymous-installation-id"

    static func loadOrCreate() -> UUID {
        if let existing = load() { return existing }
        let value = UUID()
        let data = Data(value.uuidString.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
        return value
    }

    static func load() -> UUID? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return UUID(uuidString: string)
    }
}

private enum SecurePushToken {
    private static let service = "us.naqshbaniaowaisiah.push"
    private static let account = "apns-token"

    static func save(_ token: String) {
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
