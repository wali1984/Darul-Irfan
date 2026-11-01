import Foundation
import XCTest
@testable import DarulIrfan

@MainActor
final class GroupsRefreshRaceTests: XCTestCase {
    func testLateRefreshCannotReplaceNewerRefreshOrSignedOutState() async throws {
        for signsOut in [false, true] {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [GroupsRaceProtocol.self]
            let transport = URLSession(configuration: config)
            defer { transport.invalidateAndCancel() }
            let store = GroupsRaceSession()
            let service = MemberGroupService(baseURL: URL(string: "https://groups-race.invalid")!,
                session: transport, uploads: transport, savedSession: store)
            let model = GroupsModel(service: service)
            let pending = expectation(description: "Older groups request held")
            GroupsRaceProtocol.configure { pending.fulfill() }
            let older = Task { await model.refresh() }
            await fulfillment(of: [pending], timeout: 5)
            if signsOut {
                await model.signOut()
                XCTAssertEqual(model.phase, .signedOut)
            } else {
                await model.refresh()
                XCTAssertEqual(model.signedIn, 2)
                XCTAssertEqual(model.role, .member)
            }
            GroupsRaceProtocol.releaseOlder()
            await older.value
            if signsOut {
                XCTAssertEqual(model.phase, .signedOut)
                XCTAssertNil(model.memberID)
                XCTAssertNil(model.signedIn)
                XCTAssertNil(model.displayName)
                XCTAssertEqual(model.role, .member)
                XCTAssertTrue(model.groups.isEmpty)
                XCTAssertNil(store.load())
            } else {
                XCTAssertEqual(model.phase, .ready)
                XCTAssertEqual(model.signedIn, 2)
                XCTAssertEqual(model.role, .member)
            }
        }
    }
}

private final class GroupsRaceSession: MemberSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: MemberSession? = .init(token: "fixture", expiresAt: .distantFuture, memberID: "fixture")
    func load() -> MemberSession? { lock.lock(); defer { lock.unlock() }; return session }
    func save(_ value: MemberSession) { lock.lock(); defer { lock.unlock() }; session = value }
    func delete() { lock.lock(); defer { lock.unlock() }; session = nil }
}

private final class GroupsRaceProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var first = true
    private static var older: GroupsRaceProtocol?
    private static var onHeld: (() -> Void)?
    static func configure(_ onHeld: @escaping () -> Void) {
        lock.lock(); defer { lock.unlock() }
        first = true; older = nil; self.onHeld = onHeld
    }
    static func releaseOlder() {
        lock.lock(); let held = older; older = nil; lock.unlock()
        held?.respond(200, "{\"role\":\"superadmin\",\"groups\":[],\"signedIn\":1}")
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.path == "/v1/groups" {
            Self.lock.lock()
            if Self.first {
                Self.first = false; Self.older = self
                let callback = Self.onHeld
                Self.lock.unlock()
                callback?()
                return
            }
            Self.lock.unlock()
            respond(200, "{\"role\":\"member\",\"groups\":[],\"signedIn\":2}")
        } else if request.url?.path == "/v1/members/signout" {
            respond(204, "")
        } else {
            respond(404, "{}")
        }
    }
    private func respond(_ status: Int, _ body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
