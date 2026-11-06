import Observation
import SwiftUI

/// What Today's live strip shows, when anything is live: Our Sheikh's own
/// live Zikr, Daily Zikr or, before dawn in Pakistan, the Tahajjud zikr. Both
/// are joined on Our Sheikh's live stage, with the app's own live sound
/// (owner, 2026-11-06), never the Paltalk app or the YouTube stream.
enum TodayLiveStrip: Equatable {
    case dailyZikr
    case tahajjud

    /// The strip at `now`, or nil while Our Sheikh's Zikr is not live: the
    /// status says live only when that Zikr actually is.
    static func strip(for sheikh: SheikhLiveZikr?, at now: Date) -> TodayLiveStrip? {
        switch SheikhLiveZikr.liveSession(sheikh, at: now) {
        case .daily: return .dailyZikr
        case .tahajjud: return .tahajjud
        case nil: return nil
        }
    }
}

/// Follows the live state for Today's strip while Today is on screen and
/// the app is in front: straight away, then every 30 seconds, as the Zikr
/// tab does. Owned by the Today screen, so the strip can appear the moment
/// a session goes live even though nothing shows before it.
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
        let next = TodayLiveStrip.strip(for: await platform.sheikhLiveZikr(), at: Date())
        if next != strip {
            strip = next
        }
    }
}

/// Today's live strip (boards Main and TodayDark): one line, shown only
/// while a session is live. "LIVE NOW", the session's title and Join, which
/// opens Our Sheikh's live stage with the app's own live sound. The official
/// updates that used to show here are in Discover.
@MainActor
struct TodayOfficialSection: View {
    let strip: TodayLiveStrip

    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: join) {
            HStack(spacing: 12) {
                DILivePulse(color: Color(hex: 0xFF5C5C), size: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text("LIVE NOW")
                        .diInterfaceFont(.caption2, weight: .heavy)
                        .tracking(DIBrand.readsUrdu(locale) ? 0 : 1.6)
                        .foregroundStyle(Color(hex: 0xFFE3A0))
                    title
                        .diInterfaceFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: DISpacing.sm)
                Text("Join")
                    .diInterfaceFont(.subheadline, weight: .bold)
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
    }

    /// The session's title: the broadcast's own, looked up as a key so the
    /// default titles follow the app language; or the Tahajjud zikr.
    @ViewBuilder
    private var title: some View {
        switch strip {
        case .dailyZikr:
            Text(LocalizedStringKey(DailyZikrBanner.title))
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

    /// Daily Zikr and the Tahajjud zikr alike: Our Sheikh's live stage.
    private func join() {
        DIHaptics.light()
        DeepLinkRouter.shared.open(.sheikhStage)
    }
}
