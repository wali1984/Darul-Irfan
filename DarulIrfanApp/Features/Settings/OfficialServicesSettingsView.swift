import SwiftUI
import UIKit

/// The former "Official Alerts & Privacy" screen. Settings no longer lists it:
/// the official alerts and their topics are in Settings > Notifications, and
/// the Live Activity and diagnostics in Settings > Privacy. Kept for anything
/// that still links to it; every switch works through `OfficialAlertSwitches`,
/// as those screens' do.
@MainActor
struct OfficialServicesSettingsView: View {
    let dependencies: AppDependencies
    let appState: AppState
    @State private var permissionDenied = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: pushBinding) {
                    Text("Official live and update alerts").diInterfaceFont(.body)
                }.listRowBackground(DIColor.surface)
                Toggle(isOn: liveActivityBinding) {
                    Text("Next-prayer Live Activity").diInterfaceFont(.body)
                }.listRowBackground(DIColor.surface)
            } header: { SettingsSectionHeader(titleKey: "Official Alerts", systemImage: "bell.fill") }
            footer: {
                Text("When enabled, a random installation identifier and Apple push token are registered. No account, precise location, prayer history, or reading activity is sent.")
                    .diInterfaceFont(.footnote)
                    .foregroundStyle(DIColor.textMuted)
            }

            if appState.settings.push.isEnabled {
                Section {
                    topicToggle("Live zikr", topic: .liveZikr)
                    topicToggle("Broadcasts", topic: .broadcasts)
                    topicToggle("Announcements", topic: .announcements)
                    topicToggle("Events", topic: .events)
                } header: { SettingsSectionHeader(titleKey: "Alert Topics", systemImage: "list.bullet") }
            }

            Section {
                Picker(selection: diagnosticsBinding) {
                    Text("Ask me later").diInterfaceFont(.body).tag(DiagnosticsConsent.notAsked)
                    Text("Do not share").diInterfaceFont(.body).tag(DiagnosticsConsent.declined)
                    Text("Share anonymously").diInterfaceFont(.body).tag(DiagnosticsConsent.granted)
                } label: { Text("Share diagnostics").diInterfaceFont(.body) }
                .listRowBackground(DIColor.surface)
            } header: { SettingsSectionHeader(titleKey: "Diagnostics", systemImage: "chart.bar.fill") }
            footer: {
                Text("Anonymous Apple MetricKit diagnostics are uploaded only after consent. Payloads exclude location, bookmarks, prayer history, names, and email addresses, and are retained for 30 days.")
                    .diInterfaceFont(.footnote)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .toggleStyle(SwitchToggleStyle(tint: DIColor.primary))
        .navigationTitle("Official Alerts & Privacy")
        .navigationBarTitleDisplayMode(.inline)
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
                    let done = await OfficialAlertSwitches.setOfficialAlerts(enabled, dependencies: dependencies, appState: appState)
                    if !done { permissionDenied = true }
                }
            }
        )
    }

    private var diagnosticsBinding: Binding<DiagnosticsConsent> {
        Binding(
            get: { appState.settings.diagnosticsConsent },
            set: { consent in
                Task { await OfficialAlertSwitches.setDiagnostics(consent, dependencies: dependencies, appState: appState) }
            }
        )
    }

    private var liveActivityBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.liveActivitiesEnabled },
            set: { enabled in
                // updateSettings starts or ends the Live Activity itself.
                Task { await OfficialAlertSwitches.setLiveActivity(enabled, appState: appState) }
            }
        )
    }

    /// `LocalizedStringKey`, so the topic names come from the catalogue: a
    /// `String` title is shown as written, in English.
    private func topicToggle(_ title: LocalizedStringKey, topic: PushTopic) -> some View {
        Toggle(isOn: Binding(
            get: { appState.settings.push.topics.contains(topic) },
            set: { enabled in
                Task { await OfficialAlertSwitches.setTopic(topic, enabled, appState: appState) }
            }
        )) { Text(title).diInterfaceFont(.body) }
        .listRowBackground(DIColor.surface)
    }
}
