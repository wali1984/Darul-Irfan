import AVFoundation
import SwiftUI
import UIKit

/// Bound to one transport, so an old screen cannot control a replacement room.
@MainActor
struct NativeMeetingCaptureControls: View {
    let transport: NativeMeetingTransport
    let joined: Bool
    @State private var visible = false
    @State private var failed = false

    var body: some View {
        let media = transport.participants.localMedia
        let pending = transport.microphoneRequest.pending || transport.cameraRequest.pending
        ViewThatFits(in: .horizontal) {
            HStack { microphone(media); camera(media) }
            VStack { microphone(media); camera(media) }
        }
        .buttonStyle(DICompactButtonStyle())
        .disabled(!joined || pending)
        .onAppear { visible = true }
        .onDisappear {
            visible = false
            // Cancel pending starts only. Existing broadcast audio survives
            // minimizing the room until explicitly muted or left.
            transport.microphoneRequest.cancel()
            transport.cameraRequest.cancel()
        }
        .alert("Could not complete action", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func microphone(_ media: NativeLocalMediaState) -> some View {
        Button { toggle(.microphone, enabled: media.microphoneEnabled) } label: {
            Label(LocalizedStringKey(media.microphoneEnabled ? "Mute microphone" : "Turn on microphone"),
                  systemImage: media.microphoneEnabled ? "mic.fill" : "mic.slash.fill")
        }.disabled(!media.microphoneEnabled && !media.microphoneAllowed)
    }

    private func camera(_ media: NativeLocalMediaState) -> some View {
        Button { toggle(.camera, enabled: media.cameraEnabled) } label: {
            Label(LocalizedStringKey(media.cameraEnabled ? "Stop camera" : "Turn on camera"),
                  systemImage: media.cameraEnabled ? "video.fill" : "video.slash.fill")
        }.disabled(!media.cameraEnabled && !media.cameraAllowed)
    }

    private func toggle(_ kind: HalqaCaptureKind, enabled: Bool) {
        let completion: (Bool) -> Void = { success in if visible && !success { failed = true } }
        if enabled { transport.stopCapture(kind, completion: completion); return }
        transport.requestCapture(kind, permission: { done in
            let media: AVMediaType = kind == .microphone ? .audio : .video
            switch AVCaptureDevice.authorizationStatus(for: media) {
            case .authorized: done(true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: media) { granted in
                    Task { @MainActor in done(granted) }
                }
            default: done(false)
            }
        }, foreground: { visible && UIApplication.shared.applicationState == .active }, completion: completion)
    }
}
