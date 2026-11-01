import Foundation
import XCTest
@testable import DarulIrfan

final class DailyMediaTransportTests: XCTestCase {
    func testUploadRetryExpiredSessionAndManagementPayloads() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DailyMediaProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let store = MemoryMemberSession()
        let service = MemberGroupService(baseURL: URL(string: "https://daily-media.invalid")!,
                                         session: transport, uploads: transport, savedSession: store)
        let picture = Data([0xff, 0xd8, 1, 2, 3, 0xff, 0xd9])
        DailyMediaProtocol.reset(statuses: [503, 201, 503, 200, 204, 401])
        func upload() async throws {
            try await service.uploadDailyMedia(picture, contentType: "image/jpeg", slot: .quote,
                day: "2026-11-01", endDay: "2026-11-03", caption: "A & B + ?", popup: true, publish: false)
        }

        do { try await upload(); XCTFail("A rejected upload must fail") }
        catch MemberGroupError.server(let message) { XCTAssertEqual(message, "Try again later") }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertNotNil(store.load(), "A temporary failure must preserve sign-in")
        XCTAssertEqual(DailyMediaProtocol.requests.count, 1, "Never duplicate a publication automatically")
        try await upload()
        let uploads = DailyMediaProtocol.requests
        XCTAssertEqual(uploads.count, 2)
        for captured in uploads {
            XCTAssertEqual(captured.request.httpMethod, "POST")
            XCTAssertEqual(captured.request.url?.path, "/v1/daily-media/manage")
            XCTAssertEqual(captured.request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(captured.request.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
            XCTAssertEqual(captured.body, picture)
            let query = URLComponents(url: try XCTUnwrap(captured.request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") }),
                           ["slot": "quote", "day": "2026-11-01", "endDay": "2026-11-03",
                            "caption": "A & B + ?", "popup": "1", "publish": "0"])
        }
        XCTAssertEqual(uploads[0].request.url, uploads[1].request.url)
        do { try await service.updateDailyMedia("fixture", ["status": "hidden"]); XCTFail("Hide rejection must fail") }
        catch MemberGroupError.server(let message) { XCTAssertEqual(message, "Try again later") }
        catch { XCTFail("Unexpected error: \(error)") }
        try await service.updateDailyMedia("fixture", ["status": "published", "endDay": NSNull(), "popup": false])
        try await service.deleteDailyMedia("fixture")
        let requests = DailyMediaProtocol.requests
        XCTAssertEqual(requests[2].request.httpMethod, "PUT")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: requests[2].body) as? [String: String], ["status": "hidden"])
        let update = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[3].body) as? [String: Any])
        XCTAssertEqual(update["status"] as? String, "published")
        XCTAssertTrue(update["endDay"] is NSNull)
        XCTAssertEqual(update["popup"] as? Bool, false)
        XCTAssertEqual(requests[4].request.httpMethod, "DELETE")
        XCTAssertEqual(requests[4].request.url?.path, "/v1/daily-media/manage/fixture")
        do { try await upload(); XCTFail("Expired session must fail") }
        catch MemberGroupError.notSignedIn { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertNil(store.load())
        do { try await upload(); XCTFail("Signed-out upload must fail locally") }
        catch MemberGroupError.notSignedIn { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(DailyMediaProtocol.requests.count, 6)
    }
}

private final class MemoryMemberSession: MemberSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: MemberSession? = MemberSession(token: "test-token", expiresAt: .distantFuture, memberID: "fixture")
    func load() -> MemberSession? { lock.lock(); defer { lock.unlock() }; return value }
    func save(_ value: MemberSession) { lock.lock(); defer { lock.unlock() }; self.value = value }
    func delete() { lock.lock(); defer { lock.unlock() }; value = nil }
    func deleteIfCurrent(token: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let current = value, current.token != token { return false }
        value = nil
        return true
    }
}

private final class DailyMediaProtocol: URLProtocol {
    struct Captured { let request: URLRequest; let body: Data }
    private static let lock = NSLock()
    private static var captured: [Captured] = []
    private static var statuses: [Int] = []
    static var requests: [Captured] { lock.lock(); defer { lock.unlock() }; return captured }
    static func reset(statuses: [Int]) {
        lock.lock(); defer { lock.unlock() }
        captured = []; self.statuses = statuses
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.lock.lock()
        Self.captured.append(Captured(request: request, body: body))
        let status = Self.statuses.isEmpty ? 500 : Self.statuses.removeFirst()
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"error\":\"Try again later\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
