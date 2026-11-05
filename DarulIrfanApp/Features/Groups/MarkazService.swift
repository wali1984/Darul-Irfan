import Foundation

/// The Silsila Markaz's reports, organisation and announcements
/// (Docs/MARKAZ_ANALYTICS_API.md), over the member's own session. Only the
/// Super admin and the Markaz's Administrators and Admins are answered; the
/// screens ask `MarkazAccessCache` first and show nothing to anyone else.
/// Every report is read in the phone's time zone.
struct MarkazService: Sendable {
    let groups: MemberGroupService

    // MARK: Reading

    func access() async throws -> MarkazAccess {
        try await get(MarkazAccess.self, "v1/markaz/access")
    }

    /// `from` and `to` are calendar days ("2026-11-05"); `scope` is "all",
    /// "region:<name>" or "halqah:<id>"; `kind` "all", "zikr" or "meeting".
    func analytics(from: String, to: String, scope: String, kind: String) async throws -> MarkazAnalytics {
        try await get(MarkazAnalytics.self, "v1/markaz/analytics",
                      [("from", from), ("to", to), ("scope", scope), ("kind", kind)])
    }

    /// One day's report; nil `date` is yesterday.
    func dailyReport(date: String?) async throws -> MarkazDailyReport {
        try await get(MarkazDailyReport.self, "v1/markaz/reports/daily", [("date", date)])
    }

    /// One month's report ("2026-10"); nil `month` is last month.
    func monthlyReport(month: String?) async throws -> MarkazMonthlyReport {
        try await get(MarkazMonthlyReport.self, "v1/markaz/reports/monthly", [("month", month)])
    }

    func session(_ sessionID: String) async throws -> MarkazSessionDetail {
        try await get(MarkazSessionDetail.self, "v1/markaz/sessions/\(sessionID)")
    }

    func person(_ memberID: String) async throws -> MarkazPerson {
        try await get(MarkazPerson.self, "v1/markaz/people/\(memberID)")
    }

    func organization() async throws -> MarkazOrganization {
        try await get(MarkazOrganization.self, "v1/markaz/organization")
    }

    func announcements() async throws -> [MarkazAnnouncement] {
        try await get(MarkazAnnouncementList.self, "v1/markaz/announcements").announcements
    }

    func reportingSessions() async throws -> [MarkazReportingSession] {
        try await get(MarkazReportingSessionList.self, "v1/markaz/reporting-sessions").sessions
    }

    /// A spreadsheet (CSV) of `type` - sessions, attendance, halqahs or
    /// people - saved where the share sheet can send it.
    func export(type: String, from: String, to: String, scope: String = "all") async throws -> URL {
        let query = Self.query([("type", type), ("from", from), ("to", to), ("scope", scope),
                                ("tz", TimeZone.current.identifier)])
        let data = try await groups.markaz("GET", path: "v1/markaz/export", query: query)
        let name = from == to ? "Markaz-\(type)-\(from).csv" : "Markaz-\(type)-\(from)-to-\(to).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: Changing

    /// Sets a Halqah's region, country and city (Super admin); nil clears one.
    func updateHalqah(_ groupID: String, region: String?, countryCode: String?, city: String?) async throws {
        let payload: [String: Any] = [
            "region": region.map { $0 as Any } ?? NSNull(),
            "countryCode": countryCode.map { $0 as Any } ?? NSNull(),
            "city": city.map { $0 as Any } ?? NSNull()
        ]
        _ = try await groups.markaz("PUT", path: "v1/markaz/halqahs/\(groupID)", payload: payload, expecting: [200, 204])
    }

    /// Brings every Halqah Administrator and Admin into the Silsila Markaz
    /// as a member (Super admin).
    func syncAdmins() async throws -> MarkazSyncResult {
        let data = try await groups.markaz("POST", path: "v1/markaz/sync-admins", payload: [:], expecting: [200, 201])
        return try decode(MarkazSyncResult.self, data)
    }

    /// `audience` is "members" or "admins"; `scope` "all", "region:<name>" or
    /// "halqahs" with `halqahIDs`.
    func announce(title: String, body: String, audience: String, scope: String,
                  halqahIDs: [String], notify: Bool) async throws -> MarkazAnnounceResult {
        let payload: [String: Any] = [
            "title": title, "body": body, "audience": audience, "scope": scope,
            "halqahIDs": halqahIDs, "notify": notify
        ]
        let data = try await groups.markaz("POST", path: "v1/markaz/announce", payload: payload, expecting: [200, 201])
        return try decode(MarkazAnnounceResult.self, data)
    }

    /// Lets the computer showing `code` into the reporting website.
    func approveReportingLink(code: String) async throws {
        _ = try await groups.markaz("POST", path: "v1/markaz/reporting-link/approve", payload: ["code": code],
                                    expecting: [200, 204])
    }

    func signOutComputer(_ sessionID: String) async throws {
        _ = try await groups.markaz("DELETE", path: "v1/markaz/reporting-sessions/\(sessionID)", expecting: [200, 204])
    }

    // MARK: Plumbing

    private func get<T: Decodable>(_ type: T.Type, _ path: String, _ items: [(String, String?)] = []) async throws -> T {
        let query = Self.query(items + [("tz", TimeZone.current.identifier)])
        let data = try await groups.markaz("GET", path: path, query: query)
        return try decode(type, data)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder.darulIrfanServer().decode(type, from: data) }
        catch { throw MemberGroupError.requestFailed }
    }

    /// The query, each value percent-encoded by hand (a region's name may
    /// hold spaces, "&" or "+"); empty values are left out.
    static func query(_ items: [(String, String?)]) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return items.compactMap { item -> String? in
            guard let value = item.1, !value.isEmpty,
                  let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
            return item.0 + "=" + encoded
        }
        .joined(separator: "&")
    }
}

/// Whether this member sees the Markaz's reports, asked once per signed-in
/// member while the app runs. A failed check is not remembered, so the
/// cards appear on the next visit once the server answers.
@MainActor
enum MarkazAccessCache {
    private static var cached: (memberID: String, access: MarkazAccess)?

    static func access(using service: MemberGroupService) async -> MarkazAccess {
        guard let memberID = service.memberID else { return .denied }
        if let cached = MarkazAccessCache.cached, cached.memberID == memberID { return cached.access }
        do {
            let access = try await MarkazService(groups: service).access()
            MarkazAccessCache.cached = (memberID, access)
            return access
        } catch {
            return .denied
        }
    }
}
