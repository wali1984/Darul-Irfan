import Foundation
import XCTest
@testable import DarulIrfan

final class SheikhPublicJoinTests: XCTestCase {
    func testGuestAdmissionStoresReturnedSession() async throws {
        let store = SheikhJoinTestSession()
        let transport = makeTransport()
        defer { transport.invalidateAndCancel() }
        let service = MemberGroupService(baseURL: URL(string: "https://guest.sheikh-test.invalid")!, session: transport, savedSession: store)
        let member = try await service.joinOurSheikh(name: "Visitor", city: "Lahore", countryCode: "PK", email: "contact@example.com", guestSecret: String(repeating: "a", count: 64))
        XCTAssertEqual(member, "guest")
        XCTAssertEqual(store.load()?.memberID, "guest")
        XCTAssertEqual(store.load()?.token, String(repeating: "b", count: 64))
    }

    func testAuthenticatedAdmissionPreservesSession() async throws {
        let store = SheikhJoinTestSession()
        store.save(.init(token: "original", expiresAt: .distantFuture, memberID: "member"))
        let transport = makeTransport()
        defer { transport.invalidateAndCancel() }
        let service = MemberGroupService(baseURL: URL(string: "https://member.sheikh-test.invalid")!, session: transport, savedSession: store)
        let member = try await service.joinOurSheikh(name: "Visitor", city: "Lahore", countryCode: "PK", email: nil, guestSecret: "must-not-be-sent")
        XCTAssertEqual(member, "member")
        XCTAssertEqual(store.load()?.token, "original")
    }

    func testFailedAdmissionDoesNotReplaceCurrentSession() async {
        for host in ["denied", "limited", "wrong-member"] {
            let store = SheikhJoinTestSession()
            store.save(.init(token: "original", expiresAt: .distantFuture, memberID: "member"))
            let transport = makeTransport()
            defer { transport.invalidateAndCancel() }
            let service = MemberGroupService(baseURL: URL(string: "https://\(host).sheikh-test.invalid")!, session: transport, savedSession: store)
            do {
                _ = try await service.joinOurSheikh(name: "Visitor", city: "Lahore", countryCode: "PK", email: nil, guestSecret: "unused")
                XCTFail("Admission must fail for \(host)")
            } catch { }
            XCTAssertEqual(store.load()?.token, "original")
            XCTAssertEqual(store.load()?.memberID, "member")
        }
    }

    private func makeTransport() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SheikhJoinTestProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class SheikhJoinTestSession: MemberSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: MemberSession?
    func load() -> MemberSession? { lock.lock(); defer { lock.unlock() }; return value }
    func save(_ session: MemberSession) { lock.lock(); defer { lock.unlock() }; value = session }
    func delete() { lock.lock(); defer { lock.unlock() }; value = nil }
    func deleteIfCurrent(token: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard value == nil || value?.token == token else { return false }
        value = nil
        return true
    }
}

private final class SheikhJoinTestProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".sheikh-test.invalid") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] ?? [:]
        let host = request.url!.host!.components(separatedBy: ".")[0]
        var status = 400
        var body: [String: String] = [:]
        if request.url?.path == "/v1/our-sheikh/join", request.httpMethod == "POST" {
            switch host {
            case "guest":
                if request.value(forHTTPHeaderField: "authorization") == nil,
                   payload["guestSecret"] == String(repeating: "a", count: 64), payload["email"] == "contact@example.com" {
                    status = 201
                    body = ["memberID": "guest", "token": String(repeating: "b", count: 64), "expiresAt": "2099-01-01T00:00:00.000Z"]
                }
            case "member":
                if request.value(forHTTPHeaderField: "authorization") == "Bearer original", payload["guestSecret"] == nil {
                    status = 200; body = ["memberID": "member", "groupID": "our-sheikh"]
                }
            case "denied": status = 401
            case "limited": status = 429
            case "wrong-member": status = 200; body = ["memberID": "different", "groupID": "our-sheikh"]
            default: break
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
