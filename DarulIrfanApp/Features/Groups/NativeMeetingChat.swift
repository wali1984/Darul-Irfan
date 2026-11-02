import Foundation
import Observation
import RealtimeKit

/// Conversation state belongs to the connection, never to a sheet or tab.
/// Keep SDK message objects so text, attachments and recipient metadata survive
/// the move to native presentation without flattening private messages to public.
@MainActor
@Observable
final class NativeMeetingChat {
    private(set) var messages: [ChatMessage] = []
    private(set) var privateMessages: [ChatMessage] = []
    private(set) var canSend = false
    private let client: RealtimeKitClient
    private let events = NativeMeetingChatEvents()
    private var active = true

    init(client: RealtimeKitClient) {
        self.client = client
        events.changed = { [weak self] in self?.refresh() }
        client.addChatEventListener(chatEventListener: events)
    }

    func joined() {
        guard active else { return }
        canSend = true
        refresh()
    }

    /// A false result leaves the draft with the presenter for explicit retry.
    /// SDK permission and rate-limit checks remain authoritative.
    func send(_ draft: String, recipients: [String] = []) -> Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard active, canSend, !text.isEmpty else { return false }
        return client.chat.sendTextMessage(message: text, peerIds: recipients) == nil
    }

    func leaving() { active = false; canSend = false }

    func released() {
        active = false
        canSend = false
        events.changed = nil
        client.removeChatEventListener(chatEventListener: events)
        messages = []
        privateMessages = []
    }

    private func refresh() {
        guard active else { return }
        // Read the current authoritative SDK collection on the main actor.
        // Replayed callbacks cannot append duplicates or resurrect deleted rows.
        messages = client.chat.messages
        privateMessages = client.chat.privateChatMessages
    }
}

private final class NativeMeetingChatEvents: NSObject, RtkChatEventListener {
    var changed: (@MainActor () -> Void)?
    private func refresh() { Task { @MainActor in changed?() } }
    func onChatUpdates(messages: [ChatMessage]) { refresh() }
    func onNewChatMessage(message: ChatMessage) { refresh() }
    func onMessageEdited(message: ChatMessage) { refresh() }
    func onMessageDeleted(messageId: String) { refresh() }
    func onMessageRateLimitReset() { refresh() }
}
