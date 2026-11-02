import AVFoundation
import SwiftUI

@MainActor
struct RecitationPracticeCard: View {
    let recorder: RecitationPracticeRecorder?
    let audioPlayer: any AudioPlayerServicing
    let reference: String
    let allowedNow: () -> Bool

    var body: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                DISectionHeader(titleKey: "Your recitation", systemImage: "mic.fill")
                Text("Record up to 5 minutes, then listen and compare with the reciter. Ask your teacher to check your Tajweed.")
                    .diInterfaceFont(.subheadline).foregroundStyle(DIColor.textPrimary)
                Text("Your recording stays on this device and is deleted when you leave this page.")
                    .diInterfaceFont(.footnote).foregroundStyle(.secondary)
                if let recorder {
                    if let savedReference = recorder.clipReference, recorder.hasClip {
                        Text("Recorded for ayah \(savedReference)")
                            .diInterfaceFont(.footnote, weight: .semibold)
                            .foregroundStyle(DIColor.actionForeground)
                    }
                    if let failure = recorder.failure {
                        Text(LocalizedStringKey(message(failure)))
                            .diInterfaceFont(.callout).foregroundStyle(DIColor.textPrimary)
                        if failure == .permission {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }.buttonStyle(DICompactButtonStyle())
                        }
                    }
                    switch recorder.phase {
                    case .preparing:
                        ProgressView("Preparing microphone or playback…")
                        Button("Cancel") { recorder.suspend() }.buttonStyle(DICompactButtonStyle())
                    case .recording:
                        Label("Recording your recitation", systemImage: "record.circle.fill")
                            .diInterfaceFont(.headline).foregroundStyle(DIColor.actionForeground)
                        Button("Stop recording") { recorder.stopRecording() }.buttonStyle(DIPrimaryButtonStyle())
                    case .replaying:
                        Label("Playing your recording", systemImage: "waveform")
                            .diInterfaceFont(.headline)
                        Button("Stop playback") { recorder.stopReplay() }.buttonStyle(DIPrimaryButtonStyle())
                    case .idle:
                        Button(recorder.hasClip ? "Record again" : "Record my recitation") {
                            recorder.start(reference: reference, permission: { reply in
                                AVCaptureDevice.requestAccess(for: .audio) { granted in
                                    Task { @MainActor in reply(granted) }
                                }
                            }, prepareAudio: prepare, allowedNow: allowedNow)
                        }.buttonStyle(DIPrimaryButtonStyle())
                            .accessibilityIdentifier("practice-record")
                        if recorder.hasClip {
                            Button("Listen to my recording") {
                                recorder.play(prepareAudio: prepare, allowedNow: allowedNow)
                            }.buttonStyle(DICompactButtonStyle())
                                .accessibilityIdentifier("practice-replay")
                            Button("Delete recording", role: .destructive) { recorder.deleteClip() }
                                .buttonStyle(DICompactButtonStyle())
                                .accessibilityIdentifier("practice-delete")
                        }
                    }
                } else {
                    Text("Recording storage is unavailable. Free some space and reopen this page.")
                        .diInterfaceFont(.callout)
                }
            }
        }
    }

    private func prepare(_ completion: @escaping @MainActor (Bool) -> Void) {
        RecitationAudioHandoff.prepare(audioPlayer: audioPlayer, allowedNow: allowedNow, completion: completion)
    }

    private func message(_ failure: RecitationPracticeRecorder.Failure) -> String {
        switch failure {
        case .permission: "Allow microphone access in Settings to record your recitation."
        case .audio: "Audio is busy. Finish your Halqah or other audio session, then try again."
        case .recording: "The recording could not be saved. Please try again."
        case .playback: "This recording could not be played. Please record again."
        case .storage: "Recording storage is unavailable. Free some space and reopen this page."
        }
    }
}
