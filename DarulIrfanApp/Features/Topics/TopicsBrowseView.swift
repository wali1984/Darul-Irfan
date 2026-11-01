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
    private(set) var failed = false
    private(set) var loaded = false
    private let loader: () throws -> [Topic]

    init(loader: @escaping () throws -> [Topic] = {
        guard SeedBundle.url(forFile: "topics") != nil else {
            throw SeedBundle.LoadError.unreadable(file: "topics", reason: "Missing catalogue")
        }
        return try SeedBundle.strictArray(Topic.self, fromFile: "topics")
    }) {
        self.loader = loader
    }

    func load() {
        failed = false
        do {
            topics = try loader()
            loaded = true
        } catch {
            failed = true
        }
    }
}
