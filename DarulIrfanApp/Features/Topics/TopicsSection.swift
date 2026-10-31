import SwiftUI

/// The theme Discover › Topics opens with: the same one all day and the
/// next one the next day. It is the daily choice Today's "Understand
/// something today" card made (`TodayUnderstandCard`), which moved here as
/// the Theme of the day; Android follows the same rule.
enum ThemeOfTheDay {
    static func topic(from topics: [Topic], on date: Date = Date(), calendar: Calendar = .current) -> Topic? {
        guard !topics.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let count = topics.count
        return topics[((day % count) + count) % count]
    }
}

/// Discover › Topics: the theme of the day, then the themes, the first ten
/// with the rest one tap away. Each opens its verses, hadith, books and
/// bayans.
@MainActor
struct TopicsSection: View {
    let viewModel: TopicsBrowseViewModel
    let dependencies: AppDependencies
    let appState: AppState
    @State private var showsAll = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let previewCount = 10
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var shownTopics: [Topic] {
        showsAll ? viewModel.topics : Array(viewModel.topics.prefix(Self.previewCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            if let theme = ThemeOfTheDay.topic(from: viewModel.topics) {
                NavigationLink {
                    TopicDetailView(topic: theme, dependencies: dependencies, appState: appState)
                } label: {
                    ThemeOfTheDayCard(topic: theme, language: appState.settings.language)
                }
                .buttonStyle(DIPressableStyle())
                .diAppear()
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(shownTopics.enumerated()), id: \.element.id) { index, topic in
                    NavigationLink {
                        TopicDetailView(topic: topic, dependencies: dependencies, appState: appState)
                    } label: {
                        TopicTile(topic: topic, language: appState.settings.language, gold: index % 3 == 1)
                    }
                    .buttonStyle(DIPressableStyle())
                    .diAppear(delay: 0.04 + Double(index) * 0.03)
                }
            }
            if viewModel.topics.count > Self.previewCount {
                moreButton
            }
        }
        .task {
            if viewModel.topics.isEmpty { viewModel.load() }
        }
    }

    private var moreButton: some View {
        Button {
            DIHaptics.light()
            if reduceMotion {
                showsAll.toggle()
            } else {
                withAnimation(.easeInOut(duration: 0.3)) { showsAll.toggle() }
            }
        } label: {
            HStack(spacing: 6) {
                if showsAll {
                    Text("Show fewer")
                } else {
                    Text("All \(viewModel.topics.count) themes")
                }
                Image(systemName: showsAll ? "chevron.up" : "chevron.forward")
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(DIColor.actionForeground)
            .frame(maxWidth: .infinity, minHeight: 44)
            .diGlassPanel(cornerRadius: 22)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(DIPressableStyle())
    }
}

/// The theme of the day on the emerald hero, with its glyph lit in gold.
private struct ThemeOfTheDayCard: View {
    let topic: Topic
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .top, spacing: DISpacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                DiscoverCaption(key: "Theme of the day")
                Text(verbatim: topic.name(for: language))
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Verses, tafsir, books and bayans on this theme")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: topic.systemIcon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(DIColor.goldGlow)
                .diBreathingGlow(color: DIColor.goldGlow, maxRadius: 12)
                .accessibilityHidden(true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DIHeroBackground(cornerRadius: 26))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// One theme as a glass tile: a glowing dot and its name, with the Urdu name
/// under it when the app is not in Urdu.
private struct TopicTile: View {
    let topic: Topic
    let language: AppLanguage
    let gold: Bool

    private var dot: Color { gold ? Color(hex: 0xE0B75F) : Color(hex: 0x13A06F) }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dot)
                .frame(width: 8, height: 8)
                .shadow(color: dot, radius: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: topic.name(for: language))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if language.contentLanguageCode != "ur", let urdu = topic.nameUrdu, !urdu.isEmpty {
                    Text(verbatim: urdu)
                        .font(DIFont.urduBody(scale: 0.75))
                        .foregroundStyle(DIColor.textMuted)
                        .lineLimit(1)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .diGlassPanel(cornerRadius: 20)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
