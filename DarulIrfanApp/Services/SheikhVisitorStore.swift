import Foundation
import Security

struct SheikhVisitorProfile: Codable, Sendable, Equatable {
    var name = ""
    var city = ""
    var countryCode = ""
    var email = ""
}

struct SheikhVisitorIdentity: Codable, Sendable {
    let guestSecret: String
    var profile: SheikhVisitorProfile
    /// Set only after server admission succeeds; a saved draft skips no form.
    var admitted = false
    var admittedMemberID: String? = nil
    var admittedAsGuest: Bool? = nil

    func canResume(as memberID: String?) -> Bool {
        guard admitted else { return false }
        if let memberID { return memberID == admittedMemberID }
        return admittedAsGuest == true
    }
}

/// Device-only Keychain item, separate from verified Apple member sessions.
/// Persistence errors are surfaced rather than silently replacing an identity.
enum SheikhVisitorStore {
    private static let signedOutKey = "sheikh.visitor.explicitlySignedOut"
    private static let lock = NSLock()
    private static var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "darulirfan.sheikh-visitor",
        kSecAttrAccount as String: "visitor"
    ] }

    static func loadOrCreate() throws -> SheikhVisitorIdentity {
        lock.lock(); defer { lock.unlock() }
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            var identity = try JSONDecoder().decode(SheikhVisitorIdentity.self, from: data)
            if UserDefaults.standard.bool(forKey: signedOutKey) { identity.admitted = false }
            return identity
        }
        guard status == errSecItemNotFound else { throw MemberGroupError.requestFailed }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw MemberGroupError.requestFailed }
        let identity = SheikhVisitorIdentity(guestSecret: bytes.map { String(format: "%02x", $0) }.joined(), profile: .init())
        try write(identity)
        return identity
    }

    static func save(_ identity: SheikhVisitorIdentity) throws {
        lock.lock(); defer { lock.unlock() }
        try write(identity)
        if identity.admitted { UserDefaults.standard.removeObject(forKey: signedOutKey) }
    }

    /// Update only the profile of an identity still present on this device.
    /// A disappearing form must neither resurrect a signed-out visitor nor
    /// overwrite admission metadata saved by a concurrent join.
    static func saveDraft(_ profile: SheikhVisitorProfile, matching secret: String) throws {
        lock.lock(); defer { lock.unlock() }
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return }
        guard status == errSecSuccess, let data = result as? Data else { throw MemberGroupError.requestFailed }
        var current = try JSONDecoder().decode(SheikhVisitorIdentity.self, from: data)
        guard current.guestSecret == secret, current.profile != profile else { return }
        current.profile = profile
        try write(current)
    }

    private static func write(_ identity: SheikhVisitorIdentity) throws {
        let data = try JSONEncoder().encode(identity)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw MemberGroupError.requestFailed }
        var entry = query
        attributes.forEach { entry[$0.key] = $0.value }
        guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw MemberGroupError.requestFailed }
    }

    static func delete() throws {
        lock.lock(); defer { lock.unlock() }
        // Persist the explicit sign-out even if Keychain is temporarily locked.
        UserDefaults.standard.set(true, forKey: signedOutKey)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw MemberGroupError.requestFailed }
    }
}
