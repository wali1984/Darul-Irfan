import SwiftUI
import Observation
import WatchConnectivity
import WidgetKit
import UserNotifications

@main
struct DarulIrfanWatchApp: App {
    @State private var store = WatchPrayerStore()

    var body: some Scene {
        WindowGroup { WatchPrayerView(store: store) }
    }
}

@Observable
@MainActor
final class WatchPrayerStore: NSObject, WCSessionDelegate {
    private(set) var snapshot: PrayerWidgetSnapshot?

    override init() {
        snapshot = PrayerWidgetSnapshot.load()
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard let data = session.applicationContext["prayerSnapshot"] as? Data else { return }
        receive(data)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["prayerSnapshot"] as? Data else { return }
        receive(data)
    }

    nonisolated private func receive(_ data: Data) {
        guard let value = try? JSONDecoder().decode(PrayerWidgetSnapshot.self, from: data) else { return }
        Task { @MainActor in
            value.save()
            snapshot = value
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func setPrayerAlertsEnabled(_ enabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("watch.prayer.") })
        guard enabled, let snapshot else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }
        for prayer in snapshot.upcomingTimes.filter({ $0.time > Date() }).prefix(12) {
            let content = UNMutableNotificationContent()
            content.title = "\(prayer.displayName) time"
            content.body = snapshot.placeName
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: prayer.time)
            let request = UNNotificationRequest(
                identifier: "watch.prayer.\(prayer.prayerKey).\(Int(prayer.time.timeIntervalSince1970))",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }
}

struct WatchPrayerView: View {
    let store: WatchPrayerStore
    @AppStorage("watchPrayerAlertsEnabled") private var alertsEnabled = false

    var body: some View {
        if let snapshot = store.snapshot {
            List {
                Section(snapshot.placeName) {
                    if let next = snapshot.upcomingTimes.first(where: { $0.time > Date() }) {
                        VStack(alignment: .leading) {
                            Text(next.displayName).font(.headline).foregroundStyle(Color(red: 0.85, green: 0.72, blue: 0.37))
                            Text(next.time, style: .timer).font(.title2.monospacedDigit())
                            Text(next.time, style: .time).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Today") {
                    ForEach(Array(snapshot.upcomingTimes.filter { Calendar.current.isDateInToday($0.time) }.prefix(6).enumerated()), id: \.offset) { _, prayer in
                        HStack { Text(prayer.displayName); Spacer(); Text(prayer.time, style: .time).monospacedDigit() }
                    }
                }
                Section("Preferences") {
                    Toggle("Prayer alerts", isOn: $alertsEnabled)
                        .onChange(of: alertsEnabled) { _, enabled in
                            Task { await store.setPrayerAlertsEnabled(enabled) }
                        }
                }
            }
        } else {
            ContentUnavailableView("Open Darul Irfan", systemImage: "iphone.and.arrow.forward", description: Text("Set up prayer times on your iPhone to sync them here."))
        }
    }
}
