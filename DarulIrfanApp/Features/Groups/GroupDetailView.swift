import SwiftUI

/// One community group: what is live now, its zikr times, its meetings, and
/// what its admins have published. Everything is watched and joined inside
/// the app.
///
/// Members read, watch and join; nothing here was written by another member.
/// The group's admins (and the super admin) also see the Admin section, where
/// they publish, approve forwarded drafts, start a community zikr and arrange
/// meetings - from the phone, without the admin page.
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

    enum AdminSheet: String, Identifiable {
        case post, live, meeting, zikr
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
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
                    liveSection
                    zikrSection
                    meetingsSection
                    if detail?.canManage == true { adminSection }
                    postsSection
                }
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .diPageHeading(LocalizedStringKey(group.name))
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(item: $room) { pass in
            MeetingRoomView(pass: pass)
        }
        .sheet(item: $sheet, onDismiss: { Task { await load() } }) { sheet in
            NavigationStack {
                switch sheet {
                case .post: GroupPostComposer(groupID: group.id, service: service)
                case .live: GroupLiveStarter(groupID: group.id, service: service, meetingsReady: meetingsReady)
                case .meeting: GroupMeetingScheduler(groupID: group.id, service: service)
                case .zikr: GroupZikrEditor(groupID: group.id, service: service)
                }
            }
        }
    }

    /// Connected services; an older server that does not say is taken as ready.
    private var meetingsReady: Bool { detail?.integrations?.meetings ?? true }
    private var whatsappReady: Bool { detail?.integrations?.whatsappForwarding ?? true }

    // MARK: Live

    @ViewBuilder
    private var liveSection: some View {
        if let live = detail?.live {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    HStack(spacing: DISpacing.sm) {
                        DILivePulse(color: DIColor.primary, size: 9)
                        Text(verbatim: live.title ?? (live.isMeeting ? String(localized: "Group meeting") : String(localized: "Community Zikr")))
                            .font(.headline)
                        Spacer(minLength: 0)
                        Text("LIVE")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, DISpacing.sm).padding(.vertical, 2)
                            .background(Capsule().fill(DIColor.primary))
                            .foregroundStyle(DIColor.onPrimary)
                    }
                    if let video = live.videoID {
                        YouTubePlayerView(videoID: video)
                            .frame(height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
                    }
                    if live.hasRoom {
                        Button {
                            Task { await join(meetingID: nil) }
                        } label: {
                            Label(live.isMeeting ? "Join the meeting" : "Join the zikr together", systemImage: "person.3.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(DIPrimaryButtonStyle())
                        .disabled(joining)
                        Text(live.isMeeting
                             ? "You join with your microphone and camera off; turn them on when you want to speak."
                             : "You join with your microphone off and listen as the zikr is led.")
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                    }
                    if let joinError {
                        Text(verbatim: joinError).font(.footnote).foregroundStyle(DIColor.danger)
                    }
                    if detail?.canManage == true {
                        Button("End live session", role: .destructive) {
                            Task {
                                try? await service.endLive(in: group.id)
                                await load()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    // MARK: Zikr times

    @ViewBuilder
    private var zikrSection: some View {
        if let sessions = detail?.zikrSessions, !sessions.isEmpty {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                DISectionHeader(titleKey: "Community Zikr", systemImage: "sparkles")
                ForEach(sessions) { session in
                    GroupZikrRow(session: session, groupID: group.id, dependencies: dependencies,
                                 canManage: detail?.canManage == true) {
                        Task {
                            try? await service.removeZikrSession(session.id, in: group.id)
                            await load()
                        }
                    }
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
                    DICard {
                        VStack(alignment: .leading, spacing: DISpacing.xs) {
                            Text(verbatim: meeting.title).font(.headline)
                            Text("Your time: \(ZikrScheduleMath.localTimeText(meeting.startsAt))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DIColor.primary)
                            Text(meeting.startsAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(DIColor.textMuted)
                            HStack {
                                Button {
                                    Task { await join(meetingID: meeting.id) }
                                } label: {
                                    Label("Join the meeting", systemImage: "video.fill")
                                }
                                .buttonStyle(.borderedProminent)
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
                            if !meetingsReady {
                                IntegrationPendingNote("Video meetings: integration in progress. The time is kept, and the room opens here once it is complete.")
                            } else if !meeting.isOpen() {
                                Text("The room opens ten minutes before the meeting starts.")
                                    .font(.caption)
                                    .foregroundStyle(DIColor.textMuted)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Admin

    private var adminSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Group admin", systemImage: "person.badge.key")
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    adminButton("New post", "square.and.pencil", .post)
                    adminButton("Start community zikr or meeting now", "dot.radiowaves.left.and.right", .live)
                    adminButton("Schedule a meeting", "calendar.badge.plus", .meeting)
                    adminButton("Add a zikr time", "clock.badge", .zikr)
                    if !meetingsReady {
                        IntegrationPendingNote("Video meetings and joining the zikr together: integration in progress. Meetings can be scheduled now; their rooms open once it is complete.")
                    }
                    if !whatsappReady {
                        IntegrationPendingNote("Posts forwarded from WhatsApp: integration in progress. Post here directly meanwhile.")
                    }
                }
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

    private func adminButton(_ title: LocalizedStringKey, _ icon: String, _ target: AdminSheet) -> some View {
        Button {
            sheet = target
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
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
                    Text(verbatim: post.title)
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                Text(post.publishedAt, format: .dateTime.day().month(.wide).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            let loaded = try await service.detail(of: group.id)
            detail = loaded
            posts = try await service.posts(in: group.id)
            drafts = loaded.canManage ? ((try? await service.posts(in: group.id, drafts: true)) ?? []) : []
        } catch {
            failure = error.localizedDescription
        }
        isLoading = false
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

// MARK: - Zikr row

/// One of the group's zikr times, in the phone's own time, with a reminder.
private struct GroupZikrRow: View {
    let session: ZikrSession
    let groupID: String
    let dependencies: AppDependencies?
    let canManage: Bool
    let onRemove: () -> Void

    @State private var reminderOn = false

    private var resolved: ZikrSession {
        guard let calculator = dependencies?.prayerCalculation else { return session }
        return ZikrAnchorResolver.resolved(session, at: Date(), calculator: calculator)
    }

    private var reminderKey: String { "groupZikrReminder.\(groupID).\(session.id)" }

    var body: some View {
        let current = resolved
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.xs) {
                Text(verbatim: session.title).font(.headline)
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
                Toggle("Remind me", isOn: $reminderOn)
                    .onChange(of: reminderOn) { _, on in Task { await setReminder(on, for: current) } }
                if canManage {
                    Button("Remove this time", role: .destructive, action: onRemove)
                        .font(.footnote)
                }
            }
        }
        .onAppear { reminderOn = UserDefaults.standard.bool(forKey: reminderKey) }
    }

    private func setReminder(_ on: Bool, for session: ZikrSession) async {
        UserDefaults.standard.set(on, forKey: reminderKey)
        guard let notifications = dependencies?.notifications else { return }
        if on, await notifications.requestPermission(),
           let next = ZikrScheduleMath.nextOccurrence(of: session, after: Date()) {
            await notifications.scheduleReminder(
                id: reminderKey,
                title: session.title,
                body: String(localized: "Community zikr begins soon. Open Darul Irfan to join it."),
                at: max(next.addingTimeInterval(-600), Date().addingTimeInterval(5))
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
                            await onPublish(title, bodyText.isEmpty ? nil : bodyText)
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
