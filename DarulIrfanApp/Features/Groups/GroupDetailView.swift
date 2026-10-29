import SwiftUI

/// One community group: what is live now, its zikr times, its meetings, and
/// what its admins have published. Everything is watched and joined inside
/// the app.
///
/// Members read, watch and join; nothing here was written by another member.
/// The group's admins (and the super admin) also see the Admin section, where
/// they publish, approve forwarded drafts, start a community zikr and arrange
/// meetings - from the phone, without the admin page.
///
/// The page opens on the Halqah's command centre: a glass header with its
/// name, the viewer's role and whether it is live; then the live session,
/// or a countdown to the next zikr; then, for its admins, the tiles they run
/// it from.
@MainActor
struct GroupDetailView: View {
    let group: MemberGroup
    let service: MemberGroupService
    let dependencies: AppDependencies?

    @State private var detail: GroupDetail?
    @State private var posts: [MemberGroupPost] = []
    @State private var drafts: [MemberGroupPost] = []
    @State private var isLoading = true
    @State private var failure: String?
    /// Only one video plays at a time: a tapped video expands in place rather
    /// than every card loading a player at once.
    @State private var playingVideoID: String?
    @State private var room: GroupRoomPass?
    @State private var joining = false
    @State private var joinError: String?
    @State private var sheet: AdminSheet?
    /// The official Daily Zikr, shown in every halqah while it is live.
    @State private var officialLive: LiveBroadcast?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    /// What the session follow runs for: the live session, while the app is
    /// in front or the member listens to the session with the phone locked.
    private struct Following: Equatable {
        let sessionID: String?
        let running: Bool
    }

    /// The member is listening to this Halqah's session in the app's player.
    private var listeningHere: Bool {
        dependencies?.audioPlayer.nowPlaying?.id.hasPrefix("group-recording:") == true
    }

    enum AdminSheet: String, Identifiable {
        case people, post, live, meeting, zikr, duas, history
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                HalqahCommandHeader(
                    name: group.name,
                    description: group.description,
                    role: myRole,
                    liveIsMeeting: liveIsMeeting,
                    facts: headerFacts
                )
                .diAppear()
                if isLoading && detail == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, DISpacing.lg)
                } else if let failure {
                    DICard {
                        VStack(alignment: .leading, spacing: DISpacing.sm) {
                            Text(verbatim: failure).font(.subheadline)
                            Button("Try again") { Task { await load() } }
                                .buttonStyle(.bordered)
                        }
                    }
                } else {
                    officialLiveSection
                    liveSection
                    nextZikrSection
                    if detail?.canManage == true { adminSection }
                    zikrSection
                    meetingsSection
                    postsSection
                }
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .diPageHeading(LocalizedStringKey(group.name))
        // The glass header carries the name; the bar keeps it small.
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        // Not while the app is in the background with other audio playing:
        // that was a request every 15 seconds for nothing.
        .task(id: Following(sessionID: detail?.live?.sessionID, running: scenePhase == .active || listeningHere)) {
            guard scenePhase == .active || listeningHere else { return }
            await followSession()
        }
        .refreshable { await load() }
        .fullScreenCover(item: $room) { pass in
            MeetingRoomView(pass: pass)
        }
        .sheet(item: $sheet, onDismiss: { Task { await load() } }) { sheet in
            NavigationStack {
                switch sheet {
                case .people: GroupPeopleView(groupID: group.id, groupName: group.name, service: service)
                case .post: GroupPostComposer(groupID: group.id, service: service)
                case .live: GroupLiveStarter(groupID: group.id, service: service, meetingsReady: meetingsReady)
                case .meeting: GroupMeetingScheduler(groupID: group.id, service: service)
                case .zikr: GroupZikrEditor(groupID: group.id, service: service)
                case .duas: GroupDuaRequestsView(groupID: group.id, service: service)
                case .history: GroupSessionHistoryView(groupID: group.id, service: service)
                }
            }
        }
    }

    /// Connected services; an older server that does not say is taken as ready.
    private var meetingsReady: Bool { detail?.integrations?.meetings ?? true }
    private var whatsappReady: Bool { detail?.integrations?.whatsappForwarding ?? true }

    // MARK: Header

    /// The viewer's role here. An older server sends no role; one who may
    /// manage the Halqah is then taken as an Admin, as the Halqah list does.
    private var myRole: GroupRole {
        if let role = group.myRole { return role }
        return (detail?.canManage ?? group.canManage ?? false) ? .admin : .member
    }

    /// A meeting (true) or a zikr (false) is live; nil when nothing is. Until
    /// the page has loaded, what the Halqah list said.
    private var liveIsMeeting: Bool? {
        if let detail { return detail.live?.isMeeting }
        return group.isLive == true ? group.liveKind == "meeting" : nil
    }

    /// Facts the page already holds; nothing is asked of the server for them.
    /// The number of people always; then, while live, who is listening, and
    /// otherwise its zikr times and meetings.
    private var headerFacts: [HalqahFact] {
        var facts: [HalqahFact] = []
        if let memberCount = detail?.memberCount {
            facts.append(HalqahFact(id: "members", systemImage: "person.3.fill", text: Text("Members: \(memberCount)")))
        }
        if let live = detail?.live {
            if let listenerCount = live.listeners, listenerCount > 0 {
                facts.append(HalqahFact(id: "listeners", systemImage: "person.2.fill", text: Text("\(listenerCount) listening")))
            }
            return facts
        }
        if let zikrCount = detail?.zikrSessions.count, zikrCount > 0 {
            facts.append(HalqahFact(id: "zikr", systemImage: "clock", text: Text("Zikr times: \(zikrCount)")))
        }
        if let meetingCount = detail?.meetings.count, meetingCount > 0 {
            facts.append(HalqahFact(id: "meetings", systemImage: "calendar", text: Text("Meetings: \(meetingCount)")))
        }
        return facts
    }

    // MARK: Live

    @ViewBuilder
    private var officialLiveSection: some View {
        if let officialLive, officialLive.state == .live, let dependencies {
            LiveBroadcastCard(broadcast: officialLive, audioPlayer: dependencies.audioPlayer,
                              platform: dependencies.officialPlatform)
        }
    }

    @ViewBuilder
    private var liveSection: some View {
        if let live = detail?.live {
            GroupSessionCard(
                live: live, group: group, service: service, canManage: detail?.canManage == true,
                meetingsReady: meetingsReady, audioPlayer: dependencies?.audioPlayer,
                joining: joining, joinError: joinError,
                onJoinRoom: { Task { await join(meetingID: nil) } },
                onChange: { await refreshQuietly() }
            )
        }
    }

    /// While a session is live: follow the group's clock and the admin's
    /// changes every 15 seconds, and check in each minute so the admins see
    /// who is listening.
    private func followSession() async {
        guard detail?.live?.sessionID != nil else { return }
        var tick = 0
        while !Task.isCancelled {
            if tick % 4 == 0 { await service.checkIn(in: group.id) }
            try? await Task.sleep(for: .seconds(15))
            if Task.isCancelled { break }
            await refreshQuietly()
            tick += 1
        }
    }

    // MARK: Next zikr

    /// While nothing is live: the Halqah's next zikr, counting down, with
    /// the Join button that lights once a session begins. It reads the clock
    /// again every half minute, so the ring keeps filling and moves on to the
    /// following zikr when one is over.
    @ViewBuilder
    private var nextZikrSection: some View {
        if detail?.live == nil, let sessions = detail?.zikrSessions, !sessions.isEmpty {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                if let upcoming = HalqahSchedule.nextZikr(in: sessions, at: timeline.date, calculator: dependencies?.prayerCalculation) {
                    HalqahNextZikrCard(
                        upcoming: upcoming, now: timeline.date, groupID: group.id, service: service,
                        onChange: { await refreshQuietly() }
                    )
                }
            }
            .diAppear(delay: 0.05)
        }
    }

    // MARK: Zikr times

    @ViewBuilder
    private var zikrSection: some View {
        if let sessions = detail?.zikrSessions, !sessions.isEmpty {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                DISectionHeader(titleKey: "Halqah Zikr", systemImage: "sparkles")
                ForEach(sessions) { session in
                    GroupZikrRow(session: session, groupID: group.id, dependencies: dependencies,
                                 canManage: detail?.canManage == true) {
                        Task {
                            try? await service.removeZikrSession(session.id, in: group.id)
                            await load()
                        }
                    }
                    .diScrollReveal()
                }
            }
        }
    }

    // MARK: Meetings

    @ViewBuilder
    private var meetingsSection: some View {
        if let meetings = detail?.meetings, !meetings.isEmpty {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                DISectionHeader(titleKey: "Meetings", systemImage: "person.2.wave.2")
                ForEach(meetings) { meeting in
                    meetingCard(meeting)
                        .diScrollReveal()
                }
            }
        }
    }

    /// A meeting: its day, its time in the phone's own time, and Join, lit
    /// while its room is open.
    private func meetingCard(_ meeting: GroupMeeting) -> some View {
        let roomOpen = meetingsReady && meeting.isOpen()
        let layout = typeSize.halqahRowLayout(alignment: .top)
        return VStack(alignment: .leading, spacing: DISpacing.sm) {
            layout {
                HalqahDateTile(date: meeting.startsAt)
                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text(verbatim: meeting.title).font(.headline)
                    Text("Your time: \(ZikrScheduleMath.localTimeText(meeting.startsAt))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.primary)
                    Text(meeting.startsAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DISpacing.sm) { meetingActions(meeting, roomOpen: roomOpen) }
                VStack(spacing: DISpacing.sm) { meetingActions(meeting, roomOpen: roomOpen) }
            }
            if !meetingsReady {
                IntegrationPendingNote("Video meetings: integration in progress. The time is kept, and the room opens here once it is complete.")
            } else if !meeting.isOpen() {
                Text("The room opens ten minutes before the meeting starts.")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
        .halqahCard(tint: roomOpen ? DIColor.primary : DIColor.accent)
    }

    @ViewBuilder
    private func meetingActions(_ meeting: GroupMeeting, roomOpen: Bool) -> some View {
        Button {
            Task { await join(meetingID: meeting.id) }
        } label: {
            Label("Join the meeting", systemImage: "video.fill")
        }
        .buttonStyle(HalqahLiveButtonStyle(isLive: roomOpen))
        .disabled(joining || !meetingsReady || !(meeting.isOpen() || detail?.canManage == true))
        if detail?.canManage == true {
            Button("Cancel meeting", role: .destructive) {
                Task {
                    try? await service.cancelMeeting(meeting.id, in: group.id)
                    await load()
                }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: Admin

    /// The Halqah's command centre, for its admins: going live, then a tile
    /// for each thing they run, each saying what waits in it.
    private var adminSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Halqah admin", systemImage: "person.badge.key")
            Button {
                sheet = .live
            } label: {
                HalqahHeroTileLabel(
                    titleKey: "Go live",
                    subtitle: goLiveLine,
                    systemImage: "dot.radiowaves.left.and.right",
                    isLive: detail?.live != nil
                )
            }
            .buttonStyle(HalqahTileButtonStyle())
            .halqahTileAccessibility(titleKey: "Go live", value: goLiveLine, hintKey: "Starts a zikr or meeting for the whole Halqah.")
            .diAppear(delay: 0.08)
            HalqahTileGrid(items: adminTiles)
                .diAppear(delay: 0.12)
            if !meetingsReady {
                IntegrationPendingNote("Video meetings and leading the zikr live in a room: integration in progress. Meanwhile start a zikr from YouTube or play a recording. Meetings can be scheduled now; their rooms open once it is complete.")
            }
            if !whatsappReady {
                IntegrationPendingNote("Posts forwarded from WhatsApp: integration in progress. Post here directly meanwhile.")
            }
            if !drafts.isEmpty {
                DISectionHeader(titleKey: "Waiting for approval", systemImage: "tray.full")
                ForEach(drafts) { draft in
                    GroupDraftCard(draft: draft) { title, body in
                        try? await service.publishDraft(draft.id, in: group.id, title: title, body: body)
                        await load()
                    } onDiscard: {
                        try? await service.removePost(draft.id, in: group.id)
                        await load()
                    }
                }
            }
        }
    }

    /// What the Go live tile says: what is live now, or what it starts.
    private var goLiveLine: Text {
        if let live = detail?.live {
            let title = live.title ?? (live.isMeeting ? String(localized: "Group meeting") : String(localized: "Halqah Zikr"))
            return Text("Live now: \(title)")
        }
        return Text("Start Halqah zikr or meeting now")
    }

    /// The admin tiles. Each opens the sheet its button always opened; the
    /// line beneath comes from what the page has already loaded.
    private var adminTiles: [HalqahTileItem] {
        let unreadCount = detail?.unreadDuaRequests ?? 0
        let draftCount = drafts.count
        let postLine: Text = draftCount > 0 ? Text("Drafts waiting: \(draftCount)") : Text("Pictures, videos and messages")
        let duaLine: Text = unreadCount > 0 ? Text("\(unreadCount) new") : Text("No new requests")
        var tiles: [HalqahTileItem] = []
        tiles.append(HalqahTileItem(
            id: "people", titleKey: "People", subtitle: Text("Members, admins and invitations"),
            systemImage: "person.2.badge.gearshape", hintKey: "Opens the members, admins and invitations."
        ) { sheet = .people })
        tiles.append(HalqahTileItem(
            id: "post", titleKey: "New post", subtitle: postLine,
            systemImage: "square.and.pencil", badge: draftCount > 0 ? draftCount : nil, isAlive: draftCount > 0,
            hintKey: "Opens a new post for this Halqah."
        ) { sheet = .post })
        tiles.append(HalqahTileItem(
            id: "meeting", titleKey: "Schedule a meeting", subtitle: nextMeetingLine,
            systemImage: "calendar.badge.plus", tint: DIColor.accent, hintKey: "Opens the meeting planner."
        ) { sheet = .meeting })
        tiles.append(HalqahTileItem(
            id: "zikr", titleKey: "Add a zikr time", subtitle: zikrTimesLine,
            systemImage: "clock.badge", hintKey: "Adds a regular zikr time to this Halqah."
        ) { sheet = .zikr })
        tiles.append(HalqahTileItem(
            id: "duas", titleKey: "Dua requests", subtitle: duaLine,
            systemImage: "hands.sparkles", tint: DIColor.accent, badge: unreadCount > 0 ? unreadCount : nil,
            isAlive: unreadCount > 0, hintKey: "Opens the dua requests sent to the admins."
        ) { sheet = .duas })
        tiles.append(HalqahTileItem(
            id: "history", titleKey: "Past sessions", subtitle: Text("Attendance of each session"),
            systemImage: "list.bullet.clipboard", hintKey: "Opens past sessions and who attended them."
        ) { sheet = .history })
        return tiles
    }

    /// The next meeting not yet over, in the phone's own time.
    private var nextMeetingLine: Text {
        let now = Date()
        let upcoming = detail?.meetings.first { meeting in
            meeting.startsAt.addingTimeInterval(TimeInterval(meeting.durationMinutes * 60)) > now
        }
        if let upcoming {
            return Text("Next meeting: \(ZikrScheduleMath.localTimeText(upcoming.startsAt))")
        }
        return Text("No meeting planned")
    }

    /// The next zikr time, in the phone's own time.
    private var zikrTimesLine: Text {
        guard let sessions = detail?.zikrSessions, !sessions.isEmpty else { return Text("No zikr times yet") }
        if let upcoming = HalqahSchedule.nextZikr(in: sessions, at: Date(), calculator: dependencies?.prayerCalculation) {
            return Text("Next zikr: \(ZikrScheduleMath.localTimeText(upcoming.start))")
        }
        let zikrCount = sessions.count
        return Text("Zikr times: \(zikrCount)")
    }

    // MARK: Posts

    @ViewBuilder
    private var postsSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Announcements", systemImage: "megaphone")
            if posts.isEmpty {
                DICard {
                    Text("Nothing has been posted to this group yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(posts) { post in
                postCard(post)
            }
        }
    }

    private func postCard(_ post: MemberGroupPost) -> some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) {
                    Image(systemName: post.kind == .zikr ? "waveform" : "megaphone")
                        .foregroundStyle(DIColor.accent)
                    // A post of pictures alone may have no title.
                    if !post.title.isEmpty {
                        Text(verbatim: post.title)
                            .font(.headline)
                    }
                    Spacer(minLength: 0)
                }
                Text(post.publishedAt, format: .dateTime.day().month(.wide).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let media = post.media, !media.isEmpty {
                    PostMediaView(media: media)
                }
                if let imageURL = post.imageURL {
                    GroupPostImage(url: imageURL)
                }
                if let body = post.body, body != post.title {
                    Text(verbatim: body)
                        .font(.subheadline)
                }
                if let videoID = post.youtubeVideoID {
                    if playingVideoID == videoID {
                        YouTubePlayerView(videoID: videoID)
                            .frame(height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
                    } else {
                        Button {
                            playingVideoID = videoID
                            DIHaptics.light()
                        } label: {
                            Label(post.kind == .zikr ? "Play the recorded zikr" : "Play the video", systemImage: "play.circle.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if let linkURL = post.linkURL {
                    Link(destination: linkURL) {
                        Label("Open link", systemImage: "arrow.up.right.square")
                    }
                    .font(.subheadline)
                }
                if detail?.canManage == true {
                    Button("Remove", role: .destructive) {
                        Task {
                            try? await service.removePost(post.id, in: group.id)
                            await load()
                        }
                    }
                    .font(.footnote)
                }
            }
        }
    }

    // MARK: Behaviour

    private func load() async {
        isLoading = true
        failure = nil
        do {
            var loaded = try await service.detail(of: group.id)
            // The group's clock counts from when the answer arrived here, so a
            // phone whose clock is wrong still plays in step.
            loaded.live?.playback?.at = Date()
            detail = loaded
            posts = try await service.posts(in: group.id)
            drafts = loaded.canManage ? ((try? await service.posts(in: group.id, drafts: true)) ?? []) : []
            officialLive = await dependencies?.officialPlatform.currentLiveBroadcast(forceRefresh: true)
        } catch {
            failure = error.localizedDescription
        }
        isLoading = false
    }

    /// A refresh that never replaces the page with an error, for the
    /// session's own updates.
    private func refreshQuietly() async {
        guard var loaded = try? await service.detail(of: group.id) else { return }
        loaded.live?.playback?.at = Date()
        detail = loaded
    }

    private func join(meetingID: String?) async {
        joining = true
        joinError = nil
        defer { joining = false }
        do {
            room = try await service.join(groupID: group.id, meetingID: meetingID)
        } catch {
            joinError = error.localizedDescription
        }
    }
}

extension GroupRoomPass: Identifiable {
    var id: String { authToken }
}

// MARK: - Next zikr card

/// The member's own card while nothing is live: the next zikr counting down
/// in a ring, its time in the phone's own time, and Join - quiet now, lit in
/// the session card the moment the Halqah goes live. A dua request can be
/// sent from here too; the server takes one at any time.
private struct HalqahNextZikrCard: View {
    let upcoming: HalqahSchedule.Upcoming
    let now: Date
    let groupID: String
    let service: MemberGroupService
    /// Reloads the page after a request is sent, so the admins' count of
    /// new requests is current, as the live card does.
    let onChange: () async -> Void

    @State private var composingDua = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale

    var body: some View {
        let underway = upcoming.start <= now
        let layout = typeSize.halqahRowLayout()
        VStack(alignment: .leading, spacing: DISpacing.md) {
            layout {
                HalqahCountdownRing(start: upcoming.start, since: upcoming.since, now: now)
                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text(underway ? "The zikr time has begun" : "Next zikr")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DIColor.accent)
                    Text(verbatim: upcoming.session.displayTitle(urdu: DIBrand.readsUrdu(locale)))
                        .font(.headline)
                        .foregroundStyle(DIColor.textPrimary)
                    Text("Your time: \(ZikrScheduleMath.localTimeText(upcoming.start))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.primary)
                    scheduleLine
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            // Join opens nothing until the Halqah goes live; the session
            // card then shows it, lit, in its place.
            Button {} label: {
                Label("Join", systemImage: "person.3.fill")
            }
            .buttonStyle(HalqahLiveButtonStyle(isLive: false))
            .disabled(true)
            .accessibilityHint(Text("Opens here when the Halqah goes live."))
            Text("Opens here when the Halqah goes live.")
                .font(.caption)
                .foregroundStyle(DIColor.textMuted)
                .accessibilityHidden(true)
            HalqahTile(item: duaTile, axis: .horizontal)
        }
        .halqahCard(tint: DIColor.accent)
        // The same composer, and the same request, as on the live card.
        .sheet(isPresented: $composingDua, onDismiss: { Task { await onChange() } }) {
            NavigationStack {
                GroupDuaComposer(groupID: groupID, service: service)
            }
        }
    }

    private var duaTile: HalqahTileItem {
        HalqahTileItem(
            id: "dua", titleKey: "Send a dua request",
            subtitle: Text("Only the group's admins see it, and remember it in the dua at the end of the zikr."),
            systemImage: "hands.sparkles", tint: DIColor.accent,
            hintKey: "Sends a dua request to the Halqah's admins."
        ) { composingDua = true }
    }

    /// How the time is set: against a prayer at Dar-ul-Irfan, daily, or on
    /// some days - as its row says.
    @ViewBuilder
    private var scheduleLine: some View {
        if let announcement = ZikrAnchorResolver.announcement(for: upcoming.session) {
            Text(verbatim: announcement)
        } else if ZikrScheduleMath.isDaily(upcoming.session.weekdays) {
            Text("Daily")
        } else {
            Text(verbatim: ZikrScheduleMath.shortWeekdaySymbols(for: upcoming.session.weekdays).joined(separator: " · "))
        }
    }
}

// MARK: - Zikr row

/// One of the group's zikr times, in the phone's own time, with a reminder.
private struct GroupZikrRow: View {
    let session: ZikrSession
    let groupID: String
    let dependencies: AppDependencies?
    let canManage: Bool
    let onRemove: () -> Void

    @State private var reminderOn = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .title3) private var iconBox: CGFloat = 40

    private var resolved: ZikrSession {
        guard let calculator = dependencies?.prayerCalculation else { return session }
        return ZikrAnchorResolver.resolved(session, at: Date(), calculator: calculator)
    }

    private var reminderKey: String { "groupZikrReminder.\(groupID).\(session.id)" }

    var body: some View {
        let current = resolved
        let layout = typeSize.halqahRowLayout(alignment: .top)
        layout {
            Image(systemName: session.zikrAnchor == nil ? "clock.fill" : "moon.stars.fill")
                .font(.headline)
                .foregroundStyle(DIColor.primary)
                .frame(width: iconBox, height: iconBox)
                .background(Circle().fill(DIColor.primary.opacity(0.12)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DISpacing.xs) {
                Text(verbatim: session.displayTitle(urdu: DIBrand.readsUrdu(locale))).font(.headline)
                if let start = ZikrScheduleMath.currentOrNextOccurrence(of: current, at: Date()) {
                    Text("Your time: \(ZikrScheduleMath.localTimeText(start))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.primary)
                }
                if let announcement = ZikrAnchorResolver.announcement(for: session) {
                    Text(verbatim: announcement).font(.caption).foregroundStyle(DIColor.textMuted)
                } else if ZikrScheduleMath.isDaily(session.weekdays) {
                    Text("Daily").font(.caption).foregroundStyle(DIColor.textMuted)
                } else {
                    Text(verbatim: ZikrScheduleMath.shortWeekdaySymbols(for: session.weekdays).joined(separator: " · "))
                        .font(.caption).foregroundStyle(DIColor.textMuted)
                }
                if let autoplay = session.autoplayTitle {
                    Label("Plays by itself: \(autoplay)", systemImage: "play.circle")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                Toggle("Remind me", isOn: $reminderOn)
                    .tint(DIColor.primary)
                    .onChange(of: reminderOn) { _, on in Task { await setReminder(on) } }
                if canManage {
                    Button("Remove this time", role: .destructive, action: onRemove)
                        .font(.footnote)
                }
            }
        }
        .halqahCard()
        .onAppear { reminderOn = UserDefaults.standard.bool(forKey: reminderKey) }
    }

    /// A week of reminders, set again each time this row appears: one
    /// reminder used to fire once and then stay silent until the page was
    /// opened again.
    private func setReminder(_ on: Bool) async {
        UserDefaults.standard.set(on, forKey: reminderKey)
        guard let notifications = dependencies?.notifications else { return }
        if on, await notifications.requestPermission() {
            await ZikrReminders.schedule(
                session,
                id: reminderKey,
                body: String(localized: "Halqah zikr begins soon. Open Darul Irfan to join it."),
                notifications: notifications,
                calculator: dependencies?.prayerCalculation
            )
        } else {
            await notifications.cancelReminder(id: reminderKey)
        }
    }
}

// MARK: - Draft card

/// A forwarded or saved draft, which an admin may tidy before publishing.
private struct GroupDraftCard: View {
    let draft: MemberGroupPost
    let onPublish: (String, String?) async -> Void
    let onDiscard: () async -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var working = false

    init(draft: MemberGroupPost, onPublish: @escaping (String, String?) async -> Void, onDiscard: @escaping () async -> Void) {
        self.draft = draft
        self.onPublish = onPublish
        self.onDiscard = onDiscard
        _title = State(initialValue: draft.title)
        _bodyText = State(initialValue: draft.body ?? "")
    }

    var body: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Label(draft.source == "whatsapp" ? "Forwarded from WhatsApp" : (draft.source == "feed" ? "From the official feed" : "Saved draft"),
                      systemImage: "tray")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DIColor.accent)
                if let imageURL = draft.imageURL {
                    GroupPostImage(url: imageURL)
                }
                TextField("Title", text: $title, axis: .vertical)
                    .font(.headline)
                TextField("Message", text: $bodyText, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(2...10)
                HStack {
                    Button {
                        Task {
                            working = true
                            // Always sent: an emptied message is cleared, not
                            // left out (which kept the forwarded text).
                            await onPublish(title, bodyText)
                            working = false
                        }
                    } label: {
                        Label("Publish to the group", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(working || title.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Discard", role: .destructive) {
                        Task { await onDiscard() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

/// A post's picture, full width, shown as it loads.
private struct GroupPostImage: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .failure:
                Label("The picture could not be loaded. Pull down to refresh.", systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
            default:
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
        .accessibilityLabel(Text("Picture"))
    }
}

/// A feature that waits on an outside service: said plainly, never a broken button.
struct IntegrationPendingNote: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Label(text, systemImage: "hourglass")
            .font(.caption)
            .foregroundStyle(DIColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
