import Foundation
import XCTest
@testable import DarulIrfan

/// The newest Daily Zikr, picked by itself (owner 2026-11-19, addendum 4): a
/// simple page's start sheet opens with it, and a zikr time may play it.
final class HalqahNewestZikrTests: XCTestCase {
    private let decoder = JSONDecoder.darulIrfanServer()

    private let json = #"""
    {"group":{"id":"na-evening","name":"North America - Evening Zikr","videoClips":true,"simplePage":true,
       "startTitle":"Start Daily North America Nightly Zikr",
       "newestZikr":{"videoID":"dQw4w9WgXcQ","title":"Daily Zikr 19 Nov","startSeconds":216,"endSeconds":2642}},
     "canManage":true,
     "zikrSessions":[
       {"id":"zikr-1","title":"Evening Zikr","weekdays":[1,2,3,4,5,6,7],"startHour":20,"startMinute":30,
        "durationMinutes":45,"timeZoneIdentifier":"America/New_York","autoplayNewest":true,
        "autoplayTitle":"Daily Zikr 19 Nov",
        "autoplay":[{"kind":"video","id":"dQw4w9WgXcQ","title":"Daily Zikr 19 Nov","startSeconds":216,"endSeconds":2642}]},
       {"id":"zikr-2","title":"Morning","weekdays":[1],"startHour":6,"startMinute":0,
        "durationMinutes":30,"timeZoneIdentifier":"America/New_York","autoplayTitle":"A recording",
        "autoplay":[{"kind":"recording","id":"r1","title":"A recording"}]}
     ],
     "meetings":[]}
    """#

    func testNewestZikrDecodes() throws {
        let detail = try decoder.decode(GroupDetail.self, from: Data(json.utf8))
        XCTAssertEqual(detail.group.newestZikr, GroupDetail.NewestZikr(videoID: "dQw4w9WgXcQ", title: "Daily Zikr 19 Nov",
                                                                       startSeconds: 216, endSeconds: 2642))
        XCTAssertEqual(detail.zikrSessions.map(\.autoplayNewest), [true, nil])

        let ordinary = try decoder.decode(GroupDetail.self, from: Data(
            #"{"group":{"id":"usa","name":"USA"},"canManage":true,"zikrSessions":[],"meetings":[]}"#.utf8))
        XCTAssertNil(ordinary.group.newestZikr)
    }

    func testSimpleStartSheetOpensWithTheNewestZikr() throws {
        let detail = try decoder.decode(GroupDetail.self, from: Data(json.utf8))
        let form = HalqahStartForm(simple: true, startTitle: detail.group.startTitle, newestZikr: detail.group.newestZikr)
        XCTAssertEqual(form.prefill, VideoLinkDraft(link: "https://youtu.be/dQw4w9WgXcQ", start: "3:36", end: "44:02"))
        XCTAssertEqual(VideoLink.id(from: try XCTUnwrap(form.prefill).link), "dQw4w9WgXcQ")

        let open = GroupDetail.NewestZikr(videoID: "dQw4w9WgXcQ", startSeconds: 216)
        XCTAssertEqual(HalqahStartForm(simple: true, newestZikr: open).prefill,
                       VideoLinkDraft(link: "https://youtu.be/dQw4w9WgXcQ", start: "3:36", end: ""))
        XCTAssertNil(HalqahStartForm(simple: true, startTitle: "Start Zikr").prefill, "no newest Zikr: the sheet opens empty")
        XCTAssertNil(HalqahStartForm(simple: false, newestZikr: detail.group.newestZikr).prefill, "only a simple page")
        XCTAssertNil(HalqahStartForm().prefill)
    }

    func testPlaysByItselfNamesTheNewestDailyZikr() throws {
        let detail = try decoder.decode(GroupDetail.self, from: Data(json.utf8))
        XCTAssertEqual(ZikrAutoplayLine.text(for: detail.zikrSessions[0]), "the newest Daily Zikr · 3:36 - 44:02")
        XCTAssertEqual(ZikrAutoplayLine.text(for: detail.zikrSessions[1]), "A recording")

        var plain = detail.zikrSessions[0]
        plain.autoplayNewest = nil
        XCTAssertEqual(ZikrAutoplayLine.text(for: plain), "Daily Zikr 19 Nov · 3:36 - 44:02", "an admin's own clip, as before")
        plain.autoplay = nil
        plain.autoplayTitle = nil
        XCTAssertNil(ZikrAutoplayLine.text(for: plain))
    }

    func testTheEditorOpensWithTheNewestToggle() throws {
        let detail = try decoder.decode(GroupDetail.self, from: Data(json.utf8))
        let newest = ZikrTimeDraft(detail.zikrSessions[0], videoClips: true)
        XCTAssertTrue(newest.playsNewest)
        XCTAssertEqual(newest.videoLink, "https://youtu.be/dQw4w9WgXcQ", "ready if the admin turns it off")
        XCTAssertFalse(ZikrTimeDraft(detail.zikrSessions[1], videoClips: true).playsNewest)
    }

    func testTheNewestChoiceReachesTheServer() async throws {
        let store = NewestTestSession()
        store.save(.init(token: "token", expiresAt: .distantFuture, memberID: "admin"))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NewestTestProtocol.self]
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel() }
        let service = MemberGroupService(baseURL: URL(string: "https://api.newest-test.invalid")!, session: transport,
                                         savedSession: store, onSessionInvalidated: {})
        NewestTestProtocol.reset()
        let session = ZikrSession(id: "zikr-1", title: "Evening Zikr", weekdays: [1], startHour: 20, startMinute: 30,
                                  durationMinutes: 45, timeZoneIdentifier: "America/New_York")

        try await service.saveZikrSession(session, autoplay: [], autoplayNewest: true, in: "na")
        try await service.saveZikrSession(session, autoplay: [.clip("dQw4w9WgXcQ", start: 216, end: 2642)], autoplayNewest: false, in: "na")
        try await service.saveZikrSession(session, autoplay: [.video("dQw4w9WgXcQ")], in: "usa")

        let seen = NewestTestProtocol.requests()
        XCTAssertEqual(seen.count, 3)
        XCTAssertEqual(seen[0].body["autoplayNewest"] as? Bool, true)
        XCTAssertNil(seen[0].body["autoplay"], "on: no video of the admin's own")
        XCTAssertEqual(seen[1].body["autoplayNewest"] as? Bool, false)
        XCTAssertNotNil(seen[1].body["autoplay"])
        XCTAssertNil(seen[2].body["autoplayNewest"], "every other time sends what it always sent")
    }
}

private final class NewestTestSession: MemberSessionStore, @unchecked Sendable {
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

private final class NewestTestProtocol: URLProtocol {
    struct Seen { let method: String; let path: String; let body: [String: Any] }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [Seen] = []

    static func reset() { lock.lock(); defer { lock.unlock() }; seen = [] }
    static func requests() -> [Seen] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".newest-test.invalid") == true }
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
        Self.lock.lock()
        Self.seen.append(Seen(method: request.httpMethod ?? "GET", path: request.url?.path ?? "", body: body))
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"ok":true}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
