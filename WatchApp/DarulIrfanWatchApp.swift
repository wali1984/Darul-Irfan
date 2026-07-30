import SwiftUI
import Observation
import WatchConnectivity
import WidgetKit
import UserNotifications

@main
struct DarulIrfanWatchApp: App {
    @State private var store = WatchPrayerStore()

    var body: some Scene {
        WindowGroup { WatchRootView(store: store) }
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

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard let data = session.applicationContext["prayerSnapshot"] as? Data else { return }
        receive(data)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext["prayerSnapshot"] as? Data else { return }
        receive(data)
    }

    nonisolated private func receive(_ data: Data) {
        // WatchConnectivity receives the default JSONEncoder representation;
        // the App Group file uses ISO-8601 independently in snapshot.save().
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
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("watch.prayer.") }
        )
        guard enabled, let snapshot else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }
        for prayer in snapshot.upcomingTimes.filter({ $0.isObligatory && $0.time > Date() }).prefix(12) {
            let content = UNMutableNotificationContent()
            content.title = "\(prayer.displayName) time"
            content.body = snapshot.placeName
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: prayer.time
            )
            let request = UNNotificationRequest(
                identifier: "watch.prayer.\(prayer.prayerKey).\(Int(prayer.time.timeIntervalSince1970))",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }
}

private enum WatchTheme {
    static let emerald = Color(red: 0.043, green: 0.447, blue: 0.314)
    static let deepEmerald = Color(red: 0.024, green: 0.294, blue: 0.204)
    static let gold = Color(red: 0.878, green: 0.718, blue: 0.373)
}

struct WatchRootView: View {
    let store: WatchPrayerStore

    var body: some View {
        if let snapshot = store.snapshot {
            NavigationStack {
                WatchHomeView(snapshot: snapshot, store: store)
            }
            .tint(WatchTheme.gold)
        } else {
            ContentUnavailableView(
                "Open Darul Irfan",
                systemImage: "iphone.and.arrow.forward",
                description: Text("Set up prayer times on your iPhone to sync them here.")
            )
        }
    }
}

private struct WatchHomeView: View {
    let snapshot: PrayerWidgetSnapshot
    let store: WatchPrayerStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                WatchLivingSeal(diameter: 58)
                    .padding(.top, 2)

                Text("Darul Irfan")
                    .font(.headline)
                    .foregroundStyle(WatchTheme.gold)

                TimelineView(.periodic(from: .now, by: 30)) { context in
                    WatchAzanCard(snapshot: snapshot, date: context.date)
                }

                NavigationLink {
                    WatchZikrTimerView(snapshot: snapshot)
                } label: {
                    Label("Zikr timer", systemImage: "heart.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                NavigationLink {
                    WatchPrayerScheduleView(snapshot: snapshot)
                } label: {
                    Label("Prayer times", systemImage: "clock.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                NavigationLink {
                    WatchSettingsView(store: store)
                } label: {
                    Label("Preferences", systemImage: "gearshape.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(snapshot.hijriDateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(snapshot.placeName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WatchAzanCard: View {
    let snapshot: PrayerWidgetSnapshot
    let date: Date

    var body: some View {
        VStack(spacing: 3) {
            if let next = snapshot.nextPrayer(after: date) {
                Label(next.displayName, systemImage: "moon.stars.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WatchTheme.gold)
                Text(next.time, style: .timer)
                    .font(.system(.title2, design: .rounded).weight(.medium).monospacedDigit())
                    .contentTransition(.numericText())
                Text("until azan · \(next.time.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Open the iPhone app to refresh prayer times.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(WatchTheme.deepEmerald.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WatchTheme.gold.opacity(0.42), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct WatchZikrTimerView: View {
    let snapshot: PrayerWidgetSnapshot

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView {
                VStack(spacing: 12) {
                    WatchLivingSeal(diameter: 52)
                    if let zikr = snapshot.currentOrNextZikr(at: context.date) {
                        let active = zikr.isActive(at: context.date)
                        Image(systemName: active ? "dot.radiowaves.left.and.right" : "timer")
                            .font(.title2)
                            .foregroundStyle(active ? WatchTheme.emerald : WatchTheme.gold)
                        Text(active ? "Zikr in progress" : "Zikr begins in")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Text(active ? zikr.endsAt : zikr.startsAt, style: .timer)
                            .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(active ? WatchTheme.emerald : WatchTheme.gold)
                            .contentTransition(.numericText())
                        Text(zikr.title)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                        Text(zikr.startsAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        ContentUnavailableView(
                            "No zikr schedule",
                            systemImage: "arrow.triangle.2.circlepath",
                            description: Text("Open Zikr on your iPhone to sync the latest schedule.")
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Zikr")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WatchPrayerScheduleView: View {
    let snapshot: PrayerWidgetSnapshot

    var body: some View {
        List {
            Section("Today") {
                ForEach(
                    Array(snapshot.times(onSameDayAs: Date()).prefix(7).enumerated()),
                    id: \.offset
                ) { _, prayer in
                    HStack {
                        Text(prayer.displayName)
                        Spacer()
                        Text(prayer.time, style: .time)
                            .monospacedDigit()
                            .foregroundStyle(prayer.isObligatory ? WatchTheme.gold : Color.gray)
                    }
                }
            }
        }
        .navigationTitle("Prayer times")
    }
}

private struct WatchSettingsView: View {
    let store: WatchPrayerStore
    @AppStorage("watchPrayerAlertsEnabled") private var alertsEnabled = false

    var body: some View {
        List {
            Toggle("Prayer alerts", isOn: $alertsEnabled)
                .onChange(of: alertsEnabled) { _, enabled in
                    Task { await store.setPrayerAlertsEnabled(enabled) }
                }
            Text("Prayer calculations and preferences sync privately from your iPhone.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Preferences")
    }
}

private struct WatchLivingSeal: View {
    let diameter: CGFloat
    @State private var rotating = false
    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [WatchTheme.gold.opacity(breathing ? 0.32 : 0.16), .clear],
                        center: .center,
                        startRadius: diameter * 0.35,
                        endRadius: diameter * 0.82
                    )
                )
                .frame(width: diameter * 1.62, height: diameter * 1.62)

            Circle()
                .fill(Color.white.opacity(0.98))
                .frame(width: diameter * 1.055, height: diameter * 1.055)
                .overlay(Circle().stroke(WatchTheme.gold.opacity(0.75), lineWidth: 1))
                .shadow(color: WatchTheme.gold.opacity(breathing ? 0.46 : 0.22), radius: breathing ? 8 : 4)

            Image("BrandEmblem")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())

            Circle()
                .trim(from: 0.02, to: 0.20)
                .stroke(
                    LinearGradient(
                        colors: [.clear, .white, WatchTheme.gold, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .frame(width: diameter * 1.10, height: diameter * 1.10)
                .rotationEffect(.degrees(reduceMotion ? -35 : (rotating ? 325 : -35)))
        }
        .frame(width: diameter * 1.2, height: diameter * 1.2)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                rotating = true
            }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Darul Irfan")
    }
}
