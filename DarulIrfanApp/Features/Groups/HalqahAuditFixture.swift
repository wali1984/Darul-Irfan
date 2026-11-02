#if DEBUG
import SwiftUI
import Foundation

/// Exercises the real detail screen without a Keychain session or live group requests.
struct HalqahAuditFixture: View {
    private let service: MemberGroupService
    private let sheikhAudit = ProcessInfo.processInfo.arguments.contains("--uitesting-sheikh-stage")
    private let historyAudit = ProcessInfo.processInfo.arguments.contains("--uitesting-halqah-history")
    @State private var releasedOldRefresh = false
    private let raceAudit = ProcessInfo.processInfo.arguments.contains("--uitesting-dua-race")
    private let duaAudit = ProcessInfo.processInfo.arguments.contains("--uitesting-halqah-duas")

    init() {
        if ProcessInfo.processInfo.arguments.contains("--uitesting-sheikh-stage") {
            UserDefaults.standard.removePersistentDomain(forName: "sheikh-stage-audit")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HalqahAuditProtocol.self]
        service = MemberGroupService(
            baseURL: URL(string: "https://halqah-audit.invalid")!,
            session: URLSession(configuration: configuration),
            savedSession: HalqahAuditSession())
    }

    var body: some View {
        NavigationStack {
            if ProcessInfo.processInfo.arguments.contains("--uitesting-recording-library") {
                GroupLiveStarter(groupID: "admin", service: service, meetingsReady: false)
            } else if ProcessInfo.processInfo.arguments.contains("--uitesting-directory-detail") {
                DirectoryPersonView(person: DirectoryPerson(
                    id: "audit-person", name: "Audit member", email: nil, lastSeenAt: nil,
                    isSuperAdmin: false, isYou: false,
                    halqahs: [.init(groupID: "admin", groupName: "Before refresh", role: .member)]),
                    service: service, halqahs: [], onChange: {})
            } else if ProcessInfo.processInfo.arguments.contains("--uitesting-picture-refresh") {
                DailyPictureRefreshAudit()
            } else {
            List(duaAudit ? ["admin"] : ["member", "admin"], id: \.self) { role in
                NavigationLink {
                    if sheikhAudit {
                        ScrollView { SheikhZikrPanel(groupID: role, service: service, isLiveZikr: true, pendingStore: UserDefaults(suiteName: "sheikh-stage-audit")!).padding(DISpacing.md) }
                            .diScreenBackground().navigationTitle("Our Sheikh")
                    } else if duaAudit {
                        GroupDuaRequestsView(groupID: role, service: service)
                            .safeAreaInset(edge: .bottom) {
                                if raceAudit {
                                    Button(releasedOldRefresh ? "Older response released" : "Release older refresh") {
                                        releasedOldRefresh = HalqahAuditProtocol.releaseOlderRefresh()
                                    }.accessibilityIdentifier("release-older-refresh")
                                }
                            }
                    } else if historyAudit {
                        GroupSessionHistoryView(groupID: role, service: service)
                    } else {
                    GroupDetailView(group: MemberGroup(
                        id: role, name: "Audit Halqah", description: nil,
                        meetingURL: nil, meetingNote: nil,
                        canManage: role == "admin", myRole: role == "admin" ? .admin : .member),
                        service: service, dependencies: nil)
                    }
                } label: { Text(verbatim: role) }
                .accessibilityIdentifier("halqah-audit-" + role)
            }
            .navigationTitle("Halqah audit")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if ProcessInfo.processInfo.arguments.contains("--uitesting-recording-library") {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Text(verbatim: String(HalqahAuditProtocol.recordingRemovalRequests))
                        .accessibilityIdentifier("recording-removal-requests")
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--uitesting-directory-detail") {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Text(verbatim: String(HalqahAuditProtocol.directoryRemovalRequests))
                        .accessibilityIdentifier("directory-removal-requests")
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--uitesting-halqah-schedule-removal") {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Text(verbatim: String(HalqahAuditProtocol.scheduleRemovalRequests))
                        .accessibilityIdentifier("audit-schedule-removal-requests")
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--uitesting-halqah-post-removal") {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Text(verbatim: String(HalqahAuditProtocol.removalRequests))
                        .accessibilityIdentifier("audit-removal-requests")
                }
            }
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
    private static var historyAttempts: [String: Int] = [:]
    private static var deleted: Set<String> = []
    private static var failedAfterDelete: Set<String> = []
    private static var stageAttempts = 0
    private static var firstStageID: String?
    private static var customStages: [[String: Any]] = []
    private static var stageCues: [[String: Any]] = []
    private static var duaReads = 0
    private static var duaWrites = 0
    private static var duaMarkedRead = false
    private static var olderRefresh: (() -> Void)?
    private static var scheduleAttempts: [String: Int] = [:]
    static var scheduleRemovalRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return scheduleAttempts.values.reduce(0, +)
    }
    private static var postRemovalAttempts = 0
    private static var directoryReads = 0
    private static var directoryRemovals = 0
    private static var recordingReads = 0
    private static var recordingRemovals = 0
    static var recordingRemovalRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordingRemovals
    }
    static var directoryRemovalRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return directoryRemovals
    }
    static var removalRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return postRemovalAttempts
    }

    static func releaseOlderRefresh() -> Bool {
        lock.lock()
        let pending = olderRefresh
        olderRefresh = nil
        lock.unlock()
        pending?()
        return pending != nil
    }

    // This session never falls through to the network, including unexpected requests.
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, url.host == "halqah-audit.invalid" else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let parts = url.pathComponents
        if ProcessInfo.processInfo.arguments.contains("--uitesting-recording-library") {
            Self.lock.lock()
            let result: (Int, String)
            if url.path == "/v1/groups/admin/recordings", request.httpMethod == "GET" {
                Self.recordingReads += 1
                if Self.recordingReads == 2 {
                    result = (503, "{}")
                } else {
                    let ids = Self.recordingRemovals >= 2 ? ["keep"] : ["remove", "keep"]
                    let recordings: [[String: Any]] = ids.map { id in
                        ["id": id, "title": "Audit recording " + id, "contentType": "audio/mpeg",
                         "byteSize": 1024, "durationSeconds": 60, "createdAt": "2026-11-01T12:00:00Z"]
                    }
                    let body: [String: Any] = ["recordings": recordings, "pastVideos": [], "maxUploadBytes": 99614720]
                    let data = try! JSONSerialization.data(withJSONObject: body)
                    result = (200, String(decoding: data, as: UTF8.self))
                }
            } else if url.path == "/v1/groups/admin/recordings/remove", request.httpMethod == "DELETE" {
                Self.recordingRemovals += 1
                result = (Self.recordingRemovals == 1 ? 503 : 204, "{}")
            } else {
                result = (403, "{}")
            }
            Self.lock.unlock()
            respond(result.0, result.1)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--uitesting-directory-detail") {
            Self.lock.lock()
            let result: (Int, String)
            if url.path == "/v1/members", request.httpMethod == "GET" {
                Self.directoryReads += 1
                result = Self.directoryReads == 1 ? (503, "{}") : (200,
                    "{\"members\":[{\"id\":\"audit-person\",\"name\":\"Audit member\",\"isSuperAdmin\":false,\"isYou\":false,\"halqahs\":[{\"groupID\":\"admin\",\"groupName\":\"After refresh\",\"role\":\"admin\"}]}]}")
            } else if url.path == "/v1/groups/admin/people/audit-person", request.httpMethod == "DELETE" {
                Self.directoryRemovals += 1
                result = (Self.directoryRemovals == 1 ? 503 : 204, "{}")
            } else {
                result = (403, "{}")
            }
            Self.lock.unlock()
            respond(result.0, result.1)
            return
        }
        guard parts.count >= 4, parts[1] == "v1", parts[2] == "groups",
              ["member", "admin"].contains(parts[3]) else {
            respond(404, "{}")
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--uitesting-sheikh-stage"),
           parts.count == 5, ["zikr-stages", "zikr-cues"].contains(parts[4]) {
            let result = stageResponse(parts: parts)
            respond(result.0, result.1)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--uitesting-halqah-duas"),
           parts.count >= 5, parts[4] == "duas" {
            let result = duaResponse(parts: parts)
            if result.0 == 299 {
                Self.lock.lock()
                Self.olderRefresh = { [weak self] in self?.respond(200, result.1) }
                Self.lock.unlock()
            } else {
                respond(result.0, result.1)
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--uitesting-halqah-history"),
           parts.count >= 5, parts[4] == "history" {
            let result = historyResponse(parts: parts)
            respond(result.0, result.1)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--uitesting-halqah-post-removal"),
           parts.count >= 5, parts[4] == "posts" {
            Self.lock.lock()
            let result: (Int, String)
            if request.httpMethod == "DELETE", parts.count == 6, parts[3] == "admin" {
                Self.postRemovalAttempts += 1
                result = (Self.postRemovalAttempts == 1 ? 503 : 204, "{}")
            } else if request.httpMethod == "GET" {
                let empty = url.query?.contains("draft") == true || Self.postRemovalAttempts >= 2
                let post = "{\"id\":\"audit-post\",\"kind\":\"announcement\",\"title\":\"Audit announcement\",\"publishedAt\":\"2026-11-01T12:00:00Z\"}"
                result = (200, "{\"groupID\":\"\(parts[3])\",\"posts\":[\(empty ? "" : post)]}")
            } else {
                result = (403, "{}")
            }
            Self.lock.unlock()
            respond(result.0, result.1)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--uitesting-halqah-schedule-removal"),
           parts.count == 6, ["meetings", "zikr"].contains(parts[4]), request.httpMethod == "DELETE" {
            guard parts[3] == "admin" else { respond(403, "{}"); return }
            Self.lock.lock()
            let attempts = (Self.scheduleAttempts[parts[4]] ?? 0) + 1
            Self.scheduleAttempts[parts[4]] = attempts
            Self.lock.unlock()
            respond(attempts == 1 ? 503 : 204, "{}")
            return
        }
        guard request.httpMethod == "GET" else { respond(403, "{}"); return }
        if ProcessInfo.processInfo.arguments.contains("--uitesting-halqah-schedule-removal"), parts.count == 4 {
            Self.lock.lock()
            let meetingGone = (Self.scheduleAttempts["meetings"] ?? 0) >= 2
            let zikrGone = (Self.scheduleAttempts["zikr"] ?? 0) >= 2
            Self.lock.unlock()
            let meeting: [String: Any] = ["id": "audit-meeting", "title": "Audit meeting",
                "startsAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400)), "durationMinutes": 60]
            let zikr: [String: Any] = ["id": "audit-zikr", "title": "Audit recurring Zikr",
                "weekdays": [1, 2, 3, 4, 5, 6, 7], "startHour": 20, "startMinute": 0,
                "durationMinutes": 30, "timeZoneIdentifier": "Asia/Karachi"]
            let body: [String: Any] = ["group": ["id": parts[3], "name": "Audit Halqah"],
                "canManage": parts[3] == "admin", "memberCount": 3,
                "meetings": meetingGone ? [] : [meeting], "zikrSessions": zikrGone ? [] : [zikr]]
            let data = try! JSONSerialization.data(withJSONObject: body)
            respond(200, String(decoding: data, as: UTF8.self))
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
    private func stageResponse(parts: [String]) -> (Int, String) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let admin = parts[3] == "admin"
        let stages = PersonalZikrStage.allCases.map { stage -> [String: Any] in
            let id = stage.rawValue.hasPrefix("latifa") ? stage.rawValue.replacingOccurrences(of: "latifa", with: "latifa-") : stage.rawValue
            return ["id": id, "title": stage.title, "titleUr": String(localized: String.LocalizationValue(stage.title)), "isCustom": false]
        } + Self.customStages
        func answer(_ code: Int, _ body: [String: Any]) -> (Int, String) {
            guard let data = try? JSONSerialization.data(withJSONObject: body), let text = String(data: data, encoding: .utf8) else { return (500, "{}") }
            return (code, text)
        }
        if request.httpMethod == "GET" {
            return parts[4] == "zikr-stages" ? answer(200, ["canBroadcast": admin, "stages": stages]) : answer(200, ["cues": Self.stageCues, "nextSequence": Self.stageCues.count])
        }
        guard admin, request.httpMethod == "POST" else { return (403, "{}") }
        let data: Data
        if let body = request.httpBody { data = body }
        else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var content = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; content.append(buffer, count: count) }
            data = content
        } else { return (400, "{}") }
        guard var input = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let id = input["id"] as? String else { return (400, "{}") }
        if parts[4] == "zikr-stages" {
            if let existing = Self.customStages.first(where: { $0["id"] as? String == id }) { return answer(200, existing) }
            input["isCustom"] = true; Self.customStages.append(input)
            // The write committed but its response was lost. A retry with the
            // original ID or a subsequent refresh must confirm one stage only.
            return (503, "{}")
        }
        Self.stageAttempts += 1
        if Self.stageAttempts == 1 { Self.firstStageID = id; return (503, "{}") }
        if Self.stageAttempts == 2 && Self.firstStageID != id { return (409, "{}") }
        if let existing = Self.stageCues.first(where: { $0["id"] as? String == id }) { return answer(200, ["cue": existing]) }
        guard let stage = stages.first(where: { $0["id"] as? String == input["stageID"] as? String }) else { return (404, "{}") }
        let cue: [String: Any] = ["id": id, "stageID": input["stageID"]!, "sequence": Self.stageCues.count + 1,
            "title": stage["title"]!, "titleUr": stage["titleUr"] ?? stage["title"]!, "authorID": "audit", "createdAt": "2026-11-01T12:00:00Z", "notificationState": "complete"]
        Self.stageCues.append(cue)
        return answer(201, ["cue": cue])
    }

    private func duaResponse(parts: [String]) -> (Int, String) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard parts[3] == "admin" else { return (403, "{}") }
        if request.httpMethod == "POST", parts.count == 7,
           parts[5] == "dua-unread", parts[6] == "read" {
            Self.duaWrites += 1
            if Self.duaWrites == 1 { return (503, "{}") }
            if ProcessInfo.processInfo.arguments.contains("--uitesting-dua-race"), Self.olderRefresh == nil {
                return (409, "{}") // The test must actually start the older GET before confirming the write.
            }
            Self.duaMarkedRead = true
            return (204, "{}")
        }
        guard request.httpMethod == "GET", parts.count == 5 else { return (403, "{}") }
        Self.duaReads += 1
        let race = ProcessInfo.processInfo.arguments.contains("--uitesting-dua-race")
        if (race ? [1] : [1, 3, 5]).contains(Self.duaReads) { return (503, "{}") }
        let records: [[String: Any]] = [
            ["id": "dua-unread", "text": "Audit dua request", "createdAt": "2026-10-30T12:00:00Z", "isRead": Self.duaMarkedRead],
            ["id": "dua-read", "text": "Audit previously read request", "createdAt": "2026-10-29T12:00:00Z", "isRead": true, "name": "Audit member"]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: ["requests": records]),
              let json = String(data: data, encoding: .utf8) else { return (500, "{}") }
        return (race && Self.duaReads == 3 ? 299 : 200, json)
    }
    private func historyResponse(parts: [String]) -> (Int, String) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let role = parts[3]
        let method = request.httpMethod ?? "GET"
        let key = method + parts.joined(separator: "/")
        Self.historyAttempts[key, default: 0] += 1
        let attempt = Self.historyAttempts[key]!
        if method == "DELETE" {
            guard role == "admin", parts.count == 6 else { return (403, "{}") }
            if attempt == 1 { return (503, "{}") }
            Self.deleted.insert(parts[5])
            return (204, "{}")
        }
        guard method == "GET" else { return (403, "{}") }
        if attempt == 1 { return (503, "{}") }
        let body: [String: Any]
        if parts.count == 5 {
            if !Self.deleted.isEmpty, Self.failedAfterDelete.insert(role).inserted {
                return (503, "{}")
            }
            let records: [[String: Any]] = (1...9).compactMap { number in
                let id = "history-\(number)"
                guard !Self.deleted.contains(id) else { return nil }
                return ["id": id, "kind": "zikr", "title": "Audit session \(number)",
                        "startedAt": "2026-10-30T12:00:00Z", "endedAt": "2026-10-30T12:30:00Z", "attendees": 2]
            }
            body = ["sessions": records, "canDelete": role == "admin"]
        } else {
            body = ["attendees": (1...2).map { number in
                ["name": "Audit attendee \(number)", "firstSeenAt": "2026-10-30T12:01:00Z", "lastSeenAt": "2026-10-30T12:29:00Z"]
            }]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8) else { return (500, "{}") }
        return (200, json)
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
