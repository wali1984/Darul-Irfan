import Observation
import SwiftUI

/// What Today's live strip shows, when anything is live: the Daily Zikr
/// broadcast, which plays here in the app, or the Tahajjud zikr's Paltalk
/// room, where that zikr is held and joined.
enum TodayLiveStrip: Equatable {
    case dailyZikr(title: String, source: LiveSource)
    case tahajjud(room: URL)

    /// The strip for a live state at `now`, or nil while nothing is live.
    /// Daily Zikr counts only with something the app can play (its live
    /// video, or a stream staff set). The Tahajjud room counts only while it
    /// is open before dawn in Pakistan, as the Zikr tab reads it: the same
    /// room carries Daily Zikr in the evening.
    static func strip(for live: LiveBroadcast, at now: Date) -> TodayLiveStrip? {
        if live.state == .live, let source = live.preferredSource {
            return .dailyZikr(title: live.title, source: source)
        }
        if let url = live.room?.url {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Karachi") ?? .current
            if calendar.component(.hour, from: now) < 7 {
                return .tahajjud(room: url)
            }
        }
        return nil
    }
}

/// Follows the live state for Today's strip while Today is on screen and
/// the app is in front: once at once, then every 30 seconds, as the Zikr tab
/// does. Owned by the Today screen, so the strip can appear the moment a
/// session goes live even though nothing shows before it.
@Observable
@MainActor
final class TodayLiveModel {
    private(set) var strip: TodayLiveStrip?
    private let platform: OfficialPlatformService
    /// The server's live-hub switch, read once.
    @ObservationIgnored private var liveHubEnabled: Bool?

    init(platform: OfficialPlatformService) {
        self.platform = platform
    }

    func follow() async {
        await update(forceRefresh: false)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            if Task.isCancelled { break }
            await update(forceRefresh: true)
        }
    }

    private func update(forceRefresh: Bool) async {
        if liveHubEnabled == nil {
            let bootstrap = await platform.bootstrap(forceRefresh: false)
            liveHubEnabled = bootstrap.generatedAt == .distantPast || bootstrap.featureFlags.liveHub
        }
        guard liveHubEnabled == true else {
            strip = nil
            return
        }
        let live = await platform.currentLiveBroadcast(forceRefresh: forceRefresh)
        let next = TodayLiveStrip.strip(for: live, at: Date())
        if next != strip {
            strip = next
        }
    }
}

/// Today's live strip (boards Main and TodayDark): one line, shown only
/// while a session is live. "LIVE NOW", the session's title and Join. Daily
/// Zikr plays here, in the app; the Tahajjud zikr opens its Paltalk room.
/// The official updates that used to show here are in Discover.
@MainActor
struct TodayOfficialSection: View {
    let strip: TodayLiveStrip
    let dependencies: AppDependencies

    @State private var presentedVideo: TodayLiveVideo?
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: join) {
            HStack(spacing: 12) {
                DILivePulse(color: Color(hex: 0xFF5C5C), size: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text("LIVE NOW")
                        .font(.caption2.weight(.heavy))
                        .tracking(DIBrand.readsUrdu(locale) ? 0 : 1.6)
                        .foregroundStyle(Color(hex: 0xFFE3A0))
                    title
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: DISpacing.sm)
                Text("Join")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TodayGradients.onGold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(TodayGradients.gold, in: Capsule())
                    .shadow(color: DIColor.goldGlow.opacity(0.55), radius: 8)
            }
            .padding(.vertical, 12)
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(hex: 0xE0B75F).opacity(0.55), lineWidth: 1)
            )
            .shadow(color: Color(hex: 0x064B34).opacity(0.45), radius: 14, y: 12)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(DIPressableStyle())
        .sheet(item: $presentedVideo) { video in
            YouTubePlayerSheet(videoID: video.id, title: video.title)
        }
    }

    /// The session's title: the broadcast's own, looked up as a key so the
    /// default titles follow the app language; or the Tahajjud zikr.
    @ViewBuilder
    private var title: some View {
        switch strip {
        case .dailyZikr(let title, _):
            Text(LocalizedStringKey(title))
        case .tahajjud:
            Text("Tahajjud Zikr")
        }
    }

    /// The live card's emerald, with a sheen passing across it.
    private var surface: some View {
        LinearGradient(
            colors: [Color(hex: 0x0D7A55), Color(hex: 0x04321F)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .diShimmer()
    }

    private func join() {
        DIHaptics.light()
        switch strip {
        case .dailyZikr(let title, let source):
            switch source.kind {
            case .youtube:
                if let videoID = source.videoID {
                    presentedVideo = TodayLiveVideo(
                        id: videoID,
                        title: String(localized: String.LocalizationValue(title))
                    )
                }
            case .ownedStream:
                let item = AudioPlayableItem(id: "official-live", title: title, subtitle: "Darul Irfan", url: source.url)
                dependencies.audioPlayer.play(item, queue: [item])
            case .paltalk:
                break
            }
        case .tahajjud(let room):
            // The Tahajjud zikr is held in the Paltalk room and joined there.
            openURL(room)
        }
    }
}

/// The live video the strip plays, for the sheet.
private struct TodayLiveVideo: Identifiable {
    let id: String
    let title: String
}
