import SwiftUI

/// Closing presentation is not Leave. The app-owned session outlives this view.
@MainActor
struct NativeMeetingRoomView: View {
    let pass: GroupRoomPass
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var rejected = false
    @State private var started = false
    @State private var attachmentFailed = false
    private let owner = NativeHalqaSession.shared

    private var ownsRoom: Bool {
        guard let roomID = pass.roomID else { return false }
        return owner.lifecycle.sessionID == roomID
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: DISpacing.sm) {
                if !started {
                    ProgressView("Connecting to the session…").padding()
                } else if rejected || owner.lifecycle.phase == .failed {
                    Text("Could not complete action").padding()
                } else if ownsRoom, [.joining, .joined].contains(owner.lifecycle.phase),
                          let transport = owner.lifecycle.transport as? NativeMeetingTransport {
                    if owner.lifecycle.connectionStatus == .reconnecting || owner.lifecycle.connectionStatus == .unavailable {
                        Text("Reconnecting to the session…").foregroundStyle(DIColor.textMuted)
                    }
                    if owner.lifecycle.phase != .joined {
                        ProgressView("Connecting to the session…").padding()
                    }
                    NativeMeetingCaptureControls(transport: transport, joined: owner.lifecycle.phase == .joined)
                        .padding(.horizontal)
                    TabView {
                        NativeMeetingGalleryView(participants: transport.participants)
                            .tabItem { Label("Video", systemImage: "video") }
                        NativeMeetingConversationView(chat: transport.chat, participants: transport.participants,
                                                      openAttachment: openAttachment)
                            .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                        NativeMeetingPeopleView(participants: transport.participants) { action, id in
                            ownsRoom && transport.submit(action, participantID: id)
                        }.tabItem { Label("Participants", systemImage: "person.2") }
                    }.id(ObjectIdentifier(transport))
                } else if ownsRoom {
                    ProgressView().accessibilityLabel(Text("Meeting room")).padding()
                } else {
                    Text("Session ended").padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .diScreenBackground()
            .navigationTitle("Darul Irfan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ownsRoom ? LocalizedStringKey("Minimize") : LocalizedStringKey("Close")) { dismiss() }
                        .buttonStyle(DICompactButtonStyle())
                }
                if ownsRoom {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Leave", role: .destructive) { if ownsRoom { owner.leave() } }
                            .buttonStyle(DICompactButtonStyle())
                            .disabled(owner.lifecycle.phase == .leaving)
                    }
                }
            }
            .task { rejected = !owner.join(pass: pass); started = true }
            .alert("Could not complete action", isPresented: $attachmentFailed) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func openAttachment(_ url: URL) {
        guard url.scheme?.lowercased() == "https", url.host != nil else { attachmentFailed = true; return }
        openURL(url) { accepted in if !accepted { attachmentFailed = true } }
    }
}
