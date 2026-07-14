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
                        .diAppear()

                    if let message = viewModel.loadErrorMessage {
                        loadErrorCard(message)
                    }

                    if !viewModel.resumeEntries.isEmpty {
                        continueListeningSection
                            .diAppear(delay: 0.05)
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
                        .diOctagramWatermark(size: 260, opacity: 0.05)
                        .diAppear(delay: 0.1)
                    } else {
                        categoriesSection
                            .diAppear(delay: 0.1)
                        browseByYearLink
                            .diAppear(delay: 0.15)
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

    /// The AlMurshid TV sub-brand hero — a living crimson panel with a breathing
    /// glow, a pierced-jali watermark, and a pulsing LIVE pill.
    private var liveCard: some View {
        ZStack(alignment: .topLeading) {
            MediaStyle.crimson

            DIPatternTexture(tint: .white, opacity: 0.07)
                .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous))

            DIOctagram(innerRatio: 0.5)
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 220, height: 220)
                .opacity(0.07)
                .offset(x: 130, y: -60)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                    Text("AlMurshid TV")
                        .font(DIFont.subheading)
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    MediaLivePill(fill: Color.white.opacity(0.22), foreground: .white)
                }
                Text("Listen to the live audio stream from Dar ul Irfan. The stream plays while a broadcast is on air.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    DIHaptics.light()
                    viewModel.playLiveStream()
                } label: {
                    Label("Listen live", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(DIColor.crimson)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
                }
                .buttonStyle(DIPressableStyle())
                .padding(.top, DISpacing.xs)
                .accessibilityLabel(Text("Listen to the AlMurshid TV live stream"))
            }
            .padding(DISpacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .diBreathingGlow(color: DIColor.crimson, maxRadius: 20)
    }

    // MARK: - Continue Listening

    private var continueListeningSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Continue Listening", systemImage: "play.circle")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DISpacing.md) {
                    ForEach(viewModel.resumeEntries) { entry in
                        resumeCard(entry)
                    }
                }
                .padding(.vertical, DISpacing.xs)
                .padding(.horizontal, DISpacing.xs)
            }
        }
    }

    /// A rich elevated "resume" card: gradient artwork medallion, remaining
    /// progress, and a live play affordance. Spring press + soft haptic via
    /// `DIElevatedCard`.
    private func resumeCard(_ entry: MediaResumeEntry) -> some View {
        let accent = MediaStyle.accent(entry.item.category)
        let percent = Int(entry.progress.fractionCompleted * 100)
        return DIElevatedCard(glow: accent.opacity(0.5), onTap: { viewModel.resume(entry) }) {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(alignment: .top) {
                    MediaIconMedallion(category: entry.item.category, diameter: 40, glyph: "waveform")
                    Spacer(minLength: 0)
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                }
                MediaTitleText(item: entry.item, latinFont: .subheadline.weight(.semibold), lineLimit: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let speaker = entry.item.speaker {
                    Text(speaker)
                        .font(.caption2)
                        .foregroundStyle(DIColor.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                ProgressView(value: entry.progress.fractionCompleted)
                    .tint(accent)
                Text("\(percent)% played")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
            }
            .frame(minHeight: 128, alignment: .top)
        }
        .frame(width: 232)
        .accessibilityLabel(Text("Resume \(entry.item.title), \(percent) percent played"))
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Browse", systemImage: "square.grid.2x2")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: DISpacing.md)],
                alignment: .leading,
                spacing: DISpacing.md
            ) {
                ForEach(Array(MediaCategory.allCases.enumerated()), id: \.element) { index, category in
                    categoryCell(category)
                        .diAppear(delay: 0.12 + Double(index) * 0.04)
                }
            }
        }
    }

    private func categoryCell(_ category: MediaCategory) -> some View {
        let count = viewModel.categoryCounts[category] ?? 0
        return NavigationLink {
            MediaItemListView(filter: .category(category), dependencies: dependencies)
        } label: {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    MediaIconMedallion(category: category, diameter: 46)
                    Text(LocalizedStringKey(category.englishName))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if count > 0 {
                        Text("\(count) items")
                            .font(.caption)
                            .foregroundStyle(MediaStyle.accent(category))
                    } else {
                        Text("No items yet")
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(DIPressableStyle())
        .simultaneousGesture(TapGesture().onEnded { DIHaptics.light() })
    }

    // MARK: - Archive link

    private var browseByYearLink: some View {
        NavigationLink {
            ArchiveBrowserView(dependencies: dependencies, category: nil)
        } label: {
            DICard {
                HStack(spacing: DISpacing.md) {
                    ZStack {
                        Circle().fill(DIGradient.emerald)
                        Image(systemName: "calendar")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 44, height: 44)
                    .shadow(color: DIColor.primary.opacity(0.3), radius: 6, y: 3)
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DIColor.textMuted)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(DIPressableStyle())
        .simultaneousGesture(TapGesture().onEnded { DIHaptics.light() })
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
