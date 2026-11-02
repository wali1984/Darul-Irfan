import SwiftUI
import RealtimeKit

/// Rendering only: disposing this gallery must never leave the audio session.
@MainActor
struct NativeMeetingGalleryView: View {
    let participants: NativeMeetingParticipants
    let localParticipant: RtkMeetingParticipant

    var body: some View {
        let revision = participants.revision
        ScrollView {
            LazyVStack(spacing: DISpacing.md) {
                if participants.localMedia.cameraEnabled {
                    VStack(alignment: .leading, spacing: DISpacing.sm) {
                        Text("Your camera").font(.headline)
                        NativeMeetingVideo(participant: localParticipant, revision: revision)
                            .aspectRatio(16 / 9, contentMode: .fit)
                    }.padding().background(DIColor.surface, in: RoundedRectangle(cornerRadius: 20))
                }
                ForEach(participants.screenShares, id: \.id) { person in
                    VStack(alignment: .leading, spacing: DISpacing.sm) {
                        Text(verbatim: person.name).font(.headline)
                        NativeMeetingVideo(participant: person, screenShare: true, revision: revision)
                            .aspectRatio(16 / 9, contentMode: .fit)
                    }
                    .padding().background(DIColor.surface, in: RoundedRectangle(cornerRadius: 20))
                }
                if participants.joined.isEmpty {
                    Text("No other participants yet.").foregroundStyle(DIColor.textMuted).padding()
                }
                ForEach(participants.joined, id: \.id) { person in
                    VStack(alignment: .leading, spacing: DISpacing.sm) {
                        if person.videoEnabled {
                            NativeMeetingVideo(participant: person, revision: revision)
                                .aspectRatio(16 / 9, contentMode: .fit)
                        }
                        Text(verbatim: person.name).font(.headline)
                        Text(LocalizedStringKey(person.audioEnabled ? "Microphone on" : "Microphone off"))
                            .font(.caption).foregroundStyle(DIColor.textMuted)
                    }
                    .padding().background(DIColor.surface, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(
                        participants.speakerID == person.id ? DIColor.actionForeground : .clear, lineWidth: 2))
                }
            }.padding()
        }.diScreenBackground()
    }
}
