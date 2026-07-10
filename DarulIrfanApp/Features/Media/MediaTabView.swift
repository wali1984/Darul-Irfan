import SwiftUI

/// Media tab home: AlMurshid TV live card, Continue Listening, category grid,
/// and the year archive entry point. Owns its own NavigationStack per the
/// navigation contract.
struct MediaTabView: View {
    private let dependencies: AppDependencies
    private let appState: AppState
    @State private var viewModel: MediaViewModel
    @State private var showsSearch = false

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
        _viewModel = State(initialValue: MediaViewModel(
            mediaRepository: dependencies.mediaRepository,
            downloadsRepository: dependencies.downloadsRepository,
            downloadManager: dependencies.downloadManager,
            audioPlayer: dependencies.audioPlayer
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DISpacing.lg) {
                    liveCard

                    if let message = viewModel.loadErrorMessage {
                        loadErrorCard(message)
                    }

                    if !viewModel.resumeEntries.isEmpty {
                        continueListeningSection
                    }

                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(DISpacing.lg)
                    } else if viewModel.isEmpty && viewModel.loadErrorMessage == nil {
                        DIEmptyState(
                            systemImage: "waveform",
                            titleKey: "The media library is being prepared",
                            messageKey: "Lectures and programs will appear here after the first content sync. Pull down to refresh."
                        )
                    } else {
                        categoriesSection
                        browseByYearLink
                    }
                }
                .padding(DISpacing.md)
            }
            .diScreenBackground()
            .navigationTitle("Media")
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
                GlobalSearchView(dependencies: dependencies)
            }
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
            .onDisappear {
                viewModel.cancelLiveStreamCheck()
            }
            .alert(
                "Stream Unavailable",
                isPresented: Binding(
                    get: { viewModel.showsStreamUnavailableAlert },
                    set: { viewModel.showsStreamUnavailableAlert = $0 }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The AlMurshid TV live stream could not be reached. It may be off air right now — please try again later.")
            }
        }
    }

    // MARK: - AlMurshid TV live card

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            HStack(spacing: DISpacing.sm) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundStyle(DIColor.accent)
                    .accessibilityHidden(true)
                Text("AlMurshid TV")
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.onPrimary)
                Spacer(minLength: 0)
                DIPillBadge(text: "Live", color: DIColor.accent)
            }
            Text("Listen to the live audio stream from Dar ul Irfan. The stream plays while a broadcast is on air.")
                .font(.subheadline)
                .foregroundStyle(DIColor.onPrimary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                viewModel.playLiveStream()
            } label: {
                Label("Listen live", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(DIColor.primaryDeep)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(DIColor.accent)
                    .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Listen to the AlMurshid TV live stream"))
        }
        .padding(DISpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DIColor.primaryDeep)
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous))
    }

    // MARK: - Continue Listening

    private var continueListeningSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Continue Listening", systemImage: "play.circle")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DISpacing.sm) {
                    ForEach(viewModel.resumeEntries) { entry in
                        resumeCard(entry)
                    }
                }
                .padding(.vertical, DISpacing.xs)
            }
        }
    }

    private func resumeCard(_ entry: MediaResumeEntry) -> some View {
        Button {
            viewModel.resume(entry)
        } label: {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    MediaTitleText(item: entry.item, latinFont: .subheadline.weight(.semibold), lineLimit: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ProgressView(value: entry.progress.fractionCompleted)
                        .tint(DIColor.primary)
                    HStack(spacing: DISpacing.xs) {
                        Text("\(Int(entry.progress.fractionCompleted * 100))% played")
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                        Spacer(minLength: 0)
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .foregroundStyle(DIColor.primary)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(width: 240, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Resume \(entry.item.title)"))
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Browse", systemImage: "square.grid.2x2")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: DISpacing.sm)],
                alignment: .leading,
                spacing: DISpacing.sm
            ) {
                ForEach(MediaCategory.allCases) { category in
                    categoryCell(category)
                }
            }
        }
    }

    private func categoryCell(_ category: MediaCategory) -> some View {
        NavigationLink {
            MediaItemListView(filter: .category(category), dependencies: dependencies)
        } label: {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    Image(systemName: categoryIcon(category))
                        .font(.title3)
                        .foregroundStyle(DIColor.primary)
                        .accessibilityHidden(true)
                    Text(LocalizedStringKey(category.englishName))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if let count = viewModel.categoryCounts[category], count > 0 {
                        Text("\(count) items")
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                    } else {
                        Text("No items yet")
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func categoryIcon(_ category: MediaCategory) -> String {
        switch category {
        case .audioLectures: return "headphones"
        case .videoLectures: return "video"
        case .tafseerQuranVideos: return "book.closed"
        case .alMurshidTV: return "dot.radiowaves.left.and.right"
        case .alMurshidQA: return "questionmark.bubble"
        case .shortClips: return "waveform"
        case .recommended: return "star"
        case .kalamESheikh: return "quote.opening"
        }
    }

    // MARK: - Archive link

    private var browseByYearLink: some View {
        NavigationLink {
            ArchiveBrowserView(dependencies: dependencies, category: nil)
        } label: {
            DICard {
                HStack(spacing: DISpacing.sm) {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundStyle(DIColor.primary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DISpacing.xs) {
                        Text("Browse by year")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DIColor.textPrimary)
                        Text("The lecture archive, organized by year and month")
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Error

    private func loadErrorCard(_ message: String) -> some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Label {
                    Text(LocalizedStringKey(message))
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textPrimary)
                } icon: {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(DIColor.danger)
                }
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Text("Try Again")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.primary)
                }
            }
        }
    }
}
