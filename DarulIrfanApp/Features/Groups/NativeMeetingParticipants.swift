import Foundation
import Observation
import RealtimeKit

enum NativeParticipantAction { case muteAudio, muteVideo, remove, admit, reject }

struct NativeLocalMediaState: Equatable {
    var microphoneEnabled = false
    var cameraEnabled = false
    var microphoneAllowed = false
    var cameraAllowed = false
    var canMuteParticipants = false
    var canStopParticipantVideo = false
    var canRemoveParticipants = false
    var canAdmitParticipants = false
}

/// Session-owned participant state. Presentation may disappear without
/// disconnecting listeners or losing the SDK's current video participants.
@MainActor
@Observable
final class NativeMeetingParticipants {
    private(set) var joined: [RtkRemoteParticipant] = []
    private(set) var waiting: [RtkRemoteParticipant] = []
    private(set) var visible: [RtkRemoteParticipant] = []
    private(set) var screenShares: [RtkRemoteParticipant] = []
    private(set) var speakerID: String?
    private(set) var localMedia = NativeLocalMediaState()
    private(set) var audioDevices: [AudioDevice] = []
    private(set) var selectedAudioDeviceID: String?
    // SDK participant objects can change in place. Renderers observe revision
    // as well as membership so mute/video/pin changes always invalidate rows.
    private(set) var revision = 0
    private let client: RealtimeKitClient
    private let events = NativeParticipantEvents()
    private var active = true

    init(client: RealtimeKitClient) {
        self.client = client
        events.changed = { [weak self] in self?.refresh() }
        client.addParticipantsEventListener(participantsEventListener: events)
    }

    func refresh() {
        guard active else { return }
        joined = client.participants.joined
        waiting = client.participants.waitlisted
        visible = client.participants.active
        screenShares = client.participants.screenShares
        speakerID = client.participants.lastActiveSpeaker?.id
        let local = client.localUser
        audioDevices = local.getAudioDevices()
        selectedAudioDeviceID = local.getSelectedAudioDevice()?.id
        localMedia = NativeLocalMediaState(microphoneEnabled: local.audioEnabled,
                                          cameraEnabled: local.videoEnabled,
                                          microphoneAllowed: local.permissions.media.canPublishAudio,
                                          cameraAllowed: local.permissions.media.canPublishVideo,
                                          canMuteParticipants: local.permissions.host.canMuteAudio,
                                          canStopParticipantVideo: local.permissions.host.canMuteVideo,
                                          canRemoveParticipants: local.permissions.host.canKickParticipant,
                                          canAdmitParticipants: local.permissions.host.canAcceptRequests)
        revision &+= 1
    }

    func leaving() { active = false }

    func released() {
        active = false
        events.changed = nil
        client.removeParticipantsEventListener(participantsEventListener: events)
        joined = []; waiting = []; visible = []; screenShares = []
        speakerID = nil
        localMedia = NativeLocalMediaState()
        audioDevices = []; selectedAudioDeviceID = nil
        revision &+= 1
    }
}

private final class NativeParticipantEvents: NSObject, RtkParticipantsEventListener {
    var changed: (@MainActor () -> Void)?
    private func refresh() { Task { @MainActor in changed?() } }
    func onParticipantJoin(participant: RtkRemoteParticipant) { refresh() }
    func onParticipantLeave(participant: RtkRemoteParticipant) { refresh() }
    func onAudioUpdate(participant: RtkRemoteParticipant, isEnabled: Bool) { refresh() }
    func onVideoUpdate(participant: RtkRemoteParticipant, isEnabled: Bool) { refresh() }
    func onScreenShareUpdate(participant: RtkRemoteParticipant, isEnabled: Bool) { refresh() }
    func onParticipantPinned(participant: RtkRemoteParticipant) { refresh() }
    func onParticipantUnpinned(participant: RtkRemoteParticipant) { refresh() }
    func onActiveParticipantsChanged(active: [RtkRemoteParticipant]) { refresh() }
    func onActiveSpeakerChanged(participant: RtkRemoteParticipant?) { refresh() }
    func onAllParticipantsUpdated(allParticipants: [RtkParticipant]) { refresh() }
    func onUpdate(participants: RtkParticipants) { refresh() }
    func onNewBroadcastMessage(type: String, payload: [String: Any]) {}
}
