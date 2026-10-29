import AVKit
import SwiftUI

// A Halqah session on the group page: what is playing and where the group is,
// the admin's message, who is listening, dua requests, and - for admins - the
// controls that pause, move and add to it for everyone.

@MainActor
struct GroupSessionCard: View {
    let live: GroupLive
    let group: MemberGroup
    let service: MemberGroupService
    let canManage: Bool
    var meetingsReady = true
    let audioPlayer: (any AudioPlayerServicing)?
    let joining: Bool
    let joinError: String?
    let onJoinRoom: () -> Void
    /// Reloads the page after a change.
    let onChange: () async -> Void

    private enum Sheet: String, Identifiable {
        case notice, dua, listeners, add
        var id: String { rawValue }
    }

    @State private var sheet: Sheet?
    @State private var confirmEnd = false
    @State private var working = false
    @State private var controlError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            header
            if let notice = live.notice {
                HStack(alignment: .top, spacing: DISpacing.sm) {
                    Image(systemName: "megaphone.fill").foregroundStyle(DIColor.primary)
                    Text(verbatim: notice.text).font(.subheadline)
                }
                .padding(DISpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous).fill(DIColor.primary.opacity(0.1)))
                .accessibilityElement(children: .combine)
            }
            if let video = live.videoID {
                YouTubePlayerView(videoID: video)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
            }
            if live.isRecorded, let playback = live.playback {
                recordedSection(playback)
            }
            if live.roomRecording == true {
                Label("Recording. The session is kept in the group's recordings.", systemImage: "record.circle")
                    .font(.caption)
                    .foregroundStyle(DIColor.danger)
            }
            if live.hasRoom {
                // The one button that glows: there is a room to join now.
                Button(action: onJoinRoom) {
                    Label(live.isMeeting ? "Join the meeting" : "Join the zikr together", systemImage: "person.3.fill")
                }
                .buttonStyle(HalqahLiveButtonStyle(isLive: true))
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
            if !live.isMeeting {
                HalqahTile(item: duaTile, axis: .horizontal)
            }
            if canManage { adminControls }
            if let controlError {
                Text(verbatim: controlError).font(.footnote).foregroundStyle(DIColor.danger)
            }
        }
        .padding(DISpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { liveSurface }
        .sheet(item: $sheet, onDismiss: { Task { await onChange() } }) { sheet in
            NavigationStack {
                switch sheet {
                case .notice: GroupNoticeComposer(groupID: group.id, service: service, current: live.notice?.text)
                case .dua: GroupDuaComposer(groupID: group.id, service: service)
                case .listeners: GroupListenersView(attendance: live.attendance ?? [])
                case .add: GroupLiveStarter(groupID: group.id, service: service, meetingsReady: meetingsReady, addingToSession: true)
                }
            }
        }
        .confirmationDialog("End the session for everyone?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End session", role: .destructive) {
                Task {
                    try? await service.endLive(in: group.id)
                    await onChange()
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: live.isMeeting ? "person.2.wave.2.fill" : "dot.radiowaves.left.and.right")
                .font(.headline)
                .foregroundStyle(DIColor.onPrimary)
                .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                .frame(width: 38, height: 38)
                .background(Circle().fill(DIGradient.emerald))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: live.title ?? (live.isMeeting ? String(localized: "Group meeting") : String(localized: "Halqah Zikr")))
                    .font(.headline)
                if let listeners = live.listeners, listeners > 0 {
                    Label("\(listeners) listening", systemImage: "person.2.fill")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
            Spacer(minLength: 0)
            Text("LIVE")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, DISpacing.sm).padding(.vertical, 3)
                .background(Capsule().fill(DIGradient.emerald))
                .foregroundStyle(DIColor.onPrimary)
        }
    }

    /// The session's card: paper, edged in emerald and gold while it is live.
    private var liveSurface: some View {
        let shape = RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
        return HalqahGlassSurface(tint: DIColor.primary)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [DIColor.primary.opacity(0.75), DIColor.accent.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
            }
    }

    /// A member's dua request, during a zikr, as it has always been.
    private var duaTile: HalqahTileItem {
        HalqahTileItem(
            id: "dua", titleKey: "Send a dua request",
            subtitle: Text("Only the group's admins see it, and remember it in the dua at the end of the zikr."),
            systemImage: "hands.sparkles", tint: DIColor.accent,
            hintKey: "Sends a dua request to the Halqah's admins."
        ) { sheet = .dua }
    }

    // MARK: Recorded

    @ViewBuilder
    private func recordedSection(_ playback: GroupPlayback) -> some View {
        if playback.finished {
            Text(canManage
                 ? "Everything has played. Add more, or end the session when the zikr is over."
                 : "The recording has finished. The session stays open until the admin closes it.")
                .font(.subheadline)
                .foregroundStyle(DIColor.textMuted)
        } else if let item = live.currentItem {
            Text("A recording is playing to the group. It plays from where the group is now, so everyone hears the same part.")
                .font(.caption)
                .foregroundStyle(DIColor.textMuted)
            GroupSessionPlayer(
                item: item, upNext: Array((live.queue ?? []).dropFirst(playback.index + 1)),
                playback: playback, groupName: group.name, audioPlayer: audioPlayer
            )
        }
        if let queue = live.queue, queue.count > 1 {
            VStack(alignment: .leading, spacing: DISpacing.xs) {
                Text("In this session").font(.caption.weight(.semibold)).foregroundStyle(DIColor.textMuted)
                ForEach(Array(queue.enumerated()), id: \.offset) { index, item in
                    queueRow(index: index, item: item, playback: playback)
                }
            }
        }
    }

    private func queueRow(index: Int, item: GroupQueueItem, playback: GroupPlayback) -> some View {
        let isCurrent = index == playback.index && !playback.finished
        return HStack(spacing: DISpacing.sm) {
            Image(systemName: isCurrent ? "speaker.wave.2.fill" : (index < playback.index ? "checkmark.circle" : "circle"))
                .foregroundStyle(isCurrent ? DIColor.primary : DIColor.textMuted)
                .frame(width: 20)
            Text(verbatim: item.title)
                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
            if let length = Self.clock(item.durationSeconds.map(Double.init)) {
                Text(verbatim: length).font(.caption).monospacedDigit().foregroundStyle(DIColor.textMuted)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            if canManage {
                Button("Play this now", systemImage: "play.fill") { Task { await control("jump", ["index": index]) } }
                if !isCurrent {
                    Button("Remove from the session", systemImage: "trash", role: .destructive) {
                        Task { await control("remove", ["index": index]) }
                    }
                }
            }
        }
    }

    // MARK: Admin

    @ViewBuilder
    private var adminControls: some View {
        Divider()
        Label("Session controls", systemImage: "slider.horizontal.3")
            .font(.caption.weight(.semibold))
            .foregroundStyle(DIColor.textMuted)
        if live.isRecorded, let playback = live.playback {
            HStack(spacing: DISpacing.xs) {
                controlButton("backward.end.fill", "Previous") { await control("previous") }
                controlButton("gobackward.30", "Back 30 seconds") { await control("skip", ["seconds": -30]) }
                if playback.paused {
                    controlButton("play.fill", "Resume for everyone", prominent: true) { await control("resume") }
                } else {
                    controlButton("pause.fill", "Pause for everyone", prominent: true) { await control("pause") }
                }
                controlButton("goforward.30", "Forward 30 seconds") { await control("skip", ["seconds": 30]) }
                controlButton("forward.end.fill", "Next") { await control("next") }
            }
            .padding(DISpacing.xs)
            .background(Capsule(style: .continuous).fill(DIColor.sandstone.opacity(0.7)))
            Text(playback.paused ? "Paused for everyone." : "These controls move playback for everyone listening.")
                .font(.caption)
                .foregroundStyle(DIColor.textMuted)
        }
        HalqahTileGrid(items: sessionTiles)
        Button(role: .destructive) {
            confirmEnd = true
        } label: {
            Label("End session", systemImage: "stop.circle")
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .tint(DIColor.danger)
    }

    /// The session's admin tiles: each does what its button always did, with
    /// a line from the session the page already follows.
    private var sessionTiles: [HalqahTileItem] {
        var tiles: [HalqahTileItem] = []
        if !live.isMeeting {
            tiles.append(HalqahTileItem(
                id: "add", titleKey: "Add to the session", subtitle: Text("Recordings or past zikr"),
                systemImage: "text.badge.plus", hintKey: "Adds recordings or past zikr to this session."
            ) { sheet = .add })
        }
        if live.hasRoom {
            if live.roomRecording == true {
                tiles.append(HalqahTileItem(
                    id: "record", titleKey: "Stop recording", subtitle: Text("Recording now"),
                    systemImage: "stop.circle", tint: DIColor.danger, isAlive: true,
                    hintKey: "Stops recording the room."
                ) { Task { await control("stopRecording") } })
            } else {
                tiles.append(HalqahTileItem(
                    id: "record", titleKey: "Record the session",
                    systemImage: "record.circle", tint: DIColor.danger,
                    hintKey: "Records the room into the Halqah's recordings."
                ) { Task { await control("record") } })
            }
        }
        let noticeTitle: LocalizedStringKey = live.notice == nil ? "Message the group" : "Change the message"
        let noticeLine: Text = live.notice.map { Text(verbatim: $0.text) } ?? Text("Shown on the session to everyone in the group.")
        tiles.append(HalqahTileItem(
            id: "notice", titleKey: noticeTitle, subtitle: noticeLine,
            systemImage: "megaphone", tint: DIColor.accent,
            hintKey: "Shows a short message to everyone in the session."
        ) { sheet = .notice })
        let hereCount = live.attendance?.filter { $0.isHere == true }.count ?? 0
        tiles.append(HalqahTileItem(
            id: "listeners", titleKey: "Who is listening", subtitle: Text("\(hereCount) here now"),
            systemImage: "person.2.wave.2", hintKey: "Opens who has joined this session."
        ) { sheet = .listeners })
        return tiles
    }

    private func controlButton(
        _ icon: String,
        _ label: LocalizedStringKey,
        prominent: Bool = false,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: icon)
                .font(prominent ? Font.title2.weight(.semibold) : Font.title3)
                .foregroundStyle(prominent ? DIColor.onPrimary : DIColor.primary)
                .frame(maxWidth: .infinity, minHeight: prominent ? 48 : 40)
                .background {
                    if prominent {
                        Capsule(style: .continuous).fill(DIGradient.emerald)
                    } else {
                        Capsule(style: .continuous).fill(DIColor.surface)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(HalqahTileButtonStyle())
        .disabled(working)
        .opacity(working ? 0.55 : 1)
        .accessibilityLabel(Text(label))
    }

    private func control(_ action: String, _ extra: [String: Any] = [:]) async {
        working = true
        controlError = nil
        defer { working = false }
        do {
            try await service.control(action, extra, in: group.id)
            await onChange()
        } catch {
            controlError = error.localizedDescription
        }
    }

    /// "1:05:03" or "4:07".
    static func clock(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3_600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        return formatter.string(from: seconds)
    }
}

// MARK: - Player

/// Plays what the group is playing, where the group is, and follows the
/// admin's pauses and moves. Audio plays in the app's player, so it carries on
/// from the lock screen and other pages.
@MainActor
struct GroupSessionPlayer: View {
    let item: GroupQueueItem
    /// What the group plays after this item, in order.
    var upNext: [GroupQueueItem] = []
    let playback: GroupPlayback
    let groupName: String
    let audioPlayer: (any AudioPlayerServicing)?

    @State private var videoPlayer: AVPlayer?
    @State private var starting = false
    /// Paused because the admin paused, so resumed when the admin resumes; a
    /// member's own pause is left alone.
    @State private var pausedBySession = false
    /// The member chose to listen with the group. It carries them on to the
    /// group's next item after a recording ends, and is dropped when they
    /// stop the player themselves or play something else.
    @State private var listening = false

    private static let prefix = "group-recording:"
    private var audioID: String { Self.prefix + item.id }
    /// The app's player is on the item the group is playing.
    private var playingThisItem: Bool { audioPlayer?.nowPlaying?.id == audioID }
    /// The app's player is on this item, or on one after it that it moved on
    /// to by itself before the page heard the group had.
    private var inAudioPlayer: Bool {
        guard let id = audioPlayer?.nowPlaying?.id else { return false }
        return id == audioID || upNext.contains { Self.prefix + $0.id == id }
    }

    /// The group's clock is at the end of this item.
    private var itemHasEnded: Bool {
        guard let length = item.durationSeconds else { return false }
        return playback.position() >= Double(length) - 5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            Text(verbatim: item.title).font(.subheadline.weight(.semibold))
            if item.isYouTube {
                YouTubePlayerView(
                    videoID: item.videoID ?? item.id,
                    sync: YouTubeSync(position: playback.positionSeconds, paused: playback.paused, at: playback.at)
                )
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
            } else {
                if let videoPlayer {
                    VideoPlayer(player: videoPlayer)
                        .frame(height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
                }
                if videoPlayer != nil || inAudioPlayer {
                    Button {
                        Task { await catchUp() }
                    } label: {
                        Label("Catch up with the group", systemImage: "arrow.uturn.forward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DISecondaryButtonStyle())
                } else {
                    Button {
                        Task { await listen() }
                    } label: {
                        Label(item.isVideoFile ? "Watch together" : "Listen together", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    // A member's way into a recorded session: lit, as Join is.
                    .buttonStyle(HalqahLiveButtonStyle(isLive: true))
                    .disabled(starting || item.url == nil)
                }
            }
            if playback.paused {
                Label("Paused by the admin", systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(progress(at: context.date))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(DIColor.textMuted)
            }
        }
        .onChange(of: playback) { _, _ in Task { await follow() } }
        .onChange(of: item.id) { previous, _ in
            // The player already moved on to this item by itself.
            if playingThisItem { return }
            let nowID = audioPlayer?.nowPlaying?.id
            // Something else plays now: the member moved on, and the group's
            // next item does not take over from it.
            if let nowID, !nowID.hasPrefix(Self.prefix) { listening = false }
            // The group moved on; whoever was listening hears the next item,
            // also when their player stopped at the end of the last one.
            let wasListening = nowID == Self.prefix + previous || videoPlayer != nil || listening
            videoPlayer?.pause()
            videoPlayer = nil
            if wasListening && !item.isYouTube { Task { await listen() } }
            else if wasListening, nowID?.hasPrefix(Self.prefix) == true { audioPlayer?.stop() }
        }
        .onChange(of: audioPlayer?.nowPlaying?.id) { old, new in
            // A recording stopped part-way - the player closed - was the
            // member's choice; one that played to its end was not.
            if old == audioID, new == nil, !itemHasEnded { listening = false }
        }
        .onDisappear { videoPlayer?.pause() }
    }

    private func progress(at date: Date) -> String {
        let elapsed = GroupSessionCard.clock(playback.position(at: date)) ?? ""
        if let total = GroupSessionCard.clock(item.durationSeconds.map(Double.init)) {
            return String(localized: "The group is at \(elapsed) of \(total)")
        }
        return String(localized: "The group is at \(elapsed)")
    }

    private func listen() async {
        guard let url = item.url else { return }
        listening = true
        starting = true
        defer { starting = false }
        if item.isVideoFile || audioPlayer == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            let player = AVPlayer(url: url)
            videoPlayer = player
            await seekWhenReady(player)
            if playback.paused { pausedBySession = true } else { player.play() }
        } else if let audioPlayer {
            let current = AudioPlayableItem(id: audioID, title: item.title, subtitle: groupName, url: url, mediaItemID: nil)
            // The recordings that follow, up to the next video, so the player
            // moves on with the group by itself - with the phone locked too,
            // when this page is not asking the server.
            let following = upNext
                .prefix(while: { !$0.isYouTube && !$0.isVideoFile && $0.url != nil })
                .compactMap { next in
                    next.url.map { AudioPlayableItem(id: Self.prefix + next.id, title: next.title, subtitle: groupName, url: $0, mediaItemID: nil) }
                }
            audioPlayer.play(current, queue: [current] + following)
            await waitForAudio(audioPlayer)
            audioPlayer.seek(to: playback.position())
            if playback.paused {
                if audioPlayer.isPlaying || audioPlayer.isBuffering { audioPlayer.togglePlayPause() }
                pausedBySession = true
            }
        }
    }

    /// Moves playback to where the group is now.
    private func catchUp() async {
        if let videoPlayer {
            await seekWhenReady(videoPlayer)
            if !playback.paused { videoPlayer.play() }
        } else if let audioPlayer, playingThisItem {
            await waitForAudio(audioPlayer)
            audioPlayer.seek(to: playback.position())
            if !playback.paused && !audioPlayer.isPlaying && !audioPlayer.isBuffering { audioPlayer.togglePlayPause() }
        } else if inAudioPlayer {
            // The player is on a later item than the group: back to the group's.
            await listen()
        }
    }

    /// Applies the latest shared clock: the admin's pause, resume or move.
    private func follow() async {
        let target = playback.position()
        if let videoPlayer {
            if playback.paused {
                if videoPlayer.timeControlStatus != .paused { videoPlayer.pause(); pausedBySession = true }
            } else if pausedBySession {
                pausedBySession = false
                await seekWhenReady(videoPlayer)
                videoPlayer.play()
            } else if videoPlayer.timeControlStatus == .playing, abs(videoPlayer.currentTime().seconds - target) > 4 {
                await seekWhenReady(videoPlayer)
            }
        } else if let audioPlayer, playingThisItem {
            if playback.paused {
                if audioPlayer.isPlaying || audioPlayer.isBuffering { audioPlayer.togglePlayPause(); pausedBySession = true }
            } else if pausedBySession {
                pausedBySession = false
                audioPlayer.seek(to: target)
                if !audioPlayer.isPlaying && !audioPlayer.isBuffering { audioPlayer.togglePlayPause() }
            } else if audioPlayer.isPlaying, abs(audioPlayer.currentTime - target) > 4 {
                audioPlayer.seek(to: target)
            }
        }
    }

    /// The length is known once the file has opened; a seek before then is
    /// clamped to nothing.
    private func waitForAudio(_ audioPlayer: any AudioPlayerServicing) async {
        var tries = 0
        while audioPlayer.duration <= 0 && tries < 40 {
            try? await Task.sleep(for: .milliseconds(250))
            tries += 1
        }
    }

    private func seekWhenReady(_ player: AVPlayer) async {
        var tries = 0
        while player.currentItem?.status != .readyToPlay && tries < 40 {
            try? await Task.sleep(for: .milliseconds(250))
            tries += 1
        }
        _ = await player.seek(to: CMTime(seconds: playback.position(), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

// MARK: - Sheets

/// The admin's short message on the session, optionally sent as a notification.
@MainActor
struct GroupNoticeComposer: View {
    let groupID: String
    let service: MemberGroupService
    let current: String?

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var notify = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("For example: Dua in five minutes", text: $text, axis: .vertical)
                    .lineLimit(2...5)
                Toggle("Also send it as a notification", isOn: $notify)
            } footer: {
                Text("Shown on the session to everyone in the group.")
            }
            if let error {
                Section { Text(verbatim: error).foregroundStyle(DIColor.danger) }
            }
            Section {
                Button("Show to the group") { Task { await save(text) } }
                    .disabled(working || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if current != nil {
                    Button("Remove the message", role: .destructive) { Task { await save("") } }
                        .disabled(working)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Message the group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear { text = current ?? "" }
    }

    private func save(_ value: String) async {
        working = true
        defer { working = false }
        do {
            try await service.control("notice", ["text": value.trimmingCharacters(in: .whitespacesAndNewlines), "notify": notify && !value.isEmpty], in: groupID)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A member's dua request to the group's admins.
@MainActor
struct GroupDuaComposer: View {
    let groupID: String
    let service: MemberGroupService

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var showName = true
    @State private var working = false
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        Form {
            if sent {
                Section {
                    Label("Your request was sent to the group's admins.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DIColor.primary)
                }
            } else {
                Section {
                    TextField("Your dua request", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                    Toggle("Include my name", isOn: $showName)
                } footer: {
                    Text("Only the group's admins see it, and remember it in the dua at the end of the zikr.")
                }
                if let error {
                    Section { Text(verbatim: error).foregroundStyle(DIColor.danger) }
                }
                Section {
                    Button("Send") { Task { await send() } }
                        .disabled(working || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Dua request")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(sent ? "Done" : "Cancel") { dismiss() } }
        }
    }

    private func send() async {
        working = true
        defer { working = false }
        do {
            try await service.requestDua(text.trimmingCharacters(in: .whitespacesAndNewlines), showName: showName, in: groupID)
            sent = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Who has joined the session, and who has it open now.
struct GroupListenersView: View {
    let attendance: [GroupAttendee]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if attendance.isEmpty {
                Text("No one has joined yet.").foregroundStyle(DIColor.textMuted)
            }
            ForEach(attendance) { person in
                GroupAttendeeRow(person: person)
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Who is listening")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }
}

struct GroupAttendeeRow: View {
    let person: GroupAttendee

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: person.name)
                Text("Joined \(person.firstSeenAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
            Spacer(minLength: 0)
            if person.isHere == true {
                Text("Here now")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DIColor.primary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The group's dua requests, for its admins: unread first.
@MainActor
struct GroupDuaRequestsView: View {
    let groupID: String
    let service: MemberGroupService

    @Environment(\.dismiss) private var dismiss
    @State private var requests: [GroupDuaRequest]?
    @State private var failed = false

    var body: some View {
        List {
            if let requests {
                if requests.isEmpty {
                    Text("No dua requests.").foregroundStyle(DIColor.textMuted)
                }
                ForEach(requests) { request in
                    VStack(alignment: .leading, spacing: DISpacing.xs) {
                        Text(verbatim: request.text)
                            .foregroundStyle(request.isRead ? DIColor.textMuted : DIColor.textPrimary)
                        HStack {
                            if let name = request.name {
                                Text(verbatim: name)
                            } else {
                                Text("Without a name")
                            }
                            Text(verbatim: "·")
                            Text(verbatim: request.createdAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                        if !request.isRead {
                            Button("Mark as read") { Task { await markRead(request) } }
                                .font(.footnote)
                        }
                    }
                }
            } else if failed {
                Button("Try again") { Task { await load() } }
            } else {
                ProgressView()
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Dua requests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        failed = false
        do { requests = try await service.duaRequests(in: groupID) } catch { failed = true }
    }

    private func markRead(_ request: GroupDuaRequest) async {
        try? await service.markDuaRead(request.id, in: groupID)
        await load()
    }
}

/// Past sessions and how many attended; each opens its attendance.
@MainActor
struct GroupSessionHistoryView: View {
    let groupID: String
    let service: MemberGroupService

    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [GroupSessionRecord]?
    @State private var canDelete = false
    @State private var deleting: GroupSessionRecord?
    @State private var failed = false
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Text(verbatim: error).foregroundStyle(DIColor.danger)
            }
            if let sessions {
                if sessions.isEmpty {
                    Text("No sessions yet. Each one appears here when it ends.").foregroundStyle(DIColor.textMuted)
                }
                if canDelete && !sessions.isEmpty {
                    Text("Swipe a session to delete it.").font(.caption).foregroundStyle(DIColor.textMuted)
                }
                ForEach(sessions) { session in
                    NavigationLink {
                        GroupSessionAttendeesView(groupID: groupID, session: session, service: service)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: session.title ?? String(localized: "Halqah Zikr"))
                            Text(verbatim: session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(DIColor.textMuted)
                            Text("\(session.attendees) attended")
                                .font(.caption)
                                .foregroundStyle(DIColor.textMuted)
                        }
                    }
                    .swipeActions {
                        if canDelete {
                            Button("Delete", role: .destructive) { deleting = session }
                        }
                    }
                }
            } else if failed {
                Button("Try again") { Task { await load() } }
            } else {
                ProgressView()
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Past sessions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .task { await load() }
        .confirmationDialog(
            "Delete this session?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { session in
            Button("Delete", role: .destructive) { Task { await delete(session) } }
        } message: { _ in
            Text("Its attendance and the dua requests sent during it are deleted too.")
        }
    }

    private func load() async {
        failed = false
        do {
            let history = try await service.sessionHistory(in: groupID)
            sessions = history.sessions
            canDelete = history.canDelete == true
        } catch {
            failed = true
        }
    }

    private func delete(_ session: GroupSessionRecord) async {
        do {
            try await service.deleteSessionRecord(session.id, in: groupID)
            error = nil
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

@MainActor
struct GroupSessionAttendeesView: View {
    let groupID: String
    let session: GroupSessionRecord
    let service: MemberGroupService

    @State private var attendees: [GroupAttendee]?

    var body: some View {
        List {
            Section {
                Text(verbatim: "\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) – \(session.endedAt.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(DIColor.textMuted)
            }
            if let attendees {
                if attendees.isEmpty {
                    Text("No one joined in the app.").foregroundStyle(DIColor.textMuted)
                }
                ForEach(attendees) { person in GroupAttendeeRow(person: person) }
            } else {
                ProgressView()
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle(Text(verbatim: session.title ?? String(localized: "Halqah Zikr")))
        .navigationBarTitleDisplayMode(.inline)
        .task { attendees = (try? await service.attendees(of: session.id, in: groupID)) ?? [] }
    }
}
