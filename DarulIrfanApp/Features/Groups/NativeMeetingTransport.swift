import Foundation
import RealtimeKit

/// SDK adapter for the retained session owner. It never logs participant
/// tokens and never enables capture as a side effect of reconnecting.
@MainActor
final class NativeMeetingTransport: HalqaSessionTransport {
    let client = NativeMeetingConfiguration.makeClient()
    private(set) lazy var chat = NativeMeetingChat(client: client)
    private(set) lazy var participants = NativeMeetingParticipants(client: client)
    let microphoneRequest = HalqaCaptureRequest()
    let cameraRequest = HalqaCaptureRequest()
    private var joined = false
    private let info: RtkMeetingInfo
    var onEnded: (() -> Void)?
    var onConnectionChanged: ((HalqaConnectionStatus) -> Void)?
    private let events = NativeMeetingEvents()
    private let membershipEvents = NativeMeetingMembershipEvents()

    init(authToken: String) {
        info = NativeMeetingConfiguration.meetingInfo(authToken: authToken)
        events.ended = { [weak self] in self?.onEnded?() }
        events.connectionChanged = { [weak self] status in self?.onConnectionChanged?(status) }
        membershipEvents.ended = { [weak self] in self?.onEnded?() }
        client.addMeetingRoomEventListener(meetingRoomEventListener: events)
        client.addSelfEventListener(selfEventListener: membershipEvents)
    }

    func initialize(completion: @escaping (Bool) -> Void) {
        client.doInit(meetingInfo: info,
                      onSuccess: { Task { @MainActor in completion(true) } },
                      onFailure: { _ in Task { @MainActor in completion(false) } })
    }

    func join(completion: @escaping (Bool) -> Void) {
        _ = chat // Attach before joining so initial history is observed.
        _ = participants
        client.joinRoom(onSuccess: { [weak self] in Task { @MainActor in
            self?.joined = true
            self?.chat.joined()
            self?.participants.refresh()
            completion(true)
        } },
                        onFailure: { _ in Task { @MainActor in completion(false) } })
    }

    func release(completion: @escaping (Bool) -> Void) {
        joined = false
        microphoneRequest.close()
        cameraRequest.close()
        chat.leaving()
        participants.leaving()
        client.release(onSuccess: { [weak self] in Task { @MainActor in
            if let self {
                self.chat.released()
                self.participants.released()
                self.client.removeMeetingRoomEventListener(meetingRoomEventListener: self.events)
                self.client.removeSelfEventListener(selfEventListener: self.membershipEvents)
            }
            completion(true)
        } },
                       onFailure: { _ in Task { @MainActor in completion(false) } })
    }

    /// Presenter supplies an explicit permission request and foreground check.
    /// This is never invoked by join, reconnect or a background transition.
    func requestCapture(_ kind: HalqaCaptureKind,
                        permission: (@escaping (Bool) -> Void) -> Void,
                        foreground: @escaping () -> Bool,
                        completion: @escaping (Bool) -> Void) {
        let gate = kind == .microphone ? microphoneRequest : cameraRequest
        gate.request(permission: permission, allowedNow: { [self] in
            guard joined, foreground() else { return false }
            let media = client.localUser.permissions.media
            return kind == .microphone ? media.canPublishAudio : media.canPublishVideo
        }, enable: { [self] done in
            if kind == .microphone {
                client.localUser.enableAudio { error in Task { @MainActor in done(error == nil) } }
            } else {
                client.localUser.enableVideo { error in Task { @MainActor in done(error == nil) } }
            }
        }, disableLateCapture: { [self] done in
            disableCapture(kind) { [self] stopped in
                if !stopped { onEnded?() }
                done(stopped)
            }
        }, completion: completion)
    }

    /// Mute/camera-off never needs a permission prompt. Cancel any pending
    /// enable first, so granting an older prompt cannot undo this action.
    func stopCapture(_ kind: HalqaCaptureKind, completion: @escaping (Bool) -> Void) {
        let gate = kind == .microphone ? microphoneRequest : cameraRequest
        guard joined else { gate.cancel(); completion(false); return }
        gate.stop(disable: { [self] done in disableCapture(kind, completion: done) }, completion: completion)
    }

    private func disableCapture(_ kind: HalqaCaptureKind, completion: @escaping (Bool) -> Void) {
        if kind == .microphone {
            client.localUser.disableAudio { error in Task { @MainActor in completion(error == nil) } }
        } else {
            client.localUser.disableVideo { error in Task { @MainActor in completion(error == nil) } }
        }
    }
}

/// A host removal/rejection is terminal, unlike a temporary network loss.
final class NativeMeetingMembershipEvents: NSObject, RtkSelfEventListener {
    var ended: (@MainActor () -> Void)?
    func onRemovedFromMeeting() { Task { @MainActor in ended?() } }
    func onWaitListStatusUpdate(waitListStatus: RealtimeKit.WaitListStatus) {
        if waitListStatus == .rejected { Task { @MainActor in ended?() } }
    }
    func onAudioDeviceChanged(audioDevice: AudioDevice) {}
    func onAudioDevicesUpdated(devices: [AudioDevice]) {}
    func onAudioUpdate(isEnabled: Bool) {}
    func onMeetingRoomJoinedWithoutCameraPermission() {}
    func onMeetingRoomJoinedWithoutMicPermission() {}
    func onPermissionsUpdated(permission: SelfPermissions) {}
    func onPinned() {}
    func onScreenShareStartFailed(reason: String) {}
    func onScreenShareUpdate(isEnabled: Bool) {}
    func onUnpinned() {}
    func onUpdate(participant: RtkSelfParticipant) {}
    func onVideoDeviceChanged(videoDevice: VideoDevice) {}
    func onVideoUpdate(isEnabled: Bool) {}
}

private final class NativeMeetingEvents: NSObject, RtkMeetingRoomEventListener {
    var ended: (@MainActor () -> Void)?
    var connectionChanged: (@MainActor (HalqaConnectionStatus) -> Void)?
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
    func onSocketConnectionUpdate(newState: SocketConnectionState) {
        let status: HalqaConnectionStatus
        if newState.socketState == .connected { status = .connected }
        else if newState.socketState == .failed { status = .unavailable }
        else { status = .reconnecting }
        Task { @MainActor in connectionChanged?(status) }
    }
}
