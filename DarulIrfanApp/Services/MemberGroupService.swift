import Foundation
import Security

enum MemberGroupError: LocalizedError {
    case signInRejected
    case notSignedIn
    case requestFailed
    case inviteRejected
    case tooManyAttempts

    var errorDescription: String? {
        switch self {
        case .signInRejected: "Your Apple sign-in could not be verified. Please try again."
        case .notSignedIn: "Enter your invitation code to see your group."
        case .requestFailed: "Your group could not be loaded. Check your connection and try again."
        // Deliberately one message for every refusal. The server does not say
        // whether a code was wrong, already used or expired, and neither does
        // this: anything finer would help someone guess at codes.
        case .inviteRejected: "That invitation code is not valid, or it has already been used. Please check it with the administrator who gave it to you."
        case .tooManyAttempts: "Too many attempts. Please wait a few minutes and try again."
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
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

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

    func groups() async throws -> [MemberGroup] {
        try await authorized(MemberGroupList.self, path: "v1/groups").groups
    }

    func posts(in groupID: String) async throws -> [MemberGroupPost] {
        // A group this member does not belong to answers exactly as a group that
        // does not exist, so nothing here can discover another region.
        try await authorized(MemberGroupPostList.self, path: "v1/groups/\(groupID)/posts").posts
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

    private func authorized<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        guard let saved = SecureMemberSession.load() else { throw MemberGroupError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
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
