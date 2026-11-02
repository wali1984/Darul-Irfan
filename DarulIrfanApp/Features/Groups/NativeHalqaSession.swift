import RealtimeKit
import AVFoundation
import UIKit

/// App-owned session: navigation and scene backgrounding do not release it.
/// The native room presenter must use this owner instead of creating a client.
@MainActor
final class NativeHalqaSession {
    static let shared = NativeHalqaSession()
    let lifecycle = HalqaSessionLifecycle()
    private init() {}
    private var presentation: (groupID: String, pass: GroupRoomPass)?

    var activeGroupID: String? {
        let roomID = lifecycle.sessionID
        guard lifecycle.transport != nil, let presentation,
              roomID == presentation.pass.roomID else { return nil }
        return presentation.groupID
    }

    /// In-memory only; an expired or released connection is never recreated
    /// using the old participant token.
    func resumePass(groupID: String) -> GroupRoomPass? {
        // Read observable lifecycle even before presentation exists so a
        // newly joined/minimized session invalidates the group's return link.
        let roomID = lifecycle.sessionID
        let transport = lifecycle.transport
        guard let presentation, presentation.groupID == groupID,
              transport != nil, roomID == presentation.pass.roomID else { return nil }
        return presentation.pass
    }

    var client: RealtimeKitClient? {
        (lifecycle.transport as? NativeMeetingTransport)?.client
    }

    var chat: NativeMeetingChat? {
        (lifecycle.transport as? NativeMeetingTransport)?.chat
    }

    var participants: NativeMeetingParticipants? {
        (lifecycle.transport as? NativeMeetingTransport)?.participants
    }

    @discardableResult
    func join(pass: GroupRoomPass, groupID: String, prepareAudio: () -> Void) -> Bool {
        guard let roomID = pass.roomID, !roomID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if lifecycle.transport != nil && presentation?.groupID != groupID { return false }
        let started = lifecycle.start(sessionID: roomID) {
            // Only a fresh connection takes audio ownership. Returning to an
            // existing room must not interrupt or reset its audio session.
            RecitationPracticeRecorder.yieldToHalqah()
            prepareAudio()
            return NativeMeetingTransport(authToken: pass.authToken)
        }
        if started { presentation = (groupID, pass) }
        return started
    }

    func leave() { lifecycle.leave() }

    func submit(_ action: NativeParticipantAction, participantID: String) -> Bool {
        guard lifecycle.phase == .joined,
              let transport = lifecycle.transport as? NativeMeetingTransport else { return false }
        return transport.submit(action, participantID: participantID)
    }

    /// Call only from the room's explicit microphone/camera button.
    func requestCapture(_ kind: HalqaCaptureKind, completion: @escaping (Bool) -> Void) {
        guard lifecycle.phase == .joined,
              let transport = lifecycle.transport as? NativeMeetingTransport else {
            completion(false); return
        }
        transport.requestCapture(kind, permission: { done in
            let media: AVMediaType = kind == .microphone ? .audio : .video
            switch AVCaptureDevice.authorizationStatus(for: media) {
            case .authorized: done(true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: media) { granted in Task { @MainActor in done(granted) } }
            default: done(false)
            }
        }, foreground: { UIApplication.shared.applicationState == .active }, completion: completion)
    }

    func stopCapture(_ kind: HalqaCaptureKind, completion: @escaping (Bool) -> Void) {
        guard let transport = lifecycle.transport as? NativeMeetingTransport else { completion(false); return }
        transport.stopCapture(kind, completion: completion)
    }
}
