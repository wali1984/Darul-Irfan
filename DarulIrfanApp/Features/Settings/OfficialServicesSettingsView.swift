import SwiftUI
import UIKit

@MainActor
struct OfficialServicesSettingsView: View {
    let dependencies: AppDependencies
    let appState: AppState
    @State private var permissionDenied = false

    var body: some View {
        Form {
            Section {
                Toggle("Official live and update alerts", isOn: pushBinding)
                Toggle("Next-prayer Live Activity", isOn: liveActivityBinding)
            } header: { Text("Official Alerts") }
            footer: {
                Text("When enabled, a random installation identifier and Apple push token are registered. No account, precise location, prayer history, or reading activity is sent.")
            }

            if appState.settings.push.isEnabled {
                Section("Alert Topics") {
                    topicToggle("Live zikr", topic: .liveZikr)
                    topicToggle("Broadcasts", topic: .broadcasts)
                    topicToggle("Announcements", topic: .announcements)
                    topicToggle("Events", topic: .events)
                }
            }

            Section {
                Picker("Share diagnostics", selection: diagnosticsBinding) {
                    Text("Ask me later").tag(DiagnosticsConsent.notAsked)
                    Text("Do not share").tag(DiagnosticsConsent.declined)
                    Text("Share anonymously").tag(DiagnosticsConsent.granted)
                }
            } header: { Text("Diagnostics") }
            footer: {
                Text("Anonymous Apple MetricKit diagnostics are uploaded only after consent. Payloads exclude location, bookmarks, prayer history, names, and email addresses, and are retained for 30 days.")
            }
        }
        .navigationTitle("Official Alerts & Privacy")
        .alert("Notifications are disabled", isPresented: $permissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Allow notifications in iOS Settings to receive official live alerts.") }
    }

    private var pushBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.push.isEnabled },
            set: { enabled in
                Task {
                    if enabled {
                        let granted = await dependencies.notifications.requestPermission()
                        guard granted else { permissionDenied = true; return }
                        await appState.updateSettings { $0.push.isEnabled = true }
                        UIApplication.shared.registerForRemoteNotifications()
                    } else {
                        await appState.updateSettings { $0.push.isEnabled = false }
                        await dependencies.officialPlatform.unregisterFromPush()
                    }
                }
            }
        )
    }

    private var diagnosticsBinding: Binding<DiagnosticsConsent> {
        Binding(
            get: { appState.settings.diagnosticsConsent },
            set: { consent in
                Task {
                    await appState.updateSettings { $0.diagnosticsConsent = consent }
                    await dependencies.officialPlatform.setConsent(consent)
                }
            }
        )
    }

    private var liveActivityBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.liveActivitiesEnabled },
            set: { enabled in
                Task {
                    await appState.updateSettings { $0.liveActivitiesEnabled = enabled }
                    await appState.refreshScheduledNotificationsAndWidgets()
                }
            }
        )
    }

    private func topicToggle(_ title: String, topic: PushTopic) -> some View {
        Toggle(title, isOn: Binding(
            get: { appState.settings.push.topics.contains(topic) },
            set: { enabled in
                Task {
                    await appState.updateSettings { settings in
                        if enabled { settings.push.topics.insert(topic) }
                        else { settings.push.topics.remove(topic) }
                    }
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        ))
    }
}
