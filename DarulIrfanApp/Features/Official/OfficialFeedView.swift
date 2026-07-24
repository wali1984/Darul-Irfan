import SwiftUI

struct OfficialFeedView: View {
    let dependencies: AppDependencies
    @State private var viewModel: OfficialPlatformViewModel
    @State private var presentedVideo: FeedVideo?
    @Environment(\.openURL) private var openURL

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: OfficialPlatformViewModel(
            feedService: dependencies.officialPlatform,
            liveService: dependencies.officialPlatform
        ))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DISpacing.md) {
                LiveBroadcastCard(broadcast: viewModel.live, audioPlayer: dependencies.audioPlayer)
                if viewModel.isShowingCachedContent {
                    Label("Showing saved updates", systemImage: "wifi.slash")
                        .font(.caption).foregroundStyle(DIColor.textMuted)
                }
                if let error = viewModel.errorMessage { DICard { Label(error, systemImage: "exclamationmark.triangle") } }
                if viewModel.isLoading && viewModel.feedItems.isEmpty {
                    ProgressView("Loading official updates…").frame(maxWidth: .infinity).padding(DISpacing.xl)
                } else if viewModel.feedItems.isEmpty {
                    DIEmptyState(systemImage: "newspaper", titleKey: "No official updates yet", messageKey: "Pull down to refresh or visit naqshbandiaowaisiah.org.")
                } else {
                    ForEach(viewModel.feedItems) { item in feedCard(item) }
                    if viewModel.nextCursor != nil {
                        Button { Task { await viewModel.loadMore() } } label: {
                            if viewModel.isLoadingMore { ProgressView() } else { Text("Load more updates") }
                        }
                        .buttonStyle(DISecondaryButtonStyle()).frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .refreshable { await viewModel.load(forceRefresh: true) }
        .task { await viewModel.load() }
        .sheet(item: $presentedVideo) { video in YouTubePlayerSheet(videoID: video.id, title: video.title) }
    }

    private func feedCard(_ item: OfficialFeedItem) -> some View {
        Button {
            if item.source == .youtube, let videoID = item.videoID { presentedVideo = FeedVideo(id: videoID, title: item.title) }
            else { openURL(item.sourceURL) }
        } label: {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    if let imageURL = item.imageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFill()
                            case .failure: feedArtwork(item)
                            default: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity).aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
                    }
                    HStack {
                        Label(sourceName(item.source), systemImage: sourceIcon(item.source))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.source == .youtube ? DIColor.crimson : DIColor.primary)
                        Spacer()
                        Text(item.publishedAt, format: .relative(presentation: .named)).font(.caption2).foregroundStyle(DIColor.textMuted)
                    }
                    Text(item.title).font(DIFont.subheading).foregroundStyle(DIColor.textPrimary).multilineTextAlignment(.leading)
                    if let body = item.body, body != item.title {
                        Text(body).font(.subheadline).foregroundStyle(DIColor.textMuted).lineLimit(4).multilineTextAlignment(.leading)
                    }
                    Label(item.source == .youtube ? "Watch official video" : "View official post", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.semibold)).foregroundStyle(DIColor.primary)
                }
            }
        }
        .buttonStyle(DIPressableStyle())
        .accessibilityHint("Opens content from the official \(sourceName(item.source)) account")
    }

    private func feedArtwork(_ item: OfficialFeedItem) -> some View {
        ZStack { DIGradient.emerald; Image(systemName: sourceIcon(item.source)).font(.largeTitle).foregroundStyle(.white) }
    }
    private func sourceName(_ source: OfficialFeedSource) -> String {
        switch source { case .youtube: return "YouTube"; case .facebook: return "Facebook"; case .website: return "Official Website"; case .announcement: return "Announcement"; case .event: return "Event" }
    }
    private func sourceIcon(_ source: OfficialFeedSource) -> String {
        switch source { case .youtube: return "play.rectangle.fill"; case .facebook: return "person.2.fill"; case .website: return "globe"; case .announcement: return "megaphone.fill"; case .event: return "calendar" }
    }
}

private struct FeedVideo: Identifiable { let id: String; let title: String }
