import Observation

enum HalqaCaptureKind { case microphone, camera }

/// Serializes one explicit microphone/camera request across the permission
/// dialog. A late permission answer must never enable capture after Leave.
@MainActor
@Observable
final class HalqaCaptureRequest {
    private(set) var pending = false
    private var closed = false

    func request(
        permission: (@escaping (Bool) -> Void) -> Void,
        allowedNow: @escaping () -> Bool,
        enable: @escaping (@escaping (Bool) -> Void) -> Void,
        disableLateCapture: @escaping () -> Void,
        completion: @escaping (Bool) -> Void
    ) {
        guard !closed, !pending, allowedNow() else { completion(false); return }
        pending = true
        permission { [self] granted in
            guard granted, !closed, allowedNow() else {
                pending = false
                completion(false)
                return
            }
            enable { [self] success in
                pending = false
                if closed {
                    if success { disableLateCapture() }
                    completion(false)
                } else {
                    completion(success)
                }
            }
        }
    }

    /// Terminal for this connection, including failed release/retry. A new
    /// session gets new gates rather than reopening a stale permission request.
    func close() { closed = true }
}
