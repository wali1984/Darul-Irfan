import SwiftUI

struct TodayOfficialSection: View {
    let dependencies: AppDependencies
    @State private var viewModel: OfficialPlatformViewModel

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: OfficialPlatformViewModel(
            feedService: dependencies.officialPlatform,
            liveService: dependencies.officialPlatform
        ))
    }

    var body: some View {
        Group {
            if viewModel.live.state == .live || viewModel.live.state == .scheduled {
                DISectionHeader(titleKey: "Live & Upcoming", systemImage: "dot.radiowaves.left.and.right")
                LiveBroadcastCard(broadcast: viewModel.live, audioPlayer: dependencies.audioPlayer)
            } else if let featured = viewModel.feedItems.first(where: \.isFeatured) ?? viewModel.feedItems.first {
                Link(destination: featured.sourceURL) {
                    DICard {
                        VStack(alignment: .leading, spacing: DISpacing.sm) {
                            Label("Official Update", systemImage: "megaphone.fill").font(.caption.weight(.bold)).foregroundStyle(DIColor.primary)
                            Text(featured.title).font(DIFont.subheading).foregroundStyle(DIColor.textPrimary).multilineTextAlignment(.leading)
                            Text(featured.publishedAt, format: .relative(presentation: .named)).font(.caption).foregroundStyle(DIColor.textMuted)
                        }
                    }
                }
            }
        }
        .task { await viewModel.load() }
    }
}
