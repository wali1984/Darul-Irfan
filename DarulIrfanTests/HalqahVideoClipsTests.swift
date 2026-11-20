import Foundation
import XCTest
@testable import DarulIrfan

/// Halqah video clips (owner 2026-11-19): an admin of a Halqah the server
/// marks with `videoClips` pastes a YouTube link and it plays from a start
/// time to an end time. Every other Halqah sends and shows exactly what it
/// did before.
@MainActor
final class HalqahVideoClipsTests: XCTestCase {
    private let decoder = JSONDecoder.darulIrfanServer()

    // MARK: - Times typed by the admin

    func testClipTimesAreReadAsTyped() {
        XCTAssertEqual(ClipTime.seconds(from: "3:41"), 221)
        XCTAssertEqual(ClipTime.seconds(from: "44:02"), 2642)
        XCTAssertEqual(ClipTime.seconds(from: "1:02:03"), 3723)
        XCTAssertEqual(ClipTime.seconds(from: "221"), 221)
        XCTAssertEqual(ClipTime.seconds(from: " 3:41 "), 221)
        XCTAssertEqual(ClipTime.seconds(from: "0:00"), 0)
        XCTAssertEqual(ClipTime.seconds(from: "٣:٤١"), 221, "typed with an Urdu or Arabic keyboard")
    }

    func testUnreadableClipTimesAreNil() {
        for text in ["", "  ", "abc", "3:75", "1:2", "3:", ":41", "1:02:03:04", "-5", "3:41x", "3.41", "1:60:00"] {
            XCTAssertNil(ClipTime.seconds(from: text), text)
        }
    }

    func testClipTimesAreShownAsClockText() {
        XCTAssertEqual(ClipTime.text(221), "3:41")
        XCTAssertEqual(ClipTime.text(2642), "44:02")
        XCTAssertEqual(ClipTime.text(3723), "1:02:03")
        XCTAssertEqual(ClipTime.text(0), "0:00")
        XCTAssertEqual(ClipTime.range(start: 221, end: 2642), "3:41 - 44:02")
    }

    func testStartAndEndFieldsTogether() throws {
        XCTAssertEqual(try VideoClipTimes.read(start: "3:41", end: "44:02").get(), VideoClipTimes(start: 221, end: 2642))
        XCTAssertEqual(try VideoClipTimes.read(start: "", end: "").get(), VideoClipTimes())
        XCTAssertTrue(try VideoClipTimes.read(start: "", end: "").get().isEmpty)
        XCTAssertEqual(try VideoClipTimes.read(start: "221", end: "").get(), VideoClipTimes(start: 221, end: nil))
        XCTAssertEqual(try VideoClipTimes.read(start: "0:00", end: "44:02").get(), VideoClipTimes(start: nil, end: 2642),
                       "a start of 0 is the whole video's start")
        XCTAssertEqual(VideoClipTimes.problem(start: "44:02", end: "3:41"), .endNotAfterStart)
        XCTAssertEqual(VideoClipTimes.problem(start: "3:41", end: "3:41"), .endNotAfterStart)
        XCTAssertEqual(VideoClipTimes.problem(start: "", end: "0:00"), .endNotAfterStart)
        XCTAssertEqual(VideoClipTimes.problem(start: "abc", end: ""), .unreadable)
        XCTAssertEqual(VideoClipTimes.problem(start: "", end: "4:75"), .unreadable)
        XCTAssertNil(VideoClipTimes.problem(start: "3:41", end: "44:02"))
    }

    // MARK: - A link shared from a moment in the video

    func testStartIsReadFromThePastedLink() {
        XCTAssertEqual(VideoLink.startSeconds(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=221"), 221)
        XCTAssertEqual(VideoLink.startSeconds(from: "https://www.youtube.com/watch?t=221&v=dQw4w9WgXcQ"), 221)
        XCTAssertEqual(VideoLink.startSeconds(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=3m41s"), 221)
        XCTAssertEqual(VideoLink.startSeconds(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=221s"), 221)
        XCTAssertEqual(VideoLink.startSeconds(from: "https://www.youtube.com/embed/dQw4w9WgXcQ?start=221"), 221)
        XCTAssertEqual(VideoLink.startSeconds(from: "https://youtu.be/dQw4w9WgXcQ?t=90"), 90)
        XCTAssertEqual(VideoLink.startSeconds(from: "youtu.be/dQw4w9WgXcQ?t=90"), 90)
        XCTAssertEqual(VideoLink.startSeconds(from: "https://youtu.be/dQw4w9WgXcQ?si=abc&t=1h2m3s"), 3723)
        XCTAssertNil(VideoLink.startSeconds(from: "https://youtu.be/dQw4w9WgXcQ"))
        XCTAssertNil(VideoLink.startSeconds(from: "https://youtu.be/dQw4w9WgXcQ?si=abc"))
        XCTAssertNil(VideoLink.startSeconds(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=soon"))
        // The link itself is still the same video.
        XCTAssertEqual(VideoLink.id(from: "https://youtu.be/dQw4w9WgXcQ?t=90"), "dQw4w9WgXcQ")
        XCTAssertEqual(VideoLink.id(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=3m41s"), "dQw4w9WgXcQ")
    }

    // MARK: - What the server sends

    private let detailJSON = #"""
    {"group":{"id":"north-america-evening","name":"North America - Evening Zikr","videoClips":true},
     "canManage":true,
     "live":{"kind":"zikr","title":"Evening Zikr","hasRoom":false,"sessionID":"s1","recorded":true,
       "queue":[
         {"kind":"video","id":"q1","title":"Evening Zikr","durationSeconds":2421,"videoID":"dQw4w9WgXcQ","startSeconds":221,"endSeconds":2642},
         {"kind":"video","id":"q2","title":"Whole video","durationSeconds":1800,"videoID":"yuQSH_D2iMo"},
         {"kind":"recording","id":"r1","title":"A recording","durationSeconds":600}
       ],
       "playback":{"index":0,"positionSeconds":100,"paused":false,"finished":false,"at":"2026-11-19T20:00:00.000Z"}},
     "zikrSessions":[
       {"id":"zikr-1","title":"Evening Zikr","weekdays":[1,2,3,4,5,6,7],"startHour":20,"startMinute":30,
        "durationMinutes":45,"timeZoneIdentifier":"America/New_York","autoplayTitle":"Evening Zikr",
        "autoplay":[{"kind":"video","id":"dQw4w9WgXcQ","title":"Evening Zikr","startSeconds":221,"endSeconds":2642}]}
     ],
     "meetings":[]}
    """#

    func testHalqahWithVideoClipsDecodes() throws {
        let detail = try decoder.decode(GroupDetail.self, from: Data(detailJSON.utf8))
        XCTAssertEqual(detail.group.videoClips, true)
        XCTAssertTrue(detail.hasVideoClips)
        let item = try XCTUnwrap(detail.live?.queue?.first)
        XCTAssertEqual(item.startSeconds, 221)
        XCTAssertEqual(item.endSeconds, 2642)
        XCTAssertEqual(item.durationSeconds, 2421)
        let autoplay = try XCTUnwrap(detail.zikrSessions.first?.autoplay?.first)
        XCTAssertEqual(autoplay, ZikrAutoplayItem(kind: "video", id: "dQw4w9WgXcQ", title: "Evening Zikr",
                                                  startSeconds: 221, endSeconds: 2642))
        XCTAssertEqual(detail.zikrSessions.first?.autoplayTitle, "Evening Zikr")
    }

    func testEveryOtherHalqahDecodesAsBefore() throws {
        let json = #"""
        {"group":{"id":"usa","name":"USA"},"canManage":true,
         "live":{"kind":"zikr","hasRoom":false,"recorded":true,
           "queue":[{"kind":"video","id":"q1","title":"Zikr","durationSeconds":1800,"videoID":"yuQSH_D2iMo"}],
           "playback":{"index":0,"positionSeconds":10,"paused":false,"finished":false,"at":"2026-11-19T20:00:00.000Z"}},
         "zikrSessions":[{"id":"z","title":"Zikr","weekdays":[1],"startHour":20,"startMinute":0,"durationMinutes":30,
           "timeZoneIdentifier":"America/New_York","autoplayTitle":"Zikr"}],
         "meetings":[]}
        """#
        let detail = try decoder.decode(GroupDetail.self, from: Data(json.utf8))
        XCTAssertNil(detail.group.videoClips)
        XCTAssertFalse(detail.hasVideoClips)
        let item = try XCTUnwrap(detail.live?.queue?.first)
        XCTAssertNil(item.startSeconds)
        XCTAssertFalse(item.isClip)
        XCTAssertEqual(item.clipStart, 0, "absent start is the video's start")
        XCTAssertNil(item.clipEnd)
        XCTAssertNil(item.clipRangeText)
        XCTAssertNil(detail.zikrSessions.first?.autoplay)
    }

    func testQueueItemsKnowWhereTheClipIsInTheVideo() throws {
        let detail = try decoder.decode(GroupDetail.self, from: Data(detailJSON.utf8))
        let queue = try XCTUnwrap(detail.live?.queue)
        XCTAssertTrue(queue[0].isClip)
        XCTAssertEqual(queue[0].clipStart, 221)
        XCTAssertEqual(queue[0].clipEnd, 2642, "start plus the clip's length")
        XCTAssertEqual(queue[0].clipRangeText, "3:41 - 44:02")
        XCTAssertFalse(queue[1].isClip)
        XCTAssertEqual(queue[1].clipStart, 0)
        XCTAssertFalse(queue[2].isClip, "recordings are never clips")
        XCTAssertEqual(queue[2].clipStart, 0)
    }

    // MARK: - The player rule: play at S + P, over at S + D

    func testThePlayerPlaysAtTheClipsStartPlusTheGroupsPlace() throws {
        let detail = try decoder.decode(GroupDetail.self, from: Data(detailJSON.utf8))
        let item = try XCTUnwrap(detail.live?.currentItem)
        let playback = try XCTUnwrap(detail.live?.playback)
        XCTAssertEqual(item.videoTime(atGroupPosition: playback.positionSeconds), 321)
        XCTAssertEqual(item.videoTime(atGroupPosition: Double(item.durationSeconds ?? 0)), item.clipEnd)

        let at = Date(timeIntervalSince1970: 1_000_000)
        let paused = YouTubeSync(position: 100, paused: true, at: at, clipStart: 221, clipEnd: 2642)
        XCTAssertEqual(paused.videoPosition(at: at.addingTimeInterval(30)), 321, "paused stays at S + P")
        let playing = YouTubeSync(position: 100, paused: false, at: at, clipStart: 221, clipEnd: 2642)
        XCTAssertEqual(playing.videoPosition(at: at.addingTimeInterval(10)), 331)
        XCTAssertFalse(playing.isOver(atVideoTime: 2641))
        XCTAssertTrue(playing.isOver(atVideoTime: 2642), "the item is over at S + D")

        // A whole video plays at the group's place, as before, and has no end of its own.
        let whole = YouTubeSync(position: 100, paused: false, at: at)
        XCTAssertEqual(whole.videoPosition(at: at.addingTimeInterval(10)), 110)
        XCTAssertFalse(whole.isOver(atVideoTime: 100_000))
    }

    func testAnotherPartOfTheSameVideoLoadsAgain() {
        let at = Date(timeIntervalSince1970: 1_000_000)
        let first = YouTubeSync(position: 0, paused: false, at: at, clipStart: 221, clipEnd: 2642)
        let second = YouTubeSync(position: 0, paused: false, at: at, clipStart: 3000, clipEnd: 3600)
        let pausedFirst = YouTubeSync(position: 50, paused: true, at: at, clipStart: 221, clipEnd: 2642)
        XCTAssertTrue(YouTubePlayerView.needsReload(loadedID: "video", previousSync: first, videoID: "video", sync: second))
        XCTAssertFalse(YouTubePlayerView.needsReload(loadedID: "video", previousSync: first, videoID: "video", sync: pausedFirst),
                       "a pause or move keeps the player")
    }

    func testThePlayersPageStartsAndEndsTheClip() {
        let at = Date(timeIntervalSince1970: 1_000_000)
        let clip = YouTubeWebView.syncPage(id: "dQw4w9WgXcQ",
                                           sync: YouTubeSync(position: 120, paused: false, at: at, clipStart: 221, clipEnd: 2642), now: at)
        XCTAssertTrue(clip.contains("&start=341&end=2642&origin="))
        XCTAssertTrue(clip.contains("var group = { pos: 341.0,"))
        XCTAssertTrue(clip.contains("var clipEnd = 2642.0, clipHeld = false;"))
        XCTAssertTrue(clip.contains("Math.min(2642.0, "))

        // A whole video's page has none of it.
        let whole = YouTubeWebView.syncPage(id: "yuQSH_D2iMo", sync: YouTubeSync(position: 120, paused: false, at: at), now: at)
        XCTAssertTrue(whole.contains("&start=120&origin="))
        XCTAssertTrue(whole.contains("var player = null, ready = false, joined = false;\nvar group = { pos: 120.0,"))
        XCTAssertTrue(whole.contains("function place() { return group.paused ? group.pos : group.pos + (Date.now() / 1000 - group.at); }"))
        XCTAssertFalse(whole.contains("&end="))
        XCTAssertFalse(whole.contains("clipEnd"))
        XCTAssertFalse(whole.contains("Math.min"))
    }

    // MARK: - What the app sends

    func testQueueEntriesCarryTheClipsTimes() {
        XCTAssertEqual(GroupQueueEntry.video("dQw4w9WgXcQ").payload as NSDictionary, ["videoID": "dQw4w9WgXcQ"] as NSDictionary)
        XCTAssertEqual(GroupQueueEntry.recording("r1").payload as NSDictionary, ["recordingID": "r1"] as NSDictionary)
        XCTAssertEqual(GroupQueueEntry.clip("dQw4w9WgXcQ", start: 221, end: 2642).payload as NSDictionary,
                       ["videoID": "dQw4w9WgXcQ", "startSeconds": 221, "endSeconds": 2642] as NSDictionary)
        XCTAssertEqual(GroupQueueEntry.clip("dQw4w9WgXcQ", start: nil, end: 2642).payload as NSDictionary,
                       ["videoID": "dQw4w9WgXcQ", "endSeconds": 2642] as NSDictionary)
        // No times: the same entry as before video clips.
        XCTAssertEqual(GroupQueueEntry.youTube("dQw4w9WgXcQ", times: VideoClipTimes()), .video("dQw4w9WgXcQ"))
        XCTAssertEqual(GroupQueueEntry.youTube("dQw4w9WgXcQ", times: VideoClipTimes(start: 221, end: 2642)),
                       .clip("dQw4w9WgXcQ", start: 221, end: 2642))
        XCTAssertEqual(GroupQueueEntry.clip("dQw4w9WgXcQ", start: 221, end: nil).itemID, "dQw4w9WgXcQ")
    }

    func testClipsReachTheServerAndOtherRequestsAreUnchanged() async throws {
        let store = ClipsTestSession()
        store.save(.init(token: "token", expiresAt: .distantFuture, memberID: "admin"))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ClipsTestProtocol.self]
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel() }
        let service = MemberGroupService(baseURL: URL(string: "https://api.clips-test.invalid")!, session: transport,
                                         savedSession: store, onSessionInvalidated: {})
        ClipsTestProtocol.reset()

        try await service.startLive(in: "na", kind: "zikr", title: "Evening Zikr", videoID: "dQw4w9WgXcQ", room: false,
                                    clip: VideoClipTimes(start: 221, end: 2642))
        try await service.startLive(in: "usa", kind: "zikr", title: "Halqah Zikr", videoID: "dQw4w9WgXcQ", room: false)
        try await service.addToSession([.clip("dQw4w9WgXcQ", start: 221, end: 2642)], in: "na", sessionID: "s1")
        try await service.addToSession([.video("dQw4w9WgXcQ")], in: "usa", sessionID: "s2")
        let session = ZikrSession(id: "zikr-1", title: "Evening Zikr", weekdays: [1, 2, 3, 4, 5, 6, 7], startHour: 20, startMinute: 30,
                                  durationMinutes: 45, timeZoneIdentifier: "America/New_York")
        try await service.saveZikrSession(session, autoplay: [.clip("dQw4w9WgXcQ", start: 221, end: 2642)], in: "na")

        let seen = ClipsTestProtocol.requests()
        XCTAssertEqual(seen.map(\.method), ["POST", "POST", "POST", "POST", "PUT"])
        XCTAssertEqual(seen.map(\.path), ["/v1/groups/na/live", "/v1/groups/usa/live", "/v1/groups/na/control",
                                          "/v1/groups/usa/control", "/v1/groups/na/zikr/zikr-1"])
        XCTAssertEqual(seen[0].body["videoID"] as? String, "dQw4w9WgXcQ")
        XCTAssertEqual(seen[0].body["videoStartSeconds"] as? Int, 221)
        XCTAssertEqual(seen[0].body["videoEndSeconds"] as? Int, 2642)
        XCTAssertEqual(Set(seen[1].body.keys), Set(["state", "kind", "title", "room", "record", "videoID"]),
                       "an ordinary start sends what it always sent")

        let clipItems = try XCTUnwrap(seen[2].body["items"] as? [[String: Any]])
        XCTAssertEqual(seen[2].body["action"] as? String, "add")
        XCTAssertEqual(clipItems.first?["videoID"] as? String, "dQw4w9WgXcQ")
        XCTAssertEqual(clipItems.first?["startSeconds"] as? Int, 221)
        XCTAssertEqual(clipItems.first?["endSeconds"] as? Int, 2642)
        let plainItems = try XCTUnwrap(seen[3].body["items"] as? [[String: Any]])
        XCTAssertEqual(plainItems.first.map { Set($0.keys) }, Set(["videoID"]))

        // The zikr time is changed in place, under its own id.
        let autoplay = try XCTUnwrap(seen[4].body["autoplay"] as? [[String: Any]])
        XCTAssertEqual(autoplay.first?["startSeconds"] as? Int, 221)
        XCTAssertEqual(autoplay.first?["endSeconds"] as? Int, 2642)
    }

    // MARK: - Change video: the editor filled with the time

    func testAnExistingZikrTimeFillsTheEditor() throws {
        let detail = try decoder.decode(GroupDetail.self, from: Data(detailJSON.utf8))
        let session = try XCTUnwrap(detail.zikrSessions.first)
        let draft = ZikrTimeDraft(session, videoClips: true)
        XCTAssertEqual(draft.title, "Evening Zikr")
        XCTAssertNil(draft.anchor)
        XCTAssertEqual(draft.weekdays, Set(1...7))
        XCTAssertEqual(draft.durationMinutes, 45)
        XCTAssertEqual(draft.videoLink, "https://youtu.be/dQw4w9WgXcQ")
        XCTAssertEqual(VideoLink.id(from: draft.videoLink), "dQw4w9WgXcQ")
        XCTAssertEqual(draft.clipStart, "3:41")
        XCTAssertEqual(draft.clipEnd, "44:02")
        XCTAssertNil(draft.autoplay)
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let parts = newYork.dateComponents([.hour, .minute], from: draft.time)
        XCTAssertEqual(parts.hour, 20)
        XCTAssertEqual(parts.minute, 30)

        var recorded = session
        recorded.autoplay = [ZikrAutoplayItem(kind: "recording", id: "r1", title: "A recording")]
        recorded.anchor = "afterIsha"
        let recordedDraft = ZikrTimeDraft(recorded, videoClips: true)
        XCTAssertEqual(recordedDraft.autoplay, .recording("r1"))
        XCTAssertEqual(recordedDraft.videoLink, "")
        XCTAssertEqual(recordedDraft.anchor, .afterIsha)
    }
}

private final class ClipsTestSession: MemberSessionStore, @unchecked Sendable {
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

private final class ClipsTestProtocol: URLProtocol {
    struct Seen { let method: String; let path: String; let body: [String: Any] }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [Seen] = []

    static func reset() { lock.lock(); defer { lock.unlock() }; seen = [] }
    static func requests() -> [Seen] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".clips-test.invalid") == true }
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
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"ok":true}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
