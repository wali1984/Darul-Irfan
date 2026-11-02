import RealtimeKit

/// App-owned session: navigation and scene backgrounding do not release it.
/// The native room presenter must use this owner instead of creating a client.
@MainActor
final class NativeHalqaSession {
    static let shared = NativeHalqaSession()
    let lifecycle = HalqaSessionLifecycle()
    private init() {}

    var client: RealtimeKitClient? {
        (lifecycle.transport as? NativeMeetingTransport)?.client
    }

    var chat: NativeMeetingChat? {
        (lifecycle.transport as? NativeMeetingTransport)?.chat
    }

    @discardableResult
    func join(sessionID: String, pass: GroupRoomPass) -> Bool {
        lifecycle.start(sessionID: sessionID) {
            NativeMeetingTransport(authToken: pass.authToken)
        }
    }

    func leave() { lifecycle.leave() }
}
