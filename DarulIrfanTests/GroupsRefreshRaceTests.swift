import Foundation
import XCTest
@testable import DarulIrfan

@MainActor
final class GroupsRefreshRaceTests: XCTestCase {
    func testNewLoginDuringNativeCleanupPreservesReplacementAccount() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GroupsRaceProtocol.self]
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel() }
        let store = GroupsRaceSession()
        let service = MemberGroupService(baseURL: URL(string: "https://groups-race.invalid")!,
            session: transport, uploads: transport, savedSession: store,
            onSessionInvalidated: {
                store.save(.init(token: "replacement", expiresAt: .distantFuture, memberID: "new-member"))
            })
        GroupsRaceProtocol.configure(holdFirst: false) {}
        let result = await service.signOut()
        XCTAssertFalse(result)
        XCTAssertEqual(store.load()?.token, "replacement")
    }

    func testSignoutReleasesNativeSessionIncludingWhenLoginAlreadyGone() async {
        for hasLogin in [true, false] {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [GroupsRaceProtocol.self]
            let transport = URLSession(configuration: config)
            defer { transport.invalidateAndCancel() }
            let store = GroupsRaceSession()
            if !hasLogin, let saved = store.load() { _ = store.deleteIfCurrent(token: saved.token) }
            let probe = NativeCleanupProbe()
            let service = MemberGroupService(baseURL: URL(string: "https://groups-race.invalid")!,
                session: transport, uploads: transport, savedSession: store,
                onSessionInvalidated: { await probe.record() })
            GroupsRaceProtocol.configure(holdFirst: false) {}
            let result = await service.signOut()
            XCTAssertTrue(result)
            XCTAssertEqual(probe.count, 1)
        }
    }

    func testOldSuccessfulRefreshCannotPopulateReplacementAccount() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GroupsRaceProtocol.self]
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel() }
        let store = GroupsRaceSession()
        let service = MemberGroupService(baseURL: URL(string: "https://groups-race.invalid")!,
            session: transport, uploads: transport, savedSession: store)
        let model = GroupsModel(service: service)
        let pending = expectation(description: "Old successful groups response held")
        GroupsRaceProtocol.configure { pending.fulfill() }
        let older = Task { await model.refresh() }
        await fulfillment(of: [pending], timeout: 5)
        store.save(.init(token: "replacement", expiresAt: .distantFuture, memberID: "new-member"))
        GroupsRaceProtocol.releaseOlder(status: 200)
        await older.value
        XCTAssertEqual(store.load()?.token, "replacement")
        XCTAssertNotEqual(model.role, .superadmin)
        XCTAssertNotEqual(model.signedIn, 1)
    }

    func testDelayedSignOutPreservesReplacementSessionAndModel() async {
        for status in [204, 401, 503] {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [GroupsRaceProtocol.self]
            let transport = URLSession(configuration: config)
            defer { transport.invalidateAndCancel() }
            let store = GroupsRaceSession()
            let probe = NativeCleanupProbe()
            let service = MemberGroupService(baseURL: URL(string: "https://groups-race.invalid")!,
                session: transport, uploads: transport, savedSession: store,
                onSessionInvalidated: { await probe.record() })
            let model = GroupsModel(service: service)
            let pending = expectation(description: "Old signout held")
            GroupsRaceProtocol.configure(holdFirst: false, holdSignOut: true) { pending.fulfill() }
            let older = Task { await model.signOut() }
            await fulfillment(of: [pending], timeout: 5)
            store.save(.init(token: "replacement", expiresAt: .distantFuture, memberID: "new-member"))
            model.displayName = "Replacement name"
            GroupsRaceProtocol.releaseOlder(status: status)
            await older.value
            XCTAssertEqual(probe.count, 0)
            XCTAssertEqual(store.load()?.token, "replacement")
            XCTAssertEqual(model.displayName, "Replacement name")
        }
    }

    func testDelayedAccountDeletionPreservesReplacementSession() async {
        for status in [204, 401] {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [GroupsRaceProtocol.self]
            let transport = URLSession(configuration: config)
            defer { transport.invalidateAndCancel() }
            let store = GroupsRaceSession()
            let service = MemberGroupService(baseURL: URL(string: "https://groups-race.invalid")!,
                session: transport, uploads: transport, savedSession: store)
            let pending = expectation(description: "Old account deletion held")
            GroupsRaceProtocol.configure(holdFirst: false, holdProfile: true) { pending.fulfill() }
            let older = Task { try await service.deleteAccount() }
            await fulfillment(of: [pending], timeout: 5)
            store.save(.init(token: "replacement", expiresAt: .distantFuture, memberID: "new-member"))
            GroupsRaceProtocol.releaseOlder(status: status)
            do { try await older.value; XCTFail("Old completion must be discarded") }
            catch is CancellationError { }
            catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(store.load()?.token, "replacement")
            XCTAssertEqual(store.load()?.memberID, "new-member")
        }
    }

    func testOldUnauthorizedResponseCannotDeleteReplacementSession() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GroupsRaceProtocol.self]
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel() }
        let store = GroupsRaceSession()
        let service = MemberGroupService(baseURL: URL(string: "https://groups-race.invalid")!,
            session: transport, uploads: transport, savedSession: store)
        let pending = expectation(description: "Old-token request held")
        GroupsRaceProtocol.configure { pending.fulfill() }
        let older = Task { try await service.groups() }
        await fulfillment(of: [pending], timeout: 5)
        store.save(.init(token: "replacement", expiresAt: .distantFuture, memberID: "new-member"))
        GroupsRaceProtocol.releaseOlder(status: 401)
        do { _ = try await older.value; XCTFail("Old response must be discarded") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(store.load()?.token, "replacement")
        XCTAssertEqual(store.load()?.memberID, "new-member")
    }

    func testDelayedProfileCannotOverwriteSavedName() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GroupsRaceProtocol.self]
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel() }
        let service = MemberGroupService(baseURL: URL(string: "https://groups-race.invalid")!,
            session: transport, uploads: transport, savedSession: GroupsRaceSession())
        let model = GroupsModel(service: service)
        let pending = expectation(description: "Old profile held")
        GroupsRaceProtocol.configure(holdFirst: false, holdProfile: true) { pending.fulfill() }
        let refresh = Task { await model.refresh() }
        await fulfillment(of: [pending], timeout: 5)
        await model.rename("New name")
        XCTAssertEqual(model.displayName, "New name")
        GroupsRaceProtocol.releaseOlder()
        await refresh.value
        XCTAssertEqual(model.displayName, "New name")
        XCTAssertFalse(model.isSavingName)
        XCTAssertNil(model.nameError)
    }

    func testProfileExpiryClearsAccountButTemporaryFailurePreservesName() async {
        for status in [503, 401] {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [GroupsRaceProtocol.self]
            let transport = URLSession(configuration: config)
            defer { transport.invalidateAndCancel() }
            let store = GroupsRaceSession()
            let service = MemberGroupService(baseURL: URL(string: "https://groups-race.invalid")!,
                session: transport, uploads: transport, savedSession: store)
            let model = GroupsModel(service: service)
            model.displayName = "Saved name"
            GroupsRaceProtocol.configure(holdFirst: false, profileStatus: status) { }
            await model.refresh()
            if status == 401 {
                XCTAssertEqual(model.phase, .signedOut)
                XCTAssertNil(model.displayName)
                XCTAssertNil(model.memberID)
                XCTAssertNil(model.signedIn)
                XCTAssertTrue(model.groups.isEmpty)
                XCTAssertEqual(model.role, .member)
                XCTAssertNil(store.load())
            } else {
                XCTAssertEqual(model.phase, .ready)
                XCTAssertEqual(model.displayName, "Saved name")
                XCTAssertNotNil(store.load())
            }
        }
    }

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
    func deleteIfCurrent(token: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let current = session, current.token != token { return false }
        session = nil
        return true
    }
}

private final class GroupsRaceProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var first = true
    private static var older: GroupsRaceProtocol?
    private static var onHeld: (() -> Void)?
    private static var profileStatus = 404
    private static var holdSignOut = false
    private static var holdProfile = false
    private static var heldProfile = false
    static func configure(holdFirst: Bool = true, profileStatus: Int = 404, holdProfile: Bool = false, holdSignOut: Bool = false, _ onHeld: @escaping () -> Void) {
        lock.lock(); defer { lock.unlock() }
        first = holdFirst; older = nil; self.onHeld = onHeld
        self.profileStatus = profileStatus
        self.holdSignOut = holdSignOut
        self.holdProfile = holdProfile
        heldProfile = false
    }
    static func releaseOlder(status: Int = 200) {
        lock.lock(); let held = older; let profile = heldProfile; older = nil; lock.unlock()
        held?.respond(status, profile
            ? "{\"memberID\":\"fixture\",\"role\":\"member\",\"displayName\":\"Old name\"}"
            : "{\"role\":\"superadmin\",\"groups\":[],\"signedIn\":1}")
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
            Self.lock.lock()
            if Self.holdSignOut {
                Self.holdSignOut = false; Self.older = self
                let callback = Self.onHeld
                Self.lock.unlock()
                callback?()
                return
            }
            Self.lock.unlock()
            respond(204, "")
        } else if request.url?.path == "/v1/members/me" {
            if request.httpMethod == "PUT" {
                respond(200, "{\"memberID\":\"fixture\",\"role\":\"member\",\"displayName\":\"New name\"}")
                return
            }
            Self.lock.lock()
            if Self.holdProfile {
                Self.holdProfile = false; Self.heldProfile = true; Self.older = self
                let callback = Self.onHeld
                Self.lock.unlock()
                callback?()
                return
            }
            let status = Self.profileStatus; Self.lock.unlock()
            respond(status, "{}")
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

@MainActor
private final class NativeCleanupProbe {
    var count = 0
    func record() { count += 1 }
}
