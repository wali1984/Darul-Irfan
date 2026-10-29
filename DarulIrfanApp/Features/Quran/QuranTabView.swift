import SwiftUI

// MARK: - Navigation

/// Destinations reachable inside the Quran tab's navigation stack.
enum QuranRoute: Hashable {
    case reader(surah: QuranSurah, focusAyah: Int?)
    case bookmarks
    case topics
    case paras
}

// MARK: - Tab entry point

/// Quran tab root: searchable surah index with a continue-reading card,
/// offline-availability badges, and toolbar access to bookmarks.
struct QuranTabView: View {
    private let dependencies: AppDependencies
    private let appState: AppState
    @State private var viewModel: QuranViewModel
    /// Held by the host (`ReadTabView`) so switching readers keeps this one's
    /// place: three levels into a surah, over to Hadith, back, still there.
    @Binding private var navigationPath: [QuranRoute]
    private let readerSelection: Binding<ReadSection>?
    private let onShowAllReaders: (() -> Void)?

    init(
        dependencies: AppDependencies,
        appState: AppState,
        navigationPath: Binding<[QuranRoute]>,
        readerSelection: Binding<ReadSection>? = nil,
        onShowAllReaders: (() -> Void)? = nil
    ) {
        self.dependencies = dependencies
        self.appState = appState
        _navigationPath = navigationPath
        self.readerSelection = readerSelection
        self.onShowAllReaders = onShowAllReaders
        _viewModel = State(initialValue: QuranViewModel(repository: dependencies.quranRepository))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack(path: $navigationPath) {
            content
                .diScreenBackground()
                .diPageHeading("Quran")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: QuranRoute.bookmarks) {
                            Image(systemName: "bookmark")
                        }
                        .accessibilityLabel("Bookmarks")
                    }
                }
                // Inside the stack so it lands in this reader's navigation bar.
                .modifier(OptionalReaderSwitch(
                    selection: readerSelection,
                    onShowAll: onShowAllReaders
                ))
                .navigationDestination(for: QuranRoute.self) { route in
                    destination(for: route)
                }
                .searchable(text: $viewModel.searchText, prompt: Text("Search by name or number"))
                .task {
                    await viewModel.load()
                    // The word timings are large; decoding them now, off the
                    // main thread, keeps the first surah from pausing to open.
                    await RecitationProvider.warmUp()
                }
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
                appState: appState,
                onRequestNextSurah: {
                    openNextSurah(after: surah)
                }
            )
        case .bookmarks:
            BookmarksListView(viewModel: viewModel)
        case .topics:
            TopicsBrowseView(dependencies: dependencies, appState: appState)
        case .paras:
            QuranParaListView(dependencies: dependencies, surahs: viewModel.surahs)
        }
    }

    /// The next surah takes the place of the one finished (a juz playing on,
    /// or the end of a surah reached) rather than stacking on it: readers
    /// piled up, every one kept in memory, and Back had to be tapped once per
    /// surah. Asked twice, it opens once.
    private func openNextSurah(after surah: QuranSurah) {
        guard let next = viewModel.surah(number: surah.id + 1) else { return }
        let route = QuranRoute.reader(surah: next, focusAyah: nil)
        if case .reader(let shown, _)? = navigationPath.last {
            if shown.id == next.id { return }
            if shown.id == surah.id {
                navigationPath[navigationPath.count - 1] = route
                return
            }
        }
        navigationPath.append(route)
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
                browseByTopicCard
                    .padding(.bottom, DISpacing.xs)
                browseByParaCard
                    .padding(.bottom, DISpacing.sm)
                if let progress = viewModel.lastRead,
                   let surah = viewModel.continueReadingSurah {
                    continueReadingCard(progress: progress, surah: surah)
                        .padding(.bottom, DISpacing.sm)
                }
                if let typed = viewModel.typedAyah {
                    goToAyahCard(surah: typed.surah, ayah: typed.ayah)
                        .padding(.bottom, DISpacing.sm)
                }
                if viewModel.filteredSurahs.isEmpty {
                    if viewModel.typedAyah == nil {
                        DIEmptyState(
                            systemImage: "magnifyingglass",
                            titleKey: "No surahs match your search",
                            messageKey: "Try a surah name, its English meaning, or a number from 1 to 114."
                        )
                    }
                } else {
                    ForEach(viewModel.filteredSurahs) { surah in
                        NavigationLink(value: QuranRoute.reader(surah: surah, focusAyah: nil)) {
                            SurahRow(
                                surah: surah,
                                isAvailableOffline: viewModel.hasOfflineText(surah),
                                isUrdu: appState.settings.language.contentLanguageCode == "ur"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, DISpacing.md)
            .padding(.top, DISpacing.sm)
            .padding(.bottom, DISpacing.xl)
            .diResponsiveWidth()
        }
    }

    private var browseByTopicCard: some View {
        NavigationLink(value: QuranRoute.topics) {
            ZStack {
                RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                    .fill(DIGradient.emerald)
                DIPatternTexture(tint: .white, opacity: 0.07)
                    .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous))
                DIOctagram(innerRatio: 0.5)
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: 150, height: 150)
                    .opacity(0.10)
                    .offset(x: 120)
                HStack(spacing: DISpacing.md) {
                    Image(systemName: "square.grid.2x2")
                        .font(.title2)
                        .foregroundStyle(DIColor.onPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Explore by Topic")
                            .font(DIFont.subheading)
                            .foregroundStyle(DIColor.onPrimary)
                        Text("Verses, tafseer, books & bayans by theme")
                            .font(.caption)
                            .foregroundStyle(DIColor.onPrimary.opacity(0.85))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DIColor.onPrimary.opacity(0.85))
                }
                .padding(DISpacing.md)
            }
            .shadow(color: DIColor.primaryDeep.opacity(0.3), radius: 10, y: 5)
        }
        .buttonStyle(DIPressableStyle())
        .accessibilityElement(children: .combine)
    }

    /// The Qur'an by para, as the Pakistani reader and the Silsila's printed
    /// Akram-ut-Tarajum divide it.
    private var browseByParaCard: some View {
        NavigationLink(value: QuranRoute.paras) {
            DICard(padding: DISpacing.md) {
                HStack(spacing: DISpacing.md) {
                    Image(systemName: "list.number")
                        .font(.title3)
                        .foregroundStyle(DIColor.primary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Browse by Parah")
                            .font(DIFont.subheading)
                            .foregroundStyle(DIColor.textPrimary)
                        Text("The 30 parahs, each opened at its first ayah")
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
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

    /// "2:255" typed into the search field opens that ayah.
    private func goToAyahCard(surah: QuranSurah, ayah: Int) -> some View {
        NavigationLink(value: QuranRoute.reader(surah: surah, focusAyah: ayah)) {
            DICard(padding: DISpacing.md) {
                HStack(spacing: DISpacing.md) {
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DIColor.accent)
                        .accessibilityHidden(true)
                    Text("Go to \(surah.nameTransliterated) \(surah.id):\(ayah)")
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func continueReadingCard(progress: ReadingProgress, surah: QuranSurah) -> some View {
        NavigationLink(value: QuranRoute.reader(surah: surah, focusAyah: progress.ayahNumber)) {
            DIElevatedCard(glow: DIColor.accent) {
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
    /// Urdu content language, including "System" on an Urdu phone.
    let isUrdu: Bool

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
                    if isUrdu {
                        // Urdu: the Arabic name followed by its Urdu meaning —
                        // mirrors the transliteration + English meaning below.
                        Text(surah.nameArabic)
                            .font(DIFont.quranArabic(scale: 0.72))
                            .foregroundStyle(DIColor.textPrimary)
                        Text(surah.nameUrdu ?? surah.nameEnglish)
                            .font(DIFont.urduBody(scale: 0.95))
                            .foregroundStyle(DIColor.textMuted)
                            .environment(\.layoutDirection, .rightToLeft)
                    } else {
                        Text(surah.nameTransliterated)
                            .font(.headline)
                            .foregroundStyle(DIColor.textPrimary)
                        Text(surah.nameEnglish)
                            .font(.subheadline)
                            .foregroundStyle(DIColor.textMuted)
                    }
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
                    if !isUrdu {
                        Text(surah.nameArabic)
                            .font(DIFont.quranArabic(scale: 0.62))
                            .foregroundStyle(DIColor.textPrimary)
                    }
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

// MARK: - Paras

/// The 30 paras, each with the ayah it opens at and that ayah's first words
/// from the mushaf, opening the reader there. The divisions are the
/// Silsila's printed parahs (`QuranDivisions.juzStarts`).
struct QuranParaListView: View {
    let dependencies: AppDependencies
    let surahs: [QuranSurah]
    @State private var openings: [Int: String] = [:]

    private struct Para: Identifiable {
        let number: Int
        let surah: QuranSurah
        let ayah: Int
        var id: Int { number }
    }

    private var paras: [Para] {
        QuranDivisions.juzStarts.enumerated().compactMap { index, start in
            guard let surah = surahs.first(where: { $0.id == start[0] }) else { return nil }
            return Para(number: index + 1, surah: surah, ayah: start[1])
        }
    }

    var body: some View {
        List(paras) { para in
            NavigationLink(value: QuranRoute.reader(surah: para.surah, focusAyah: para.ayah)) {
                HStack(spacing: DISpacing.md) {
                    Text("\(para.number)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DIColor.onPrimary)
                        .frame(minWidth: 34, minHeight: 34)
                        .background(Circle().fill(DIColor.primary))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(para.surah.nameTransliterated) \(para.surah.id):\(para.ayah)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DIColor.textPrimary)
                        if let opening = openings[para.number] {
                            Text(verbatim: opening)
                                .font(DIFont.quranArabic(scale: 0.6))
                                .foregroundStyle(DIColor.textMuted)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .environment(\.layoutDirection, .rightToLeft)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Parah \(para.number)"))
            }
            .listRowBackground(DIColor.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Parahs")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadOpenings() }
    }

    /// The first words of each para's opening ayah, from the mushaf itself.
    @MainActor
    private func loadOpenings() async {
        guard openings.isEmpty else { return }
        var bySurah: [Int: [Int: String]] = [:]
        var found: [Int: String] = [:]
        for para in paras {
            if bySurah[para.surah.id] == nil {
                let ayahs = (try? await dependencies.quranRepository.ayahs(inSurah: para.surah.id)) ?? []
                bySurah[para.surah.id] = Dictionary(ayahs.map { ($0.ayahNumber, $0.textArabic) }, uniquingKeysWith: { first, _ in first })
            }
            if let text = bySurah[para.surah.id]?[para.ayah] {
                found[para.number] = text.split(separator: " ").prefix(4).joined(separator: " ")
            }
        }
        openings = found
    }
}
