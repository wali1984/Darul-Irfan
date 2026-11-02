import SwiftUI
import RealtimeKit

@MainActor
struct NativeMeetingConversationView: View {
    let chat: NativeMeetingChat
    let participants: NativeMeetingParticipants
    let openAttachment: (URL) -> Void
    @State private var peerID: String?
    @State private var drafts: [String: String] = [:]
    @State private var failed = false

    private var draftKey: String { peerID.map { "peer:\($0)" } ?? "public" }

    var body: some View {
        let _ = participants.revision
        let person = participants.joined.first { $0.id == peerID }
        let unavailable = peerID != nil && person == nil
        let rows = chat.conversation(peerID: peerID)
        VStack(spacing: DISpacing.sm) {
            Menu {
                Button("Everyone in the session") { peerID = nil }
                ForEach(participants.joined, id: \.id) { person in
                    Button { peerID = person.id } label: { Text(verbatim: person.name) }
                }
            } label: {
                VStack {
                    Text(peerID == nil ? LocalizedStringKey("Everyone in the session") : LocalizedStringKey("Private conversation"))
                    if let person { Text(verbatim: person.name) }
                }
            }.buttonStyle(DISecondaryButtonStyle())
            if unavailable { Text("This participant has left. Choose a recipient to continue.").foregroundStyle(DIColor.textMuted) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DISpacing.md) {
                    ForEach(rows, id: \.id) { message in
                        VStack(alignment: .leading, spacing: DISpacing.xs) {
                            Text(verbatim: message.displayName).bold()
                            if let text = message as? TextMessage { Text(verbatim: text.message).textSelection(.enabled) }
                            if let image = message as? ImageMessage { attachment(image.link, label: "Open image") }
                            if let file = message as? FileMessage {
                                Text(verbatim: file.name)
                                attachment(file.link, label: "Open attachment")
                            }
                        }.padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(DIColor.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            TextField("Message", text: Binding(get: { drafts[draftKey] ?? "" }, set: { drafts[draftKey] = $0 }), axis: .vertical)
                .lineLimit(1...5).textFieldStyle(.roundedBorder)
            Button("Send") {
                let key = draftKey
                if chat.send(drafts[key] ?? "", recipients: peerID.map { [$0] } ?? []) { drafts[key] = "" }
                else { failed = true }
            }.buttonStyle(DIPrimaryButtonStyle())
                .disabled(!chat.canSend || unavailable || (drafts[draftKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding().diScreenBackground()
            .alert("Could not complete action", isPresented: $failed) { Button("OK", role: .cancel) {} }
    }

    @ViewBuilder private func attachment(_ address: String, label: LocalizedStringKey) -> some View {
        if let url = URL(string: address), url.scheme?.lowercased() == "https" {
            Button(label) { openAttachment(url) }.buttonStyle(DICompactButtonStyle())
        } else { Text("Attachment unavailable").foregroundStyle(DIColor.textMuted) }
    }
}
