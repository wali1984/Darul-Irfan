import Foundation
import XCTest
@testable import DarulIrfan

/// Test Zikr and taking things off the stage (owner, 2026-11-04): what the
/// server sends decodes, older servers still decode, removed announcements
/// leave the stage, and the requests go where the server expects them.
final class HalqahModerationTests: XCTestCase {
    private let decoder = JSONDecoder.darulIrfanServer()

    // MARK: - Decoding

    func testStagePollCarriesModerationAndTest() throws {
        let json = #"{"live":{"title":"Online Zikr","startedAt":"2026-11-04T20:00:00.000Z","isTest":true},"#
            + #""canLead":true,"canModerate":true,"cues":[],"nextCue":12,"hiddenCues":["e-1"],"#
            + #""messages":[],"nextChat":4,"hidden":[]}"#
        let update = try decoder.decode(HalqaStageUpdate.self, from: Data(json.utf8))
        XCTAssertEqual(update.live?.isTest, true)
        XCTAssertEqual(update.canModerate, true)
        XCTAssertEqual(update.hiddenCues, ["e-1"])
    }

    func testOlderStagePollStillDecodes() throws {
        let json = #"{"live":null,"canLead":false,"cues":[],"nextCue":0,"messages":[],"nextChat":0,"hidden":[]}"#
        let update = try decoder.decode(HalqaStageUpdate.self, from: Data(json.utf8))
        XCTAssertNil(update.live)
        XCTAssertNil(update.canModerate)
        XCTAssertNil(update.hiddenCues)
    }

    func testTestSessionIsMarkedOnTheGroupListLiveAndHistory() throws {
        let list = try decoder.decode(MemberGroupList.self, from: Data(
            #"{"groups":[{"id":"usa","name":"USA","isLive":true,"liveKind":"zikr","liveIsTest":true},{"id":"uk","name":"UK"}]}"#.utf8))
        XCTAssertEqual(list.groups.map(\.liveIsTest), [true, nil])

        let live = try decoder.decode(GroupLive.self, from: Data(#"{"kind":"zikr","hasRoom":true,"isTest":true}"#.utf8))
        XCTAssertEqual(live.isTest, true)
        let ordinary = try decoder.decode(GroupLive.self, from: Data(#"{"kind":"zikr","hasRoom":true}"#.utf8))
        XCTAssertNil(ordinary.isTest)

        let history = try decoder.decode(GroupSessionHistory.self, from: Data((
            #"{"canDelete":false,"sessions":[{"id":"s1","kind":"zikr","startedAt":"2026-11-04T20:00:00.000Z","#
            + #""endedAt":"2026-11-04T20:30:00.000Z","attendees":1,"isTest":true},"#
            + #"{"id":"s2","kind":"zikr","startedAt":"2026-11-03T20:00:00.000Z","endedAt":"2026-11-03T20:30:00.000Z","attendees":9}]}"#).utf8))
        XCTAssertEqual(history.sessions.map(\.isTest), [true, nil])
    }

    // MARK: - The stage's announcements

    private func cue(_ id: String, _ sequence: Int64) -> HalqaZikrCue {
        HalqaZikrCue(sequence: sequence, id: id, stageID: "latifa-1", title: "Qalb", titleUr: nil, authorID: "a",
                     createdAt: Date(timeIntervalSince1970: TimeInterval(sequence)), notificationState: "complete")
    }

    func testRemovedAnnouncementsLeaveTheStage() {
        let shown = [cue("e-1", 1), cue("e-2", 2)]
        let after = ZikrStageModel.stageCues(shown, adding: [cue("e-3", 3), cue("e-2", 2)], hidden: ["E-2"], isLive: true)
        XCTAssertEqual(after.map(\.id), ["e-1", "e-3"])
    }

    func testNoAnnouncementsOnceTheZikrIsNotLive() {
        let shown = [cue("e-1", 1), cue("e-2", 2)]
        XCTAssertTrue(ZikrStageModel.stageCues(shown, adding: [], hidden: [], isLive: false).isEmpty)
    }

    // MARK: - Requests

    func testTestZikrAndRemovalsReachTheServer() async throws {
        let store = ModerationTestSession()
        store.save(.init(token: "token", expiresAt: .distantFuture, memberID: "admin"))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ModerationTestProtocol.self]
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel() }
        let service = MemberGroupService(baseURL: URL(string: "https://api.moderation-test.invalid")!, session: transport,
                                         savedSession: store, onSessionInvalidated: {})
        ModerationTestProtocol.reset()

        try await service.startLive(in: "usa", kind: "zikr", title: "Halqah Zikr", videoID: nil, room: true, test: true)
        try await service.startLive(in: "usa", kind: "zikr", title: "Halqah Zikr", videoID: nil, room: true)
        try await service.removeZikrCue("e-1", in: "our-sheikh")
        try await service.removeDua("dua-1", in: "usa")

        let seen = ModerationTestProtocol.requests()
        XCTAssertEqual(seen.map(\.method), ["POST", "POST", "DELETE", "DELETE"])
        XCTAssertEqual(seen.map(\.path), ["/v1/groups/usa/live", "/v1/groups/usa/live",
                                          "/v1/groups/our-sheikh/zikr-cues/e-1", "/v1/groups/usa/duas/dua-1"])
        XCTAssertEqual(seen[0].body["test"] as? Bool, true)
        XCTAssertNil(seen[1].body["test"], "An ordinary start must not send test")
    }
}

private final class ModerationTestSession: MemberSessionStore, @unchecked Sendable {
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

private final class ModerationTestProtocol: URLProtocol {
    struct Seen { let method: String; let path: String; let body: [String: Any] }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [Seen] = []

    static func reset() { lock.lock(); defer { lock.unlock() }; seen = [] }
    static func requests() -> [Seen] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".moderation-test.invalid") == true }
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
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let method = request.httpMethod ?? "GET"
        Self.lock.lock()
        Self.seen.append(Seen(method: method, path: request.url?.path ?? "", body: body))
        Self.lock.unlock()
        let status = method == "DELETE" ? 204 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if status == 200 { client?.urlProtocol(self, didLoad: Data(#"{"ok":true,"state":"live"}"#.utf8)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
