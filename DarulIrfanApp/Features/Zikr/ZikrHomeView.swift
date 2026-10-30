import SwiftUI
import UIKit

/// The Zikr tab: practice, live sessions and the member's own zikr. At its
/// head Qur'an 13:28, centred; then Daily Zikr, one card for the broadcast
/// and its session (YouTube only, played in the app); the Tahajjud zikr,
/// joined on Paltalk; any halqah where zikr is live now; the member's own
/// practice (Tasbih and the illustrated Method of Zikr); and the recent
/// bayans.
@MainActor
struct ZikrHomeView: View {
    @State private var viewModel: ZikrHomeViewModel
    @State private var presentedVideo: ZikrPresentedVideo?
    @State private var liveAlertsDenied = false
    @State private var isSearchPresented = false
    /// What a notification or a link asked this screen to show.
    @State private var focus: Focus?
    @Environment(\.scenePhase) private var scenePhase
    private let dependencies: AppDependencies
    private let appState: AppState
    private let groupService = MemberGroupService()

    private enum Focus: Equatable {
        /// The Daily Zikr broadcast.
        case live
        /// An online zikr session, by its id or a word of it ("tahajjud").
        case session(String)
        /// The screen itself.
        case top
    }

    /// The Daily Zikr card, where a link to the broadcast, or to Daily
    /// Zikr's own session, scrolls.
    private static let liveAnchor = "zikr.live"

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
        _viewModel = State(initialValue: ZikrHomeViewModel(
            notifications: dependencies.notifications,
            platform: dependencies.officialPlatform,
            watchSync: dependencies.watchSync,
            prayerCalculation: dependencies.prayerCalculation,
            trackerRepository: dependencies.trackerRepository
        ))
    }

    var body: some View {
        ScrollViewReader { proxy in
            page
                .onAppear {
                    if let asked = DeepLinkRouter.shared.take(Self.focus(for:)) { focus = asked }
                    scrollToFocus(proxy)
                    // Also on returning from the counters, so the tile shows
                    // the count left there.
                    Task { await viewModel.refreshPractice() }
                }
                .onChange(of: viewModel.isLoaded) { _, _ in scrollToFocus(proxy) }
        }
    }

    private static func focus(for route: AppRoute) -> Focus? {
        switch route {
        case .live: return .live
        case .zikr(let session): return session.map { .session($0) } ?? .top
        default: return nil
        }
    }

    /// Brings what was asked for into view. A session waits for the
    /// schedule, which arrives with the first load.
    private func scrollToFocus(_ proxy: ScrollViewProxy) {
        guard let focus else { return }
        let target: String?
        switch focus {
        case .top:
            target = nil
        case .live:
            target = Self.liveAnchor
        case .session(let name):
            guard viewModel.isLoaded else { return }
            target = ZikrSessionRoles.scrollTarget(
                forSessionNamed: name,
                in: viewModel.sessions,
                dailyTarget: Self.liveAnchor
            )
        }
        self.focus = nil
        guard let target else { return }
        Task { @MainActor in
            // Once the page is laid out.
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeInOut) { proxy.scrollTo(target, anchor: .top) }
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                ZikrAyahBlock()
                    .diAppear()

                dailyZikrCard
                    .id(Self.liveAnchor)
                    .diAppear(delay: 0.06)

                if viewModel.isLoaded && viewModel.sessions.isEmpty {
                    scheduleUnavailable
                        .diAppear(delay: 0.1)
                }

                // The Tahajjud zikr, and any further session published.
                ForEach(Array(viewModel.otherSessions.enumerated()), id: \.element.id) { index, session in
                    ZikrSessionPanel(
                        session: session,
                        live: viewModel.live,
                        reminder: reminderBinding(for: session),
                        playVideo: { videoID in playLiveVideo(videoID) }
                    )
                    .id(session.id)
                    .diAppear(delay: 0.1 + 0.04 * Double(index))
                }

                liveHalqahs

                DISectionHeader(titleKey: "Your practice", systemImage: "heart")
                    .padding(.top, DISpacing.xs)
                practiceTiles
                    .diAppear(delay: 0.16)

                // Recent Bayans stay on the Zikr tab (owner).
                if !viewModel.recentBayans.isEmpty {
                    bayansHeader
                        .padding(.top, DISpacing.xs)
                    ZikrBayanCarousel(items: viewModel.recentBayans) { item in
                        if let videoID = item.videoID {
                            presentedVideo = ZikrPresentedVideo(id: videoID, title: item.title)
                        }
                    }
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diPageHeading("Zikr")
        .diScreenBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isSearchPresented = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel(Text("Search"))
            }
        }
        .task { await viewModel.load() }
        // Followed while the app is in front only: in the background, with a
        // lecture playing, this screen kept asking the server for nothing.
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await viewModel.followLiveGroups(service: groupService)
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await viewModel.followLive()
        }
        .refreshable {
            await viewModel.load(forceRefresh: true)
            await viewModel.refreshLiveGroups(service: groupService)
        }
        .alert("Notifications are off", isPresented: $viewModel.showPermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To receive zikr reminders, please allow notifications for Darul Irfan in iOS Settings.")
        }
        .alert("Notifications are off", isPresented: $liveAlertsDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To be told when Daily Zikr goes live, please allow notifications for Darul Irfan in iOS Settings.")
        }
        .sheet(item: $presentedVideo) { video in
            YouTubePlayerSheet(videoID: video.id, title: video.title)
        }
        .sheet(isPresented: $isSearchPresented) {
            GlobalSearchView(dependencies: dependencies, appState: appState)
        }
    }

    // MARK: - Daily Zikr

    /// The screen keeps the live state current itself (the session panels
    /// need it too), so the card does not ask a second time.
    private var dailyZikrCard: some View {
        let session = viewModel.dailySession
        return DailyZikrCard(
            broadcast: viewModel.live,
            session: session,
            recordings: viewModel.recordedZikr,
            alertsWhenLive: liveAlertsBinding,
            reminderBeforeSession: session.map { reminderBinding(for: $0) },
            join: { source in joinDailyZikr(source) },
            playRecording: { item in
                if let videoID = item.videoID {
                    presentedVideo = ZikrPresentedVideo(id: videoID, title: item.title)
                }
            }
        )
    }

    /// Plays Daily Zikr in the app: the room's own sound when staff relay
    /// it, the channel's live video otherwise.
    private func joinDailyZikr(_ source: LiveSource) {
        switch source.kind {
        case .ownedStream:
            let title = DailyZikrPresentation.headline(for: viewModel.live).title
            let item = AudioPlayableItem(id: "official-live", title: title, subtitle: "Darul Irfan", url: source.url)
            dependencies.audioPlayer.play(item, queue: [item])
        case .youtube:
            if let videoID = source.videoID { playLiveVideo(videoID) }
        case .paltalk:
            // The Paltalk room is the Tahajjud zikr's; Daily Zikr is YouTube only.
            break
        }
    }

    private func playLiveVideo(_ videoID: String) {
        presentedVideo = ZikrPresentedVideo(id: videoID, title: DailyZikrPresentation.headline(for: viewModel.live).title)
    }

    // MARK: - Reminders

    /// The official "Daily Zikr has started" notification. It is the same
    /// consented choice as Settings > Official Alerts, offered where it matters.
    private var liveAlertsBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.push.isEnabled && appState.settings.push.topics.contains(.liveZikr) },
            set: { enabled in Task { await setLiveAlerts(enabled) } }
        )
    }

    /// The local reminder before each of a session's starts.
    private func reminderBinding(for session: ZikrSession) -> Binding<Bool> {
        Binding(
            get: { viewModel.isReminderEnabled(session.id) },
            set: { enabled in Task { await viewModel.setReminder(enabled, for: session) } }
        )
    }

    private func setLiveAlerts(_ enabled: Bool) async {
        if enabled {
            guard await dependencies.notifications.requestPermission() else { liveAlertsDenied = true; return }
            await appState.updateSettings {
                $0.push.isEnabled = true
                $0.push.topics.insert(.liveZikr)
                $0.push.consentVersion = PushPreferences.currentConsentVersion
            }
        } else {
            await appState.updateSettings {
                $0.push.topics.remove(.liveZikr)
                $0.push.consentVersion = PushPreferences.currentConsentVersion
            }
        }
        // Registration carries the topics, so a change is sent the same way.
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - Sections

    private var scheduleUnavailable: some View {
        DIEmptyState(
            systemImage: "clock",
            titleKey: "Schedule not available",
            messageKey: "The online zikr schedule could not be loaded. Pull down later to check for a verified update."
        )
        .diOctagramWatermark(size: 200, opacity: 0.06)
        .frame(maxWidth: .infinity)
        .diGlassPanel(cornerRadius: 26)
    }

    /// Halqah zikr that admins have started in the member's groups, joined
    /// from here as well as from the group itself. Shown only while live; a
    /// session ends only when an admin ends it, never here.
    @ViewBuilder
    private var liveHalqahs: some View {
        if !viewModel.liveGroups.isEmpty {
            DISectionHeader(titleKey: "Halqah Zikr live now", systemImage: "person.3.fill")
                .padding(.top, DISpacing.xs)
            ForEach(viewModel.liveGroups) { group in
                NavigationLink {
                    GroupDetailView(group: group, service: groupService, dependencies: dependencies)
                } label: {
                    LiveHalqahRow(group: group)
                }
                .buttonStyle(DIPressableStyle())
            }
        }
    }

    /// Tasbih (the counters) and the illustrated Method of Zikr.
    private var practiceTiles: some View {
        HStack(alignment: .top, spacing: 10) {
            NavigationLink {
                TasbihListView(
                    trackerRepository: dependencies.trackerRepository,
                    devotionalMetrics: dependencies.devotionalMetrics
                )
            } label: {
                ZikrTasbihTile(practice: viewModel.practice)
            }
            .buttonStyle(DIPressableStyle())

            NavigationLink {
                NativeMethodOfZikrView(repository: dependencies.contentRepository)
            } label: {
                ZikrMethodTile()
            }
            .buttonStyle(DIPressableStyle())
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "Recent Bayans", with See all to Discover › Bayans (the `media` route).
    private var bayansHeader: some View {
        HStack(spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Recent Bayans", systemImage: "play.rectangle.on.rectangle")
            Button {
                DIHaptics.soft()
                DeepLinkRouter.shared.open(.media)
            } label: {
                Text("See all")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DIColor.primary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Live halqah zikr

/// A group of the member's where an admin has started zikr; opens the group,
/// whose live card plays it and holds the room.
private struct LiveHalqahRow: View {
    let group: MemberGroup

    var body: some View {
        HStack(spacing: DISpacing.md) {
            DILivePulse(color: DIColor.primary, size: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: group.name)
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                Text("Zikr is live in this halqah. Tap to join.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.footnote)
                .foregroundStyle(DIColor.textMuted)
                .accessibilityHidden(true)
        }
        .padding(DISpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .diGlassPanel(cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Video sheet

private struct ZikrPresentedVideo: Identifiable {
    let id: String
    let title: String
}
