import Foundation
import RealtimeKit

/// SDK adapter for the retained session owner. It never logs participant
/// tokens and never enables capture as a side effect of reconnecting.
@MainActor
final class NativeMeetingTransport: HalqaSessionTransport {
    let client = NativeMeetingConfiguration.makeClient()
    private let info: RtkMeetingInfo
    var onEnded: (() -> Void)?
    private let events = NativeMeetingEvents()

    init(authToken: String) {
        info = NativeMeetingConfiguration.meetingInfo(authToken: authToken)
        events.ended = { [weak self] in self?.onEnded?() }
        client.addMeetingRoomEventListener(meetingRoomEventListener: events)
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
        client.release(onSuccess: { [weak self] in Task { @MainActor in
            if let self { self.client.removeMeetingRoomEventListener(meetingRoomEventListener: self.events) }
            completion(true)
        } },
                       onFailure: { _ in Task { @MainActor in completion(false) } })
    }
}

private final class NativeMeetingEvents: NSObject, RtkMeetingRoomEventListener {
    var ended: (@MainActor () -> Void)?
    func onMeetingEnded() { Task { @MainActor in ended?() } }
    func onMeetingRoomLeaveCompleted() { Task { @MainActor in ended?() } }
    func onMeetingInitStarted() {}
    func onMeetingInitCompleted(meeting: RealtimeKitClient) {}
    func onMeetingInitFailed(error: MeetingError) {}
    func onMeetingRoomJoinStarted() {}
    func onMeetingRoomJoinCompleted(meeting: RealtimeKitClient) {}
    func onMeetingRoomJoinFailed(error: MeetingError) {}
    func onMeetingRoomLeaveStarted() {}
    func onActiveTabUpdate(meeting: RealtimeKitClient, activeTab: ActiveTab) {}
    func onMediaConnectionUpdate(update: MediaConnectionUpdate) {}
    func onSocketConnectionUpdate(newState: SocketConnectionState) {}
}
