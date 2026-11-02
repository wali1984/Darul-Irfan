import RealtimeKit

/// SDK adapter for the retained session owner. It never logs participant
/// tokens and never enables capture as a side effect of reconnecting.
@MainActor
final class NativeMeetingTransport: HalqaSessionTransport {
    let client = NativeMeetingConfiguration.makeClient()
    private let info: RtkMeetingInfo

    init(authToken: String) {
        info = NativeMeetingConfiguration.meetingInfo(authToken: authToken)
    }

    func initialize(completion: @escaping (Bool) -> Void) {
        client.doInit(meetingInfo: info,
                      onSuccess: { Task { @MainActor in completion(true) } },
                      onFailure: { _ in Task { @MainActor in completion(false) } })
    }

    func join(completion: @escaping (Bool) -> Void) {
        client.joinRoom(onSuccess: { Task { @MainActor in completion(true) } },
                        onFailure: { _ in Task { @MainActor in completion(false) } })
    }

    func release(completion: @escaping (Bool) -> Void) {
        client.release(onSuccess: { Task { @MainActor in completion(true) } },
                       onFailure: { _ in Task { @MainActor in completion(false) } })
    }
}
