import Foundation
import WatchConnectivity

@MainActor
final class WatchSyncService: NSObject, WCSessionDelegate {
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func send(_ snapshot: PrayerWidgetSnapshot) {
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(snapshot) else { return }
        let context: [String: Any] = ["prayerSnapshot": data]
        try? WCSession.default.updateApplicationContext(context)
    }

    /// Resolves several concrete occurrences per remote/bundled zikr schedule,
    /// merges them into the prayer snapshot, and transfers one atomic payload.
    func updateZikrSessions(_ sessions: [ZikrSession], reference: Date = Date()) {
        guard var snapshot = PrayerWidgetSnapshot.load() else { return }
        var occurrences: [WidgetZikrSession] = []

        for session in sessions {
            var cursor = reference.addingTimeInterval(-TimeInterval(max(session.durationMinutes, 0) * 60))
            for _ in 0..<8 {
                guard let start = ZikrScheduleMath.nextOccurrence(of: session, after: cursor) else { break }
                let end = start.addingTimeInterval(TimeInterval(max(session.durationMinutes, 1) * 60))
                if end > reference {
                    occurrences.append(WidgetZikrSession(
                        id: "\(session.id)|\(Int(start.timeIntervalSince1970))",
                        title: session.title,
                        startsAt: start,
                        endsAt: end
                    ))
                }
                cursor = start.addingTimeInterval(1)
            }
        }

        snapshot.zikrSessions = occurrences.sorted { $0.startsAt < $1.startsAt }
        snapshot.save()
        send(snapshot)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
