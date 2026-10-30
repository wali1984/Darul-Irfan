import AudioToolbox
import SwiftUI

struct LiveBroadcastCard: View {
    let broadcast: LiveBroadcast
    let audioPlayer: any AudioPlayerServicing
    /// When given, the card checks the live state every 30 seconds while it is
    /// on screen, so the in-app player appears the moment the stream starts.
    var platform: OfficialPlatformService? = nil
    /// The channel's recordings of earlier sessions, listed under the Join
    /// button and folded away until opened (the Zikr tab passes them).
    var recordings: [OfficialFeedItem] = []
    @State private var presentedVideo: PresentedVideo?
    @State private var latest: LiveBroadcast?
    @State private var showsRecordings = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.followsLiveState) private var followsLiveState

    private var current: LiveBroadcast { latest ?? broadcast }
    private var isLive: Bool { current.state == .live }
    private var fg: Color { isLive ? .white : DIColor.textPrimary }
    private var fgMuted: Color { isLive ? Color.white.opacity(0.82) : DIColor.textMuted }

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            HStack(spacing: DISpacing.sm) {
                if isLive {
                    DILivePulse(color: .white, size: 9)
                } else {
                    Image(systemName: "moon.stars").foregroundStyle(DIColor.primary)
                }
                // Looked up as a key so the default title ("Daily Zikr")
                // follows the app language; a title the server sends that is
                // not in the catalogue shows exactly as sent.
                Text(LocalizedStringKey(current.title))
                    .font(DIFont.subheading)
                    .foregroundStyle(fg)
                Spacer(minLength: DISpacing.sm)
                statusBadge
            }

            if isLive, let cue = current.cue {
                cueBanner(cue)
            }
            if let details = current.details, !details.isEmpty {
                Text(details).font(.subheadline).foregroundStyle(fgMuted)
            }
            if let start = current.scheduledStart, current.state == .scheduled {
                Label(start.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(fg)
            }

            // Always shown; greyed out until the channel is live with
            // something the app can play.
            let source = displaySources.first
            Button { if let source { activate(source) } } label: {
                Label("Join Daily Zikr with Sheikh-ul-Mukarram",
                      systemImage: source?.kind == .ownedStream ? "headphones" : "play.rectangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(source == nil ? DIColor.textMuted : (isLive ? DIColor.primaryDeep : DIColor.onPrimary))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(
                        source == nil ? AnyShapeStyle(DIColor.sandstone.opacity(isLive ? 0.35 : 0.6))
                            : isLive ? AnyShapeStyle(DIGradient.goldSheen) : AnyShapeStyle(DIColor.primary),
                        in: RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                    )
            }
            .buttonStyle(DIPressableStyle())
            .disabled(source == nil)
            .accessibilityHint(source == nil ? Text("Available when Daily Zikr is live") : Text(""))
            // Says only what the channel itself reports: nothing here claims
            // the zikr has begun before its live video is on air.
            if displaySources.isEmpty {
                Text("Daily Zikr appears here, live, when the session begins. Turn on a reminder below to be told when.")
                    .font(.footnote).foregroundStyle(fgMuted)
            }
            if current.updatedAt != .distantPast {
                Text("Updated \(current.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundStyle(fgMuted)
            }
            if !recordings.isEmpty {
                recordingsList
            }
        }
        .padding(DISpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                .stroke(isLive ? DIColor.accent.opacity(0.55) : DIColor.border, lineWidth: isLive ? 1.5 : 1)
        )
        .shadow(
            color: isLive ? DIColor.primaryDeep.opacity(0.4) : Color.black.opacity(0.06),
            radius: isLive ? 18 : 8, x: 0, y: isLive ? 10 : 4
        )
        .sheet(item: $presentedVideo) { video in YouTubePlayerSheet(videoID: video.id, title: video.title ?? current.title) }
        .onChange(of: broadcast) { latest = nil }
        .onChange(of: current.cue) { old, new in
            // A new latifa or muraqaba while the card is on screen: a chime
            // over the stream, since the mic may have dropped as it changed.
            if old != nil, let new, new != old {
                AudioServicesPlaySystemSound(1013)
                DIHaptics.success()
            }
        }
        // Only while the app is in front and the card is in sight: with
        // audio playing in the background, a card left on screen kept asking
        // the server.
        .task(id: platform != nil && scenePhase == .active && followsLiveState) { await follow() }
    }

    /// Re-reads the live state while the card is visible: every 10 seconds
    /// during a session, so a cue shows promptly; every 30 otherwise.
    private func follow() async {
        guard let platform, scenePhase == .active, followsLiveState else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(isLive ? 10 : 30))
            if Task.isCancelled { break }
            let fresh = await platform.currentLiveBroadcast(forceRefresh: true)
            if fresh != current { latest = fresh }
        }
    }

    /// Earlier sessions to play, folded away until opened. Every recording
    /// carries the same title, so each is named by when it was streamed.
    private var recordingsList: some View {
        DisclosureGroup(isExpanded: $showsRecordings) {
            VStack(spacing: 0) {
                ForEach(recordings) { item in
                    Button {
                        guard let videoID = item.videoID else { return }
                        DIHaptics.light()
                        presentedVideo = PresentedVideo(id: videoID, title: item.title)
                    } label: {
                        HStack(spacing: DISpacing.sm) {
                            Image(systemName: "play.fill")
                                .font(.caption2)
                                .foregroundStyle(isLive ? DIColor.primaryDeep : DIColor.onPrimary)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(isLive ? AnyShapeStyle(DIGradient.goldSheen) : AnyShapeStyle(DIColor.primary)))
                                .accessibilityHidden(true)
                            Text(item.publishedAt, format: .dateTime.weekday(.wide).day().month(.wide))
                                .font(.subheadline)
                                .foregroundStyle(fg)
                            Spacer(minLength: DISpacing.sm)
                            Text(item.publishedAt, format: .dateTime.hour().minute())
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(fgMuted)
                        }
                        .padding(.vertical, DISpacing.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if item.id != recordings.last?.id {
                        Divider().overlay(isLive ? Color.white.opacity(0.2) : DIColor.border)
                    }
                }
            }
            .padding(.top, DISpacing.xs)
        } label: {
            Label("Recorded zikr", systemImage: "play.rectangle.on.rectangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(fg)
        }
        .tint(fgMuted)
    }

    /// The host's current latifa or muraqaba, exactly as written in the room.
    private func cueBanner(_ cue: LiveCue) -> some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: "bell.and.waves.left.and.right.fill")
                .font(.title3)
                .foregroundStyle(DIColor.primaryDeep)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: cue.text)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DIColor.primaryDeep)
                Text("Now in the zikr · \(cue.at.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(DIColor.primaryDeep.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .padding(DISpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DIGradient.goldSheen, in: RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder private var cardBackground: some View {
        if isLive {
            LinearGradient(
                colors: [Color(hex: 0x0D7A55), Color(hex: 0x04321F)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        } else {
            DIColor.surface
        }
    }

    private var statusBadge: some View {
        Text(LocalizedStringKey(statusText))
            .font(.caption2.weight(.bold))
            .foregroundStyle(isLive ? DIColor.primaryDeep : DIColor.textMuted)
            .padding(.horizontal, DISpacing.sm)
            .padding(.vertical, DISpacing.xs)
            .background(isLive ? Color.white : DIColor.sandstone, in: Capsule())
    }

    private func activate(_ source: LiveSource) {
        switch source.kind {
        case .ownedStream:
            let item = AudioPlayableItem(id: "official-live", title: current.title, subtitle: "Darul Irfan", url: source.url)
            audioPlayer.play(item, queue: [item])
        case .youtube:
            if let videoID = source.videoID { presentedVideo = PresentedVideo(id: videoID) }
        case .paltalk:
            break
        }
    }

    /// What the app plays inside itself - its own audio stream, or the live
    /// video - while it is live. The Paltalk room is not this card's: the
    /// Tahajjud zikr's card below joins it.
    private var displaySources: [LiveSource] {
        // One Join button: the room's own sound when it is relayed, the
        // channel's live video otherwise - both played here, in the app.
        guard isLive, let source = current.preferredSource else { return [] }
        return [source]
    }

    private var statusText: String {
        switch current.state { case .offline: return "OFF AIR"; case .scheduled: return "SCHEDULED"; case .live: return "LIVE"; case .ended: return "ENDED" }
    }
}

private struct PresentedVideo: Identifiable {
    let id: String
    /// A recording's own title; the live video goes by the broadcast's.
    var title: String? = nil
}

private struct FollowsLiveStateKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether a live card keeps the live state current. A screen kept alive
    /// out of sight (a Discover section not chosen) turns it off.
    var followsLiveState: Bool {
        get { self[FollowsLiveStateKey.self] }
        set { self[FollowsLiveStateKey.self] = newValue }
    }
}
