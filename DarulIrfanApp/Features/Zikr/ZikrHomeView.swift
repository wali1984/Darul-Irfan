import SwiftUI
import UIKit

/// Zikr section entry point, linked from the More tab: a living gradient hero
/// carrying the anchor verse of remembrance, the verified Method of Zikr, the
/// online zikr schedule as live session panels, and the personal tasbih.
@MainActor
struct ZikrHomeView: View {
    @State private var viewModel: ZikrHomeViewModel
    @State private var presentedVideo: ZikrPresentedVideo?
    @State private var liveAlertsDenied = false
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

    private static let liveAnchor = "zikr.live"

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
        _viewModel = State(initialValue: ZikrHomeViewModel(
            notifications: dependencies.notifications,
            platform: dependencies.officialPlatform,
            watchSync: dependencies.watchSync,
            prayerCalculation: dependencies.prayerCalculation
        ))
    }

    var body: some View {
        ScrollViewReader { proxy in
            page
                .onAppear {
                    if let asked = DeepLinkRouter.shared.take(Self.focus(for:)) { focus = asked }
                    scrollToFocus(proxy)
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
            target = viewModel.sessions.first { session in
                session.id == name || session.id.contains(name) || (name == "tahajjud" && ZikrReminders.isTahajjud(session))
            }?.id
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
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                ZikrHeroHeader()
                    .diAppear()
                    .diParallaxHero()

                DISectionHeader(titleKey: "Method of Zikr", systemImage: "heart")
                NavigationLink {
                    NativeMethodOfZikrView(repository: dependencies.contentRepository)
                } label: {
                    MethodOfZikrCard()
                }
                .buttonStyle(DIPressableStyle())
                    .diAppear(delay: 0.05)

                DISectionHeader(titleKey: "Daily Zikr", systemImage: "dot.radiowaves.left.and.right")
                    .id(Self.liveAnchor)
                // The screen keeps the live state current itself (the session
                // cards need it too), so the card does not ask a second time.
                LiveBroadcastCard(broadcast: viewModel.live, audioPlayer: dependencies.audioPlayer)
                    .diAppear(delay: 0.08)
                liveAlertToggle

                // Halqah zikr that admins have started in the member's groups,
                // joined from here as well as from the group itself.
                if !viewModel.liveGroups.isEmpty {
                    DISectionHeader(titleKey: "Halqah Zikr live now", systemImage: "person.3.fill")
                    ForEach(viewModel.liveGroups) { group in
                        NavigationLink {
                            GroupDetailView(group: group, service: groupService, dependencies: dependencies)
                        } label: {
                            LiveHalqahRow(group: group)
                        }
                        .buttonStyle(DIPressableStyle())
                    }
                }

                DISectionHeader(titleKey: "Online Zikr", systemImage: "clock")
                if viewModel.isLoaded && viewModel.sessions.isEmpty {
                    DIElevatedCard {
                        DIEmptyState(
                            systemImage: "clock",
                            titleKey: "Schedule not available",
                            messageKey: "The online zikr schedule could not be loaded. Pull down later to check for a verified update."
                        )
                        .diOctagramWatermark(size: 200, opacity: 0.06)
                    }
                    .diAppear(delay: 0.1)
                } else {
                    ForEach(Array(viewModel.sessions.enumerated()), id: \.element.id) { index, session in
                        ZikrSessionCard(session: session, viewModel: viewModel) { videoID in
                            presentedVideo = ZikrPresentedVideo(id: videoID, title: viewModel.live.title)
                        }
                            .id(session.id)
                            .diAppear(delay: 0.1 + 0.05 * Double(index))
                    }
                }

                if !viewModel.recentBayans.isEmpty {
                    DISectionHeader(titleKey: "Recent Bayans", systemImage: "play.rectangle.on.rectangle")
                    ForEach(Array(viewModel.recentBayans.enumerated()), id: \.element.id) { index, item in
                        Button {
                            DIHaptics.light()
                            if let videoID = item.videoID {
                                presentedVideo = ZikrPresentedVideo(id: videoID, title: item.title)
                            }
                        } label: {
                            BayanRow(item: item)
                        }
                        .buttonStyle(DIPressableStyle())
                        .diAppear(delay: 0.12 + 0.04 * Double(index))
                    }
                }

                DISectionHeader(titleKey: "Tasbih", systemImage: "hand.tap")
                NavigationLink {
                    TasbihListView(
                        trackerRepository: dependencies.trackerRepository,
                        devotionalMetrics: dependencies.devotionalMetrics
                    )
                } label: {
                    tasbihEntryCard
                }
                .buttonStyle(DIPressableStyle())
                .diAppear(delay: 0.2)
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diPageHeading("Zikr")
        .diScreenBackground()
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
    }

    // MARK: - Live alert

    /// The official "Daily Zikr has started" notification. It is the same
    /// consented choice as Settings > Official Alerts, offered where it matters.
    private var liveAlertToggle: some View {
        DICard(padding: DISpacing.sm) {
            Toggle(isOn: Binding(
                get: { appState.settings.push.isEnabled && appState.settings.push.topics.contains(.liveZikr) },
                set: { enabled in Task { await setLiveAlerts(enabled) } }
            )) {
                Label("Notify me when Daily Zikr goes live", systemImage: "bell.badge")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textPrimary)
            }
            .tint(DIColor.primary)
        }
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

    // MARK: - Tasbih entry

    private var tasbihEntryCard: some View {
        DIElevatedCard(tint: DIColor.sandstone) {
            HStack(spacing: DISpacing.md) {
                ZStack {
                    Circle()
                        .fill(DIGradient.emerald)
                        .frame(width: 46, height: 46)
                    Image(systemName: "hand.tap.fill")
                        .font(.title3)
                        .foregroundStyle(DIColor.onPrimary)
                }
                .diGoldGlow(radius: 8, opacity: 0.3)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text("Tasbih Counters")
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                    Text("Count your personal zikr and build a gentle daily habit.")
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
        }
    }
}

// MARK: - Hero

/// A living gradient header carrying Qur'an 13:28 — the verse of remembrance
/// that anchors the whole app and this section in particular.
private struct ZikrHeroHeader: View {
    @Environment(\.locale) private var locale

    var body: some View {
        ZStack(alignment: .topLeading) {
            DIGradient.hero()
                .diPatternOverlay(tint: .white, opacity: 0.07)
                .overlay(alignment: .topTrailing) {
                    DIOctagram(innerRatio: 0.5)
                        .stroke(Color.white, lineWidth: 1.5)
                        .frame(width: 260, height: 260)
                        .opacity(0.06)
                        .offset(x: 70, y: -70)
                }

            VStack(alignment: .leading, spacing: DISpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zikr Allah")
                            .font(DIFont.heading)
                            .foregroundStyle(.white)
                        Text("The remembrance of Allah")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    DILivingSealMark(diameter: 50)
                }

                VStack(alignment: .center, spacing: DISpacing.sm) {
                    Text(DIBrand.anchorVerseArabic)
                        .font(DIFont.quranArabic(scale: 0.78))
                        .foregroundStyle(.white)
                        .diGoldGlow(radius: 12, opacity: 0.5)
                        .environment(\.layoutDirection, .rightToLeft)
                        .multilineTextAlignment(.center)
                    // The Silsila's own translation of 13:28 in the reader's language.
                    if DIBrand.readsUrdu(locale) {
                        Text(verbatim: DIBrand.anchorVerseUrdu)
                            .font(DIFont.urduBody(scale: 0.85))
                            .foregroundStyle(.white.opacity(0.88))
                            .multilineTextAlignment(.center)
                            .environment(\.layoutDirection, .rightToLeft)
                    } else {
                        Text(verbatim: DIBrand.anchorVerseEnglish)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.88))
                            .multilineTextAlignment(.center)
                    }
                    Text(DIBrand.anchorVerseReference)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DIColor.goldGlow)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, DISpacing.xs)
            }
            .padding(DISpacing.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg + 6, style: .continuous))
        .shadow(color: DIColor.primaryDeep.opacity(0.35), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Method of Zikr

/// Verified description only — see Docs/RESEARCH_NOTES.md. The full
/// illustrated instructions are deliberately not reproduced here; they are
/// supplied through the verified content manifest.
private struct MethodOfZikrCard: View {
    var body: some View {
        DIElevatedCard(tint: DIColor.sandstone) {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) {
                    Image(systemName: "heart.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DIColor.primary)
                        .accessibilityHidden(true)
                    Text("Zikr-e Khafi Qalbi")
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                }
                DIJaliDivider(height: 14, opacity: 0.4)
                    .padding(.vertical, DISpacing.xs)
                Text("The method of zikr in the Naqshbandia Owaisiah order is Zikr-e Khafi Qalbi, practised with Pas Anfas — \"guarding every breath\".")
                    .font(.body)
                    .foregroundStyle(DIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A distinguishing feature of this order is spiritual bai'at directly at the hands of the holy Prophet ﷺ — the Owaisiah transmission.")
                    .font(.body)
                    .foregroundStyle(DIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The complete illustrated method is available natively in Darul Irfan.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Open Illustrated Method", systemImage: "book.pages")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DIColor.primary)
                    .padding(.top, DISpacing.xs)
            }
        }
    }
}

// MARK: - Online zikr session card

@MainActor
private struct ZikrSessionCard: View {
    let session: ZikrSession
    let viewModel: ZikrHomeViewModel
    /// Plays the channel's live video in the app.
    let playVideo: (String) -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    /// The app is in Urdu (chosen in the app, or the phone's own language).
    private var inUrdu: Bool { DIBrand.readsUrdu(locale) }

    /// The Tahajjud zikr is held in the Paltalk room; Daily Zikr is joined
    /// through the channel's live video, in the app.
    private var joinsOnPaltalk: Bool {
        session.zikrAnchor == .beforeFajr || session.zikrAnchor == .tahajjud || session.id.contains("tahajjud")
    }

    /// The room is open now and it is before dawn in Pakistan, as the server
    /// names the session; the same room carries Daily Zikr in the evening.
    private var openRoom: LiveRoom? {
        guard joinsOnPaltalk, let room = viewModel.live.room, room.url != nil else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Karachi") ?? .current
        return calendar.component(.hour, from: Date()) < 7 ? room : nil
    }

    /// The channel's live video, while it is on air.
    private var liveVideoID: String? {
        guard !joinsOnPaltalk, viewModel.live.state == .live else { return nil }
        return viewModel.live.sources.first { $0.kind == .youtube && $0.videoID != nil }?.videoID
    }

    var body: some View {
        DIElevatedCard(glow: DIColor.primary) {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) {
                    liveDot
                    Text(verbatim: session.displayTitle(urdu: inUrdu))
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                }

                HStack(spacing: DISpacing.sm) {
                    if ZikrScheduleMath.isDaily(session.weekdays) {
                        DIPillBadge(text: String(localized: "Daily"))
                    } else {
                        DIPillBadge(text: ZikrScheduleMath.shortWeekdaySymbols(for: session.weekdays).joined(separator: " · "))
                    }
                    if session.durationMinutes > 0 {
                        DIPillBadge(text: String(localized: "About \(session.durationMinutes) minutes"), color: DIColor.accent)
                    }
                }

                ZikrSessionCountdown(session: session)

                // Pakistan time is the reference the silsila announces in; the
                // countdown above is already in this phone's own time.
                VStack(alignment: .leading, spacing: 2) {
                    if let announcement = ZikrAnchorResolver.announcement(for: session) {
                        Text(verbatim: announcement)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DIColor.textPrimary)
                    }
                    Group {
                        if session.zikrAnchor == nil {
                            Text("In Pakistan: \(ZikrScheduleMath.announcedTimeText(for: session))")
                        } else {
                            Text("In Pakistan: about \(ZikrScheduleMath.announcedTimeText(for: session))")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                }

                if let note = session.displayAvailabilityNote(urdu: inUrdu) {
                    Text(verbatim: note)
                        .font(.footnote)
                        .italic()
                        .foregroundStyle(DIColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let room = openRoom {
                    Label("Live on Paltalk now · \(room.listeners) listening", systemImage: "person.3.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.primary)
                }
                joinButton

                Toggle(isOn: Binding(
                    get: { viewModel.isReminderEnabled(session.id) },
                    set: { newValue in
                        Task { await viewModel.setReminder(newValue, for: session) }
                    }
                )) {
                    Label("Remind me before each session", systemImage: "bell")
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textPrimary)
                }
                .tint(DIColor.primary)
                .padding(.top, DISpacing.xs)

            }
        }
    }

    /// Always shown; greyed out until the zikr is on: the live video for
    /// Daily Zikr, the open room for the Tahajjud zikr.
    private var joinButton: some View {
        let available = joinsOnPaltalk ? openRoom != nil : liveVideoID != nil
        return Button {
            DIHaptics.light()
            if let url = openRoom?.url { openURL(url) } else if let videoID = liveVideoID { playVideo(videoID) }
        } label: {
            Label(joinsOnPaltalk ? "Join Zikr on Paltalk" : "Join Zikr on YouTube",
                  systemImage: joinsOnPaltalk ? "person.3.fill" : "play.rectangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(available ? DIColor.onPrimary : DIColor.textMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    available ? AnyShapeStyle(DIColor.primary) : AnyShapeStyle(DIColor.sandstone.opacity(0.6)),
                    in: RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                )
        }
        .buttonStyle(DIPressableStyle())
        .disabled(!available)
        .accessibilityHint(available ? Text("")
            : joinsOnPaltalk ? Text("Available when the Paltalk room is open") : Text("Available when the zikr is live on YouTube"))
    }

    private var liveDot: some View {
        Circle()
            .fill(DIColor.primary)
            .frame(width: 9, height: 9)
            .diBreathingGlow(color: DIColor.primary, maxRadius: 8)
            .accessibilityHidden(true)
    }
}

/// Battery-conscious live countdown: SwiftUI's timer text animates the digits
/// while the timeline reevaluates session state only every thirty seconds.
private struct ZikrSessionCountdown: View {
    let session: ZikrSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let start = ZikrScheduleMath.currentOrNextOccurrence(of: session, at: context.date) {
                let end = start.addingTimeInterval(TimeInterval(max(session.durationMinutes, 1) * 60))
                let active = start <= context.date && context.date < end

                HStack(spacing: DISpacing.md) {
                    ZStack {
                        Circle()
                            .fill(active ? DIColor.primary : DIColor.accent.opacity(0.18))
                            .frame(width: 42, height: 42)
                        Image(systemName: active ? "dot.radiowaves.left.and.right" : "timer")
                            .foregroundStyle(active ? Color.white : DIColor.primary)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(active ? "Zikr in progress" : "Zikr begins in")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(active ? DIColor.primary : DIColor.textMuted)
                        Text(active ? end : start, style: .timer)
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(DIColor.textPrimary)
                            .contentTransition(.numericText())
                        Text("Your time: \(ZikrScheduleMath.localTimeText(start))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DIColor.primary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(DISpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                        .fill(active ? DIColor.primary.opacity(0.10) : DIColor.accent.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                        .stroke(active ? DIColor.primary.opacity(0.42) : DIColor.accent.opacity(0.32), lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Live halqah zikr

/// A group of the member's where an admin has started zikr; opens the group,
/// whose live card plays it and holds the room.
private struct LiveHalqahRow: View {
    let group: MemberGroup

    var body: some View {
        DIElevatedCard(glow: DIColor.primary) {
            HStack(spacing: DISpacing.md) {
                DILivePulse(color: DIColor.primary, size: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: group.name)
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                    Text("Zikr is live in this halqah. Tap to join.")
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Recent bayans

private struct ZikrPresentedVideo: Identifiable {
    let id: String
    let title: String
}

/// A tappable video row — thumbnail with a play glyph + title. Opens the
/// in-app YouTube player, so watching a bayan never leaves the app.
private struct BayanRow: View {
    let item: OfficialFeedItem

    var body: some View {
        DICard(padding: DISpacing.sm) {
            HStack(spacing: DISpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous)
                        .fill(DIColor.primaryDeep.opacity(0.12))
                    if let imageURL = item.imageURL {
                        AsyncImage(url: imageURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.clear
                        }
                        .frame(width: 104, height: 62)
                        .clipped()
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 4)
                }
                .frame(width: 104, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous))

                Text(verbatim: item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DIColor.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: item.title))
        .accessibilityAddTraits(.isButton)
    }
}
