import SwiftUI

// MARK: - Navigation

/// Destinations reachable inside the Quran tab's navigation stack.
enum QuranRoute: Hashable {
    case reader(surah: QuranSurah, focusAyah: Int?)
    case bookmarks
}

// MARK: - Tab entry point

/// Quran tab root: searchable surah index with a continue-reading card,
/// offline-availability badges, and toolbar access to bookmarks.
struct QuranTabView: View {
    private let dependencies: AppDependencies
    private let appState: AppState
    @State private var viewModel: QuranViewModel

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
        _viewModel = State(initialValue: QuranViewModel(repository: dependencies.quranRepository))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            content
                .diScreenBackground()
                .navigationTitle("Quran")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: QuranRoute.bookmarks) {
                            Image(systemName: "bookmark")
                        }
                        .accessibilityLabel("Bookmarks")
                    }
                }
                .navigationDestination(for: QuranRoute.self) { route in
                    destination(for: route)
                }
                .searchable(text: $viewModel.searchText, prompt: Text("Search by name or number"))
                .task { await viewModel.load() }
                .onAppear {
                    Task { await viewModel.refreshReaderState() }
                }
        }
    }

    @ViewBuilder
    private func destination(for route: QuranRoute) -> some View {
        switch route {
        case .reader(let surah, let focusAyah):
            SurahReaderView(
                surah: surah,
                focusAyah: focusAyah,
                dependencies: dependencies,
                appState: appState
            )
        case .bookmarks:
            BookmarksListView(viewModel: viewModel)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView("Loading surahs…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            VStack(spacing: DISpacing.md) {
                DIEmptyState(
                    systemImage: "book.closed",
                    titleKey: "The surah list could not be loaded",
                    messageKey: "Please try again. If this continues, reinstalling the app can restore the bundled Quran data."
                )
                Button("Try Again") {
                    Task { await viewModel.load() }
                }
                .buttonStyle(DISecondaryButtonStyle())
                .padding(.horizontal, DISpacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            surahList
        }
    }

    private var surahList: some View {
        ScrollView {
            LazyVStack(spacing: DISpacing.sm) {
                if let progress = viewModel.lastRead,
                   let surah = viewModel.continueReadingSurah {
                    continueReadingCard(progress: progress, surah: surah)
                        .padding(.bottom, DISpacing.sm)
                }
                if viewModel.filteredSurahs.isEmpty {
                    DIEmptyState(
                        systemImage: "magnifyingglass",
                        titleKey: "No surahs match your search",
                        messageKey: "Try a surah name, its English meaning, or a number from 1 to 114."
                    )
                } else {
                    ForEach(viewModel.filteredSurahs) { surah in
                        NavigationLink(value: QuranRoute.reader(surah: surah, focusAyah: nil)) {
                            SurahRow(
                                surah: surah,
                                isAvailableOffline: viewModel.hasOfflineText(surah)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, DISpacing.md)
            .padding(.top, DISpacing.sm)
            .padding(.bottom, DISpacing.xl)
        }
    }

    private func continueReadingCard(progress: ReadingProgress, surah: QuranSurah) -> some View {
        NavigationLink(value: QuranRoute.reader(surah: surah, focusAyah: progress.ayahNumber)) {
            DICard {
                HStack(spacing: DISpacing.md) {
                    Image(systemName: "book")
                        .font(.title3)
                        .foregroundStyle(DIColor.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DISpacing.xs) {
                        Text("Continue reading")
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(DIColor.textMuted)
                        Text("\(surah.nameTransliterated), Ayah \(progress.ayahNumber)")
                            .font(DIFont.subheading)
                            .foregroundStyle(DIColor.textPrimary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DIColor.textMuted)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Surah row

private struct SurahRow: View {
    let surah: QuranSurah
    let isAvailableOffline: Bool

    var body: some View {
        DICard(padding: DISpacing.md) {
            HStack(spacing: DISpacing.md) {
                Text("\(surah.id)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DIColor.onPrimary)
                    .padding(DISpacing.xs)
                    .frame(minWidth: 34, minHeight: 34)
                    .background(Circle().fill(DIColor.primary))

                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text(surah.nameTransliterated)
                        .font(.headline)
                        .foregroundStyle(DIColor.textPrimary)
                    Text(surah.nameEnglish)
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textMuted)
                    HStack(spacing: DISpacing.sm) {
                        DIPillBadge(
                            text: revelationPlaceName,
                            color: surah.revelationPlace == .makkah ? DIColor.primary : DIColor.accent
                        )
                        Text("\(surah.ayahCount) ayahs")
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                    }
                }

                Spacer(minLength: DISpacing.sm)

                VStack(alignment: .trailing, spacing: DISpacing.sm) {
                    Text(surah.nameArabic)
                        .font(DIFont.quranArabic(scale: 0.62))
                        .foregroundStyle(DIColor.textPrimary)
                    if isAvailableOffline {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundStyle(DIColor.primary)
                            .accessibilityLabel("Available offline")
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var revelationPlaceName: String {
        switch surah.revelationPlace {
        case .makkah: return String(localized: "Makkah")
        case .madinah: return String(localized: "Madinah")
        }
    }
}
