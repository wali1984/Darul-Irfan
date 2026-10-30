import SwiftUI
import Observation

/// The spiritual topics as a page of their own (from Tools, and the
/// Qur'an's topics card): the theme of the day, then the themes. Discover ›
/// Topics shows the same `TopicsSection` under its switch. Tapping a topic
/// opens its Quran verses plus related tafseer, books, and audio bayans.
struct TopicsBrowseView: View {
    let dependencies: AppDependencies
    let appState: AppState
    @State private var viewModel = TopicsBrowseViewModel()

    var body: some View {
        ScrollView {
            TopicsSection(viewModel: viewModel, dependencies: dependencies, appState: appState)
                .padding(DISpacing.md)
                .diResponsiveWidth()
        }
        .diScreenBackground()
        .navigationTitle("Topics")
    }
}

@Observable
@MainActor
final class TopicsBrowseViewModel {
    private(set) var topics: [Topic] = []
    func load() { topics = SeedBundle.topics() }
}
