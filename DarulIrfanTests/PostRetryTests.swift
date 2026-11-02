import Foundation
import XCTest
@testable import DarulIrfan

@MainActor
final class PostRetryTests: XCTestCase {
    func testLostResponseRetryKeepsRequestIdentity() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PostRetryProtocol.self]
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel() }
        PostRetryProtocol.configure(conflict: false)
        let service = MemberGroupService(baseURL: URL(string: "https://post-retry.invalid")!,
            session: transport, uploads: transport, savedSession: PostRetrySession())
        let requestID = UUID()
        do {
            try await service.createPost(in: "usa", title: "Post", body: "Message", videoID: nil,
                media: ["saved-media-key"], publish: true, requestID: requestID)
            XCTFail("Expected the lost response")
        } catch is URLError { }
        try await service.createPost(in: "usa", title: "Post", body: "Message", videoID: nil,
            media: ["saved-media-key"], publish: true, requestID: requestID)
        let requests = PostRetryProtocol.bodies()
        XCTAssertEqual(requests.count, 2)
        let first = try XCTUnwrap(try JSONSerialization.jsonObject(with: requests[0]) as? NSDictionary)
        let second = try XCTUnwrap(try JSONSerialization.jsonObject(with: requests[1]) as? NSDictionary)
        XCTAssertEqual(first, second)
        XCTAssertEqual(second["requestID"] as? String, requestID.uuidString)
    }

    func testConflictingRetryUsesLocalizedRecoveryError() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PostRetryProtocol.self]
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel() }
        PostRetryProtocol.configure(conflict: true)
        let service = MemberGroupService(baseURL: URL(string: "https://post-retry.invalid")!,
            session: transport, uploads: transport, savedSession: PostRetrySession())
        do {
            try await service.createPost(in: "usa", title: "Changed", body: nil, videoID: nil,
                publish: true, requestID: UUID())
            XCTFail("Expected conflict")
        } catch MemberGroupError.postRequestConflict { }
    }
}

private final class PostRetrySession: MemberSessionStore, @unchecked Sendable {
    func load() -> MemberSession? { .init(token: "fixture", expiresAt: .distantFuture, memberID: "fixture") }
    func save(_ value: MemberSession) { }
    func delete() { }
    func deleteIfCurrent(token: String) -> Bool { true }
}

private final class PostRetryProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var captured: [Data] = []
    private static var conflict = false
    static func configure(conflict: Bool) {
        lock.lock(); defer { lock.unlock() }
        captured = []; self.conflict = conflict
    }
    static func bodies() -> [Data] {
        lock.lock(); defer { lock.unlock() }
        return captured
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.lock.lock()
        Self.captured.append(body)
        let first = Self.captured.count == 1
        let conflict = Self.conflict
        Self.lock.unlock()
        if first && !conflict {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: conflict ? 409 : 201,
            httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let payload = conflict ? #"{"code":"post_request_conflict","error":"server English"}"# : "{}"
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
