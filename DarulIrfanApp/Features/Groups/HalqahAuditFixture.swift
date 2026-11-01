#if DEBUG
import SwiftUI
import Foundation

/// Exercises the real detail screen without a Keychain session or live group requests.
struct HalqahAuditFixture: View {
    private let service: MemberGroupService

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
                    GroupDetailView(group: MemberGroup(
                        id: role, name: "Audit Halqah", description: nil,
                        meetingURL: nil, meetingNote: nil,
                        canManage: role == "admin", myRole: role == "admin" ? .admin : .member),
                        service: service, dependencies: nil)
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

    // This session never falls through to the network, including unexpected requests.
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, url.host == "halqah-audit.invalid",
              request.httpMethod == "GET" else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let parts = url.pathComponents
        guard parts.count >= 4, parts[1] == "v1", parts[2] == "groups",
              ["member", "admin"].contains(parts[3]) else {
            respond(404, "{}")
            return
        }
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
