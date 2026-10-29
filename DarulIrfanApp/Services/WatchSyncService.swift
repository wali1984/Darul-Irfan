import Foundation
import WatchConnectivity

@MainActor
final class WatchSyncService: NSObject, WCSessionDelegate {
    /// Occurrences shown per session: covers the nine days of prayer times
    /// the snapshot carries.
    static let zikrOccurrencesPerSession = 9

    /// Resolves sessions announced against a prayer time day by day. Set by
    /// `AppState`; without it they keep the time they were resolved to.
    var prayerCalculation: (any PrayerCalculationServicing)?

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

    /// Takes the official zikr schedule the Zikr tab loaded, remembers it for
    /// the reminders and Today, resolves concrete occurrences into the prayer
    /// snapshot, and transfers one atomic payload.
    func updateZikrSessions(_ sessions: [ZikrSession], reference: Date = Date()) {
        OfficialZikrSchedule.remember(sessions)
        guard var snapshot = PrayerWidgetSnapshot.load() else { return }
        snapshot.zikrSessions = ZikrOccurrences.widgetSessions(
            for: sessions,
            reference: reference,
            perSession: Self.zikrOccurrencesPerSession,
            calculator: prayerCalculation
        )
        snapshot.save()
        send(snapshot)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
