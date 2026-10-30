import SwiftUI

// MARK: - Filters

/// The Updates filters. "Announcements and press" lists the Library's
/// announcements and press releases with the feed's own announcements;
/// events have their own section in Discover.
enum UpdatesFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case videos = "Videos"
    case posts = "Posts"
    case articles = "Articles"
    case announcements = "Announcements and press"

    var id: String { rawValue }

    /// Whether an official update is listed under this filter. Announcements
    /// and press is listed from `UpdatesNews`, which adds the library's.
    func includes(_ item: OfficialFeedItem) -> Bool {
        switch self {
        case .all: return true
        case .videos: return item.source == .youtube
        case .posts: return item.source == .facebook
        case .articles: return item.source == .website
        case .announcements: return item.source == .announcement
        }
    }
}

// MARK: - Page

/// The official updates as a page of their own (the Halqah tab's link).
/// Discover shows the same `UpdatesSection` under its switch.
struct OfficialFeedView: View {
    let dependencies: AppDependencies
    private let appState: AppState?
    /// Opens the update a link names. Only Discover's copy does, so this
    /// page does not take it as well.
    private let followsLinks: Bool
    @State private var viewModel: OfficialPlatformViewModel
    @State private var news: UpdatesNewsModel
    @State private var filter: UpdatesFilter = .all

    init(dependencies: AppDependencies, appState: AppState? = nil, followsLinks: Bool = false) {
        self.dependencies = dependencies
        self.appState = appState
        self.followsLinks = followsLinks
        _viewModel = State(initialValue: OfficialPlatformViewModel(
            feedService: dependencies.officialPlatform,
            liveService: dependencies.officialPlatform
        ))
        _news = State(initialValue: UpdatesNewsModel(
            contentRepository: dependencies.contentRepository,
            eventsRepository: dependencies.eventsRepository
        ))
    }

    var body: some View {
        ScrollView {
            UpdatesSection(
                feed: viewModel,
                news: news,
                filter: $filter,
                dependencies: dependencies,
                appState: appState,
                followsLinks: followsLinks
            )
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .refreshable {
            await news.load()
            await viewModel.load(forceRefresh: true)
        }
    }
}

// MARK: - Section

/// Discover › Updates: the official updates under their filters, with the
/// Library's announcements and press releases under "Announcements and
/// press". The Daily Zikr live card is on the Zikr tab now.
@MainActor
struct UpdatesSection: View {
    let feed: OfficialPlatformViewModel
    let news: UpdatesNewsModel
    @Binding private var filter: UpdatesFilter
    let dependencies: AppDependencies
    /// Needed to open a library item; a page without it lists them only.
    let appState: AppState?
    let followsLinks: Bool
    @State private var presentedVideo: FeedVideo?
    @State private var presentedItem: OfficialFeedItem?
    /// For a library item opened from here: its favourite star.
    @State private var libraryViewModel: LibraryViewModel

    init(
        feed: OfficialPlatformViewModel,
        news: UpdatesNewsModel,
        filter: Binding<UpdatesFilter>,
        dependencies: AppDependencies,
        appState: AppState?,
        followsLinks: Bool = false
    ) {
        self.feed = feed
        self.news = news
        _filter = filter
        self.dependencies = dependencies
        self.appState = appState
        self.followsLinks = followsLinks
        _libraryViewModel = State(initialValue: LibraryViewModel(contentRepository: dependencies.contentRepository))
    }

    private var visibleItems: [OfficialFeedItem] {
        feed.feedItems.filter(filter.includes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            if feed.isShowingCachedContent {
                Label("Showing saved updates", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
            if let error = feed.errorMessage {
                DICard { Label(error, systemImage: "exclamationmark.triangle") }
            }
            filterBar
            if filter == .announcements {
                newsContent
            } else {
                feedContent
            }
        }
        .task {
            await news.loadIfNeeded()
            await libraryViewModel.loadFavorites()
            if feed.feedItems.isEmpty && !feed.isLoading {
                await feed.load()
            }
            openLinkedUpdate()
        }
        .onChange(of: feed.isLoading) { _, isLoading in
            if !isLoading { openLinkedUpdate() }
        }
        .onChange(of: DeepLinkRouter.shared.requestCount) { _, _ in openLinkedUpdate() }
        .sheet(item: $presentedVideo) { video in
            YouTubePlayerSheet(videoID: video.id, title: video.title)
        }
        .sheet(item: $presentedItem) { item in
            OfficialFeedDetailView(item: item)
        }
    }

    /// A link to one update ("darulirfan://feed/<id>") opens it once the
    /// feed has loaded, when it is among the updates shown.
    private func openLinkedUpdate() {
        guard followsLinks, !feed.isLoading,
              let id = DeepLinkRouter.shared.take(\.updateID) else { return }
        guard let item = feed.feedItems.first(where: { $0.id == id }) else { return }
        if let videoID = item.videoID {
            presentedVideo = FeedVideo(id: videoID, title: item.title)
        } else {
            presentedItem = item
        }
    }

    /// A video plays in the app; anything else opens in full.
    private func open(_ item: OfficialFeedItem) {
        DIHaptics.light()
        if item.source == .youtube, let videoID = item.videoID {
            presentedVideo = FeedVideo(id: videoID, title: item.title)
        } else {
            presentedItem = item
        }
    }

    // MARK: Filters

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DISpacing.sm) {
                ForEach(UpdatesFilter.allCases) { candidate in
                    filterChip(candidate)
                }
            }
        }
        .accessibilityLabel("Filter official updates")
    }

    private func filterChip(_ candidate: UpdatesFilter) -> some View {
        let selected = candidate == filter
        return Button {
            DIHaptics.light()
            filter = candidate
        } label: {
            Text(LocalizedStringKey(candidate.rawValue))
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(selected ? Color.white : DIColor.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(
                    Capsule().fill(selected ? AnyShapeStyle(DIGradient.emerald) : AnyShapeStyle(DIColor.primary.opacity(0.06)))
                )
                .overlay(
                    Capsule().stroke(selected ? Color.clear : DIColor.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: selected ? DIColor.primary.opacity(0.35) : Color.clear, radius: 6, y: 3)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Official updates

    @ViewBuilder
    private var feedContent: some View {
        if feed.isLoading && feed.feedItems.isEmpty {
            ProgressView("Loading official updates…")
                .frame(maxWidth: .infinity)
                .padding(DISpacing.xl)
        } else if !feed.isOfficialFeedEnabled {
            DIEmptyState(
                systemImage: "newspaper",
                titleKey: "Official updates are temporarily paused",
                messageKey: "Previously saved content remains available throughout the app."
            )
        } else if feed.feedItems.isEmpty {
            DIEmptyState(
                systemImage: "newspaper",
                titleKey: "No official updates yet",
                messageKey: "Pull down to check for new updates."
            )
        } else if visibleItems.isEmpty {
            DIEmptyState(
                systemImage: "line.3.horizontal.decrease.circle",
                titleKey: "No updates in this section",
                messageKey: feed.nextCursor == nil
                    ? "Choose another filter or check again later."
                    : "More saved updates may be available."
            )
            if feed.nextCursor != nil {
                loadMoreButton
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(visibleItems) { item in
                    Button { open(item) } label: { feedRow(item) }
                        .buttonStyle(DIPressableStyle())
                        .accessibilityHint(hint(for: item))
                        .diScrollReveal()
                        .task {
                            if item.id == visibleItems.last?.id, feed.nextCursor != nil {
                                await feed.loadMore()
                            }
                        }
                }
                if feed.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(DISpacing.md)
                }
            }
        }
    }

    private var loadMoreButton: some View {
        Button {
            Task { await feed.loadMore() }
        } label: {
            if feed.isLoadingMore {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Label("Load More Updates", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(DISecondaryButtonStyle())
        .disabled(feed.isLoadingMore)
    }

    private func feedRow(_ item: OfficialFeedItem) -> some View {
        DiscoverUpdateRow(
            kind: Self.sourceName(item.source),
            date: Self.dayText(item.publishedAt, timeZone: .current),
            title: item.title,
            systemImage: Self.sourceIcon(item.source),
            gold: item.source == .youtube
        )
    }

    private func hint(for item: OfficialFeedItem) -> Text {
        item.source == .youtube ? Text("Plays in Darul Irfan") : Text("Read in Darul Irfan")
    }

    // MARK: Announcements and press

    @ViewBuilder
    private var newsContent: some View {
        let entries = news.entries(feed: feed.feedItems)
        if !news.isLoaded {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(DISpacing.xl)
        } else if entries.isEmpty {
            DIEmptyState(
                systemImage: "megaphone",
                titleKey: "No announcements",
                messageKey: "News and announcements from Dar-ul-Irfan will appear here."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(entries) { entry in
                    newsRow(entry)
                        .diScrollReveal()
                }
            }
        }
    }

    @ViewBuilder
    private func newsRow(_ entry: UpdatesNewsEntry) -> some View {
        switch entry {
        case .feed(let item):
            Button { open(item) } label: { feedRow(item) }
                .buttonStyle(DIPressableStyle())
                .accessibilityHint(hint(for: item))
        case .library(let item):
            if let appState {
                NavigationLink {
                    ContentItemDetailView(
                        itemID: item.id,
                        dependencies: dependencies,
                        appState: appState,
                        libraryViewModel: libraryViewModel
                    )
                } label: {
                    libraryRow(item)
                }
                .buttonStyle(DIPressableStyle())
            } else {
                libraryRow(item)
            }
        case .note(let note):
            DiscoverUpdateRow(
                kind: "Announcement",
                date: note.publishedAt.map { Self.dayText($0, timeZone: .gmt) },
                title: note.title,
                detail: note.body,
                systemImage: "megaphone.fill"
            )
        }
    }

    private func libraryRow(_ item: ContentItem) -> some View {
        let isPress = item.type == .pressRelease
        // Catalogue days are midnight UTC: read in UTC, or west of
        // Greenwich they show the day before.
        return DiscoverUpdateRow(
            kind: isPress ? "Press Release" : "Announcement",
            date: (item.publishedAt ?? item.updatedAt).map { Self.dayText($0, timeZone: .gmt) },
            title: item.title,
            urduTitle: item.titleUrdu,
            systemImage: isPress ? "newspaper.fill" : "megaphone.fill"
        )
    }

    // MARK: Labels

    /// "2 Oct", or "2 Oct 2024" in another year.
    static func dayText(_ date: Date, timeZone: TimeZone) -> Text {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let style = Date.FormatStyle(timeZone: timeZone).day().month()
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            return Text(date, format: style)
        }
        return Text(date, format: style.year())
    }

    static func sourceName(_ source: OfficialFeedSource) -> LocalizedStringKey {
        switch source {
        case .youtube: return "Video"
        case .facebook: return "Post"
        case .website: return "Article"
        case .announcement: return "Announcement"
        case .event: return "Event"
        }
    }

    static func sourceIcon(_ source: OfficialFeedSource) -> String {
        switch source {
        case .youtube: return "play.rectangle.fill"
        case .facebook: return "person.2.fill"
        case .website: return "doc.text.fill"
        case .announcement: return "megaphone.fill"
        case .event: return "calendar"
        }
    }
}

// MARK: - Row

/// One update as the board draws it: a glass row with the kind's tile, the
/// kind and the day in small gold capitals, and the title.
struct DiscoverUpdateRow: View {
    let kind: LocalizedStringKey
    let date: Text?
    let title: String
    var urduTitle: String?
    var detail: String?
    let systemImage: String
    var gold = false
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DiscoverStyle.orbInk(gold: gold))
                .frame(width: 54, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DiscoverStyle.orb(gold: gold))
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    caption(Text(kind))
                    if let date {
                        caption(Text(verbatim: "·"))
                        caption(date)
                    }
                }
                .textCase(.uppercase)
                .foregroundStyle(DiscoverStyle.goldInk)
                Text(verbatim: title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let urduTitle, !urduTitle.isEmpty {
                    Text(verbatim: urduTitle)
                        .font(DIFont.urduBody(scale: 0.85))
                        .foregroundStyle(DIColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                if let detail, !detail.isEmpty, detail != title {
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textMuted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .diGlassPanel(cornerRadius: 22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func caption(_ text: Text) -> Text {
        text
            .font(.caption2.weight(.heavy))
            .tracking(DiscoverStyle.tracking(1.2, in: locale))
    }
}

private struct FeedVideo: Identifiable {
    let id: String
    let title: String
}
