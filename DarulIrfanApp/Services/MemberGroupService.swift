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
    private let decoder: JSONDecoder

    init(baseURL: URL = OfficialPlatformConfiguration.baseURL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
        let decoder = JSONDecoder()
        // The server writes JavaScript's toISOString(), which carries
        // milliseconds ("2026-10-27T10:15:00.000Z"). The stock .iso8601
        // strategy rejects fractional seconds, which made every post and
        // meeting fail to decode; both forms are accepted.
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = Self.fractional.date(from: text) ?? Self.whole.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unreadable date \(text)"))
        }
        self.decoder = decoder
    }

    private nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let whole: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    var isSignedIn: Bool { SecureMemberSession.load() != nil }
    var memberID: String? { SecureMemberSession.load()?.memberID }

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

    /// Forgets the session on this device without deleting the account.
    func signOut() {
        SecureMemberSession.delete()
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

    func createPost(in groupID: String, title: String, body: String?, videoID: String?, publish: Bool) async throws {
        var payload: [String: Any] = ["title": title, "kind": "announcement", "publish": publish]
        if let body, !body.isEmpty { payload["body"] = body }
        if let videoID { payload["youtubeVideoID"] = videoID }
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

    /// Starts a live zikr or meeting in the group. `videoID` streams it; `room`
    /// lets members join it together.
    func startLive(in groupID: String, kind: String, title: String, videoID: String?, room: Bool) async throws {
        var payload: [String: Any] = ["state": "live", "kind": kind, "title": title, "room": room]
        if let videoID { payload["videoID"] = videoID }
        try await send("POST", path: "v1/groups/\(groupID)/live", payload: payload, expecting: [200])
    }

    func endLive(in groupID: String) async throws {
        try await send("POST", path: "v1/groups/\(groupID)/live", payload: ["state": "offline"], expecting: [200])
    }

    func scheduleMeeting(in groupID: String, title: String, startsAt: Date, durationMinutes: Int) async throws {
        try await send("POST", path: "v1/groups/\(groupID)/meetings", payload: [
            "title": title, "startsAt": Self.whole.string(from: startsAt), "durationMinutes": durationMinutes,
        ], expecting: [201])
    }

    func cancelMeeting(_ meetingID: String, in groupID: String) async throws {
        try await send("DELETE", path: "v1/groups/\(groupID)/meetings/\(meetingID)", payload: nil, expecting: [204])
    }

    func saveZikrSession(_ session: ZikrSession, in groupID: String) async throws {
        var payload: [String: Any] = [
            "title": session.title, "weekdays": session.weekdays, "startHour": session.startHour,
            "startMinute": session.startMinute, "timeZoneIdentifier": session.timeZoneIdentifier,
            "durationMinutes": session.durationMinutes,
        ]
        if let anchor = session.anchor { payload["anchor"] = anchor }
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
