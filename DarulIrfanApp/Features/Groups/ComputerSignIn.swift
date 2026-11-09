import Foundation

// "Approve a computer": the Darul Irfan desktop app (Windows, macOS) shows a
// code and its QR; the member types the code here, or scans the QR with the
// phone's camera (it opens darulirfan://approve-computer?code=...), checks
// which computer is asking, and approves it. The computer is then signed in
// as this member, with the same role, for 30 days after it was last used.
// Server contract: Server/src/computerLinks.ts.

/// The code a computer shows: eight letters and digits, "K7Q2-9MXD".
enum ComputerLinkCode {
    /// Letters and digits only, in capitals, eight at most - however it was typed.
    static func letters(of text: String) -> String {
        String(text.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(8))
    }

    /// The code as the computer shows it, the dash put in.
    static func shown(_ text: String) -> String {
        let value = letters(of: text)
        guard value.count > 4 else { return value }
        return String(value.prefix(4)) + "-" + String(value.dropFirst(4))
    }

    /// The code in what the camera or the clipboard gave: the QR's link
    /// ("darulirfan://approve-computer?code=K7Q2-9MXD") or the code itself.
    /// Nil unless it holds a whole code.
    static func code(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("?") {
            let query = trimmed.split(separator: "?", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
            return code(inQuery: query)
        }
        let value = letters(of: trimmed)
        return value.count == 8 && trimmed.count <= 12 ? shown(value) : nil
    }

    /// The `code` of a link's query ("code=K7Q2-9MXD&..."), when it is a whole code.
    /// Read by hand: URLComponents traps on a query that is not properly
    /// percent-encoded, and this one comes from whatever QR was scanned.
    static func code(inQuery query: String) -> String? {
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].lowercased() == "code" else { continue }
            let value = letters(of: parts[1].removingPercentEncoding ?? parts[1])
            return value.count == 8 ? shown(value) : nil
        }
        return nil
    }
}

/// Which computer is asking, shown before the member approves it.
struct ComputerLinkPreview: Decodable, Sendable, Equatable, Identifiable {
    var deviceName: String
    var platform: String
    var expiresAt: Date?

    var id: String { deviceName + "|" + platform }

    enum CodingKeys: String, CodingKey { case deviceName, platform, expiresAt }

    init(deviceName: String, platform: String, expiresAt: Date? = nil) {
        self.deviceName = deviceName
        self.platform = platform
        self.expiresAt = expiresAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceName = c.markazString(.deviceName) ?? ""
        platform = c.markazString(.platform) ?? ""
        expiresAt = c.markazDate(.expiresAt)
    }
}

/// A computer signed in to the member's account through the desktop app.
struct SignedInComputer: Decodable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String?
    var platform: String
    var createdAt: Date?
    var lastSeenAt: Date?
    var expiresAt: Date?
    /// The computer this request came from; never true from the phone.
    var current: Bool

    enum CodingKeys: String, CodingKey { case id, name, platform, createdAt, lastSeenAt, expiresAt, current }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.markazString(.id) ?? ""
        name = c.markazString(.name)
        platform = c.markazString(.platform) ?? ""
        createdAt = c.markazDate(.createdAt)
        lastSeenAt = c.markazDate(.lastSeenAt)
        expiresAt = c.markazDate(.expiresAt)
        current = c.markazBool(.current) ?? false
    }
}

struct SignedInComputerList: Decodable, Sendable {
    var computers: [SignedInComputer]

    enum CodingKeys: String, CodingKey { case computers }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        computers = c.markazList(SignedInComputer.self, .computers).filter { !$0.id.isEmpty }
    }
}

/// The computer's platform as people name it, and its symbol.
enum ComputerPlatform {
    static func name(_ platform: String) -> String {
        switch platform.lowercased() {
        case "macos": return "macOS"
        case "windows": return "Windows"
        default: return platform
        }
    }

    static func symbol(_ platform: String) -> String {
        platform.lowercased() == "macos" ? "laptopcomputer" : "desktopcomputer"
    }
}

/// The routes, over the member's own session on this phone.
struct ComputerSignInService: Sendable {
    let groups: MemberGroupService

    /// Which computer shows `code`; nothing is approved yet.
    func preview(code: String) async throws -> ComputerLinkPreview {
        let data = try await groups.markaz("POST", path: "v1/members/computer-link/preview", payload: ["code": code], expecting: [200])
        return try decode(ComputerLinkPreview.self, data)
    }

    /// Lets the computer showing `code` in, signed in as this member.
    @discardableResult
    func approve(code: String) async throws -> ComputerLinkPreview {
        let data = try await groups.markaz("POST", path: "v1/members/computer-link/approve", payload: ["code": code], expecting: [200])
        return (try? decode(ComputerLinkPreview.self, data)) ?? ComputerLinkPreview(deviceName: "", platform: "")
    }

    func computers() async throws -> [SignedInComputer] {
        let data = try await groups.markaz("GET", path: "v1/members/computers")
        return try decode(SignedInComputerList.self, data).computers
    }

    func signOut(_ computerID: String) async throws {
        _ = try await groups.markaz("DELETE", path: "v1/members/computers/\(computerID)", expecting: [200, 204])
    }

    func signOutAll() async throws {
        _ = try await groups.markaz("DELETE", path: "v1/members/computers", expecting: [200, 204])
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder.darulIrfanServer().decode(type, from: data) }
        catch { throw MemberGroupError.requestFailed }
    }

    /// What to tell the member when a code was refused. The server says the
    /// same for a wrong, used or expired code, and so does this.
    static func failureText(for error: Error) -> String {
        if let groupError = error as? MemberGroupError {
            switch groupError {
            case .notSignedIn:
                return String(localized: "Sign in on this phone first, then approve the computer from here.")
            case .tooManyAttempts:
                return groupError.localizedDescription
            case .server(let message) where message == "Too many requests":
                return MemberGroupError.tooManyAttempts.localizedDescription
            case .server:
                return String(localized: "That code was not accepted. It may have expired: get a new code on the computer and try again.")
            default:
                break
            }
        }
        return MemberGroupError.actionDescription(for: error)
    }
}
