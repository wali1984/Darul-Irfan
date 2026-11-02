import Foundation
import RealtimeKit

/// SDK adapter for the retained session owner. It never logs participant
/// tokens and never enables capture as a side effect of reconnecting.
@MainActor
final class NativeMeetingTransport: HalqaSessionTransport {
    let client = NativeMeetingConfiguration.makeClient()
    let conversationDrafts = NativeConversationDrafts()
    private var chatStorage: NativeMeetingChat?
    private var participantsStorage: NativeMeetingParticipants?
    var chat: NativeMeetingChat {
        if let chatStorage { return chatStorage }
        let value = NativeMeetingChat(client: client)
        chatStorage = value
        return value
    }
    var participants: NativeMeetingParticipants {
        if let participantsStorage { return participantsStorage }
        let value = NativeMeetingParticipants(client: client)
        participantsStorage = value
        return value
    }
    let microphoneRequest = HalqaCaptureRequest()
    let cameraRequest = HalqaCaptureRequest()
    private var joined = false
    private let operations = HalqaTransportOperationGate()

    /// Submission only; the SDK's device event confirms the selected route.
    func selectAudioDevice(id: String) -> Bool {
        guard joined, let device = client.localUser.getAudioDevices().first(where: { $0.id == id }) else { return false }
        client.localUser.setAudioDevice(rtkAudioDevice: device)
        return true
    }

    /// True means the SDK accepted submission, not that a remote participant
    /// has already changed state. Participant events remain authoritative.
    func submit(_ action: NativeParticipantAction, participantID: String) -> Bool {
        guard joined else { return false }
        let permissions = client.localUser.permissions.host
        switch action {
        case .admit, .reject:
            guard permissions.canAcceptRequests,
                  client.participants.waitlisted.contains(where: { $0.id == participantID }) else { return false }
            if action == .admit { client.participants.acceptWaitingRoomRequest(id: participantID) }
            else { client.participants.rejectWaitingRoomRequest(id: participantID) }
            return true
        case .muteAudio, .muteVideo, .remove:
            guard let person = client.participants.joined.first(where: { $0.id == participantID }) else { return false }
            switch action {
            case .muteAudio: return permissions.canMuteAudio && person.disableAudio() == nil
            case .muteVideo: return permissions.canMuteVideo && person.disableVideo() == nil
            case .remove: return permissions.canKickParticipant && person.kick() == nil
            default: return false
            }
        }
    }
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
        membershipEvents.changed = { [weak self] in self?.participantsStorage?.refresh() }
        client.addMeetingRoomEventListener(meetingRoomEventListener: events)
        client.addSelfEventListener(selfEventListener: membershipEvents)
    }

    func initialize(completion: @escaping (Bool) -> Void) {
        guard operations.begin() else { completion(false); return }
        client.doInit(meetingInfo: info,
                      onSuccess: { [self] in Task { @MainActor in completion(operations.finish()) } },
                      onFailure: { [self] _ in Task { @MainActor in _ = operations.finish(); completion(false) } })
    }

    func join(completion: @escaping (Bool) -> Void) {
        guard operations.begin() else { completion(false); return }
        _ = chat // Attach before joining so initial history is observed.
        _ = participants
        client.joinRoom(onSuccess: { [self] in Task { @MainActor in
            guard operations.finish() else { completion(false); return }
            joined = true
            chat.joined()
            participants.refresh()
            completion(true)
        } },
                        onFailure: { [self] _ in Task { @MainActor in _ = operations.finish(); completion(false) } })
    }

    func release(completion: @escaping (Bool) -> Void) {
        joined = false
        conversationDrafts.clear()
        microphoneRequest.close()
        cameraRequest.close()
        // Initialization may have failed before either observer was created.
        // Teardown must not instantiate new SDK state or attach listeners.
        chatStorage?.leaving()
        participantsStorage?.leaving()
        operations.close { [self] in
        client.release(onSuccess: { [weak self] in Task { @MainActor in
            if let self {
                self.chatStorage?.released()
                self.participantsStorage?.released()
                self.membershipEvents.changed = nil
                self.client.removeMeetingRoomEventListener(meetingRoomEventListener: self.events)
                self.client.removeSelfEventListener(selfEventListener: self.membershipEvents)
            }
            completion(true)
        } },
                       onFailure: { _ in Task { @MainActor in completion(false) } })
        }
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
    var changed: (@MainActor () -> Void)?
    private func refresh() { Task { @MainActor in changed?() } }
    func onRemovedFromMeeting() { Task { @MainActor in ended?() } }
    func onWaitListStatusUpdate(waitListStatus: RealtimeKit.WaitListStatus) {
        if waitListStatus == .rejected { Task { @MainActor in ended?() } }
    }
    func onAudioDeviceChanged(audioDevice: AudioDevice) { refresh() }
    func onAudioDevicesUpdated(devices: [AudioDevice]) { refresh() }
    func onAudioUpdate(isEnabled: Bool) { refresh() }
    func onMeetingRoomJoinedWithoutCameraPermission() {}
    func onMeetingRoomJoinedWithoutMicPermission() {}
    func onPermissionsUpdated(permission: SelfPermissions) { refresh() }
    func onPinned() {}
    func onScreenShareStartFailed(reason: String) {}
    func onScreenShareUpdate(isEnabled: Bool) {}
    func onUnpinned() {}
    func onUpdate(participant: RtkSelfParticipant) { refresh() }
    func onVideoDeviceChanged(videoDevice: VideoDevice) {}
    func onVideoUpdate(isEnabled: Bool) { refresh() }
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
