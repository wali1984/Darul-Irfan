import AVFoundation
import Observation
import SwiftUI
import UIKit
import UserNotifications

/// Notifications: one screen for every alert and reminder. Permission
/// status; the prayer alerts (per-prayer styles, the pre-prayer and iqamah
/// reminders); the zikr reminders (each session's "10 minutes before" and
/// Daily Zikr going live, the same settings the Zikr tab uses); Halqah
/// notifications; the official alerts and their topics; the event reminders
/// that are set; a test reminder; and the alert sound and full azan.
@MainActor
struct NotificationSettingsView: View {
    private let appState: AppState
    private let dependencies: AppDependencies
    @State private var viewModel: NotificationSettingsViewModel
    @State private var zikrReminders: ZikrReminderSettingsModel
    @State private var halqahNotices: HalqahNoticesModel
    /// Signed in to the private groups on this phone.
    @State private var isHalqahMember = false
    @State private var eventsWithReminders: [CommunityEvent] = []
    @State private var liveAlertsDenied = false
    @State private var officialAlertsDenied = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale

    /// `halqahNotices` is the Halqah tab's own switch, so a change made here
    /// shows on the tab at once; without it the screen uses its own.
    init(dependencies: AppDependencies, appState: AppState, halqahNotices: HalqahNoticesModel? = nil) {
        self.appState = appState
        self.dependencies = dependencies
        _viewModel = State(initialValue: NotificationSettingsViewModel(notifications: dependencies.notifications))
        _zikrReminders = State(initialValue: ZikrReminderSettingsModel(
            notifications: dependencies.notifications,
            calculator: dependencies.prayerCalculation
        ))
        _halqahNotices = State(initialValue: halqahNotices ?? HalqahNoticesModel())
    }

    var body: some View {
        List {
            permissionSection
            alertStylesSection
            preReminderSection
            iqamahSection
            zikrSection
            halqahSection
            officialAlertsSection
            eventRemindersSection
            testReminderSection
            soundSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .toggleStyle(SwitchToggleStyle(tint: DIColor.primary))
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.refresh()
            await loadGathered()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task {
                    await viewModel.refresh()
                    if isHalqahMember { await halqahNotices.refreshState() }
                }
            }
        }
        .onDisappear {
            viewModel.stopFullAzan()
        }
        .alert("Notifications are off", isPresented: $zikrReminders.permissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To receive zikr reminders, please allow notifications for Darul Irfan in iOS Settings.")
        }
        .alert("Notifications are off", isPresented: $liveAlertsDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To be told when Daily Zikr goes live, please allow notifications for Darul Irfan in iOS Settings.")
        }
        .alert("Notifications are disabled", isPresented: $officialAlertsDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow notifications in iOS Settings to receive official live alerts.")
        }
    }

    /// The reminders and notices gathered here from elsewhere, read again
    /// each time the screen shows (a program's reminder may have been
    /// cancelled on its page meanwhile).
    private func loadGathered() async {
        zikrReminders.load()
        isHalqahMember = MemberGroupService.hasSavedSession
        if isHalqahMember {
            // Registers the phone when the switch is turned on, as the
            // Halqah page does.
            if halqahNotices.platform == nil { halqahNotices.platform = dependencies.officialPlatform }
            await halqahNotices.refreshState()
        }
        let events = (try? await dependencies.eventsRepository.events()) ?? []
        eventsWithReminders = EventReminderList.upcomingWithReminders(in: events)
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
                    Task {
                        await viewModel.requestPermission()
                        // Alerts added before permission was given were
                        // rejected, so schedule them now and show the count.
                        if viewModel.permission == .authorized {
                            await appState.refreshScheduledNotificationsAndWidgets()
                            await viewModel.refresh()
                        }
                    }
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
                .foregroundStyle(DIColor.actionForeground)
                .listRowBackground(DIColor.surface)
            case .denied:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("Open Settings to Allow Notifications", systemImage: "gear")
                }
                .foregroundStyle(DIColor.actionForeground)
                .listRowBackground(DIColor.surface)
            case .authorized, .unknown:
                EmptyView()
            }
        } header: {
            SettingsSectionHeader(titleKey: "Permission", systemImage: "checkmark.shield.fill")
        } footer: {
            permissionFooter
        }
    }

    private var permissionIcon: some View {
        Group {
            switch viewModel.permission {
            case .authorized:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DIColor.actionForeground)
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
            SettingsSectionHeader(titleKey: "Prayer Alerts", systemImage: "bell.badge.fill")
        } footer: {
            Text("Silent shows a banner without sound. Azan Clip plays the opening of the azan with the alert.")
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
            SettingsSectionHeader(titleKey: "Pre-Prayer Reminder", systemImage: "clock.badge")
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

    // MARK: - Iqamah

    private var iqamahSection: some View {
        Section {
            ForEach(Prayer.obligatory, id: \.self) { prayer in
                Picker(selection: iqamahBinding(for: prayer)) {
                    ForEach(PrayerNotificationPreferences.iqamahGapChoices, id: \.self) { minutes in
                        iqamahLabel(minutes).tag(minutes)
                    }
                } label: {
                    Text(LocalizedStringKey(prayer.englishName))
                        .foregroundStyle(DIColor.textPrimary)
                }
                .listRowBackground(DIColor.surface)
            }
        } header: {
            SettingsSectionHeader(titleKey: "Iqamah Reminders", systemImage: "person.2.fill")
        } footer: {
            Text("Set how long after the azan your iqamah usually is. You are reminded five minutes before it, whatever the azan alert is set to.")
        }
    }

    private func iqamahLabel(_ minutes: Int) -> Text {
        minutes == 0 ? Text("Off") : Text("\(minutes) minutes after azan")
    }

    private func iqamahBinding(for prayer: Prayer) -> Binding<Int> {
        SettingsBinding.value(
            in: appState,
            get: { $0.prayerNotifications.iqamahGap(for: prayer) },
            set: { settings, minutes in
                var gaps = settings.prayerNotifications.iqamahGaps ?? [:]
                gaps[prayer] = minutes == 0 ? nil : minutes
                settings.prayerNotifications.iqamahGaps = gaps.isEmpty ? nil : gaps
            }
        )
    }

    // MARK: - Zikr reminders

    /// Each official session's reminder ten minutes before, and Daily Zikr
    /// going live: the same settings as the Zikr tab's.
    private var zikrSection: some View {
        Section {
            ForEach(zikrReminders.sessions) { session in
                Toggle(isOn: Binding(
                    get: { zikrReminders.isOn(session) },
                    set: { on in Task { await zikrReminders.set(on, for: session) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: session.displayTitle(urdu: DIBrand.readsUrdu(locale)))
                            .foregroundStyle(DIColor.textPrimary)
                        Text("\(ZikrReminders.leadMinutes) minutes before")
                            .font(.footnote)
                            .foregroundStyle(DIColor.textMuted)
                    }
                }
                .tint(DIColor.primary)
                .listRowBackground(DIColor.surface)
            }
            Toggle(isOn: Binding(
                get: { AlertSettingsRules.dailyZikrLiveIsOn(appState.settings) },
                set: { enabled in
                    Task {
                        let done = await OfficialAlertSwitches.setDailyZikrLive(enabled, dependencies: dependencies, appState: appState)
                        if !done { liveAlertsDenied = true }
                    }
                }
            )) {
                Text("Notify me when Daily Zikr goes live")
                    .foregroundStyle(DIColor.textPrimary)
            }
            .tint(DIColor.primary)
            .listRowBackground(DIColor.surface)
        } header: {
            SettingsSectionHeader(titleKey: "Zikr reminders", systemImage: "sparkles")
        }
    }

    // MARK: - Halqah

    /// The member's Halqah notices on this phone, shown while signed in to
    /// the private groups. The same switch as on the Halqah tab.
    @ViewBuilder
    private var halqahSection: some View {
        if isHalqahMember {
            Section {
                Toggle(isOn: Binding(
                    get: { halqahNotices.status == .on },
                    set: { on in Task { await halqahNotices.set(on) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Halqah notifications")
                            .foregroundStyle(DIColor.textPrimary)
                        Text("Posts, zikr and meetings from your Halqah, on this phone.")
                            .font(.footnote)
                            .foregroundStyle(DIColor.textMuted)
                    }
                }
                .tint(DIColor.primary)
                .disabled(halqahNotices.isChanging)
                .listRowBackground(DIColor.surface)
                if halqahNotices.status == .blocked {
                    Text("Notifications are off for Darul Irfan. Allow them in iOS Settings to receive Halqah notifications.")
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                        .listRowBackground(DIColor.surface)
                }
            } header: {
                SettingsSectionHeader(titleKey: "Halqah", systemImage: "person.3.fill")
            }
        }
    }

    // MARK: - Official alerts

    /// The official live and update alerts and their topics. Daily Zikr
    /// going live, the live zikr topic, is switched with the zikr reminders
    /// above.
    private var officialAlertsSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { appState.settings.push.isEnabled },
                set: { enabled in
                    Task {
                        let done = await OfficialAlertSwitches.setOfficialAlerts(enabled, dependencies: dependencies, appState: appState)
                        if !done { officialAlertsDenied = true }
                    }
                }
            )) {
                Text("Official live and update alerts")
                    .foregroundStyle(DIColor.textPrimary)
            }
            .tint(DIColor.primary)
            .listRowBackground(DIColor.surface)
            if appState.settings.push.isEnabled {
                topicToggle("Broadcasts", topic: .broadcasts)
                topicToggle("Announcements", topic: .announcements)
                topicToggle("Events", topic: .events)
            }
        } header: {
            SettingsSectionHeader(titleKey: "Official Alerts", systemImage: "dot.radiowaves.left.and.right")
        } footer: {
            Text("When enabled, a random installation identifier and Apple push token are registered. No account, precise location, prayer history, or reading activity is sent.")
        }
    }

    /// `LocalizedStringKey`, so the topic names come from the catalogue.
    private func topicToggle(_ title: LocalizedStringKey, topic: PushTopic) -> some View {
        Toggle(isOn: Binding(
            get: { appState.settings.push.topics.contains(topic) },
            set: { enabled in Task { await OfficialAlertSwitches.setTopic(topic, enabled, appState: appState) } }
        )) {
            Text(title)
                .foregroundStyle(DIColor.textPrimary)
        }
        .tint(DIColor.primary)
        .listRowBackground(DIColor.surface)
    }

    // MARK: - Event reminders

    /// The programs with a reminder set, each opening its page, where the
    /// reminder is cancelled.
    @ViewBuilder
    private var eventRemindersSection: some View {
        if !eventsWithReminders.isEmpty {
            Section {
                ForEach(eventsWithReminders) { event in
                    NavigationLink {
                        EventDetailView(event: event, notifications: dependencies.notifications)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: eventTitle(event))
                                .foregroundStyle(DIColor.textPrimary)
                            if let start = event.startDate {
                                Text(verbatim: CommunityEvent.dayText(start, .abbreviated))
                                    .font(.footnote)
                                    .foregroundStyle(DIColor.textMuted)
                            }
                        }
                    }
                    .listRowBackground(DIColor.surface)
                }
            } header: {
                SettingsSectionHeader(titleKey: "Event reminders", systemImage: "calendar")
            }
        }
    }

    private func eventTitle(_ event: CommunityEvent) -> String {
        if DIBrand.readsUrdu(locale), let urdu = event.titleUrdu, !urdu.isEmpty { return urdu }
        return event.title
    }

    // MARK: - Test reminder

    /// Proves the whole path - permission, delivery, sound - in a few
    /// seconds, rather than leaving someone to wait for the next prayer to
    /// find out alerts were never going to arrive.
    private var testReminderSection: some View {
        Section {
            Button {
                Task { await viewModel.sendTestReminder() }
            } label: {
                Label("Send a test reminder", systemImage: "bell.and.waves.left.and.right")
            }
            .disabled(viewModel.permission != .authorized)
            .foregroundStyle(DIColor.actionForeground)
            .listRowBackground(DIColor.surface)
            if viewModel.testReminderSent {
                Text("A test reminder will arrive in about five seconds. Lock the phone or leave the app to see it as you would a prayer alert.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .listRowBackground(DIColor.surface)
            }
        } header: {
            SettingsSectionHeader(titleKey: "Check Alerts", systemImage: "checkmark.bubble.fill")
        }
    }

    // MARK: - Sound

    private var soundSection: some View {
        Section {
            Button {
                viewModel.previewAlertSound()
            } label: {
                Label("Preview Alert Sound", systemImage: "speaker.wave.2.fill")
            }
            .foregroundStyle(DIColor.actionForeground)
            .listRowBackground(DIColor.surface)

            if viewModel.chimeUnavailable {
                Text("The chime preview could not be played right now.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .listRowBackground(DIColor.surface)
            }

            if viewModel.hasFullAzan {
                Button {
                    viewModel.toggleFullAzan(resource: NotificationSettingsViewModel.fullAzanResource)
                } label: {
                    if viewModel.playingAzanResource == NotificationSettingsViewModel.fullAzanResource {
                        Label("Stop Azan", systemImage: "stop.fill")
                    } else {
                        Label("Play Full Azan", systemImage: "play.fill")
                    }
                }
                .foregroundStyle(DIColor.actionForeground)
                .listRowBackground(DIColor.surface)
            }

            if viewModel.hasFajrAzan {
                Button {
                    viewModel.toggleFullAzan(resource: NotificationSettingsViewModel.fajrAzanResource)
                } label: {
                    if viewModel.playingAzanResource == NotificationSettingsViewModel.fajrAzanResource {
                        Label("Stop Azan", systemImage: "stop.fill")
                    } else {
                        Label("Play Fajr Azan", systemImage: "play.fill")
                    }
                }
                .foregroundStyle(DIColor.actionForeground)
                .listRowBackground(DIColor.surface)
            }

            if viewModel.azanUnavailable {
                Text("The azan could not be played right now.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .listRowBackground(DIColor.surface)
            }
        } header: {
            SettingsSectionHeader(titleKey: "Sound", systemImage: "speaker.wave.2.fill")
        } footer: {
            Text("Alerts play a short azan clip so they stay within the iOS notification sound limit. The full azan can be played here inside the app.")
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

    /// Bundle resource names of the licensed full azan recordings
    /// (see Resources/Audio/README.md for sources and licenses).
    static let fullAzanResource = "azan-full"
    static let fajrAzanResource = "azan-fajr-full"

    private let notifications: any NotificationScheduling
    private var chimePlayer: AVAudioPlayer?
    private var azanPlayer: AVAudioPlayer?
    private let azanPlaybackDelegate = AzanPlaybackDelegate()

    private(set) var permission: PermissionState = .unknown
    private(set) var pendingCount: Int?
    private(set) var isRequestingPermission = false
    private(set) var chimeUnavailable = false
    private(set) var azanUnavailable = false
    /// Resource name of the full azan currently playing, if any.
    private(set) var playingAzanResource: String?
    private(set) var testReminderSent = false

    /// Whether the bundled full azan recordings are present; the playback
    /// rows are hidden when the assets are missing.
    let hasFullAzan = Bundle.main.url(forResource: "azan-full", withExtension: "mp3") != nil
    let hasFajrAzan = Bundle.main.url(forResource: "azan-fajr-full", withExtension: "mp3") != nil

    init(notifications: any NotificationScheduling) {
        self.notifications = notifications
        azanPlaybackDelegate.onFinish = { [weak self] in
            Task { @MainActor in
                self?.azanPlaybackDidFinish()
            }
        }
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

    func sendTestReminder() async {
        await notifications.scheduleReminder(
            id: "test-reminder",
            title: String(localized: "Test reminder"),
            body: String(localized: "Prayer alerts from Darul Irfan will arrive like this."),
            at: Date().addingTimeInterval(5)
        )
        testReminderSent = true
        await refresh()
    }

    /// Plays the bundled short azan clip once, in-app, so the user can hear
    /// what the Azan Clip alert style sounds like. Mirrors the lookup order
    /// used by `NotificationScheduler`: `azan-short.caf` first, then the
    /// original `prayer-chime.wav`.
    func previewAlertSound() {
        chimeUnavailable = false
        let clipURL = Bundle.main.url(forResource: "azan-short", withExtension: "caf")
            ?? Bundle.main.url(forResource: "prayer-chime", withExtension: "wav")
        guard let url = clipURL else {
            chimeUnavailable = true
            return
        }
        do {
            // Same reason as the full azan: claim the playback session so the
            // preview is audible with the ringer switch on and is not cut short.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
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

    /// Starts in-app playback of a bundled full azan recording
    /// (`Self.fullAzanResource` or `Self.fajrAzanResource`), or stops it when
    /// the same recording is already playing.
    func toggleFullAzan(resource: String) {
        azanUnavailable = false
        if playingAzanResource == resource {
            stopFullAzan()
            return
        }
        stopFullAzan()
        guard let url = Bundle.main.url(forResource: resource, withExtension: "mp3") else {
            azanUnavailable = true
            return
        }
        do {
            // The azan must own the audio session for its full duration. Without
            // this the player runs in the default (ambient) session: it is
            // silenced by the ringer switch and is cut short as soon as anything
            // else touches the session — which truncated playback a few seconds
            // in, right after "Allahu Akbar".
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = azanPlaybackDelegate
            player.prepareToPlay()
            if player.play() {
                azanPlayer = player
                playingAzanResource = resource
            } else {
                azanUnavailable = true
            }
        } catch {
            azanUnavailable = true
        }
    }

    /// Stops any full azan playback (also called when the view disappears).
    func stopFullAzan() {
        azanPlayer?.stop()
        azanPlayer = nil
        playingAzanResource = nil
    }

    private func azanPlaybackDidFinish() {
        azanPlayer = nil
        playingAzanResource = nil
    }
}

// MARK: - Playback finish bridge

/// Small `NSObject` bridge so the view model can reset its playback state
/// when a full azan recording finishes (`AVAudioPlayerDelegate` requires an
/// `NSObject` conformer). The callback hops to the main actor in the owner.
private final class AzanPlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}
