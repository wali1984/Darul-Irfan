import SwiftUI

// MARK: - Navigation

/// Destinations reachable inside the Quran tab's navigation stack.
enum QuranRoute: Hashable {
    case reader(surah: QuranSurah, focusAyah: Int?)
    case bookmarks
    case topics
    case paras
}

/// How the Quran reader's page lists the Qur'an: by surah or by parah.
enum QuranListMode: String, CaseIterable, Hashable {
    case surah
    case parah
}

// MARK: - Tab entry point

/// The Quran reader's page: Continue reading, Surah | Parah, a find field
/// that also takes "2:255", and the surahs (or the 30 parahs) on glass.
///
/// Under Read it is titled "Read", with the Quran | Hadith | Books switch at
/// the top of the page and Saved and Search in its toolbar (`readerSwitch`).
/// Topics, once a banner here, lives in Discover.
struct QuranTabView: View {
    private let dependencies: AppDependencies
    private let appState: AppState
    @State private var viewModel: QuranViewModel
    /// Held by the host (`ReadTabView`) so a link can open a place in it, and
    /// so this reader keeps its place while another one is shown.
    @Binding private var navigationPath: [QuranRoute]
    private let readerSelection: Binding<ReadSection>?
    private let onShowAllReaders: (() -> Void)?
    /// Surah or Parah, for the session.
    @State private var listMode: QuranListMode = .surah
    /// The first words of each parah's opening ayah, read once.
    @State private var paraOpenings: [Int: String] = [:]

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
        NavigationStack(path: $navigationPath) {
            content
                .diScreenBackground()
                .diPageHeading("Quran", hidden: readerSelection != nil)
                .toolbar {
                    // Under Read, Saved holds the bookmarks.
                    if readerSelection == nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink(value: QuranRoute.bookmarks) {
                                Image(systemName: "bookmark")
                            }
                            .accessibilityLabel("Bookmarks")
                        }
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
            // Each surah gets a reader of its own. Next surah replaces the
            // route in the same place in the stack, and without this the
            // reader there kept its state - the surah it had - so the button
            // showed the same surah again and then did nothing.
            SurahReaderView(
                surah: surah,
                focusAyah: focusAyah,
                dependencies: dependencies,
                appState: appState,
                onRequestNextSurah: {
                    openNextSurah(after: surah)
                }
            )
            .id(surah.id)
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

    // MARK: - Page

    /// Urdu content language, including "System" on an Urdu phone.
    private var isUrdu: Bool { appState.settings.language.contentLanguageCode == "ur" }

    private var isSearching: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The parahs show in Parah mode until something is typed, which finds surahs.
    private var showsParahs: Bool { listMode == .parah && !isSearching }

    private var searchBinding: Binding<String> {
        Binding(
            get: { viewModel.searchText },
            set: { viewModel.searchText = $0 }
        )
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                if let readerSelection {
                    ReadSectionPicker(selection: readerSelection)
                }
                switch viewModel.phase {
                case .loading:
                    ProgressView("Loading surahs…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DISpacing.xl)
                case .failed:
                    failedState
                case .loaded:
                    loadedContent
                }
            }
            .padding(.horizontal, DISpacing.md)
            .padding(.top, DISpacing.sm)
            .padding(.bottom, DISpacing.xl)
            .diResponsiveWidth()
        }
    }

    private var failedState: some View {
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
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var loadedContent: some View {
        if let progress = viewModel.lastRead,
           let surah = viewModel.continueReadingSurah {
            continueReadingCard(progress: progress, surah: surah)
                .diAppear()
        }
        HStack(spacing: 10) {
            ReadChipToggle(
                items: QuranListMode.allCases,
                title: { $0 == .surah ? "Surah" : "Parah" },
                selection: $listMode
            )
            .frame(width: 170)
            ReadFindField(prompt: "Name, number, 2:255", text: searchBinding)
        }
        if let typed = viewModel.typedAyah {
            goToAyahCard(surah: typed.surah, ayah: typed.ayah)
        }
        if showsParahs {
            paraPanel
        } else if viewModel.filteredSurahs.isEmpty {
            if viewModel.typedAyah == nil {
                DIEmptyState(
                    systemImage: "magnifyingglass",
                    titleKey: "No surahs match your search",
                    messageKey: "Try a surah name, its English meaning, or a number from 1 to 114."
                )
            }
        } else {
            surahPanel
        }
    }

    /// "2:255" typed into the find field opens that ayah.
    private func goToAyahCard(surah: QuranSurah, ayah: Int) -> some View {
        NavigationLink(value: QuranRoute.reader(surah: surah, focusAyah: ayah)) {
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
            .padding(DISpacing.md)
            .diGlassPanel(cornerRadius: 22)
        }
        .buttonStyle(DIPressableStyle())
    }

    /// The emerald hero: the surah left last, how far through it, and its
    /// name in Arabic.
    private func continueReadingCard(progress: ReadingProgress, surah: QuranSurah) -> some View {
        let fraction = surah.ayahCount > 0 ? Double(progress.ayahNumber) / Double(surah.ayahCount) : 0
        return NavigationLink(value: QuranRoute.reader(surah: surah, focusAyah: progress.ayahNumber)) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    ReadCaps("Continue reading", color: Color(hex: 0xFFE3A0))
                    if isUrdu {
                        Text(verbatim: surah.nameArabic)
                            .font(DIFont.quranArabic(scale: 0.85))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                    } else {
                        Text(verbatim: surah.nameTransliterated)
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text("Ayah \(progress.ayahNumber) of \(surah.ayahCount)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                    ReadProgressLight(fraction: fraction)
                        .padding(.top, DISpacing.sm)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: DISpacing.xs) {
                    if !isUrdu {
                        Text(verbatim: surah.nameArabic)
                            .font(DIFont.quranArabic(scale: 0.85))
                            .foregroundStyle(Color(hex: 0xFFE9A8))
                            .diGoldGlow(radius: 10, opacity: 0.6)
                            .lineLimit(1)
                    }
                    ReadPlayDisc()
                }
            }
            .padding(DISpacing.md)
            .background(DIHeroBackground(cornerRadius: 26))
            .readSheen(cornerRadius: 26)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(DIPressableStyle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Lists

    private var surahPanel: some View {
        let surahs = viewModel.filteredSurahs
        return LazyVStack(spacing: 0) {
            ForEach(Array(surahs.enumerated()), id: \.element.id) { index, surah in
                VStack(spacing: 0) {
                    if index > 0 {
                        ReadRowRule()
                    }
                    NavigationLink(value: QuranRoute.reader(surah: surah, focusAyah: nil)) {
                        SurahRow(
                            surah: surah,
                            isAvailableOffline: viewModel.hasOfflineText(surah),
                            isUrdu: isUrdu
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(6)
        .readGlassList(cornerRadius: 26)
    }

    /// The Qur'an by parah, as the Pakistani reader and the Silsila's printed
    /// Akram-ut-Tarajum divide it, each opened at its first ayah.
    private var paraPanel: some View {
        let paras = QuranParas.list(surahs: viewModel.surahs)
        return LazyVStack(spacing: 0) {
            ForEach(Array(paras.enumerated()), id: \.element.id) { index, para in
                VStack(spacing: 0) {
                    if index > 0 {
                        ReadRowRule()
                    }
                    NavigationLink(value: QuranRoute.reader(surah: para.surah, focusAyah: para.ayah)) {
                        QuranParaRow(para: para, opening: paraOpenings[para.number])
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(6)
        .readGlassList(cornerRadius: 26)
        .task { await loadParaOpenings(paras) }
    }

    @MainActor
    private func loadParaOpenings(_ paras: [QuranPara]) async {
        guard paraOpenings.isEmpty, !paras.isEmpty else { return }
        paraOpenings = await QuranParas.openings(for: paras, repository: dependencies.quranRepository)
    }
}

// MARK: - Surah row

private struct SurahRow: View {
    let surah: QuranSurah
    let isAvailableOffline: Bool
    /// Urdu content language, including "System" on an Urdu phone.
    let isUrdu: Bool

    var body: some View {
        HStack(spacing: 14) {
            ReadOctagramBadge(number: surah.id, gold: surah.revelationPlace == .madinah)

            VStack(alignment: .leading, spacing: 2) {
                if isUrdu {
                    // Urdu: the Arabic name followed by its Urdu meaning,
                    // mirroring the transliteration and English meaning.
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
                HStack(spacing: 6) {
                    DIPillBadge(
                        text: revelationPlaceName,
                        color: surah.revelationPlace == .makkah ? ReadPalette.makkahInk : ReadPalette.madinahInk
                    )
                    Text("\(surah.ayahCount) ayahs")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                .padding(.top, 3)
            }

            Spacer(minLength: DISpacing.sm)

            VStack(alignment: .trailing, spacing: DISpacing.xs) {
                if !isUrdu {
                    Text(surah.nameArabic)
                        .font(DIFont.quranArabic(scale: 0.62))
                        .foregroundStyle(ReadPalette.arabicInk)
                        .diGoldGlow(radius: 8, opacity: 0.3)
                }
                if isAvailableOffline {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(ReadPalette.emeraldInk)
                        .accessibilityLabel("Available offline")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var revelationPlaceName: String {
        switch surah.revelationPlace {
        case .makkah: return String(localized: "Makkah")
        case .madinah: return String(localized: "Madinah")
        }
    }
}

// MARK: - Parahs

/// One of the 30 parahs and the ayah it opens at.
struct QuranPara: Identifiable, Hashable {
    let number: Int
    let surah: QuranSurah
    let ayah: Int
    var id: Int { number }
}

/// The 30 parahs: the Silsila's printed divisions (`QuranDivisions.juzStarts`).
enum QuranParas {
    static func list(surahs: [QuranSurah]) -> [QuranPara] {
        QuranDivisions.juzStarts.enumerated().compactMap { index, start in
            guard start.count > 1, let surah = surahs.first(where: { $0.id == start[0] }) else { return nil }
            return QuranPara(number: index + 1, surah: surah, ayah: start[1])
        }
    }

    /// The first words of each parah's opening ayah, from the mushaf itself.
    @MainActor
    static func openings(for paras: [QuranPara], repository: any QuranRepositoryProtocol) async -> [Int: String] {
        var bySurah: [Int: [Int: String]] = [:]
        var found: [Int: String] = [:]
        for para in paras {
            if bySurah[para.surah.id] == nil {
                let ayahs = (try? await repository.ayahs(inSurah: para.surah.id)) ?? []
                bySurah[para.surah.id] = Dictionary(ayahs.map { ($0.ayahNumber, $0.textArabic) }, uniquingKeysWith: { first, _ in first })
            }
            if let text = bySurah[para.surah.id]?[para.ayah] {
                found[para.number] = text.split(separator: " ").prefix(4).joined(separator: " ")
            }
        }
        return found
    }
}

/// A parah on the Quran page: its number on the star, where it opens, and
/// its opening words from the mushaf.
private struct QuranParaRow: View {
    let para: QuranPara
    let opening: String?

    var body: some View {
        HStack(spacing: 14) {
            ReadOctagramBadge(number: para.number)
            VStack(alignment: .leading, spacing: 2) {
                Text("Parah \(para.number)")
                    .font(.headline)
                    .foregroundStyle(DIColor.textPrimary)
                Text(verbatim: "\(para.surah.nameTransliterated) \(para.surah.id):\(para.ayah)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
            }
            Spacer(minLength: DISpacing.sm)
            if let opening {
                Text(verbatim: opening)
                    .font(DIFont.quranArabic(scale: 0.6))
                    .foregroundStyle(ReadPalette.arabicInk)
                    .lineLimit(1)
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(maxWidth: 170, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Parah \(para.number)"))
    }
}

/// The 30 paras as a list of their own, each with the ayah it opens at and
/// that ayah's first words from the mushaf, opening the reader there. The
/// Quran page lists them in place now; this stays routable (`.paras`).
struct QuranParaListView: View {
    let dependencies: AppDependencies
    let surahs: [QuranSurah]
    @State private var openings: [Int: String] = [:]

    private var paras: [QuranPara] { QuranParas.list(surahs: surahs) }

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

    @MainActor
    private func loadOpenings() async {
        guard openings.isEmpty else { return }
        openings = await QuranParas.openings(for: paras, repository: dependencies.quranRepository)
    }
}
