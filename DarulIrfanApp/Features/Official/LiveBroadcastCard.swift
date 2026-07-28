import SwiftUI

struct LiveBroadcastCard: View {
    let broadcast: LiveBroadcast
    let audioPlayer: any AudioPlayerServicing
    @State private var presentedVideo: PresentedVideo?
    @Environment(\.openURL) private var openURL

    private var isLive: Bool { broadcast.state == .live }
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
                Text(broadcast.title)
                    .font(DIFont.subheading)
                    .foregroundStyle(fg)
                Spacer(minLength: DISpacing.sm)
                statusBadge
            }

            if let details = broadcast.details, !details.isEmpty {
                Text(details).font(.subheadline).foregroundStyle(fgMuted)
            }
            if let start = broadcast.scheduledStart, broadcast.state == .scheduled {
                Label(start.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(fg)
            }

            ForEach(displaySources) { source in
                Button { activate(source) } label: {
                    Label(label(for: source), systemImage: icon(for: source))
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
                Text("The live broadcast is currently off air. Scheduled reminders remain available below.")
                    .font(.footnote).foregroundStyle(fgMuted)
            }
            if broadcast.updatedAt != .distantPast {
                Text("Updated \(broadcast.updatedAt.formatted(.relative(presentation: .named)))")
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
        .sheet(item: $presentedVideo) { video in YouTubePlayerSheet(videoID: video.id, title: broadcast.title) }
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
        Text(statusText)
            .font(.caption2.weight(.bold))
            .foregroundStyle(isLive ? DIColor.primaryDeep : DIColor.textMuted)
            .padding(.horizontal, DISpacing.sm)
            .padding(.vertical, DISpacing.xs)
            .background(isLive ? Color.white : DIColor.sandstone, in: Capsule())
    }

    private func activate(_ source: LiveSource) {
        switch source.kind {
        case .ownedStream:
            let item = AudioPlayableItem(id: "official-live", title: broadcast.title, subtitle: "Darul Irfan", url: source.url)
            audioPlayer.play(item, queue: [item])
        case .youtube:
            if let videoID = source.videoID { presentedVideo = PresentedVideo(id: videoID) }
        case .paltalk: openURL(source.url)
        }
    }

    private var displaySources: [LiveSource] {
        broadcast.sources.filter { source in
            source.kind != .youtube || source.videoID != nil
        }
    }

    private var statusText: String {
        switch broadcast.state { case .offline: return "OFF AIR"; case .scheduled: return "SCHEDULED"; case .live: return "LIVE"; case .ended: return "ENDED" }
    }
    private func label(for source: LiveSource) -> LocalizedStringKey {
        switch source.kind { case .ownedStream: return "Listen live"; case .youtube: return "Watch live in Darul Irfan"; case .paltalk: return "Join OURSHEIKH on Paltalk" }
    }
    private func icon(for source: LiveSource) -> String {
        switch source.kind { case .ownedStream: return "headphones"; case .youtube: return "play.rectangle.fill"; case .paltalk: return "arrow.up.right.square" }
    }
}

private struct PresentedVideo: Identifiable { let id: String }
