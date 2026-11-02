#if DEBUG
import SwiftUI
import Foundation

/// Exercises the real detail screen without a Keychain session or live group requests.
struct HalqahAuditFixture: View {
    private let service: MemberGroupService
    private let historyAudit = ProcessInfo.processInfo.arguments.contains("--uitesting-halqah-history")

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HalqahAuditProtocol.self]
        service = MemberGroupService(
            baseURL: URL(string: "https://halqah-audit.invalid")!,
            session: URLSession(configuration: configuration),
            savedSession: HalqahAuditSession())
    }

    var body: some View {
        NavigationStack {
            List(["member", "admin"], id: \.self) { role in
                NavigationLink {
                    if historyAudit {
                        GroupSessionHistoryView(groupID: role, service: service)
                    } else {
                    GroupDetailView(group: MemberGroup(
                        id: role, name: "Audit Halqah", description: nil,
                        meetingURL: nil, meetingNote: nil,
                        canManage: role == "admin", myRole: role == "admin" ? .admin : .member),
                        service: service, dependencies: nil)
                    }
                } label: { Text(verbatim: role) }
                .accessibilityIdentifier("halqah-audit-" + role)
            }
            .navigationTitle("Halqah audit")
        }
    }
}

private struct HalqahAuditSession: MemberSessionStore {
    func load() -> MemberSession? {
        MemberSession(token: "local-fixture", expiresAt: .distantFuture, memberID: "audit")
    }
    func save(_ value: MemberSession) {}
    func delete() {}
    func deleteIfCurrent(token: String) -> Bool { false }
}

private final class HalqahAuditProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var failedGroups: Set<String> = []
    private static var historyAttempts: [String: Int] = [:]
    private static var deleted: Set<String> = []

    // This session never falls through to the network, including unexpected requests.
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, url.host == "halqah-audit.invalid" else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let parts = url.pathComponents
        guard parts.count >= 4, parts[1] == "v1", parts[2] == "groups",
              ["member", "admin"].contains(parts[3]) else {
            respond(404, "{}")
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--uitesting-halqah-history"),
           parts.count >= 5, parts[4] == "history" {
            let result = historyResponse(parts: parts)
            respond(result.0, result.1)
            return
        }
        guard request.httpMethod == "GET" else { respond(403, "{}"); return }
        if parts.count == 5 && parts[4] == "posts" {
            respond(200, "{\"groupID\":\"\(parts[3])\",\"posts\":[]}")
        } else if parts.count == 4 {
            Self.lock.lock()
            let first = Self.failedGroups.insert(parts[3]).inserted
            Self.lock.unlock()
            if first {
                respond(503, "{}")
            } else {
                let admin = parts[3] == "admin" ? "true" : "false"
                respond(200, "{\"group\":{\"id\":\"\(parts[3])\",\"name\":\"Audit Halqah\"},\"canManage\":\(admin),\"zikrSessions\":[],\"meetings\":[],\"memberCount\":3}")
            }
        } else {
            respond(404, "{}")
        }
    }
    private func historyResponse(parts: [String]) -> (Int, String) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let role = parts[3]
        let method = request.httpMethod ?? "GET"
        let key = method + parts.joined(separator: "/")
        Self.historyAttempts[key, default: 0] += 1
        let attempt = Self.historyAttempts[key]!
        if method == "DELETE" {
            guard role == "admin", parts.count == 6 else { return (403, "{}") }
            if attempt == 1 { return (503, "{}") }
            Self.deleted.insert(parts[5])
            return (204, "{}")
        }
        guard method == "GET" else { return (403, "{}") }
        if attempt == 1 { return (503, "{}") }
        let body: [String: Any]
        if parts.count == 5 {
            let records: [[String: Any]] = (1...9).compactMap { number in
                let id = "history-\(number)"
                guard !Self.deleted.contains(id) else { return nil }
                return ["id": id, "kind": "zikr", "title": "Audit session \(number)",
                        "startedAt": "2026-10-30T12:00:00Z", "endedAt": "2026-10-30T12:30:00Z", "attendees": 2]
            }
            body = ["sessions": records, "canDelete": role == "admin"]
        } else {
            body = ["attendees": (1...2).map { number in
                ["name": "Audit attendee \(number)", "firstSeenAt": "2026-10-30T12:01:00Z", "lastSeenAt": "2026-10-30T12:29:00Z"]
            }]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8) else { return (500, "{}") }
        return (200, json)
    }
    private func respond(_ status: Int, _ body: String) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                              headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
