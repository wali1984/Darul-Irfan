import SwiftUI

/// Ayah-by-ayah reader for one surah. Shows Arabic with word-by-word recitation
/// highlighting, the Akram-ut-Tarajum translation, and an expandable tafsir
/// (Asrar-at-Tanzil / Akram-ut-Tafaseer) selected from a segmented control.
struct SurahReaderView: View {
    private let appState: AppState
    private let focusAyah: Int?
    private let onRequestNextSurah: () -> Void
    /// Needed to turn a linked bayan into something playable: the index stores
    /// only the media id, so the catalogue stays the one description of a
    /// lecture.
    private let mediaRepository: any MediaRepositoryProtocol
    private let audioPlayer: any AudioPlayerServicing
    private let dependencies: AppDependencies
    @State private var viewModel: SurahReaderViewModel
    @State private var player = QuranListenPlayer.shared
    @State private var speaker = TranslationSpeaker()
    @AppStorage("quranListenContent") private var listenContent: QuranListenContent = .arabic
    @AppStorage("quranListenScope") private var listenScope: QuranListenScope = .surah
    @State private var hasScrolledToFocus = false
    @State private var hasAutoAdvanced = false
    @State private var bayanError: String?

    init(
        surah: QuranSurah,
        focusAyah: Int?,
        dependencies: AppDependencies,
        appState: AppState,
        onRequestNextSurah: @escaping () -> Void
    ) {
        self.appState = appState
        self.focusAyah = focusAyah
        self.onRequestNextSurah = onRequestNextSurah
        self.mediaRepository = dependencies.mediaRepository
        self.audioPlayer = dependencies.audioPlayer
        self.dependencies = dependencies
        let langCode = SurahReaderViewModel.initialReadingLanguage(
            appLanguage: appState.settings.language.contentLanguageCode
        )
        _viewModel = State(initialValue: SurahReaderViewModel(
            surah: surah,
            repository: dependencies.quranRepository,
            devotionalMetrics: dependencies.devotionalMetrics,
            preferredLanguageCode: langCode
        ))
    }

    var body: some View {
        content
            .diScreenBackground()
            .navigationTitle(viewModel.surah.nameTransliterated)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.phase == .ready {
                    // Deliberately its own toolbar item rather than a row in the
                    // scroll view or a line inside the options menu: the header
                    // selectors scroll away, and a reader has to be able to
                    // change language at any point without hunting for it.
                    if viewModel.availableReadingLanguages.count > 1 {
                        ToolbarItem(placement: .topBarTrailing) {
                            readingLanguageMenu
                        }
                    }
                    if viewModel.recitation != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink {
                                HifzView(surah: viewModel.surah, dependencies: dependencies)
                            } label: {
                                Image(systemName: "brain.head.profile")
                            }
                            .accessibilityLabel("Memorise this surah")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        readerOptionsMenu
                    }
                }
            }
            .task {
                // Notes are counted on each ayah card; read them once here
                // rather than during a card's render.
                MyDayStore.shared.loadIfNeeded()
                await viewModel.load()
                await NarrationCatalog.shared.load()
            }
            .onDisappear {
                // A juz carries on into the next surah's reader; anything
                // else stops with the surah it belongs to.
                if player.scope != .juz || !player.isPlaying { player.stop() }
                speaker.stop()
                let readerViewModel = viewModel
                Task { await readerViewModel.flushLastRead() }
            }
    }

    // MARK: - Phases

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .textUnavailable:
            textUnavailableView
        case .failed:
            VStack(spacing: DISpacing.md) {
                DIEmptyState(
                    systemImage: "book.closed",
                    titleKey: "This surah could not be opened",
                    messageKey: "Something went wrong while loading. Please go back and try again."
                )
                Button("Try Again") {
                    Task { await viewModel.load() }
                }
                .buttonStyle(DISecondaryButtonStyle())
                .padding(.horizontal, DISpacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            readerScroll
        }
    }

    private var textUnavailableView: some View {
        ScrollView {
            VStack(spacing: DISpacing.md) {
                DIEmptyState(
                    systemImage: "arrow.down.circle",
                    titleKey: "This surah's text is not on your device yet",
                    messageKey: "Offline text packs arrive automatically through verified content updates."
                )
            }
            .padding(.vertical, DISpacing.xl)
        }
    }

    // MARK: - Reader

    private var readerScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DISpacing.md) {
                    surahHeader
                    if showsBismillahHeader {
                        bismillahHeader
                    }
                    if viewModel.recitation != nil || canPlayTranslation {
                        listenBar
                    }
                    if appState.settings.quranReaderDisplayMode.showsTranslation {
                        contentModeSelector
                    }
                    if !viewModel.bayans.isEmpty {
                        bayanCard
                    }
                    if appState.settings.quranReaderDisplayMode.showsTranslation
                        && viewModel.contentMode.isTafsir
                        && !viewModel.hasTafsirForMode {
                        // No verse-by-verse commentary in this language: the
                        // full printed volume comes first, then the other
                        // language if it has the per-verse text.
                        if !viewModel.fullVolumes.isEmpty {
                            tafsirVolumesCard(isPrimary: true)
                        }
                        if !viewModel.readingLanguagesWithTafsirForMode.isEmpty {
                            otherLanguageTafsirCard
                        } else if viewModel.fullVolumes.isEmpty && !viewModel.tafsirEditionPointers.isEmpty {
                            tafsirPointerCard
                        }
                    }
                    ForEach(viewModel.ayahs, id: \.ayahNumber) { ayah in
                        AyahCardView(
                            ayah: ayah,
                            viewModel: viewModel,
                            dependencies: dependencies,
                            player: player,
                            speaker: speaker,
                            listen: { start(from: $0) },
                            fontScale: appState.settings.readerFontScale.rawValue,
                            displayMode: appState.settings.quranReaderDisplayMode
                        )
                        .id(ayah.ayahNumber)
                        .onAppear { viewModel.ayahBecameVisible(ayah.ayahNumber) }
                    }
                    if appState.settings.quranReaderDisplayMode.showsTranslation
                        && viewModel.contentMode.isTafsir
                        && viewModel.hasTafsirForMode
                        && !viewModel.fullVolumes.isEmpty {
                        tafsirVolumesCard(isPrimary: false)
                    }
                    readerEndMarker
                }
                .padding(.horizontal, DISpacing.md)
                .padding(.top, DISpacing.sm)
                .padding(.bottom, DISpacing.xl)
            }
            .onAppear { scrollToFocusIfNeeded(proxy: proxy) }
        }
    }

    private func scrollToFocusIfNeeded(proxy: ScrollViewProxy) {
        guard !hasScrolledToFocus else { return }
        hasScrolledToFocus = true
        guard let focusAyah, focusAyah > 1 else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(focusAyah, anchor: .top)
        }
    }

    @ViewBuilder
    private var readerEndMarker: some View {
        if viewModel.surah.id < 114 {
            if appState.settings.quranAutoAdvanceSurah {
                HStack(spacing: DISpacing.sm) {
                    ProgressView()
                    Text("Opening next surah…")
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DISpacing.md)
                .onAppear(perform: requestNextSurahIfNeeded)
            }
        } else {
            Label("Quran reading complete", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DIColor.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DISpacing.md)
        }
    }

    private func requestNextSurahIfNeeded() {
        guard appState.settings.quranAutoAdvanceSurah,
              viewModel.surah.id < 114,
              !hasAutoAdvanced else { return }
        hasAutoAdvanced = true
        onRequestNextSurah()
    }

    private var surahHeader: some View {
        DICard {
            VStack(spacing: DISpacing.sm) {
                Text(viewModel.surah.nameArabic)
                    .font(DIFont.quranArabic(scale: 1.15))
                    .foregroundStyle(DIColor.primary)
                    .diGoldGlow(radius: 7, opacity: 0.28)
                Text(viewModel.surah.nameEnglish)
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                HStack(spacing: DISpacing.sm) {
                    DIPillBadge(
                        text: revelationPlaceName,
                        color: viewModel.surah.revelationPlace == .makkah ? DIColor.primary : DIColor.accent
                    )
                    Text("\(viewModel.surah.ayahCount) ayahs")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    /// Whether to print the Basmala above the first ayah.
    ///
    /// Every surah opens with it except **at-Tawbah (9)**, which alone has no
    /// Basmala. **Al-Fatihah (1)** is excluded for the opposite reason: there the
    /// Basmala is ayah 1 itself in the Kufan numbering this mushaf follows, so a
    /// header would print it twice. (An-Naml (27) also carries a Basmala inside
    /// ayah 30, within Sulayman's letter — that is part of the verse text and is
    /// unaffected by this header.)
    private var showsBismillahHeader: Bool {
        viewModel.surah.id != 1 && viewModel.surah.id != 9
    }

    /// The Basmala line. The text is not hardcoded: it is taken from the mushaf
    /// the app ships (Al-Fatihah 1:1), so it always matches the bundled
    /// orthography — IndoPak here — instead of drifting from it.
    @ViewBuilder
    private var bismillahHeader: some View {
        if let text = viewModel.bismillahText {
            DICard {
                Text(verbatim: text)
                    .font(DIFont.quranArabic(scale: appState.settings.readerFontScale.rawValue))
                    .foregroundStyle(DIColor.primary)
                    .diGoldGlow(radius: 6, opacity: 0.25)
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text("Bismillah ir-Rahman ir-Raheem"))
            }
        }
    }

    private var revelationPlaceName: String {
        switch viewModel.surah.revelationPlace {
        case .makkah: return String(localized: "Makkah")
        case .madinah: return String(localized: "Madinah")
        }
    }

    // MARK: - Listen

    /// The translation on screen, when its narration exists.
    private var narratedTranslationEdition: String? {
        let edition = viewModel.translationEdition?.id
        return QuranListenPlayer.hasTranslation(edition: edition) ? edition : nil
    }

    private var canPlayTranslation: Bool { narratedTranslationEdition != nil }

    /// What can be chosen here: the recitation needs the reciter's timings,
    /// the translation its narration.
    private var listenContents: [QuranListenContent] {
        QuranListenContent.allCases.filter { content in
            switch content {
            case .arabic: return viewModel.recitation != nil
            case .translation: return canPlayTranslation
            case .both: return viewModel.recitation != nil && canPlayTranslation
            }
        }
    }

    private var effectiveContent: QuranListenContent {
        listenContents.contains(listenContent) ? listenContent : (listenContents.first ?? .arabic)
    }

    /// Starts playback at an ayah in the chosen mode and range.
    private func start(from ayahNumber: Int) {
        speaker.stop()
        player.start(from: AyahRef(surah: viewModel.surah.id, ayah: ayahNumber), content: effectiveContent,
                     scope: listenScope, translationEdition: narratedTranslationEdition)
    }

    /// Recitation, translation, or both ayah by ayah - over an ayah, ruku,
    /// surah or juz (para) - from the top, or from any ayah's play button.
    private var listenBar: some View {
        let isHere = player.isActive(inSurah: viewModel.surah.id)
        let isPlaying = player.isPlaying && isHere
        return DICard(padding: DISpacing.sm) {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.md) {
                    Button {
                        if isPlaying {
                            player.pause()
                        } else if isHere {
                            speaker.stop()
                            player.resume()
                        } else {
                            start(from: 1)
                        }
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(DIColor.primary)
                    }
                    .accessibilityLabel(isPlaying ? Text("Pause") : Text("Play"))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Listen")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DIColor.textPrimary)
                        Text(listenSubtitle)
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isHere {
                        if isPlaying {
                            Image(systemName: "waveform")
                                .foregroundStyle(DIColor.accent)
                                .symbolEffect(.variableColor.iterative, options: .repeating)
                        }
                        Button {
                            player.stop()
                        } label: {
                            Image(systemName: "stop.circle")
                                .font(.title3)
                                .foregroundStyle(DIColor.textMuted)
                        }
                        .accessibilityLabel(Text("Stop"))
                    }
                }
                if listenContents.count > 1 {
                    DISegmentedControl(
                        items: listenContents,
                        title: { content in
                            switch content {
                            case .arabic: return "Recitation"
                            case .translation: return "Translation"
                            case .both: return "Both"
                            }
                        },
                        selection: Binding(get: { effectiveContent }, set: { listenContent = $0 })
                    )
                }
                Picker(selection: $listenScope) {
                    Text("Ayah").tag(QuranListenScope.ayah)
                    Text("Ruku").tag(QuranListenScope.ruku)
                    Text("Surah").tag(QuranListenScope.surah)
                    Text("Juz (Para)").tag(QuranListenScope.juz)
                } label: {
                    Text("Play to the end of")
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(Text("Play to the end of"))
            }
        }
        .onChange(of: listenContent) { if isHere { player.stop() } }
        .onChange(of: listenScope) { if isHere { player.stop() } }
    }

    /// Who reads: the reciter, the translation, or both.
    private var listenSubtitle: String {
        switch effectiveContent {
        case .arabic: return RecitationProvider.shared.reciterName
        case .translation: return viewModel.translationEdition?.title ?? String(localized: "Translation")
        case .both: return String(localized: "Recitation, then translation, ayah by ayah")
        }
    }

    /// Segmented control choosing translation-only vs a tafsir edition.
    private var contentModeSelector: some View {
        DISegmentedControl(
            items: QuranContentMode.allCases,
            title: { LocalizedStringKey($0.shortTitle) },
            selection: contentModeBinding
        )
    }

    /// The sheikh's bayans on this surah, each labelled with the verses it
    /// expounds so a reader can go straight to the one covering what they are
    /// reading. Only part of the catalogue is verse-addressed, so this appears
    /// for the surahs that have such lectures and is absent elsewhere rather
    /// than showing an empty shelf.
    private var bayanCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                DISectionHeader(titleKey: "Bayan on these verses", systemImage: "waveform")
                ForEach(viewModel.bayans) { link in
                    Button {
                        DIHaptics.light()
                        play(link)
                    } label: {
                        HStack(spacing: DISpacing.sm) {
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(DIColor.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.title)
                                    .font(.subheadline.weight(.medium))
                                    .multilineTextAlignment(.leading)
                                Text(LocalizedStringKey("Ayat \(link.ayahStart)-\(link.ayahEnd)"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                if let error = bayanError {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Resolves the linked lecture in the media catalogue and hands it to the
    /// shared player, so it keeps playing with the mini player and Lock Screen
    /// controls the rest of the app already uses.
    private func play(_ link: AyahBayanLink) {
        let repository = mediaRepository
        let player = audioPlayer
        Task {
            guard let item = try? await repository.item(id: link.mediaID) else {
                bayanError = "This bayan is not in the offline catalogue yet."
                return
            }
            guard let stream = item.streamUrl, let url = URL(string: stream) else {
                bayanError = "This bayan has no playable audio source."
                return
            }
            bayanError = nil
            player.play(
                AudioPlayableItem(
                    id: item.id,
                    title: item.title,
                    subtitle: item.speaker,
                    url: url,
                    mediaItemID: item.id
                ),
                queue: []
            )
        }
    }

    /// Shown when this commentary exists for the surah, but not in the language
    /// being read. It offers the switch rather than substituting the other
    /// language, which would hand an Urdu reader English prose or the reverse.
    private var otherLanguageTafsirCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                if viewModel.fullVolumes.isEmpty {
                    Text("\(viewModel.contentMode.localizedTitle) is not in this language")
                        .font(.headline)
                    Text("This commentary has not been prepared in the language you are reading. It is available in:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Verse by verse, this commentary is available in:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: DISpacing.sm) {
                    ForEach(viewModel.readingLanguagesWithTafsirForMode, id: \.self) { code in
                        Button(Self.readingLanguageName(code)) {
                            DIHaptics.light()
                            let readerViewModel = viewModel
                            Task { await readerViewModel.setReadingLanguage(code) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    /// The whole printed commentary on this surah, opened at the page where
    /// the surah begins. Primary when there is no verse-by-verse text in the
    /// language being read (Asrar-at-Tanzil in Urdu); otherwise offered at the
    /// end for anyone who wants to keep reading the book itself.
    private func tafsirVolumesCard(isPrimary: Bool) -> some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text(isPrimary ? "Read the full commentary" : "Continue in the full volume")
                    .font(.headline)
                Text(isPrimary
                     ? "Verse-by-verse commentary is not available for this surah in this language. The complete printed text is available below, opened where this surah begins."
                     : "The complete printed commentary, opened where this surah begins.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(viewModel.fullVolumes) { volume in
                    NavigationLink {
                        TafsirVolumeDestination(volume: volume, dependencies: dependencies)
                    } label: {
                        Label {
                            Text(volumeTitle(volume))
                                .font(.subheadline.weight(.medium))
                                .multilineTextAlignment(.leading)
                        } icon: {
                            Image(systemName: "text.book.closed")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
                Text("Machine-read from the printed book and not yet proofread.")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
    }

    private func volumeTitle(_ volume: TafsirVolume) -> String {
        if volume.bookID.hasPrefix("tafaseer-parah-"),
           let parah = Int(volume.bookID.dropFirst("tafaseer-parah-".count)) {
            return String(localized: "\(viewModel.contentMode.localizedTitle), Parah \(parah), from page \(volume.page)")
        }
        return String(localized: "\(viewModel.contentMode.localizedTitle): Surah \(viewModel.surah.nameTransliterated)")
    }

    /// Native availability status for a tafsir edition not yet included for
    /// this surah. The edition remains visible so content updates are seamless.
    private var tafsirPointerCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Tafsir availability")
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                Text("This tafsir is not included for this surah in the current offline edition. Darul Irfan checks for verified native content updates automatically.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
                ForEach(viewModel.tafsirEditionPointers) { edition in
                    Label(edition.title, systemImage: "clock.arrow.circlepath")
                        .font(.footnote)
                        .foregroundStyle(DIColor.primary)
                }
            }
        }
    }

    // MARK: - Toolbar

    /// Always-visible language switch. Shows the language being read and moves
    /// both the translation and the commentary when it changes, so the two never
    /// disagree about which language the reader asked for.
    private var readingLanguageMenu: some View {
        Menu {
            Picker("Reading language", selection: readingLanguageBinding) {
                ForEach(viewModel.availableReadingLanguages, id: \.self) { code in
                    Text(Self.readingLanguageName(code)).tag(code)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "character.book.closed")
                Text(Self.readingLanguageShortName(viewModel.readingLanguage))
                    .font(.footnote.weight(.semibold))
            }
        }
        .accessibilityLabel("Reading language")
        .accessibilityValue(Self.readingLanguageName(viewModel.readingLanguage))
    }

    private var readingLanguageBinding: Binding<String> {
        Binding(
            get: { viewModel.readingLanguage },
            set: { code in
                DIHaptics.light()
                let readerViewModel = viewModel
                Task { await readerViewModel.setReadingLanguage(code) }
            }
        )
    }

    /// Each language in its own script, which is how a reader recognises it.
    static func readingLanguageName(_ code: String) -> String {
        switch code {
        case "en": "English"
        case "ur": "اردو"
        case "ar": "العربية"
        default: code.uppercased()
        }
    }

    static func readingLanguageShortName(_ code: String) -> String {
        switch code {
        case "en": "EN"
        case "ur": "اردو"
        case "ar": "ع"
        default: code.uppercased()
        }
    }

    private var readerOptionsMenu: some View {
        Menu {
            Picker("Text Size", selection: fontScaleBinding) {
                ForEach(ReaderFontScale.allCases) { scale in
                    Text(LocalizedStringKey(scale.readerDisplayName)).tag(scale)
                }
            }
            Picker("Reading display", selection: displayModeBinding) {
                ForEach(QuranReaderDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Toggle("Automatically open next surah", isOn: autoAdvanceBinding)
            if appState.settings.quranReaderDisplayMode.showsTranslation,
               viewModel.availableTranslationEditions.count > 1 {
                Picker("Translation", selection: editionBinding) {
                    ForEach(viewModel.availableTranslationEditions) { edition in
                        Text(edition.title).tag(edition.id)
                    }
                }
            }
        } label: {
            Image(systemName: "textformat.size")
        }
        .accessibilityLabel("Reader options")
    }

    private var fontScaleBinding: Binding<ReaderFontScale> {
        Binding(
            get: { appState.settings.readerFontScale },
            set: { newValue in
                Task { await appState.updateSettings { $0.readerFontScale = newValue } }
            }
        )
    }

    private var editionBinding: Binding<String> {
        Binding(
            get: { viewModel.translationEdition?.id ?? "" },
            set: { newID in Task { await viewModel.selectEdition(newID) } }
        )
    }

    private var displayModeBinding: Binding<QuranReaderDisplayMode> {
        Binding(
            get: { appState.settings.quranReaderDisplayMode },
            set: { newValue in
                Task { await appState.updateSettings { $0.quranReaderDisplayMode = newValue } }
            }
        )
    }

    private var autoAdvanceBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.quranAutoAdvanceSurah },
            set: { newValue in
                Task { await appState.updateSettings { $0.quranAutoAdvanceSurah = newValue } }
            }
        )
    }

    private var contentModeBinding: Binding<QuranContentMode> {
        Binding(
            get: { viewModel.contentMode },
            set: { viewModel.contentMode = $0 }
        )
    }
}

// MARK: - Tafsir volume

/// Opens a tafsir volume's text at a page. The library row gives the title;
/// if the library has not imported it, a minimal item still opens the pages,
/// which is all the text reader needs.
struct TafsirVolumeDestination: View {
    let volume: TafsirVolume
    let dependencies: AppDependencies
    @State private var item: ContentItem?

    var body: some View {
        Group {
            if let item {
                BookTextReaderView(item: item, dependencies: dependencies, startPage: volume.page)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            let stored = try? await dependencies.contentRepository.item(id: volume.bookID)
            item = stored ?? ContentItem(
                id: volume.bookID,
                sourceUrl: "",
                type: .book,
                title: volume.bookID,
                titleUrdu: nil,
                language: volume.language,
                author: nil,
                category: .quranTafsir,
                bodyHtml: nil,
                bodyPlainText: nil,
                excerpt: nil,
                publishedAt: nil,
                updatedAt: nil,
                mediaUrls: [],
                downloadUrls: [],
                checksum: nil,
                rightsStatus: .permissionConfirmed
            )
        }
    }
}

// MARK: - Ayah card

private struct AyahCardView: View {
    let ayah: QuranAyah
    let viewModel: SurahReaderViewModel
    let dependencies: AppDependencies
    let player: QuranListenPlayer
    let speaker: TranslationSpeaker
    let listen: (Int) -> Void
    let fontScale: Double
    let displayMode: QuranReaderDisplayMode

    @ScaledMetric(relativeTo: .body) private var bodyBaseSize: CGFloat = 17
    @State private var tafsirExpanded = true
    @State private var isWritingNote = false
    @State private var showsTafsir = false

    private var isSounding: Bool {
        player.isSounding(surah: ayah.surahNumber, ayah: ayah.ayahNumber)
    }


    var body: some View {
        DICard(
            background: DIColor.primary.opacity(0.055),
            borderColor: DIColor.primary.opacity(0.45),
            borderWidth: 1.5
        ) {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                header
                if displayMode.showsArabic {
                    arabicText
                }
                if displayMode.showsTranslation,
                   let translation = viewModel.translation(for: ayah.ayahNumber) {
                    if displayMode.showsArabic { Divider() }
                    translationView(translation)
                }
                if displayMode.showsTranslation,
                   viewModel.contentMode.isTafsir,
                   let entry = viewModel.tafsirEntry(startingAt: ayah.ayahNumber) {
                    Divider()
                    tafsirDisclosure(entry)
                }
                Divider()
                shellsRow
            }
        }
        .sheet(isPresented: $showsTafsir) {
            NavigationStack {
                AyahTafsirSheet(ayah: ayah, viewModel: viewModel, dependencies: dependencies, fontScale: fontScale)
            }
        }
        .overlay(alignment: .leading) {
            if isSounding {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DIColor.accent)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
    }

    // MARK: Header (per-ayah toolbar)

    private var header: some View {
        HStack(spacing: DISpacing.md) {
            ayahNumberBadge
            playButton
            Spacer(minLength: 0)
            // Either tafsir, in either language, for this ayah alone.
            Button {
                showsTafsir = true
            } label: {
                Label("Tafsir", systemImage: "text.book.closed")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, DISpacing.sm)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(DIColor.primary.opacity(0.12)))
                    .foregroundStyle(DIColor.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Tafsir of Ayah \(ayah.ayahNumber)"))
            Button {
                Task { await viewModel.toggleBookmark(ayahNumber: ayah.ayahNumber) }
            } label: {
                Image(systemName: viewModel.isBookmarked(ayah.ayahNumber) ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(viewModel.isBookmarked(ayah.ayahNumber) ? DIColor.accent : DIColor.textMuted)
            }
            .accessibilityLabel(
                viewModel.isBookmarked(ayah.ayahNumber)
                    ? Text("Remove bookmark from Ayah \(ayah.ayahNumber)")
                    : Text("Bookmark Ayah \(ayah.ayahNumber)")
            )

            ShareLink(item: viewModel.shareReference(for: ayah.ayahNumber)) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(DIColor.textMuted)
            }
            .accessibilityLabel(Text("Share reference to Ayah \(ayah.ayahNumber)"))
        }
    }

    @ViewBuilder
    private var playButton: some View {
        if viewModel.recitation != nil || QuranListenPlayer.hasTranslation(edition: viewModel.translationEdition?.id) {
            Button {
                if isSounding {
                    player.pause()
                } else {
                    listen(ayah.ayahNumber)
                }
            } label: {
                Image(systemName: isSounding ? "pause.circle.fill" : "play.circle")
                    .foregroundStyle(isSounding ? DIColor.accent : DIColor.primary)
            }
            .accessibilityLabel(isSounding ? Text("Pause") : Text("Play Ayah \(ayah.ayahNumber)"))
        }
    }

    private var ayahNumberBadge: some View {
        Text("\(ayah.ayahNumber)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(DIColor.primaryDeep)
            .frame(minWidth: 30, minHeight: 30)
            .background(
                Circle()
                    .fill(DIGradient.goldSheen)
                    .overlay(Circle().stroke(DIColor.accent.opacity(0.6), lineWidth: 1))
            )
            .diGoldGlow(radius: 4, opacity: 0.25)
            .accessibilityLabel(Text("Ayah \(ayah.ayahNumber)"))
    }

    // MARK: Arabic (word-by-word highlight)

    private var arabicText: some View {
        Group {
            if let words = viewModel.words(forAyah: ayah.ayahNumber), !words.isEmpty {
                Text(highlightedArabic(words: words))
            } else {
                Text(ayah.textArabic)
            }
        }
        .font(DIFont.quranArabic(scale: fontScale * 1.15))
        .lineSpacing(CGFloat(18 * fontScale))
        .foregroundStyle(DIColor.textPrimary)
        .diGoldGlow(radius: 5, opacity: 0.18)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.layoutDirection, .rightToLeft)
    }

    /// Joins the recitation words, tinting the one currently sounding.
    private func highlightedArabic(words: [RecitationWord]) -> AttributedString {
        let highlight = isSounding && player.part == .arabic ? player.currentWordPosition : nil
        var result = AttributedString()
        for (index, word) in words.enumerated() {
            var piece = AttributedString(word.text)
            if word.position == highlight {
                piece.backgroundColor = DIColor.accent.opacity(0.30)
                piece.foregroundColor = DIColor.primaryDeep
            }
            result += piece
            if index < words.count - 1 {
                result += AttributedString(" ")
            }
        }
        return result
    }

    // MARK: Translation

    private func translationView(_ translation: QuranTranslation) -> some View {
        // No per-ayah edition caption — the work is already named in the
        // content-mode selector above, so repeating it under every ayah is noise.
        VStack(alignment: .leading, spacing: DISpacing.xs) {
            bodyText(
                translation.text,
                languageCode: viewModel.edition(id: translation.editionID)?.language
            )
        }
    }

    // MARK: Tafsir (expandable, expanded by default)

    private func tafsirDisclosure(_ entry: QuranTafsir) -> some View {
        let edition = viewModel.edition(id: entry.editionID)
        return DisclosureGroup(isExpanded: $tafsirExpanded) {
            VStack(alignment: .leading, spacing: DISpacing.xs) {
                if edition?.language == "ur" && !entry.text.isEmpty {
                    // Urdu tafsir quotes the Qur'an inside its prose; set
                    // the quotations apart as the book pages do.
                    FormattedBookPage(page: BookPageFormatter.format(entry.text), scale: fontScale)
                } else if !entry.text.isEmpty {
                    bodyText(entry.text, languageCode: edition?.language)
                }
            }
            .padding(.top, DISpacing.xs)
        } label: {
            Text(edition?.title ?? "Tafsir")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DIColor.primary)
        }
        .tint(DIColor.primary)
    }

    // MARK: Listen and note

    private var shellsRow: some View {
        VStack(alignment: .leading, spacing: DISpacing.xs) {
            HStack(spacing: DISpacing.sm) {
                if let passage = narratedTafsirPassage {
                    Button {
                        player.stop()
                        speaker.toggle(edition: passage.editionID, kind: "tafsir", surah: passage.surahNumber,
                                       ayah: passage.ayahStart, end: passage.ayahEnd, lastAyah: viewModel.surah.ayahCount)
                    } label: {
                        shellChip(
                            isReadingTafsir ? "Stop" : "Listen to tafsir",
                            isReadingTafsir ? "stop.fill" : "text.bubble",
                            enabled: true
                        )
                    }
                    .accessibilityLabel(
                        isReadingTafsir
                            ? Text("Stop the tafsir narration")
                            : Text("Listen to the tafsir of Ayah \(ayah.ayahNumber)")
                    )
                }
                // A private note on this ayah, kept in My Day on this phone.
                Button {
                    isWritingNote = true
                } label: {
                    shellChip(noteCount > 0 ? String(localized: "Notes (\(noteCount))") : String(localized: "Note"), "square.and.pencil", enabled: true)
                }
                .accessibilityLabel(Text("Write a note on Ayah \(ayah.ayahNumber)"))
            }
        }
        .sheet(isPresented: $isWritingNote) {
            NavigationStack {
                NoteEditorView(note: nil, reference: noteReference)
            }
        }
    }

    private var noteReference: NoteReference {
        NoteReference(
            kind: .ayah,
            itemID: "\(ayah.surahNumber):\(ayah.ayahNumber)",
            label: "\(viewModel.surah.nameTransliterated) \(ayah.surahNumber):\(ayah.ayahNumber)"
        )
    }

    private var noteCount: Int {
        MyDayStore.shared.notes(about: noteReference).count
    }

    /// The tafsir passage beginning at this ayah, when it has a narration.
    private var narratedTafsirPassage: QuranTafsir? {
        guard let passage = viewModel.tafsirEntry(startingAt: ayah.ayahNumber),
              NarrationCatalog.shared.has(edition: passage.editionID, kind: "tafsir", surah: passage.surahNumber,
                                          start: passage.ayahStart, end: passage.ayahEnd)
        else { return nil }
        return passage
    }

    private var isReadingTafsir: Bool {
        speaker.currentKind == "tafsir" && speaker.isSounding(surah: ayah.surahNumber, ayah: ayah.ayahNumber)
    }

    private func shellChip(_ label: String, _ icon: String, enabled: Bool) -> some View {
        Label(LocalizedStringKey(label), systemImage: icon)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, DISpacing.sm)
            .padding(.vertical, 5)
            .background(Capsule().fill(enabled ? DIColor.primary.opacity(0.12) : DIColor.sandstone.opacity(0.45)))
            .overlay(Capsule().stroke(enabled ? DIColor.primary.opacity(0.4) : DIColor.textMuted.opacity(0.25), lineWidth: 1))
            .foregroundStyle(enabled ? DIColor.primary : DIColor.textMuted)
    }

    // MARK: Language-aware body text

    /// Direction comes from the text's own language, never from the app's
    /// layout. Without the explicit left-to-right, English inherited the
    /// right-to-left environment whenever the app was in Urdu and read
    /// right-aligned like Urdu.
    @ViewBuilder
    private func bodyText(_ text: String, languageCode: String?) -> some View {
        if languageCode == "ur" || languageCode == "ar" {
            Text(verbatim: text)
                .font(DIFont.urduBody(scale: fontScale))
                .lineSpacing(CGFloat(8 * fontScale))
                .foregroundStyle(DIColor.textPrimary)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .rightToLeft)
        } else {
            Text(verbatim: text)
                .font(.system(size: bodyBaseSize * CGFloat(fontScale)))
                .lineSpacing(CGFloat(4 * fontScale))
                .foregroundStyle(DIColor.textPrimary)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}

// MARK: - Font scale display names

private extension ReaderFontScale {
    var readerDisplayName: String {
        switch self {
        case .small: return "Small"
        case .standard: return "Standard"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }
}
