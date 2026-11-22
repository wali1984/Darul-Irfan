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

// MARK: - What an update opens

/// What an official update opens when it is chosen.
enum UpdateDestination: Equatable, Sendable {
    /// A video, played in the app.
    case video(id: String, title: String)
    /// A website item the library holds: its page there, with its text.
    case libraryItem(id: String)
    /// A programme the app holds: its page, with its dates and reminder.
    case event(CommunityEvent)
    /// Anything else: the update's own sheet.
    case sheet(OfficialFeedItem)

    /// Where `item` opens. A website item goes to its library page when
    /// the library holds it (and `opensLibrary`: the page needs the app's
    /// state), a programme to its event page when the app holds it; the
    /// sheet is left for an update the app holds nothing more about.
    static func resolve(
        _ item: OfficialFeedItem,
        opensLibrary: Bool,
        contentRepository: any ContentRepositoryProtocol,
        eventsRepository: any EventsRepositoryProtocol
    ) async -> UpdateDestination {
        if item.source == .youtube, let videoID = item.videoID {
            return .video(id: videoID, title: item.title)
        }
        if opensLibrary, let id = item.libraryItemID {
            let stored = try? await contentRepository.item(id: id)
            if let stored {
                return .libraryItem(id: stored.id)
            }
        }
        if let id = item.programmeID {
            let events = (try? await eventsRepository.events()) ?? []
            if let event = events.first(where: { $0.id == id }) {
                return .event(event)
            }
        }
        return .sheet(item)
    }
}

extension OfficialFeedItem {
    /// A website item's id in the library: the one the server names, or
    /// what follows "website:" in the update's own id.
    var libraryItemID: String? {
        Self.linkedID(named: libraryID, in: id, prefix: "website:", when: source == .website)
    }

    /// A programme's id among the events: the one the server names, or
    /// what follows "event:" in the update's own id.
    var programmeID: String? {
        Self.linkedID(named: eventID, in: id, prefix: "event:", when: source == .event)
    }

    private static func linkedID(named: String?, in id: String, prefix: String, when applies: Bool) -> String? {
        guard applies else { return nil }
        if let named, !named.isEmpty { return named }
        guard id.hasPrefix(prefix) else { return nil }
        let rest = String(id.dropFirst(prefix.count))
        return rest.isEmpty ? nil : rest
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
    @State private var linkAttempt = 0
    @State private var linkFailure: String?
    @State private var presentedVideo: FeedVideo?
    @State private var presentedItem: OfficialFeedItem?
    /// A website update the library holds, opened on its page there.
    @State private var openedLibraryItemID: String?
    /// A programme update the app holds, opened on its event page.
    @State private var openedEvent: CommunityEvent?
    /// Finding what the update last chosen opens.
    @State private var opening: Task<Void, Never>?
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
            if followsLinks, let route = DeepLinkRouter.shared.pending, route.updateID != nil {
                DICard {
                    VStack(spacing: DISpacing.sm) {
                        if let linkFailure {
                            Text(LocalizedStringKey(linkFailure)).diInterfaceFont(.callout)
                            Button("Retry") { linkAttempt += 1 }.buttonStyle(DISecondaryButtonStyle())
                        } else {
                            ProgressView()
                            Text("Opening update…").diInterfaceFont(.callout)
                        }
                        Button("Close") { DeepLinkRouter.shared.clear(route) }.buttonStyle(DISecondaryButtonStyle())
                    }
                }
            }
            if feed.isShowingCachedContent {
                Label("Showing saved updates", systemImage: "wifi.slash")
                    .diInterfaceFont(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
            if let error = feed.errorMessage {
                DICard {
                    VStack(alignment: .leading, spacing: DISpacing.sm) {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .diInterfaceFont(.body)
                        Button("Retry") {
                            Task {
                                if error == String(localized: "More updates could not be loaded.") {
                                    await feed.loadMore()
                                } else {
                                    await feed.load(forceRefresh: true)
                                }
                            }
                        }
                        .buttonStyle(DISecondaryButtonStyle())
                        .disabled(feed.isLoading || feed.isLoadingMore)
                    }
                }
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
        }
        .task(id: "\(DeepLinkRouter.shared.requestCount):\(linkAttempt):\(DeepLinkRouter.shared.pending?.updateID ?? "")") {
            await openLinkedUpdate()
        }
        .sheet(item: $presentedVideo) { video in
            YouTubePlayerSheet(videoID: video.id, title: video.title)
        }
        .sheet(item: $presentedItem) { item in
            OfficialFeedDetailView(item: item)
        }
        .navigationDestination(isPresented: Binding(
            get: { openedLibraryItemID != nil },
            set: { if !$0 { openedLibraryItemID = nil } }
        )) {
            if let openedLibraryItemID, let appState {
                ContentItemDetailView(
                    itemID: openedLibraryItemID,
                    dependencies: dependencies,
                    appState: appState,
                    libraryViewModel: libraryViewModel
                )
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { openedEvent != nil },
            set: { if !$0 { openedEvent = nil } }
        )) {
            if let openedEvent {
                EventDetailView(event: openedEvent, notifications: dependencies.notifications)
            }
        }
    }

    /// A link to one update ("darulirfan://feed/<id>") opens it once the
    /// feed has loaded, when it is among the updates shown.
    private func openLinkedUpdate() async {
        linkFailure = nil
        guard followsLinks, let route = DeepLinkRouter.shared.pending,
              let id = route.updateID else { return }
        let request = DeepLinkRouter.shared.requestCount
        do {
            let item = try await feed.findLinkedUpdate(id: id)
            try Task.checkCancellation()
            guard DeepLinkRouter.shared.requestCount == request,
                  DeepLinkRouter.shared.pending == route else { return }
            guard let item else {
                linkFailure = "This update is no longer available."
                return
            }
            DeepLinkRouter.shared.clear(route)
            open(item)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, DeepLinkRouter.shared.requestCount == request,
                  DeepLinkRouter.shared.pending == route else { return }
            linkFailure = "The action could not be completed. Check your connection and try again."
        }
    }

    /// A video plays in the app. An article the library holds opens on its
    /// page there, with its text, and a programme on its event page; an
    /// update the app holds nothing more about opens in its own sheet.
    private func open(_ item: OfficialFeedItem) {
        DIHaptics.light()
        opening?.cancel()
        let opensLibrary = appState != nil
        let contentRepository = dependencies.contentRepository
        let eventsRepository = dependencies.eventsRepository
        opening = Task {
            let destination = await UpdateDestination.resolve(
                item,
                opensLibrary: opensLibrary,
                contentRepository: contentRepository,
                eventsRepository: eventsRepository
            )
            guard !Task.isCancelled else { return }
            switch destination {
            case .video(let id, let title):
                presentedVideo = FeedVideo(id: id, title: title)
            case .libraryItem(let id):
                openedLibraryItemID = id
            case .event(let event):
                openedEvent = event
            case .sheet(let update):
                presentedItem = update
            }
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
                .diInterfaceFont(.footnote, weight: .semibold)
                .fixedSize(horizontal: true, vertical: true)
                .foregroundStyle(selected ? Color.white : DIColor.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(minHeight: 40)
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
        .buttonStyle(DIPressableStyle())
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
        if news.loadFailed {
            VStack(spacing: DISpacing.sm) {
                Text("The action could not be completed. Check your connection and try again.")
                    .diInterfaceFont(.callout)
                    .foregroundStyle(DIColor.textPrimary)
                Button("Retry") { Task { await news.load() } }
                    .buttonStyle(DISecondaryButtonStyle())
                    .disabled(news.isLoading)
            }.padding(DISpacing.md)
        }
        if !news.isLoaded && !news.loadFailed && entries.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(DISpacing.xl)
        } else if news.loadFailed && entries.isEmpty {
            EmptyView()
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
            urduTitle: item.urduTitle,
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
/// kind and the day in small gold capitals, and the title in the interface's
/// language, with the other's under it where there is one.
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
                if DIBrand.readsUrdu(locale), let urduTitle, !urduTitle.isEmpty {
                    BookTextDrawing.urduName(urduTitle, scale: 0.95)
                        .font(DIFont.urduBody(scale: 0.95).weight(.bold))
                        .foregroundStyle(DIColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .rightToLeft)
                    if title != urduTitle {
                        LibraryCatalogueText(text: title, latinFont: .footnote, urduScale: 0.8)
                            .foregroundStyle(DIColor.textMuted)
                    }
                } else {
                    Text(verbatim: title)
                        .diInterfaceFont(.subheadline, weight: .bold)
                        .foregroundStyle(DIColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let urduTitle, !urduTitle.isEmpty {
                        BookTextDrawing.urduName(urduTitle, scale: 0.85)
                            .font(DIFont.urduBody(scale: 0.85))
                            .foregroundStyle(DIColor.textPrimary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                }
                if let detail, !detail.isEmpty, detail != title {
                    Text(verbatim: detail)
                        .diInterfaceFont(.subheadline)
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

    private func caption(_ text: Text) -> some View {
        text
            .diInterfaceFont(.caption2, weight: .heavy)
            .tracking(DiscoverStyle.tracking(1.2, in: locale))
    }
}

private struct FeedVideo: Identifiable {
    let id: String
    let title: String
}
