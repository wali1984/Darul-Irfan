import SwiftUI
import RealtimeKit

@MainActor
struct NativeMeetingAudioOutputView: View {
    let transport: NativeMeetingTransport
    let joined: Bool
    @State private var failed = false

    var body: some View {
        Menu {
            ForEach(transport.participants.audioDevices, id: \.id) { device in
                Button {
                    if !transport.selectAudioDevice(id: device.id) { failed = true }
                } label: {
                    if device.id == transport.participants.selectedAudioDeviceID {
                        Label(LocalizedStringKey(label(device)), systemImage: "checkmark")
                    } else { Text(LocalizedStringKey(label(device))) }
                }
            }
        } label: { Label("Audio output", systemImage: "speaker.wave.2") }
        .buttonStyle(DICompactButtonStyle())
        .disabled(!joined || transport.participants.audioDevices.isEmpty)
        .alert("Could not complete action", isPresented: $failed) { Button("OK", role: .cancel) {} }
    }

    private func label(_ device: AudioDevice) -> String {
        if device.type == .speaker { return "Speaker" }
        if device.type == .earPiece { return "Earpiece" }
        if device.type == .wired { return "Headset" }
        if device.type == .bluetooth { return "Bluetooth" }
        return "Audio output"
    }
}
