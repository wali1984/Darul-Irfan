import SwiftUI
import UIKit

// MARK: - Sections

/// The Discover tab's four sections, in the order of its switch. The Library
/// moved to Read › Books; the Daily Zikr live card is on the Zikr tab.
enum DiscoverSection: String, CaseIterable, Identifiable, Hashable {
    case bayans
    case updates
    case events
    case topics

    var id: String { rawValue }

    /// The key the last choice is kept under, across launches.
    static let storageKey = "discover.section"

    var titleKey: LocalizedStringKey {
        switch self {
        case .bayans: return "Bayans"
        case .updates: return "Updates"
        case .events: return "Events"
        case .topics: return "Topics"
        }
    }

    /// The section Discover opens on: the last one chosen, and Bayans on the
    /// first visit. A value this build does not know (the Library or Media
    /// chip of the older layout) also opens Bayans.
    static func remembered(_ stored: String?) -> DiscoverSection {
        if let stored, let section = DiscoverSection(rawValue: stored) {
            return section
        }
        return .bayans
    }

    /// The same, read from `defaults`; the tab keeps it in the standard ones.
    static func remembered(in defaults: UserDefaults) -> DiscoverSection {
        remembered(defaults.string(forKey: storageKey))
    }
}

extension DiscoverSection {
    /// The section a route opens, when it is one of Discover's. A library
    /// route is not: the books moved to Read.
    init?(route: AppRoute) {
        switch route {
        case .media: self = .bayans
        case .updates: self = .updates
        case .events: self = .events
        case .topics: self = .topics
        default: return nil
        }
    }
}

// MARK: - Discover

/// The Discover tab: one large title with Search, and one switch for
/// Bayans, Updates, Events and Topics (boards/Discover.dc.html).
@MainActor
struct ExploreTabView: View {
    let dependencies: AppDependencies
    let appState: AppState

    /// The last section chosen; Bayans until one is.
    @AppStorage(DiscoverSection.storageKey) private var storedSection: String = ""
    @State private var showsSearch = false
    /// Changed to bring Discover back to its first page when a link asks
    /// for one of its sections.
    @State private var stackID = UUID()
    /// The link request already followed, so each one moves the page once.
    @State private var followedRequest = -1
    // Each section's state lives here, so a look at another section neither
    // loads it again nor forgets the updates read so far.
    @State private var media: MediaViewModel
    @State private var bayanVideos: BayansFeedModel
    @State private var feed: OfficialPlatformViewModel
    @State private var news: UpdatesNewsModel
    @State private var updatesFilter: UpdatesFilter = .all
    @State private var events: EventsHomeViewModel
    @State private var topics = TopicsBrowseViewModel()

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
        _media = State(initialValue: MediaViewModel(
            mediaRepository: dependencies.mediaRepository,
            downloadsRepository: dependencies.downloadsRepository,
            downloadManager: dependencies.downloadManager,
            audioPlayer: dependencies.audioPlayer
        ))
        _bayanVideos = State(initialValue: BayansFeedModel(feed: dependencies.officialPlatform))
        _feed = State(initialValue: OfficialPlatformViewModel(
            feedService: dependencies.officialPlatform,
            liveService: dependencies.officialPlatform
        ))
        _news = State(initialValue: UpdatesNewsModel(
            contentRepository: dependencies.contentRepository,
            eventsRepository: dependencies.eventsRepository
        ))
        _events = State(initialValue: EventsHomeViewModel(eventsRepository: dependencies.eventsRepository))
    }

    private var section: DiscoverSection {
        DiscoverSection.remembered(storedSection)
    }

    private var sectionBinding: Binding<DiscoverSection> {
        Binding(
            get: { section },
            set: { storedSection = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DISpacing.md) {
                    DISegmentedControl(
                        items: DiscoverSection.allCases,
                        title: { $0.titleKey },
                        selection: sectionBinding
                    )
                    .diGlassPanel(cornerRadius: 24)

                    sectionContent
                }
                .padding(DISpacing.md)
                .diResponsiveWidth()
            }
            .diScreenBackground()
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(Text("Search"))
                }
            }
            .sheet(isPresented: $showsSearch) {
                GlobalSearchView(dependencies: dependencies, appState: appState)
            }
            .refreshable { await refresh() }
        }
        .id(stackID)
        .onAppear(perform: followRoute)
        .onChange(of: DeepLinkRouter.shared.requestCount) { _, _ in followRoute() }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .bayans:
            BayansSection(media: media, feed: bayanVideos, dependencies: dependencies)
        case .updates:
            UpdatesSection(
                feed: feed,
                news: news,
                filter: $updatesFilter,
                dependencies: dependencies,
                appState: appState,
                followsLinks: true
            )
        case .events:
            EventsSection(viewModel: events, dependencies: dependencies, appState: appState, followsLinks: true)
        case .topics:
            TopicsSection(viewModel: topics, dependencies: dependencies, appState: appState)
        }
    }

    /// Pull to refresh: the section on screen.
    private func refresh() async {
        switch section {
        case .bayans:
            await media.load()
            await bayanVideos.load(forceRefresh: true)
        case .updates:
            await news.load()
            await feed.load(forceRefresh: true)
        case .events:
            await events.load()
        case .topics:
            topics.load()
        }
    }

    /// A notification or a link asked for one of Discover's sections. The
    /// tab goes back to its first page once per request, so the section
    /// shows what was asked for; an event or an update it names is opened
    /// by that section.
    private func followRoute() {
        let router = DeepLinkRouter.shared
        guard let route = router.pending, let target = DiscoverSection(route: route) else { return }
        if followedRequest != router.requestCount {
            followedRequest = router.requestCount
            stackID = UUID()
        }
        storedSection = target.rawValue
        if route.eventID == nil && route.updateID == nil { router.clear(route) }
    }
}

// MARK: - Shared pieces

/// Colours the four sections share, from the board
/// (parity-spec/redesign/boards/Discover.dc.html).
enum DiscoverStyle {
    /// Small gold text on the ground: #7A5A14 on cream and #E0B75F on the
    /// dark ground, for 4.5:1 contrast.
    static let goldInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 224.0 / 255.0, green: 183.0 / 255.0, blue: 95.0 / 255.0, alpha: 1)
            : UIColor(red: 122.0 / 255.0, green: 90.0 / 255.0, blue: 20.0 / 255.0, alpha: 1)
    })

    /// Small gold text on emerald (#FFE3A0).
    static let goldOnEmerald = Color(hex: 0xFFE3A0)

    /// The gold of the board's key buttons.
    static let goldButton = LinearGradient(
        colors: [Color(hex: 0xFFE9A8), Color(hex: 0xE0B75F)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// A glossy orb's fill, emerald or gold, lit from the upper left.
    static func orb(gold: Bool) -> RadialGradient {
        RadialGradient(
            colors: gold
                ? [Color(hex: 0xFFE9A8), Color(hex: 0xE0B75F), Color(hex: 0xB48A2C)]
                : [Color(hex: 0x34B98A), Color(hex: 0x0B7250), Color(hex: 0x064B34)],
            center: UnitPoint(x: 0.32, y: 0.26),
            startRadius: 0,
            endRadius: 40
        )
    }

    /// The glyph on an orb.
    static func orbInk(gold: Bool) -> Color {
        gold ? Color(hex: 0x064B34) : Color.white
    }

    /// Letter spacing for small capitals. None in Urdu, whose letters join.
    static func tracking(_ value: CGFloat, in locale: Locale) -> CGFloat {
        locale.language.languageCode?.identifier == "ur" ? 0 : value
    }
}

/// A small gold capital caption on a hero card, such as "CONTINUE LISTENING".
struct DiscoverCaption: View {
    let key: LocalizedStringKey
    var color: Color = DiscoverStyle.goldOnEmerald
    @Environment(\.locale) private var locale

    var body: some View {
        Text(key)
            .font(.caption2.weight(.heavy))
            .tracking(DiscoverStyle.tracking(1.6, in: locale))
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// A section's small muted capital heading, such as "REGULAR PROGRAMMES".
struct DiscoverSectionLabel: View {
    let key: LocalizedStringKey
    @Environment(\.locale) private var locale

    var body: some View {
        Text(key)
            .font(.footnote.weight(.heavy))
            .tracking(DiscoverStyle.tracking(1.2, in: locale))
            .textCase(.uppercase)
            .foregroundStyle(DIColor.textMuted)
            .padding(.horizontal, DISpacing.xs)
            .padding(.top, DISpacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A glass row that opens a page: a gold glyph, a title with a line under
/// it, and a chevron ("Browse by year", "Past programmes").
struct DiscoverLinkRow: View {
    let systemImage: String
    let title: Text
    var subtitle: Text?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DIColor.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    subtitle
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DIColor.textMuted)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.bold))
                .foregroundStyle(DIColor.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, DISpacing.md)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .diGlassPanel(cornerRadius: 22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
