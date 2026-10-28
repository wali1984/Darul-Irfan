import AudioToolbox
import SwiftUI

struct LiveBroadcastCard: View {
    let broadcast: LiveBroadcast
    let audioPlayer: any AudioPlayerServicing
    /// A zikr session's time has come: the card says the zikr has begun and
    /// that the live stream appears here, rather than "off air".
    var sessionOpen = false
    /// When given, the card checks the live state every 30 seconds while it is
    /// on screen, so the in-app player appears the moment the stream starts.
    var platform: OfficialPlatformService? = nil
    @State private var presentedVideo: PresentedVideo?
    @State private var latest: LiveBroadcast?

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

            ForEach(displaySources) { source in
                Button { activate(source) } label: {
                    Label(source.kind == .youtube ? "Join Daily Zikr with Sheikh ul Mukarram - YouTube" : "Join Daily Zikr with Sheikh ul Mukarram",
                          systemImage: source.kind == .ownedStream ? "headphones" : "play.rectangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isLive ? DIColor.primaryDeep : DIColor.onPrimary)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(
                            isLive ? AnyShapeStyle(DIGradient.goldSheen) : AnyShapeStyle(DIColor.primary),
                            in: RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                        )
                }
                .buttonStyle(DIPressableStyle())
            }
            if displaySources.isEmpty {
                if isLive || sessionOpen {
                    // The zikr has begun (the room is open) but no stream the
                    // app can play is on air yet. Zikr is joined here, never in
                    // another app, so the card waits for the stream.
                    Label("Zikr has started. The live stream appears here as soon as it is on air.", systemImage: "dot.radiowaves.left.and.right")
                        .font(.footnote).foregroundStyle(fgMuted)
                } else {
                    Text("Daily Zikr appears here, live, when the session begins. Turn on a reminder below to be told when.")
                        .font(.footnote).foregroundStyle(fgMuted)
                }
            }
            if current.updatedAt != .distantPast {
                Text("Updated \(current.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundStyle(fgMuted)
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
        .sheet(item: $presentedVideo) { video in YouTubePlayerSheet(videoID: video.id, title: current.title) }
        .onChange(of: broadcast) { latest = nil }
        .onChange(of: current.cue) { old, new in
            // A new latifa or muraqaba while the card is on screen: a chime
            // over the stream, since the mic may have dropped as it changed.
            if old != nil, let new, new != old {
                AudioServicesPlaySystemSound(1013)
                DIHaptics.success()
            }
        }
        .task(id: platform == nil) { await follow() }
    }

    /// Re-reads the live state while the card is visible: every 10 seconds
    /// during a session, so a cue shows promptly; every 30 otherwise.
    private func follow() async {
        guard let platform else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(isLive ? 10 : 30))
            if Task.isCancelled { break }
            let fresh = await platform.currentLiveBroadcast(forceRefresh: true)
            if fresh != current { latest = fresh }
        }
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
    /// video - while it is live or announced. The Paltalk room the server may
    /// still list is never offered: zikr is joined inside Darul Irfan, not in
    /// another app.
    private var displaySources: [LiveSource] {
        guard isLive || current.state == .scheduled else { return [] }
        return current.sources.filter { $0.kind == .ownedStream || ($0.kind == .youtube && $0.videoID != nil) }
    }

    private var statusText: String {
        if !isLive && sessionOpen { return "STARTING" }
        switch current.state { case .offline: return "OFF AIR"; case .scheduled: return "SCHEDULED"; case .live: return "LIVE"; case .ended: return "ENDED" }
    }
}

private struct PresentedVideo: Identifiable { let id: String }
