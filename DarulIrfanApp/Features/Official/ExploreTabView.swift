import SwiftUI

struct ExploreTabView: View {
    enum Section: String, CaseIterable, Identifiable {
        case updates = "Updates"
        case library = "Library"
        case media = "Media"
        case events = "Events"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .updates: return "newspaper.fill"
            case .library: return "books.vertical.fill"
            case .media: return "play.rectangle.fill"
            case .events: return "calendar"
            }
        }
    }

    let dependencies: AppDependencies
    let appState: AppState
    @State private var section: Section = .updates

    var body: some View {
        VStack(spacing: 0) {
            DISegmentedControl(
                items: Section.allCases,
                title: { LocalizedStringKey($0.rawValue) },
                icon: { $0.icon },
                selection: $section
            )
            .padding(.horizontal, DISpacing.md)
            .padding(.vertical, DISpacing.sm)
            .background(DIColor.background)

            content
        }
        .diScreenBackground()
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .updates:
            NavigationStack {
                OfficialFeedView(dependencies: dependencies)
                    .navigationTitle("Official Updates")
            }
        case .library:
            LibraryTabView(dependencies: dependencies, appState: appState)
        case .media:
            MediaTabView(dependencies: dependencies, appState: appState)
        case .events:
            NavigationStack {
                EventsHomeView(dependencies: dependencies, appState: appState)
            }
        }
    }
}
