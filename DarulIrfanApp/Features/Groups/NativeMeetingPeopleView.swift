import SwiftUI
import RealtimeKit

@MainActor
struct NativeMeetingPeopleView: View {
    let participants: NativeMeetingParticipants
    let submit: (NativeParticipantAction, String) -> Bool
    @State private var removing: RtkRemoteParticipant?
    @State private var failed = false

    var body: some View {
        let _ = participants.revision // SDK participant media properties mutate in place.
        let permissions = participants.localMedia
        List {
            if permissions.canAdmitParticipants && !participants.waiting.isEmpty {
                Section("Waiting to join") {
                    ForEach(participants.waiting, id: \.id) { person in
                        VStack(alignment: .leading, spacing: DISpacing.sm) {
                            Text(verbatim: person.name)
                            HStack {
                                Button("Admit") { act(.admit, person.id) }
                                Button("Reject", role: .destructive) { act(.reject, person.id) }
                            }.buttonStyle(DICompactButtonStyle())
                        }
                    }
                }.listRowBackground(DIColor.surface)
            }
            Section("Participants") {
                if participants.joined.isEmpty { Text("No other participants yet.").foregroundStyle(DIColor.textMuted) }
                ForEach(participants.joined, id: \.id) { person in
                    HStack(alignment: .top, spacing: DISpacing.sm) {
                        VStack(alignment: .leading, spacing: DISpacing.xs) {
                            Text(verbatim: person.name)
                            Text(LocalizedStringKey(person.audioEnabled ? "Microphone on" : "Microphone off"))
                                .foregroundStyle(DIColor.textMuted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if (permissions.canMuteParticipants && person.audioEnabled) || (permissions.canStopParticipantVideo && person.videoEnabled) || permissions.canRemoveParticipants {
                            Menu {
                                if permissions.canMuteParticipants && person.audioEnabled {
                                    Button("Mute microphone") { act(.muteAudio, person.id) }
                                }
                                if permissions.canStopParticipantVideo && person.videoEnabled {
                                    Button("Stop camera") { act(.muteVideo, person.id) }
                                }
                                if permissions.canRemoveParticipants {
                                    Button("Remove from session", role: .destructive) { removing = person }
                                }
                            } label: { Label("Controls", systemImage: "ellipsis.circle") }
                                .buttonStyle(DICompactButtonStyle())
                        }
                    }
                }
            }.listRowBackground(DIColor.surface)
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .confirmationDialog("Remove from session?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        ), presenting: removing) { person in
            Button("Remove from session", role: .destructive) { act(.remove, person.id); removing = nil }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { person in Text(verbatim: person.name) }
        .alert("Could not complete action", isPresented: $failed) { Button("OK", role: .cancel) {} }
    }

    private func act(_ action: NativeParticipantAction, _ id: String) {
        if !submit(action, id) { failed = true }
    }
}
