import SwiftUI

struct ExploreTabView: View {
    enum Section: String, CaseIterable, Identifiable {
        case updates = "Updates"
        case library = "Library"
        case media = "Media"
        case events = "Events"
        var id: String { rawValue }
    }

    let dependencies: AppDependencies
    let appState: AppState
    @State private var section: Section = .updates

    var body: some View {
        VStack(spacing: 0) {
            Picker("Explore section", selection: $section) {
                ForEach(Section.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DISpacing.md).padding(.vertical, DISpacing.sm)
            .background(DIColor.background)

            switch section {
            case .updates:
                NavigationStack {
                    OfficialFeedView(dependencies: dependencies)
                        .navigationTitle("Official Updates")
                }
            case .library: LibraryTabView(dependencies: dependencies, appState: appState)
            case .media: MediaTabView(dependencies: dependencies, appState: appState)
            case .events:
                NavigationStack {
                    EventsHomeView(dependencies: dependencies, appState: appState)
                }
            }
        }
        .diScreenBackground()
    }
}
