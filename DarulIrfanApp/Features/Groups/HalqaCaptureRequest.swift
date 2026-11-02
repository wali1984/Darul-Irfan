import Observation

enum HalqaCaptureKind { case microphone, camera }

/// Serializes one explicit microphone/camera request across the permission
/// dialog. A late permission answer must never enable capture after Leave.
@MainActor
@Observable
final class HalqaCaptureRequest {
    private(set) var pending = false
    private var closed = false
    private var generation = 0
    private var requestPending = false
    private var stopsPending = 0
    private func refreshPending() { pending = requestPending || stopsPending > 0 }

    func request(
        permission: (@escaping (Bool) -> Void) -> Void,
        allowedNow: @escaping () -> Bool,
        enable: @escaping (@escaping (Bool) -> Void) -> Void,
        disableLateCapture: @escaping (@escaping (Bool) -> Void) -> Void,
        completion: @escaping (Bool) -> Void
    ) {
        guard !closed, !pending, allowedNow() else { completion(false); return }
        requestPending = true
        refreshPending()
        generation &+= 1
        let ticket = generation
        permission { [self] granted in
            guard granted, !closed, ticket == generation, allowedNow() else {
                requestPending = false
                refreshPending()
                completion(false)
                return
            }
            enable { [self] success in
                // The SDK may finish after the app backgrounds or the host
                // revokes publishing permission. Recheck after enable too.
                if success && (closed || ticket != generation || !allowedNow()) {
                    disableLateCapture { [self] stopped in
                        if !stopped { closed = true }
                        requestPending = false
                        refreshPending()
                        completion(false)
                    }
                } else {
                    requestPending = false
                    refreshPending()
                    completion(success && !closed && ticket == generation)
                }
            }
        }
    }

    func stop(disable: (@escaping (Bool) -> Void) -> Void, completion: @escaping (Bool) -> Void) {
        cancel()
        stopsPending += 1
        refreshPending()
        disable { [self] success in
            stopsPending -= 1
            refreshPending()
            completion(success)
        }
    }

    func cancel() { generation &+= 1 }
    /// A new connection gets a new gate; a late callback cannot reopen this one.
    func close() { closed = true; cancel() }
}
