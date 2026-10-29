import Foundation
import Security

enum MemberGroupError: LocalizedError {
    case signInRejected
    case notSignedIn
    case requestFailed
    case inviteRejected
    case tooManyAttempts
    /// A refusal the server explained in words meant for the person.
    case server(String)

    var errorDescription: String? {
        switch self {
        case .signInRejected: String(localized: "Your Apple sign-in could not be verified. Please try again.")
        case .notSignedIn: String(localized: "Enter your invitation code to see your group.")
        case .requestFailed: String(localized: "Your group could not be loaded. Check your connection and try again.")
        // Deliberately one message for every refusal. The server does not say
        // whether a code was wrong, already used or expired, and neither does
        // this: anything finer would help someone guess at codes.
        case .inviteRejected: String(localized: "That invitation code is not valid, or it has already been used. Please check it with the administrator who gave it to you.")
        case .tooManyAttempts: String(localized: "Too many attempts. Please wait a few minutes and try again.")
        case .server(let message): message
        }
    }
}

/// Reads the private regional groups.
///
/// Signing in does not grant access to anything: the backend gives a new member
/// no groups until an admin adds them, so a member who has just signed in sees
/// an empty list rather than someone else's group. The member identifier is
/// shown to the member for exactly that reason — it is what an admin needs in
/// order to place them.
actor MemberGroupService {
    private let baseURL: URL
    private let session: URLSession
    /// Recordings can take minutes to send; everything else stays short.
    private let uploads: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL = OfficialPlatformConfiguration.baseURL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
        let uploading = URLSessionConfiguration.ephemeral
        uploading.timeoutIntervalForRequest = 60
        uploading.timeoutIntervalForResource = 3_600
        uploads = URLSession(configuration: uploading)
        // The server writes JavaScript's toISOString(), which carries
        // milliseconds ("2026-10-27T10:15:00.000Z"). The stock .iso8601
        // strategy rejects fractional seconds, which made every post and
        // meeting fail to decode; both forms are accepted (ServerDate).
        decoder = JSONDecoder.darulIrfanServer()
    }

    var isSignedIn: Bool { SecureMemberSession.load() != nil }
    var memberID: String? { SecureMemberSession.load()?.memberID }

    /// Whether a member is signed in on this phone. Static, so it is read
    /// without the actor (by the push registration).
    static var hasSavedSession: Bool { SecureMemberSession.load() != nil }

    /// Exchanges Apple's signed identity token for a session of our own.
    ///
    /// The token is verified by the backend against Apple's public keys; an
    /// identifier taken from the client would let anyone claim to be anyone.
    func signIn(identityToken: Data, displayName: String?) async throws -> String {
        guard let token = String(data: identityToken, encoding: .utf8) else { throw MemberGroupError.signInRejected }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/members/session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        var payload: [String: String] = ["identityToken": token]
        if let displayName, !displayName.isEmpty { payload["displayName"] = displayName }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 201,
              let value = try? decoder.decode(MemberSession.self, from: data) else {
            throw MemberGroupError.signInRejected
        }
        SecureMemberSession.save(value)
        return value.memberID
    }

    /// Redeems an administrator's invitation code.
    ///
    /// Unlike signing in, redeeming is admission: an administrator already
    /// decided it by issuing the code, so this both identifies the member and
    /// places them in the one group the code was minted for. Single-use, so a
    /// forwarded code cannot let a second person in.
    func redeemInvite(code: String, displayName: String?) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/members/invite"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        // Signed in already: the code is added to this same account. Without
        // the token the server cannot tell, and makes a new one-group account
        // that replaces this one on the phone.
        if let saved = SecureMemberSession.load() {
            request.setValue("Bearer \(saved.token)", forHTTPHeaderField: "authorization")
        }
        var payload: [String: String] = ["code": code]
        if let displayName, !displayName.isEmpty { payload["displayName"] = displayName }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 201, let value = try? decoder.decode(MemberSession.self, from: data) else {
            throw status == 429 ? MemberGroupError.tooManyAttempts : MemberGroupError.inviteRejected
        }
        SecureMemberSession.save(value)
        return value.memberID
    }

    /// Signs this phone out without deleting the account: the server ends
    /// this session and stops sending the member's Halqah notices here, so
    /// the next person to use the phone does not see them on the lock screen.
    /// The local session goes even when the server cannot be reached.
    func signOut() async {
        if SecureMemberSession.load() != nil {
            var payload: [String: Any] = [:]
            if let installation = SecureInstallationIdentity.load() { payload["installationID"] = installation.uuidString }
            _ = try? await send("POST", path: "v1/members/signout", payload: payload, expecting: [204])
        }
        SecureMemberSession.delete()
        HalqahNoticeChoice.isTurnedOff = false
    }

    /// The member's own name, as their Halqah's admins, the attendance and the
    /// meeting room show it.
    func rename(to displayName: String) async throws -> MemberProfile {
        let data = try await send("PUT", path: "v1/members/me", payload: ["displayName": displayName], expecting: [200])
        guard let profile = try? decoder.decode(MemberProfile.self, from: data) else { throw MemberGroupError.requestFailed }
        return profile
    }

    func groups() async throws -> MemberGroupList {
        try await authorized(MemberGroupList.self, path: "v1/groups")
    }

    func posts(in groupID: String, drafts: Bool = false) async throws -> [MemberGroupPost] {
        // A group this member does not belong to answers exactly as a group that
        // does not exist, so nothing here can discover another region.
        try await authorized(MemberGroupPostList.self, path: "v1/groups/\(groupID)/posts", query: drafts ? "drafts=1" : nil).posts
    }

    func detail(of groupID: String) async throws -> GroupDetail {
        try await authorized(GroupDetail.self, path: "v1/groups/\(groupID)")
    }

    func profile() async throws -> MemberProfile {
        try await authorized(MemberProfile.self, path: "v1/members/me")
    }

    // MARK: Group admin actions

    /// `media` are keys from `uploadPostMedia`, in the order they show.
    func createPost(in groupID: String, title: String, body: String?, videoID: String?, media: [String] = [], publish: Bool) async throws {
        var payload: [String: Any] = ["title": title, "kind": "announcement", "publish": publish]
        if let body, !body.isEmpty { payload["body"] = body }
        if let videoID { payload["youtubeVideoID"] = videoID }
        if !media.isEmpty { payload["media"] = media }
        try await send("POST", path: "v1/groups/\(groupID)/posts", payload: payload, expecting: [201])
    }

    func publishDraft(_ postID: String, in groupID: String, title: String, body: String?) async throws {
        var payload: [String: Any] = ["title": title]
        if let body { payload["body"] = body }
        try await send("POST", path: "v1/groups/\(groupID)/posts/\(postID)/publish", payload: payload, expecting: [200])
    }

    func removePost(_ postID: String, in groupID: String) async throws {
        try await send("DELETE", path: "v1/groups/\(groupID)/posts/\(postID)", payload: nil, expecting: [204])
    }

    /// Starts a live zikr or meeting in the group. `videoID` streams it (a
    /// past video plays as a recording); `room` lets members join it
    /// together; `queue` plays recordings and past zikr one after another.
    /// `record` records the room; the recording is kept in the group's
    /// recordings afterwards.
    func startLive(
        in groupID: String, kind: String, title: String, videoID: String?, room: Bool,
        queue: [GroupQueueEntry] = [], record: Bool = false
    ) async throws {
        var payload: [String: Any] = ["state": "live", "kind": kind, "title": title, "room": room, "record": record && room]
        if let videoID { payload["videoID"] = videoID }
        if !queue.isEmpty { payload["queue"] = queue.map(\.payload) }
        try await send("POST", path: "v1/groups/\(groupID)/live", payload: payload, expecting: [200])
    }

    /// A playback control applied for everyone: pause, resume, skip (by
    /// seconds), seek (to seconds), next, previous, jump (to index), add
    /// (items), remove (index) or notice (text).
    func control(_ action: String, _ extra: [String: Any] = [:], in groupID: String) async throws {
        var payload = extra
        payload["action"] = action
        try await send("POST", path: "v1/groups/\(groupID)/control", payload: payload, expecting: [200])
    }

    func addToSession(_ entries: [GroupQueueEntry], in groupID: String) async throws {
        try await control("add", ["items": entries.map(\.payload)], in: groupID)
    }

    /// Tells the group's admins this member has the session open.
    func checkIn(in groupID: String) async {
        _ = try? await send("POST", path: "v1/groups/\(groupID)/presence", payload: [:], expecting: [200])
    }

    func requestDua(_ text: String, showName: Bool, in groupID: String) async throws {
        try await send("POST", path: "v1/groups/\(groupID)/duas", payload: ["text": text, "showName": showName], expecting: [201])
    }

    func duaRequests(in groupID: String) async throws -> [GroupDuaRequest] {
        try await authorized(GroupDuaRequestList.self, path: "v1/groups/\(groupID)/duas").requests
    }

    func markDuaRead(_ duaID: String, in groupID: String) async throws {
        try await send("POST", path: "v1/groups/\(groupID)/duas/\(duaID)/read", payload: [:], expecting: [204])
    }

    func sessionHistory(in groupID: String) async throws -> GroupSessionHistory {
        try await authorized(GroupSessionHistory.self, path: "v1/groups/\(groupID)/history")
    }

    /// Removes a past session, with its attendance and dua requests (Super admin).
    func deleteSessionRecord(_ sessionID: String, in groupID: String) async throws {
        try await send("DELETE", path: "v1/groups/\(groupID)/history/\(sessionID)", payload: nil, expecting: [204])
    }

    func attendees(of sessionID: String, in groupID: String) async throws -> [GroupAttendee] {
        try await authorized(GroupSessionAttendees.self, path: "v1/groups/\(groupID)/history/\(sessionID)").attendees
    }

    func recordings(in groupID: String) async throws -> GroupRecordingLibrary {
        try await authorized(GroupRecordingLibrary.self, path: "v1/groups/\(groupID)/recordings")
    }

    /// Sends a recording file to the group. The file stays where it is; it is
    /// read as it is sent.
    func uploadRecording(
        from file: URL, contentType: String, title: String, durationSeconds: Int?, in groupID: String
    ) async throws {
        guard let saved = SecureMemberSession.load() else { throw MemberGroupError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/groups/\(groupID)/recordings"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "title", value: title)]
            + (durationSeconds.map { [URLQueryItem(name: "durationSeconds", value: String($0))] } ?? [])
        guard let url = components?.url else { throw MemberGroupError.requestFailed }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(saved.token)", forHTTPHeaderField: "authorization")
        request.setValue(contentType, forHTTPHeaderField: "content-type")
        let (data, response) = try await uploads.upload(for: request, fromFile: file)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 {
            SecureMemberSession.delete()
            throw MemberGroupError.notSignedIn
        }
        guard code == 201 else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw message.map(MemberGroupError.server) ?? MemberGroupError.requestFailed
        }
    }

    func deleteRecording(_ recordingID: String, in groupID: String) async throws {
        try await send("DELETE", path: "v1/groups/\(groupID)/recordings/\(recordingID)", payload: nil, expecting: [204])
    }

    func endLive(in groupID: String) async throws {
        try await send("POST", path: "v1/groups/\(groupID)/live", payload: ["state": "offline"], expecting: [200])
    }

    func scheduleMeeting(in groupID: String, title: String, startsAt: Date, durationMinutes: Int) async throws {
        try await send("POST", path: "v1/groups/\(groupID)/meetings", payload: [
            "title": title, "startsAt": ServerDate.string(from: startsAt), "durationMinutes": durationMinutes,
        ], expecting: [201])
    }

    func cancelMeeting(_ meetingID: String, in groupID: String) async throws {
        try await send("DELETE", path: "v1/groups/\(groupID)/meetings/\(meetingID)", payload: nil, expecting: [204])
    }

    /// `autoplay` is what a clock-time zikr plays by itself.
    func saveZikrSession(_ session: ZikrSession, autoplay: [GroupQueueEntry] = [], in groupID: String) async throws {
        var payload: [String: Any] = [
            "title": session.title, "weekdays": session.weekdays, "startHour": session.startHour,
            "startMinute": session.startMinute, "timeZoneIdentifier": session.timeZoneIdentifier,
            "durationMinutes": session.durationMinutes,
        ]
        if let anchor = session.anchor { payload["anchor"] = anchor }
        if !autoplay.isEmpty { payload["autoplay"] = autoplay.map(\.payload) }
        try await send("PUT", path: "v1/groups/\(groupID)/zikr/\(session.id)", payload: payload, expecting: [200])
    }

    func removeZikrSession(_ sessionID: String, in groupID: String) async throws {
        try await send("DELETE", path: "v1/groups/\(groupID)/zikr/\(sessionID)", payload: nil, expecting: [204])
    }

    // MARK: Group people (admins)

    func people(in groupID: String) async throws -> GroupPeople {
        try await authorized(GroupPeople.self, path: "v1/groups/\(groupID)/people")
    }

    /// Adds someone by email, or makes a single-use code to send to their
    /// phone (or to hand over) when there is no email.
    func addPerson(to groupID: String, email: String?, phone: String?, role: GroupRole, codeDays: Int) async throws -> AddPersonResult {
        var payload: [String: Any] = ["role": role.rawValue, "expiresInDays": codeDays]
        if let email { payload["email"] = email }
        if let phone { payload["phone"] = phone }
        let data = try await send("POST", path: "v1/groups/\(groupID)/people", payload: payload, expecting: [201])
        guard let result = try? decoder.decode(AddPersonResult.self, from: data) else { throw MemberGroupError.requestFailed }
        return result
    }

    /// The Super admin places someone from the directory.
    func place(_ memberID: String, in groupID: String, role: GroupRole) async throws {
        try await send("POST", path: "v1/groups/\(groupID)/people", payload: ["memberID": memberID, "role": role.rawValue], expecting: [201])
    }

    /// Sends one picture (as data) or video (as a file) for a post, and
    /// returns its key.
    func uploadPostMedia(picture: Data? = nil, video: URL? = nil, contentType: String, in groupID: String) async throws -> String {
        guard let saved = SecureMemberSession.load() else { throw MemberGroupError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/groups/\(groupID)/media"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(saved.token)", forHTTPHeaderField: "authorization")
        request.setValue(contentType, forHTTPHeaderField: "content-type")
        let result: (Data, URLResponse)
        if let video {
            result = try await uploads.upload(for: request, fromFile: video)
        } else {
            result = try await uploads.upload(for: request, from: picture ?? Data())
        }
        let (data, response) = result
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 {
            SecureMemberSession.delete()
            throw MemberGroupError.notSignedIn
        }
        let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard code == 201, let key = body?["key"] as? String else {
            throw (body?["error"] as? String).map(MemberGroupError.server) ?? MemberGroupError.requestFailed
        }
        return key
    }

    // MARK: Today's pictures

    /// What the Super admin published for a local day ("yyyy-MM-dd"). Public:
    /// no sign-in needed.
    func dailyMedia(day: String) async throws -> [DailyMediaItem] {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/daily-media"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "day", value: day)]
        guard let url = components?.url else { throw MemberGroupError.requestFailed }
        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let list = try? decoder.decode(DailyMediaList.self, from: data) else { throw MemberGroupError.requestFailed }
        return list.items
    }

    /// The Super admin's list: drafts, then what is published from a week ago.
    func manageDailyMedia() async throws -> [DailyMediaItem] {
        try await authorized(DailyMediaList.self, path: "v1/daily-media/manage").items
    }

    func uploadDailyMedia(
        _ picture: Data, contentType: String, slot: DailyMediaItem.Slot, day: String?, endDay: String?,
        caption: String?, popup: Bool, publish: Bool
    ) async throws {
        guard let saved = SecureMemberSession.load() else { throw MemberGroupError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/daily-media/manage"), resolvingAgainstBaseURL: false)
        var query = [URLQueryItem(name: "slot", value: slot.rawValue), URLQueryItem(name: "popup", value: popup ? "1" : "0"),
                     URLQueryItem(name: "publish", value: publish ? "1" : "0")]
        if let day { query.append(URLQueryItem(name: "day", value: day)) }
        if let endDay { query.append(URLQueryItem(name: "endDay", value: endDay)) }
        if let caption, !caption.isEmpty { query.append(URLQueryItem(name: "caption", value: caption)) }
        components?.queryItems = query
        guard let url = components?.url else { throw MemberGroupError.requestFailed }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(saved.token)", forHTTPHeaderField: "authorization")
        request.setValue(contentType, forHTTPHeaderField: "content-type")
        let (data, response) = try await uploads.upload(for: request, from: picture)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 {
            SecureMemberSession.delete()
            throw MemberGroupError.notSignedIn
        }
        guard code == 201 else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw message.map(MemberGroupError.server) ?? MemberGroupError.requestFailed
        }
    }

    /// Changes place, day, last day, caption, pop-up or status
    /// ("draft", "published", "hidden").
    func updateDailyMedia(_ id: String, _ fields: [String: Any]) async throws {
        try await send("PUT", path: "v1/daily-media/manage/\(id)", payload: fields, expecting: [200])
    }

    func deleteDailyMedia(_ id: String) async throws {
        try await send("DELETE", path: "v1/daily-media/manage/\(id)", payload: nil, expecting: [204])
    }

    // MARK: Halqahs (Super admin)

    func createHalqah(name: String, description: String?) async throws {
        var payload: [String: Any] = ["name": name]
        if let description, !description.isEmpty { payload["description"] = description }
        try await send("POST", path: "v1/groups", payload: payload, expecting: [201])
    }

    func updateHalqah(_ groupID: String, name: String, description: String?) async throws {
        try await send("PUT", path: "v1/groups/\(groupID)", payload: ["name": name, "description": description ?? ""], expecting: [200])
    }

    /// Hides the Halqah from everyone; its people and history are kept.
    func retireHalqah(_ groupID: String) async throws {
        try await send("DELETE", path: "v1/groups/\(groupID)", payload: nil, expecting: [204])
    }

    func directory() async throws -> [DirectoryPerson] {
        try await authorized(MemberDirectory.self, path: "v1/members").members
    }

    func setRole(_ role: GroupRole, of personID: String, in groupID: String) async throws {
        try await send("PUT", path: "v1/groups/\(groupID)/people/\(personID)", payload: ["role": role.rawValue], expecting: [200])
    }

    func remove(_ personID: String, from groupID: String) async throws {
        try await send("DELETE", path: "v1/groups/\(groupID)/people/\(personID)", payload: nil, expecting: [204])
    }

    func revokeInvitation(_ invitationID: String, in groupID: String) async throws {
        try await send("DELETE", path: "v1/groups/\(groupID)/invitations/\(invitationID)", payload: nil, expecting: [204])
    }

    /// A place in the group's live room, or in a scheduled meeting's.
    func join(groupID: String, meetingID: String?) async throws -> GroupRoomPass {
        var payload: [String: Any] = [:]
        if let meetingID { payload["meetingID"] = meetingID }
        let data = try await send("POST", path: "v1/groups/\(groupID)/join", payload: payload, expecting: [200])
        guard let pass = try? decoder.decode(GroupRoomPass.self, from: data) else { throw MemberGroupError.requestFailed }
        return pass
    }

    /// Links this phone's notification registration to the member, so a group's
    /// notices reach it. Harmless before notifications are turned on: there is
    /// simply nothing registered to send to yet.
    func linkNotifications(installationID: UUID) async {
        _ = try? await send("POST", path: "v1/members/devices", payload: ["installationID": installationID.uuidString], expecting: [204])
    }

    /// Stops the member's Halqah notices on this phone; the session stays.
    func unlinkNotifications(installationID: UUID) async throws {
        try await send("DELETE", path: "v1/members/devices/\(installationID.uuidString)", payload: nil, expecting: [204])
    }

    @discardableResult
    private func send(_ method: String, path: String, payload: [String: Any]?, expecting codes: Set<Int>) async throws -> Data {
        guard let saved = SecureMemberSession.load() else { throw MemberGroupError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(saved.token)", forHTTPHeaderField: "authorization")
        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 {
            SecureMemberSession.delete()
            throw MemberGroupError.notSignedIn
        }
        guard codes.contains(code) else {
            // The server's own plain message ("The meeting room opens ten
            // minutes before it starts.") is what the person should read.
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw message.map(MemberGroupError.server) ?? MemberGroupError.requestFailed
        }
        return data
    }

    /// Deletes the account, its sessions and its group memberships.
    ///
    /// Apple requires an account created in an app to be deletable from inside
    /// it. Published posts belong to the organisation, so nothing the silsila
    /// published is lost.
    func deleteAccount() async throws {
        guard let saved = SecureMemberSession.load() else { throw MemberGroupError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/members/me"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(saved.token)", forHTTPHeaderField: "authorization")
        let (_, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 401 means the session is already gone server-side; the local copy
        // should still go, so the member is not left signed in to nothing.
        guard code == 204 || code == 401 else { throw MemberGroupError.requestFailed }
        SecureMemberSession.delete()
        HalqahNoticeChoice.isTurnedOff = false
    }

    private func authorized<T: Decodable>(_ type: T.Type, path: String, query: String? = nil) async throws -> T {
        guard let saved = SecureMemberSession.load() else { throw MemberGroupError.notSignedIn }
        var url = baseURL.appendingPathComponent(path)
        if let query, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.percentEncodedQuery = query
            url = components.url ?? url
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(saved.token)", forHTTPHeaderField: "authorization")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 {
            // The session expired or was revoked; drop it so the UI asks for a
            // fresh sign-in instead of retrying a token that will never work.
            SecureMemberSession.delete()
            throw MemberGroupError.notSignedIn
        }
        guard code == 200, let value = try? decoder.decode(type, from: data) else {
            throw MemberGroupError.requestFailed
        }
        return value
    }
}

/// Whether this phone shows its member's Halqah notices: posts, sessions and
/// notices of their Halqahs. On once a member is signed in here, unless they
/// turned it off on the Halqah page. While it is wanted, the phone stays
/// registered for notifications even with official alerts off, since a group
/// notice can only reach a registered phone.
enum HalqahNoticeChoice {
    private static let offKey = "halqah.notices.turnedOff"

    static var isTurnedOff: Bool {
        get { UserDefaults.standard.bool(forKey: offKey) }
        set { UserDefaults.standard.set(newValue, forKey: offKey) }
    }

    static var isWanted: Bool { MemberGroupService.hasSavedSession && !isTurnedOff }
}

/// The member's bearer token, kept in the keychain rather than user defaults:
/// it is a credential, and it stays on this device only.
private enum SecureMemberSession {
    private static let service = "us.naqshbaniaowaisiah.member"
    private static let account = "member-session"

    static func save(_ session: MemberSession) {
        delete()
        // The matching read decodes ISO-8601, so the write has to produce it:
        // the default strategy writes a number and the session would never be
        // readable again.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> MemberSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let session = try? decoder.decode(MemberSession.self, from: data) else { return nil }
        // An expired token is treated as absent so the UI offers sign-in rather
        // than failing every request.
        return session.expiresAt > Date() ? session : nil
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
