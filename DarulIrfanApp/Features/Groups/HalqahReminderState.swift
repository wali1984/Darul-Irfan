import Foundation

/// Only successful server snapshots may invalidate a saved reminder.
@MainActor
final class HalqahReminderState {
    static let shared = HalqahReminderState()
    private var sessions: [String: Set<String>] = [:]

    static func key(groupID: String, sessionID: String) -> String {
        "groupZikrReminder.\(groupID).\(sessionID)"
    }

    func permits(groupID: String, sessionID: String) -> Bool {
        sessions[groupID]?.contains(sessionID) ?? true
    }

    func accept(groupID: String, sessionIDs: Set<String>, savedKeys: [String]) -> [String] {
        sessions[groupID] = sessionIDs
        let prefix = "groupZikrReminder.\(groupID)."
        let retained = Set(sessionIDs.map { Self.key(groupID: groupID, sessionID: $0) })
        return savedKeys.filter { $0.hasPrefix(prefix) && !retained.contains($0) }
    }

    func remove(groupID: String, sessionID: String) {
        sessions[groupID]?.remove(sessionID)
    }

    func reconcile(groupID: String, sessionIDs: Set<String>, notifications: any NotificationScheduling) async {
        let stale = accept(groupID: groupID, sessionIDs: sessionIDs,
                           savedKeys: Array(UserDefaults.standard.dictionaryRepresentation().keys))
        for key in stale {
            UserDefaults.standard.removeObject(forKey: key)
            await notifications.cancelReminder(id: key)
        }
    }
}
