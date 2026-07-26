import SwiftUI

struct OfficialFeedView: View {
    private enum FeedFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case videos = "Videos"
        case facebook = "Facebook"
        case articles = "Articles"
        case announcements = "Announcements"
        case events = "Events"

        var id: String { rawValue }

        func includes(_ item: OfficialFeedItem) -> Bool {
            switch self {
            case .all: return true
            case .videos: return item.source == .youtube
            case .facebook: return item.source == .facebook
            case .articles: return item.source == .website
            case .announcements: return item.source == .announcement
            case .events: return item.source == .event
            }
        }
    }

    let dependencies: AppDependencies
    @State private var viewModel: OfficialPlatformViewModel
    @State private var presentedVideo: FeedVideo?
    @State private var presentedItem: OfficialFeedItem?
    @State private var filter: FeedFilter = .all

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: OfficialPlatformViewModel(
            feedService: dependencies.officialPlatform,
            liveService: dependencies.officialPlatform
        ))
    }

    private var visibleItems: [OfficialFeedItem] {
        viewModel.feedItems.filter(filter.includes)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DISpacing.md) {
                if viewModel.isLiveHubEnabled {
                    LiveBroadcastCard(broadcast: viewModel.live, audioPlayer: dependencies.audioPlayer)
                }
                if viewModel.isShowingCachedContent {
                    Label("Showing saved updates", systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                if let error = viewModel.errorMessage {
                    DICard { Label(error, systemImage: "exclamationmark.triangle") }
                }
                if !viewModel.feedItems.isEmpty {
                    filterBar
                }
                feedContent
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .refreshable { await viewModel.load(forceRefresh: true) }
        .task { await viewModel.load() }
        .sheet(item: $presentedVideo) { video in
            YouTubePlayerSheet(videoID: video.id, title: video.title)
        }
        .sheet(item: $presentedItem) { item in
            OfficialFeedDetailView(item: item)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DISpacing.sm) {
                ForEach(FeedFilter.allCases) { candidate in
                    Button { filter = candidate } label: {
                        Text(LocalizedStringKey(candidate.rawValue))
                            .font(.caption.weight(.semibold))
                    }
                        .foregroundStyle(filter == candidate ? DIColor.onPrimary : DIColor.primary)
                        .padding(.horizontal, DISpacing.md)
                        .frame(minHeight: 36)
                        .background(filter == candidate ? DIColor.primary : DIColor.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(DIColor.primary.opacity(0.35), lineWidth: 1))
                        .accessibilityAddTraits(filter == candidate ? .isSelected : [])
                }
            }
        }
        .accessibilityLabel("Filter official updates")
    }

    @ViewBuilder
    private var feedContent: some View {
        if viewModel.isLoading && viewModel.feedItems.isEmpty {
            ProgressView("Loading official updates…")
                .frame(maxWidth: .infinity)
                .padding(DISpacing.xl)
        } else if !viewModel.isOfficialFeedEnabled {
            DIEmptyState(
                systemImage: "newspaper",
                titleKey: "Official updates are temporarily paused",
                messageKey: "Previously saved content remains available throughout the app."
            )
        } else if viewModel.feedItems.isEmpty {
            DIEmptyState(
                systemImage: "newspaper",
                titleKey: "No official updates yet",
                messageKey: "Pull down to check for new updates."
            )
        } else if visibleItems.isEmpty {
            DIEmptyState(
                systemImage: "line.3.horizontal.decrease.circle",
                titleKey: "No updates in this section",
                messageKey: viewModel.nextCursor == nil
                    ? "Choose another filter or check again later."
                    : "More saved updates may be available."
            )
            if viewModel.nextCursor != nil {
                Button {
                    Task { await viewModel.loadMore() }
                } label: {
                    if viewModel.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Load More Updates", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(DISecondaryButtonStyle())
                .disabled(viewModel.isLoadingMore)
            }
        } else {
            ForEach(visibleItems) { item in
                feedCard(item)
                    .task {
                        if item.id == visibleItems.last?.id, viewModel.nextCursor != nil {
                            await viewModel.loadMore()
                        }
                    }
            }
            if viewModel.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(DISpacing.md)
            }
        }
    }

    private func feedCard(_ item: OfficialFeedItem) -> some View {
        Button {
            if item.source == .youtube, let videoID = item.videoID {
                presentedVideo = FeedVideo(id: videoID, title: item.title)
            } else {
                presentedItem = item
            }
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
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
                    }
                    HStack {
                        Label(sourceName(item.source), systemImage: sourceIcon(item.source))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.source == .youtube ? DIColor.crimson : DIColor.primary)
                        Spacer()
                        Text(item.publishedAt, format: .relative(presentation: .named))
                            .font(.caption2)
                            .foregroundStyle(DIColor.textMuted)
                    }
                    Text(item.title)
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let body = item.body, body != item.title {
                        Text(body)
                            .font(.subheadline)
                            .foregroundStyle(DIColor.textMuted)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                    }
                    Label {
                        Text(LocalizedStringKey(item.source == .youtube ? "Watch in Darul Irfan" : "Read in Darul Irfan"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DIColor.primary)
                    } icon: {
                        Image(systemName: "arrow.forward.circle")
                    }
                }
            }
        }
        .buttonStyle(DIPressableStyle())
        .accessibilityHint(item.source == .youtube ? "Plays the official video in the app" : "Opens the complete update in the app")
    }

    private func feedArtwork(_ item: OfficialFeedItem) -> some View {
        ZStack {
            DIGradient.emerald
            Image(systemName: sourceIcon(item.source)).font(.largeTitle).foregroundStyle(.white)
        }
    }

    private func sourceName(_ source: OfficialFeedSource) -> LocalizedStringKey {
        switch source {
        case .youtube: return "YouTube"
        case .facebook: return "Facebook"
        case .website: return "Article"
        case .announcement: return "Announcement"
        case .event: return "Event"
        }
    }

    private func sourceIcon(_ source: OfficialFeedSource) -> String {
        switch source {
        case .youtube: return "play.rectangle.fill"
        case .facebook: return "person.2.fill"
        case .website: return "doc.text.fill"
        case .announcement: return "megaphone.fill"
        case .event: return "calendar"
        }
    }
}

private struct FeedVideo: Identifiable {
    let id: String
    let title: String
}
