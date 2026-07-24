import SwiftUI

struct ExploreTabView: View {
    enum Section: String, CaseIterable, Identifiable {
        case updates = "Updates"
        case library = "Library"
        case media = "Media"
        var id: String { rawValue }
    }

    let dependencies: AppDependencies
    let appState: AppState
    @State private var section: Section = .updates

    var body: some View {
        VStack(spacing: 0) {
            Picker("Explore section", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DISpacing.md).padding(.vertical, DISpacing.sm)
            .background(DIColor.background)

            switch section {
            case .updates:
                NavigationStack {
                    OfficialFeedView(dependencies: dependencies)
                        .navigationTitle("Official Updates")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink { EventsHomeView(dependencies: dependencies, appState: appState) } label: { Image(systemName: "calendar") }
                            }
                        }
                }
            case .library: LibraryTabView(dependencies: dependencies, appState: appState)
            case .media: MediaTabView(dependencies: dependencies, appState: appState)
            }
        }
        .diScreenBackground()
    }
}
