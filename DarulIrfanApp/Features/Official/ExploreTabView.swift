import SwiftUI

@MainActor
struct ExploreTabView: View {
    enum Section: String, CaseIterable, Identifiable {
        case topics = "Topics"
        case updates = "Updates"
        case library = "Library"
        case media = "Media"
        case events = "Events"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .topics: return "square.grid.2x2.fill"
            case .updates: return "newspaper.fill"
            case .library: return "books.vertical.fill"
            case .media: return "play.rectangle.fill"
            case .events: return "calendar"
            }
        }
    }

    let dependencies: AppDependencies
    let appState: AppState
    @State private var section: Section = .topics
    /// The sections opened so far. Each is built the first time it is chosen
    /// and then kept, with its navigation: switching used to rebuild each one,
    /// so a book read under Library was gone after a look at Media. Not all
    /// five at once, which would load every section on the first visit.
    @State private var opened: Set<Section> = [.topics]

    var body: some View {
        VStack(spacing: 0) {
            // Chips sized to their names, so none is cut short.
            DIChipTabs(
                items: Section.allCases,
                title: { LocalizedStringKey($0.rawValue) },
                icon: { $0.icon },
                selection: Binding(get: { section }, set: { open($0) })
            )
            .padding(.vertical, DISpacing.sm)
            .background(DIColor.background)

            ZStack {
                ForEach(Section.allCases) { candidate in
                    if opened.contains(candidate) {
                        sectionView(candidate)
                            .opacity(candidate == section ? 1 : 0)
                            .allowsHitTesting(candidate == section)
                            .accessibilityHidden(candidate != section)
                            .zIndex(candidate == section ? 1 : 0)
                            // Out of sight, its live card stops asking the server.
                            .environment(\.followsLiveState, candidate == section)
                    }
                }
            }
        }
        .diScreenBackground()
        .onAppear(perform: followRoute)
        .onChange(of: DeepLinkRouter.shared.requestCount) { _, _ in followRoute() }
    }

    private func open(_ target: Section) {
        opened.insert(target)
        section = target
    }

    /// A notification or a link asked for one of Discover's sections. An
    /// event or an update it names is opened by that section's screen.
    private func followRoute() {
        let router = DeepLinkRouter.shared
        guard let route = router.pending, let target = Section(route: route) else { return }
        open(target)
        if route.eventID == nil && route.updateID == nil { router.clear(route) }
    }

    @ViewBuilder
    private func sectionView(_ candidate: Section) -> some View {
        switch candidate {
        case .topics:
            NavigationStack {
                TopicsBrowseView(dependencies: dependencies, appState: appState)
            }
        case .updates:
            NavigationStack {
                OfficialFeedView(dependencies: dependencies, followsLinks: true)
                    .navigationTitle("Official Updates")
            }
        case .library:
            LibraryTabView(dependencies: dependencies, appState: appState)
        case .media:
            MediaTabView(dependencies: dependencies, appState: appState)
        case .events:
            NavigationStack {
                EventsHomeView(dependencies: dependencies, appState: appState, followsLinks: true)
            }
        }
    }
}

private extension ExploreTabView.Section {
    /// The section a route opens, if it is one of Discover's.
    init?(route: AppRoute) {
        switch route {
        case .updates: self = .updates
        case .events: self = .events
        case .media: self = .media
        case .library: self = .library
        case .topics: self = .topics
        default: return nil
        }
    }
}
