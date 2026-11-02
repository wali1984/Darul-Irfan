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
    private(set) var operationPending = false
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

    func conversation(peerID: String?) -> [ChatMessage] {
        guard let peerID else { return messages }
        _ = privateMessages // Observe private-chat updates before reading SDK filtering.
        guard let person = client.participants.joined.first(where: { $0.id == peerID }) else { return [] }
        return client.chat.getPrivateChatMessages(participant: person)
    }

    /// A false result leaves the draft with the presenter for explicit retry.
    /// SDK permission and rate-limit checks remain authoritative.
    func send(_ draft: String, recipients: [String] = []) -> Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard active, canSend, !text.isEmpty, recipientsAvailable(recipients) else { return false }
        return client.chat.sendTextMessage(message: text, peerIds: recipients) == nil
    }

    /// The presenter keeps a readable local copy until completion. Recipient
    /// IDs are captured at submission, never taken from a later UI selection.
    func sendAttachment(_ url: URL, image: Bool, recipients: [String] = [],
                        completion: @escaping (Bool) -> Void) {
        guard url.isFileURL, recipientsAvailable(recipients) else { completion(false); return }
        perform(completion: completion) { done in
            if image {
                client.chat.sendImageMessage(imageURL: url, peerIds: recipients) { done($0 == nil) }
            } else {
                client.chat.sendFileMessage(fileURL: url, peerIds: recipients) { done($0 == nil) }
            }
        }
    }

    func edit(messageID: String, draft: String, completion: @escaping (Bool) -> Void) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageID.isEmpty, !text.isEmpty else { completion(false); return }
        perform(completion: completion) { done in
            client.chat.editTextMessage(messageId: messageID, newMessage: text) { done($0 == nil) }
        }
    }

    func delete(messageID: String, completion: @escaping (Bool) -> Void) {
        guard !messageID.isEmpty else { completion(false); return }
        perform(completion: completion) { done in
            client.chat.deleteMessage(messageId: messageID) { done($0 == nil) }
        }
    }

    private func perform(completion: @escaping (Bool) -> Void,
                         operation: (@escaping (Bool) -> Void) -> Void) {
        guard active, canSend, !operationPending else { completion(false); return }
        operationPending = true
        operation { [self] success in
            Task { @MainActor in
                operationPending = false
                if success { refresh() }
                // Report the actual outcome even after Leave. A completed send
                // must not look failed and encourage sending a duplicate.
                completion(success)
            }
        }
    }

    private func recipientsAvailable(_ ids: [String]) -> Bool {
        let joined = Set(client.participants.joined.map(\.id))
        return ids.allSatisfy { !$0.isEmpty && joined.contains($0) }
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
