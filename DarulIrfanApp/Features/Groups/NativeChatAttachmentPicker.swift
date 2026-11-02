import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct NativeChatAttachmentPicker: View {
    let chat: NativeMeetingChat
    let recipients: [String]
    let recipientName: String?
    let enabled: Bool
    let lockRecipient: (Bool) -> Void
    @State private var choosing = false
    @State private var preparing = false
    @State private var uploading = false
    @State private var visible = false
    @State private var selected: NativeChatAttachment?
    @State private var targets: [String] = []
    @State private var targetName: String?
    @State private var error: LocalizedStringKey?
    private var locked: Bool { choosing || preparing || uploading || selected != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.xs) {
            if let selected {
                Text(verbatim: selected.name).lineLimit(2)
                if targets.isEmpty { Text("Everyone in the session") }
                else { Text("Private conversation"); Text(verbatim: targetName ?? "") }
                HStack {
                    Button("Send attachment") { send(selected) }
                        .disabled(!enabled || uploading || chat.operationPending)
                    Button("Cancel", role: .cancel) {
                        selected.discard(); self.selected = nil; error = nil
                    }.disabled(uploading)
                }.buttonStyle(DICompactButtonStyle())
            } else {
                Button("Attach file") {
                    targets = recipients; targetName = recipientName; error = nil; choosing = true
                }.buttonStyle(DICompactButtonStyle()).disabled(!enabled || choosing || preparing || uploading)
            }
            if preparing || uploading { ProgressView() }
            if let error { Text(error).foregroundStyle(DIColor.danger) }
        }
        .onAppear { visible = true }
        .onDisappear {
            visible = false
            if !uploading { selected?.discard(); selected = nil }
            lockRecipient(false)
        }
        .onChange(of: locked, initial: true) { _, value in lockRecipient(value) }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            preparing = true
            Task {
                do {
                    let copy = try await Task.detached { try NativeChatAttachment.prepare(url) }.value
                    if visible { selected = copy } else { copy.discard() }
                } catch {
                    if visible { self.error = "Could not prepare attachment. Choose a readable file up to 20 MB." }
                }
                preparing = false
            }
        }
    }

    private func send(_ file: NativeChatAttachment) {
        guard !uploading else { return }
        uploading = true; error = nil
        chat.sendAttachment(file.url, image: file.isImage, recipients: targets) { success in
            uploading = false
            if success || !visible { file.discard(); selected = nil }
            else { error = "Could not complete action" }
        }
    }
}
