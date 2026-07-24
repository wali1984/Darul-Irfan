import SwiftUI

struct LiveBroadcastCard: View {
    let broadcast: LiveBroadcast
    let audioPlayer: any AudioPlayerServicing
    @State private var presentedVideo: PresentedVideo?
    @Environment(\.openURL) private var openURL

    var body: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                HStack {
                    Label(broadcast.title, systemImage: broadcast.state == .live ? "dot.radiowaves.left.and.right" : "moon.stars")
                        .font(DIFont.subheading)
                        .foregroundStyle(broadcast.state == .live ? DIColor.crimson : DIColor.textPrimary)
                    Spacer()
                    Text(statusText)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(broadcast.state == .live ? Color.white : DIColor.textMuted)
                        .padding(.horizontal, DISpacing.sm).padding(.vertical, DISpacing.xs)
                        .background(broadcast.state == .live ? DIColor.crimson : DIColor.sandstone)
                        .clipShape(Capsule())
                }
                if let details = broadcast.details, !details.isEmpty {
                    Text(details).font(.subheadline).foregroundStyle(DIColor.textMuted)
                }
                if let start = broadcast.scheduledStart, broadcast.state == .scheduled {
                    Label(start.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                }
                ForEach(broadcast.sources) { source in
                    Button { activate(source) } label: {
                        Label(label(for: source), systemImage: icon(for: source)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(DIPrimaryButtonStyle())
                }
                if broadcast.sources.isEmpty {
                    Text("The live broadcast is currently off air. Scheduled reminders remain available below.")
                        .font(.footnote).foregroundStyle(DIColor.textMuted)
                }
                if broadcast.updatedAt != .distantPast {
                    Text("Updated \(broadcast.updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2).foregroundStyle(DIColor.textMuted)
                }
            }
        }
        .sheet(item: $presentedVideo) { video in YouTubePlayerSheet(videoID: video.id, title: broadcast.title) }
    }

    private func activate(_ source: LiveSource) {
        switch source.kind {
        case .ownedStream:
            let item = AudioPlayableItem(id: "official-live", title: broadcast.title, subtitle: "Darul Irfan", url: source.url)
            audioPlayer.play(item, queue: [item])
        case .youtube:
            if let videoID = source.videoID { presentedVideo = PresentedVideo(id: videoID) } else { openURL(source.url) }
        case .paltalk: openURL(source.url)
        }
    }

    private var statusText: String {
        switch broadcast.state { case .offline: return "OFF AIR"; case .scheduled: return "SCHEDULED"; case .live: return "LIVE"; case .ended: return "ENDED" }
    }
    private func label(for source: LiveSource) -> String {
        switch source.kind { case .ownedStream: return "Listen live"; case .youtube: return "Watch on YouTube"; case .paltalk: return "Join OURSHEIKH on Paltalk" }
    }
    private func icon(for source: LiveSource) -> String {
        switch source.kind { case .ownedStream: return "headphones"; case .youtube: return "play.rectangle.fill"; case .paltalk: return "arrow.up.right.square" }
    }
}

private struct PresentedVideo: Identifiable { let id: String }
