import SwiftUI
import Observation

/// A grid of spiritual topics that cross-link the whole app. Tapping a topic
/// opens its Quran verses plus related tafseer, books, and audio bayans.
struct TopicsBrowseView: View {
    let dependencies: AppDependencies
    let appState: AppState
    @State private var viewModel = TopicsBrowseViewModel()

    private let columns = [GridItem(.flexible(), spacing: DISpacing.md),
                           GridItem(.flexible(), spacing: DISpacing.md)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                Text("Explore themes across the Qur'an, tafseer, books, and bayans.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
                    .padding(.horizontal, DISpacing.xs)
                LazyVGrid(columns: columns, spacing: DISpacing.md) {
                    ForEach(Array(viewModel.topics.enumerated()), id: \.element.id) { index, topic in
                        NavigationLink {
                            TopicDetailView(topic: topic, dependencies: dependencies, appState: appState)
                        } label: {
                            topicCard(topic)
                        }
                        .buttonStyle(DIPressableStyle())
                        .diAppear(delay: Double(index) * 0.03)
                    }
                }
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .navigationTitle("Topics")
        .task { viewModel.load() }
    }

    private func topicCard(_ topic: Topic) -> some View {
        DIElevatedCard(padding: DISpacing.md, glow: DIColor.accent) {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                ZStack {
                    Circle()
                        .fill(DIGradient.emerald)
                        .frame(width: 46, height: 46)
                    Image(systemName: topic.systemIcon)
                        .font(.title3)
                        .foregroundStyle(DIColor.onPrimary)
                }
                .diBreathingGlow(color: DIColor.primary.opacity(0.5), maxRadius: 8)
                Text(topic.name(for: appState.settings.language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DIColor.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let urdu = topic.nameUrdu, appState.settings.language != .urdu {
                    Text(urdu)
                        .font(DIFont.urduBody(scale: 0.8))
                        .foregroundStyle(DIColor.textMuted)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        }
    }
}

@Observable
@MainActor
final class TopicsBrowseViewModel {
    private(set) var topics: [Topic] = []
    func load() { topics = SeedBundle.topics() }
}
