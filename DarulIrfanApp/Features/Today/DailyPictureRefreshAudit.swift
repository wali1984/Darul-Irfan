#if DEBUG
import SwiftUI
import Foundation

struct DailyPictureRefreshAudit: View {
    private let service: MemberGroupService
    @State private var released = false

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DailyPictureRefreshProtocol.self]
        service = MemberGroupService(baseURL: URL(string: "https://picture-refresh.invalid")!,
            session: URLSession(configuration: config), savedSession: PictureRefreshSession())
    }

    var body: some View {
        DailyMediaManagerView(service: service)
            .safeAreaInset(edge: .bottom) {
                VStack {
                    TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                        Text(verbatim: String(DailyPictureRefreshProtocol.requestCount))
                            .accessibilityIdentifier("picture-list-request-count")
                    }
                    Button(released ? "Initial list released" : "Release initial list") {
                        released = DailyPictureRefreshProtocol.releaseInitial()
                    }
                    .disabled(released)
                    .accessibilityIdentifier("release-picture-list")
                }
            }
    }
}

private struct PictureRefreshSession: MemberSessionStore {
    func load() -> MemberSession? { .init(token: "fixture", expiresAt: .distantFuture, memberID: "fixture") }
    func save(_ value: MemberSession) { }
    func delete() { }
    func deleteIfCurrent(token: String) -> Bool { true }
}

private final class DailyPictureRefreshProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var pending: DailyPictureRefreshProtocol?
    private static var count = 0
    static var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.httpMethod == "GET", request.url?.path == "/v1/daily-media/manage" else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        Self.lock.lock()
        Self.count += 1
        let first = Self.count == 1
        if first { Self.pending = self }
        Self.lock.unlock()
        if !first { respond(caption: "Fresh picture list") }
    }
    static func releaseInitial() -> Bool {
        lock.lock(); let held = pending; pending = nil; lock.unlock()
        held?.respond(caption: "Older picture list")
        return held != nil
    }
    private func respond(caption: String) {
        let data = try! JSONSerialization.data(withJSONObject: ["items": [
            ["id": "fixture", "slot": "quote", "caption": caption, "popup": false, "status": "draft"]
        ]])
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        if Self.pending === self { Self.pending = nil }
    }
}
#endif
