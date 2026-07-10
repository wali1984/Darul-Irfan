import AVFoundation
import Observation
import SwiftUI
import UIKit
import UserNotifications

/// Notification settings: permission status, per-prayer alert styles,
/// a shared pre-prayer reminder, and a chime preview.
@MainActor
struct NotificationSettingsView: View {
    private let appState: AppState
    @State private var viewModel: NotificationSettingsViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(dependencies: AppDependencies, appState: AppState) {
        self.appState = appState
        _viewModel = State(initialValue: NotificationSettingsViewModel(notifications: dependencies.notifications))
    }

    var body: some View {
        List {
            permissionSection
            alertStylesSection
            preReminderSection
            soundSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.refresh()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task { await viewModel.refresh() }
            }
        }
    }

    // MARK: - Permission

    private var permissionSection: some View {
        Section {
            HStack(spacing: DISpacing.sm) {
                permissionIcon
                permissionText
                    .foregroundStyle(DIColor.textPrimary)
                Spacer(minLength: 0)
            }
            .listRowBackground(DIColor.surface)

            switch viewModel.permission {
            case .notDetermined:
                Button {
                    Task { await viewModel.requestPermission() }
                } label: {
                    HStack {
                        Text("Allow Notifications")
                        Spacer()
                        if viewModel.isRequestingPermission {
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isRequestingPermission)
                .foregroundStyle(DIColor.primary)
                .listRowBackground(DIColor.surface)
            case .denied:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("Open Settings to Allow Notifications", systemImage: "gear")
                }
                .foregroundStyle(DIColor.primary)
                .listRowBackground(DIColor.surface)
            case .authorized, .unknown:
                EmptyView()
            }
        } header: {
            Text("Permission")
        } footer: {
            permissionFooter
        }
    }

    private var permissionIcon: some View {
        Group {
            switch viewModel.permission {
            case .authorized:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DIColor.primary)
            case .denied:
                Image(systemName: "bell.slash.fill")
                    .foregroundStyle(DIColor.danger)
            case .notDetermined, .unknown:
                Image(systemName: "bell")
                    .foregroundStyle(DIColor.textMuted)
            }
        }
        .accessibilityHidden(true)
    }

    private var permissionText: Text {
        switch viewModel.permission {
        case .authorized:
            return Text("Notifications are allowed")
        case .denied:
            return Text("Notifications are turned off")
        case .notDetermined:
            return Text("Permission has not been requested yet")
        case .unknown:
            return Text("Checking notification permission")
        }
    }

    @ViewBuilder
    private var permissionFooter: some View {
        switch viewModel.permission {
        case .authorized:
            if let count = viewModel.pendingCount {
                Text("\(count) alerts are currently scheduled on this device. Open the app now and then to keep the schedule fresh.")
            } else {
                Text("Alerts are scheduled locally on this device.")
            }
        case .denied:
            Text("Prayer alerts stay silent until notifications are allowed in the Settings app.")
        case .notDetermined, .unknown:
            Text("Darul Irfan uses notifications only for prayer alerts and the reminders you set.")
        }
    }

    // MARK: - Per-prayer styles

    private var alertStylesSection: some View {
        Section {
            ForEach(Prayer.allCases) { prayer in
                Picker(selection: styleBinding(for: prayer)) {
                    ForEach(PrayerAlertStyle.allCases) { style in
                        Text(LocalizedStringKey(style.englishName)).tag(style)
                    }
                } label: {
                    Text(LocalizedStringKey(prayer.englishName))
                        .foregroundStyle(DIColor.textPrimary)
                }
                .listRowBackground(DIColor.surface)
            }
        } header: {
            Text("Prayer Alerts")
        } footer: {
            Text("Silent shows a banner without sound. Azan Clip plays a short chime with the alert.")
        }
    }

    private func styleBinding(for prayer: Prayer) -> Binding<PrayerAlertStyle> {
        SettingsBinding.value(
            in: appState,
            get: { $0.prayerNotifications.style(for: prayer) },
            set: { settings, style in settings.prayerNotifications.styles[prayer] = style }
        )
    }

    // MARK: - Pre-prayer reminder

    private var preReminderSection: some View {
        Section {
            Picker(selection: preReminderBinding) {
                ForEach(PrePrayerReminder.allCases) { reminder in
                    reminderLabel(reminder).tag(reminder)
                }
            } label: {
                Text("Remind Me Before Each Prayer")
                    .foregroundStyle(DIColor.textPrimary)
            }
            .listRowBackground(DIColor.surface)
        } header: {
            Text("Pre-Prayer Reminder")
        } footer: {
            Text("A gentle heads-up before Fajr, Dhuhr, Asr, Maghrib and Isha.")
        }
    }

    private func reminderLabel(_ reminder: PrePrayerReminder) -> Text {
        if reminder == .off {
            return Text("Off")
        }
        return Text("\(reminder.rawValue) minutes before")
    }

    private var preReminderBinding: Binding<PrePrayerReminder> {
        SettingsBinding.value(
            in: appState,
            get: { $0.prayerNotifications.preReminder(for: .fajr) },
            set: { settings, reminder in
                for prayer in Prayer.obligatory {
                    settings.prayerNotifications.preReminders[prayer] = reminder
                }
            }
        )
    }

    // MARK: - Sound

    private var soundSection: some View {
        Section {
            Button {
                viewModel.previewChime()
            } label: {
                Label("Preview Chime", systemImage: "speaker.wave.2.fill")
            }
            .foregroundStyle(DIColor.primary)
            .listRowBackground(DIColor.surface)

            if viewModel.chimeUnavailable {
                Text("The chime preview could not be played right now.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .listRowBackground(DIColor.surface)
            }
        } header: {
            Text("Sound")
        } footer: {
            Text("Alerts use this short chime so they stay within the iOS notification sound limit. Full recitations can be played inside the app.")
        }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class NotificationSettingsViewModel {
    enum PermissionState {
        case unknown
        case notDetermined
        case denied
        case authorized
    }

    private let notifications: any NotificationScheduling
    private var chimePlayer: AVAudioPlayer?

    private(set) var permission: PermissionState = .unknown
    private(set) var pendingCount: Int?
    private(set) var isRequestingPermission = false
    private(set) var chimeUnavailable = false

    init(notifications: any NotificationScheduling) {
        self.notifications = notifications
    }

    /// Reads the system authorization status directly because
    /// `NotificationScheduling` exposes only a request call; this keeps the
    /// keystone protocol untouched.
    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            permission = .notDetermined
        case .denied:
            permission = .denied
        case .authorized, .provisional, .ephemeral:
            permission = .authorized
        @unknown default:
            permission = .unknown
        }
        if permission == .authorized {
            pendingCount = await notifications.pendingCount()
        } else {
            pendingCount = nil
        }
    }

    func requestPermission() async {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        _ = await notifications.requestPermission()
        isRequestingPermission = false
        await refresh()
    }

    /// Plays the bundled prayer chime once, in-app, so the user can hear what
    /// the Azan Clip alert style sounds like.
    func previewChime() {
        chimeUnavailable = false
        guard let url = Bundle.main.url(forResource: "prayer-chime", withExtension: "wav") else {
            chimeUnavailable = true
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            if player.play() {
                chimePlayer = player
            } else {
                chimeUnavailable = true
            }
        } catch {
            chimeUnavailable = true
        }
    }
}
