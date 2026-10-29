import SwiftUI

/// Ayah-by-ayah reader for one surah. Shows the mushaf Arabic, tinting the
/// word the reciter is sounding, the Akram-ut-Tarajum translation, and an
/// expandable tafsir (Asrar-at-Tanzil / Akram-ut-Tafaseer) selected from a
/// segmented control.
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
    @State private var showsBayanList = false
    /// The ayah at the top of the screen; it is where the reader is.
    @State private var topAyah: Int?
    /// Set once the reader has scrolled into the surah, so reaching its end
    /// can open the next one; a surah that fits on the screen never fires.
    @State private var hasScrolledIntoSurah = false
    /// Only the reader on screen follows the recitation. A reader further
    /// back in the stack, or one being left, must not scroll or push.
    @State private var isOnScreen = false
    /// Set just before a juz is handed on to the next surah's reader, so
    /// leaving this one does not stop the recitation.
    @State private var isHandingOnJuz = false
    @State private var showsGoToAyah = false
    @State private var goToAyahText = ""
    @State private var pendingScrollAyah: Int?
    /// Volumes whose book still has original OCR pages, which carry the
    /// "not yet proofread" line; the re-read volumes do not.
    @State private var machineReadVolumeIDs: Set<String> = []

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
                    // The sheikhs' bayans on this surah, to choose from; the
                    // ayat carry their own notes, so nothing is set above the
                    // text.
                    if !viewModel.bayans.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showsBayanList = true
                            } label: {
                                Image(systemName: "waveform.circle")
                            }
                            .accessibilityLabel(Text("Bayans on this surah"))
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
            .alert("Go to ayah", isPresented: $showsGoToAyah) {
                TextField("Ayah number", text: $goToAyahText)
                    .keyboardType(.numberPad)
                Button("Go") { goToTypedAyah() }
                Button("Cancel", role: .cancel) { goToAyahText = "" }
            } message: {
                Text("1 to \(viewModel.surah.ayahCount)")
            }
            .sheet(isPresented: $showsBayanList) {
                NavigationStack {
                    BayanListSheet(links: viewModel.bayans) { play($0) }
                }
            }
            .task {
                // Notes are counted on each ayah card; read them once here
                // rather than during a card's render.
                MyDayStore.shared.loadIfNeeded()
                await viewModel.load()
                await NarrationCatalog.shared.load()
            }
            .onAppear {
                isOnScreen = true
                isHandingOnJuz = false
            }
            .onDisappear {
                isOnScreen = false
                // The recitation stops with the reader that started it. Only a
                // juz being handed on to the next surah's reader carries on;
                // anything else would keep sounding with no control in reach.
                if !isHandingOnJuz { player.stop() }
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
                        } else if viewModel.fullVolumes.isEmpty {
                            tafsirMissingCard
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
                            displayMode: appState.settings.quranReaderDisplayMode,
                            playBayan: { play($0) },
                            scrollToAyah: { pendingScrollAyah = $0 }
                        )
                        .id(ayah.ayahNumber)
                    }
                    if appState.settings.quranReaderDisplayMode.showsTranslation
                        && viewModel.contentMode.isTafsir
                        && viewModel.hasTafsirForMode
                        && !viewModel.fullVolumes.isEmpty {
                        tafsirVolumesCard(isPrimary: false)
                    }
                    readerEndMarker
                }
                .scrollTargetLayout()
                .padding(.horizontal, DISpacing.md)
                .padding(.top, DISpacing.sm)
                .padding(.bottom, DISpacing.xl)
            }
            .scrollPosition(id: $topAyah, anchor: .top)
            .alert("Bayan", isPresented: Binding(get: { bayanError != nil }, set: { if !$0 { bayanError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(bayanError ?? "")
            }
            .onChange(of: topAyah) { _, ayah in
                guard let ayah else { return }
                if ayah > 1 { hasScrolledIntoSurah = true }
                viewModel.topAyahChanged(ayah)
            }
            .onAppear {
                scrollToFocusIfNeeded(proxy: proxy)
                // A juz carried into this surah: show the ayah it is on.
                if let current = player.current, current.surah == viewModel.surah.id, player.isPlaying {
                    DispatchQueue.main.async { proxy.scrollTo(current.ayah, anchor: .top) }
                }
            }
            .onChange(of: pendingScrollAyah) { _, ayah in
                guard let ayah else { return }
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(ayah, anchor: .top) }
                pendingScrollAyah = nil
            }
            // The reader follows what is playing: each ayah is brought into
            // view as it starts, and a juz turns to the next surah.
            .onChange(of: player.current) { _, current in
                guard isOnScreen, let current, player.isPlaying else { return }
                if current.surah == viewModel.surah.id {
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(current.ayah, anchor: .top) }
                } else if current.surah == viewModel.surah.id + 1, player.scope == .juz, !isHandingOnJuz {
                    isHandingOnJuz = true
                    onRequestNextSurah()
                }
            }
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

    /// "Go to ayah": the number typed, on any keyboard (Urdu and Arabic
    /// digits are read as well).
    private func goToTypedAyah() {
        let digits = SearchNormalizer.normalize(goToAyahText).trimmingCharacters(in: .whitespaces)
        goToAyahText = ""
        guard let number = Int(digits), (1...viewModel.surah.ayahCount).contains(number) else { return }
        pendingScrollAyah = number
    }

    /// The end of the surah: the next one opens on its own when the reader
    /// has scrolled here with "Automatically open next surah" on, and can
    /// always be opened from here.
    @ViewBuilder
    private var readerEndMarker: some View {
        if viewModel.surah.id < 114 {
            Button {
                advanceToNextSurah()
            } label: {
                Label("Next surah", systemImage: "arrow.forward.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.vertical, DISpacing.md)
            .onAppear {
                guard appState.settings.quranAutoAdvanceSurah, hasScrolledIntoSurah else { return }
                advanceToNextSurah()
            }
        } else {
            Label("Quran reading complete", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DIColor.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DISpacing.md)
        }
    }

    private func advanceToNextSurah() {
        guard viewModel.surah.id < 114, !hasAutoAdvanced else { return }
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
                Text(surahMeaning)
                    .font(viewModel.readingLanguage == "ur" ? DIFont.urduBody() : DIFont.subheading)
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

    /// The surah's meaning in the language being read, as the surah list
    /// shows it.
    private var surahMeaning: String {
        if viewModel.readingLanguage == "ur", let urdu = viewModel.surah.nameUrdu, !urdu.isEmpty { return urdu }
        return viewModel.surah.nameEnglish
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
        player.start(from: ListenAyah(surah: viewModel.surah.id, ayah: ayahNumber), content: effectiveContent,
                     scope: listenScope, translationEdition: narratedTranslationEdition)
    }

    /// Recitation, translation, or both ayah by ayah - over an ayah, ruku,
    /// surah or juz (para) - from the top, or from any ayah's play button.
    /// A deep emerald player with a gold play control, so it stands out from
    /// the text cards around it.
    private var listenBar: some View {
        let isHere = player.isActive(inSurah: viewModel.surah.id)
        let isPlaying = player.isPlaying && isHere
        return VStack(alignment: .leading, spacing: DISpacing.md) {
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
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(DIColor.primaryDeep)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(DIGradient.goldSheen))
                        .overlay(Circle().stroke(DIColor.onPrimary.opacity(0.6), lineWidth: 1))
                        .diGoldGlow(radius: isPlaying ? 14 : 8, opacity: isPlaying ? 0.6 : 0.4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? Text("Pause") : Text("Play"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Listen")
                        .font(.headline)
                        .foregroundStyle(DIColor.onPrimary)
                    Text(listenSubtitle)
                        .font(.caption)
                        .foregroundStyle(DIColor.onPrimary.opacity(0.75))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isHere {
                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.title3)
                            .foregroundStyle(DIColor.goldGlow)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                    }
                    Button {
                        player.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(DIColor.onPrimary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(DIColor.onPrimary.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
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
                    icon: { content in
                        switch content {
                        case .arabic: return "music.mic"
                        case .translation: return "text.bubble"
                        case .both: return "square.stack.3d.up"
                        }
                    },
                    selection: Binding(get: { effectiveContent }, set: { listenContent = $0 }),
                    onDark: true
                )
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Play to the end of")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DIColor.onPrimary.opacity(0.75))
                DISegmentedControl(
                    items: QuranListenScope.allCases,
                    title: { scope in
                        switch scope {
                        case .ayah: return "Ayah"
                        case .ruku: return "Ruku"
                        case .surah: return "Surah"
                        case .juz: return "Juz (Para)"
                        }
                    },
                    selection: $listenScope,
                    onDark: true
                )
            }
        }
        .padding(DISpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                .fill(DIGradient.emerald)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                .stroke(DIGradient.goldSheen, lineWidth: 1)
                .opacity(0.75)
        )
        .shadow(color: DIColor.primaryDeep.opacity(0.35), radius: 14, x: 0, y: 8)
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

    /// The three works as tiles: the translation, and the two commentaries
    /// shown under it. The chosen one is lit in emerald with a gold edge.
    private var contentModeSelector: some View {
        HStack(spacing: DISpacing.sm) {
            ForEach(QuranContentMode.allCases) { mode in
                contentModeTile(mode)
            }
        }
    }

    private func contentModeTile(_ mode: QuranContentMode) -> some View {
        let selected = viewModel.contentMode == mode
        let shape = RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
        return Button {
            DIHaptics.soft()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { viewModel.contentMode = mode }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: Self.symbol(for: mode))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(selected ? DIColor.goldGlow : DIColor.primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(selected ? Color.white.opacity(0.14) : DIColor.primary.opacity(0.10)))
                Text(LocalizedStringKey(mode.shortTitle))
                    .font(.footnote.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(selected ? DIColor.onPrimary : DIColor.textPrimary)
                Text(mode.isTafsir ? LocalizedStringKey("Tafsir") : LocalizedStringKey("Translation"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(selected ? DIColor.onPrimary.opacity(0.8) : DIColor.textMuted)
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .padding(.vertical, DISpacing.sm)
            .padding(.horizontal, 6)
            .background(shape.fill(selected ? AnyShapeStyle(DIGradient.emerald) : AnyShapeStyle(DIColor.surface)))
            .overlay(shape.stroke(selected ? AnyShapeStyle(DIGradient.goldSheen) : AnyShapeStyle(DIColor.primary.opacity(0.25)),
                                  lineWidth: selected ? 1.5 : 1))
            .shadow(color: selected ? DIColor.primaryDeep.opacity(0.35) : .clear, radius: 10, x: 0, y: 5)
            .scaleEffect(selected ? 1 : 0.97)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private static func symbol(for mode: QuranContentMode) -> String {
        switch mode {
        case .tarajum: return "character.book.closed"
        case .asrarTanzil: return "sparkles"
        case .akramTafaseer: return "books.vertical"
        }
    }

    /// Resolves the linked lecture in the media catalogue and hands it to the
    /// shared player, so it keeps playing with the mini player and Lock Screen
    /// controls the rest of the app already uses. The recitation and any
    /// narration stop first: one recording at a time.
    private func play(_ link: AyahBayanLink) {
        let repository = mediaRepository
        let bayanPlayer = audioPlayer
        player.stop()
        speaker.stop()
        Task {
            guard let item = try? await repository.item(id: link.mediaID) else {
                bayanError = String(localized: "This bayan is not in the offline catalogue yet.")
                return
            }
            guard let stream = item.streamUrl, let url = URL(string: stream) else {
                bayanError = String(localized: "This bayan has no playable audio source.")
                return
            }
            bayanError = nil
            bayanPlayer.play(
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
                    volumeLink(volume, title: volumeTitle(volume))
                }
                // Only while the volume still holds original OCR pages; the
                // volumes re-read from the scan carry no such notice.
                if viewModel.fullVolumes.contains(where: { machineReadVolumeIDs.contains($0.bookID) }) {
                    Text("Machine-read from the printed book and not yet proofread.")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
        }
        .task(id: viewModel.fullVolumes.map(\.bookID)) {
            await loadVolumeProvenance(viewModel.fullVolumes)
        }
    }

    private func volumeLink(_ volume: TafsirVolume, title: String) -> some View {
        NavigationLink {
            TafsirVolumeDestination(
                volume: volume,
                dependencies: dependencies,
                fontScale: appState.settings.readerFontScale.rawValue
            )
        } label: {
            Label {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.leading)
            } icon: {
                Image(systemName: "text.book.closed")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }

    @MainActor
    private func loadVolumeProvenance(_ volumes: [TafsirVolume]) async {
        var machineRead: Set<String> = []
        for volume in volumes {
            if (try? await dependencies.contentRepository.bookHasMachineProvisionalPages(bookID: volume.bookID)) ?? true {
                machineRead.insert(volume.bookID)
            }
        }
        machineReadVolumeIDs = machineRead
    }

    private func volumeTitle(_ volume: TafsirVolume) -> String {
        volumeTitle(volume, workTitle: viewModel.contentMode.localizedTitle)
    }

    private func volumeTitle(_ volume: TafsirVolume, workTitle: String) -> String {
        let prefix = "tafaseer-parah-"
        if volume.bookID.hasPrefix(prefix) {
            let name = volume.bookID.dropFirst(prefix.count)
            if let parah = Int(name) {
                return String(localized: "\(workTitle), Parah \(parah), from page \(volume.page)")
            }
            // Parah 30 is printed in two volumes; the second is
            // "tafaseer-parah-30-part-2".
            let parts = name.components(separatedBy: "-part-")
            if parts.count == 2, let parah = Int(parts[0]), parts[1] == "2" {
                return String(localized: "\(workTitle), Parah \(parah) (part 2), from page \(volume.page)")
            }
        }
        return String(localized: "\(workTitle): Surah \(viewModel.surah.nameTransliterated)")
    }

    /// This work has nothing for the surah in the app, in either language.
    /// Says so plainly - nothing is on its way by itself - and points to the
    /// Silsila's other tafsir, which the app does have.
    private var tafsirMissingCard: some View {
        let otherWork: QuranContentMode = viewModel.contentMode == .akramTafaseer ? .asrarTanzil : .akramTafaseer
        let otherVolumes = viewModel.fullVolumes(for: otherWork)
        let otherHasVerses = viewModel.hasTafsir(for: otherWork)
        return DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Tafsir availability")
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                Group {
                    if viewModel.contentMode == .akramTafaseer && viewModel.surah.id >= 92 {
                        Text("Akram-ut-Tafaseer for this surah is in Parah 30, part 2, which is not in the app yet.")
                    } else {
                        Text("This commentary is not in the app for this surah.")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(DIColor.textMuted)
                if otherHasVerses || !otherVolumes.isEmpty {
                    Text("The Silsila's other tafsir is available:")
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textMuted)
                    if otherHasVerses {
                        Button {
                            DIHaptics.light()
                            viewModel.contentMode = otherWork
                        } label: {
                            Text("Read \(otherWork.localizedTitle)")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                    ForEach(otherVolumes) { volume in
                        volumeLink(volume, title: volumeTitle(volume, workTitle: otherWork.localizedTitle))
                    }
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
            Button {
                showsGoToAyah = true
            } label: {
                Label("Go to ayah", systemImage: "arrow.down.to.line")
            }
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
}

// MARK: - Tafsir volume

/// Opens a tafsir volume's text at a page. The library row gives the title;
/// if the library has not imported it, a minimal item still opens the pages,
/// which is all the text reader needs. A volume with no stored pages opens
/// nothing, not an empty reader.
struct TafsirVolumeDestination: View {
    let volume: TafsirVolume
    let dependencies: AppDependencies
    /// The reader's text size, carried into the book text.
    var fontScale: Double = 1
    @State private var item: ContentItem?
    @State private var hasNoPages = false

    var body: some View {
        Group {
            if let item {
                BookTextReaderView(item: item, dependencies: dependencies, startPage: volume.page, fontScale: fontScale)
            } else if hasNoPages {
                DIEmptyState(systemImage: "text.book.closed", titleKey: "No text for this book yet")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            let pageCount = (try? await dependencies.contentRepository.bookPageCount(bookID: volume.bookID)) ?? 0
            guard pageCount > 0 else {
                hasNoPages = true
                return
            }
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
    let playBayan: (AyahBayanLink) -> Void
    let scrollToAyah: (Int) -> Void

    @ScaledMetric(relativeTo: .body) private var bodyBaseSize: CGFloat = 17
    @State private var tafsirExpanded = true
    @State private var isWritingNote = false
    @State private var showsTafsir = false
    /// The sheikh whose note was tapped where no bayan of his is linked yet.
    @State private var bayanNotYet: BayanSheikh?

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
                } else if displayMode.showsTranslation, viewModel.isAsrarTranslationWithheld(ayah.ayahNumber) {
                    if displayMode.showsArabic { Divider() }
                    Text("Asrar-at-Tanzil's translation of this ayah is still being checked and is not shown yet.")
                        .font(.footnote)
                        .italic()
                        .foregroundStyle(DIColor.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if displayMode.showsTranslation,
                   viewModel.contentMode.isTafsir,
                   let entry = viewModel.tafsirEntry(startingAt: ayah.ayahNumber) {
                    Divider()
                    tafsirDisclosure(entry)
                } else if displayMode.showsTranslation,
                          viewModel.contentMode.isTafsir,
                          let covering = viewModel.tafsirEntry(covering: ayah.ayahNumber) {
                    // Explained with the passage it belongs to: say where.
                    Divider()
                    Button {
                        scrollToAyah(covering.ayahStart)
                    } label: {
                        Label("Commentary with ayat \(covering.ayahStart)–\(covering.ayahEnd)", systemImage: "arrow.up.doc")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DIColor.primary)
                    }
                    .buttonStyle(.plain)
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
        .alert(Text(LocalizedStringKey(bayanNotYet?.tafsirTitle ?? "Bayan")),
               isPresented: Binding(get: { bayanNotYet != nil }, set: { if !$0 { bayanNotYet = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A bayan on this ayah is not in the app yet.")
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
            if let para = QuranDivisions.juzStarting(surah: ayah.surahNumber, ayah: ayah.ayahNumber) {
                DIPillBadge(text: String(localized: "Parah \(para)"), color: DIColor.accent)
            }
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
        Text(arabicAttributedText)
            .font(DIFont.quranArabic(scale: fontScale * 1.15))
            .lineSpacing(CGFloat(18 * fontScale))
            .foregroundStyle(DIColor.textPrimary)
            .diGoldGlow(radius: 5, opacity: 0.18)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .rightToLeft)
    }

    /// Always the mushaf text (quran_ayahs.json), never the reciter's word
    /// list: that follows the recitation, repeats and all. The timings only
    /// choose which word of the mushaf to tint while it sounds; an ayah whose
    /// timings do not spell the mushaf is shown untinted.
    private var arabicAttributedText: AttributedString {
        let text = ayah.textArabic
        guard isSounding, player.part == .arabic, let position = player.currentWordPosition,
              let pieces = viewModel.wordMap(forAyah: ayah.ayahNumber)?.pieces(of: text, position: position) else {
            return AttributedString(text)
        }
        var word = AttributedString(pieces.word)
        word.backgroundColor = DIColor.accent.opacity(0.30)
        word.foregroundColor = DIColor.primaryDeep
        var result = AttributedString(pieces.before)
        result += word
        result += AttributedString(pieces.after)
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
                    // the quotations apart as the book pages do. Laid out
                    // once by the view model, not on every redraw.
                    FormattedBookPage(page: viewModel.formattedTafsir(entry), scale: fontScale)
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
                // A private note on this ayah, kept in My Day on this phone;
                // at the far side of the row.
                Spacer(minLength: 0)
                Button {
                    isWritingNote = true
                } label: {
                    shellChip(noteCount > 0 ? String(localized: "Notes (\(noteCount))") : String(localized: "Note"), "square.and.pencil", enabled: true)
                }
                .accessibilityLabel(Text("Write a note on Ayah \(ayah.ayahNumber)"))
            }
            // The sheikhs' bayans on this ayah, one note each. Not in
            // Arabic-only reading, which is the mushaf alone.
            if displayMode.showsTranslation {
                ForEach(bayanGroups) { group in
                    bayanNote(group)
                }
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

    /// The notes beside an ayah with bayans: Hazrat Ameer Akram Awan (RA)'s
    /// where his cover it, and Hazrat Ameer Abdul Qadeer Awan (MZA)'s below it
    /// always (owner, 29 October 2026), playing his where one covers the ayah.
    private var bayanGroups: [BayanGroup] {
        let links = AyahBayanLinkProvider.shared.links(surah: ayah.surahNumber, ayah: ayah.ayahNumber)
        guard !links.isEmpty else { return [] }
        return BayanSheikh.allCases.compactMap { sheikh in
            let own = links.filter { $0.sheikh == sheikh }
            return own.isEmpty && sheikh != .abdulQadeerAwan ? nil : BayanGroup(sheikh: sheikh, links: own)
        }
    }

    /// One bayan plays at a tap; several open a short list to choose from;
    /// none yet says so.
    @ViewBuilder
    private func bayanNote(_ group: BayanGroup) -> some View {
        if group.links.isEmpty {
            Button {
                bayanNotYet = group.sheikh
            } label: {
                bayanNoteLabel(group)
            }
            .buttonStyle(.plain)
        } else if group.links.count == 1, let link = group.links.first {
            Button {
                DIHaptics.light()
                playBayan(link)
            } label: {
                bayanNoteLabel(group)
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                ForEach(group.links) { link in
                    Button {
                        playBayan(link)
                    } label: {
                        Text(verbatim: "\(link.title) · \(link.reference)")
                    }
                }
            } label: {
                bayanNoteLabel(group)
            }
        }
    }

    private func bayanNoteLabel(_ group: BayanGroup) -> some View {
        let available = !group.links.isEmpty
        return HStack(spacing: 6) {
            Image(systemName: "note.text")
                .font(.caption.weight(.semibold))
                .foregroundStyle(available ? DIColor.accent : DIColor.textMuted)
            Text(LocalizedStringKey(group.sheikh.tafsirTitle))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if group.links.count > 1 {
                Text(verbatim: "\(group.links.count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .background(Capsule().fill(DIColor.accent.opacity(0.3)))
            }
            if available {
                Image(systemName: "play.fill")
                    .font(.caption2)
                    .foregroundStyle(DIColor.accent)
            }
        }
        .foregroundStyle(available ? DIColor.textPrimary : DIColor.textMuted)
        .padding(.horizontal, DISpacing.sm)
        .padding(.vertical, 6)
        .background(Capsule().fill(available ? DIColor.accent.opacity(0.14) : DIColor.sandstone.opacity(0.45)))
        .overlay(Capsule().stroke(available ? DIColor.accent.opacity(0.55) : DIColor.textMuted.opacity(0.25), lineWidth: 1))
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

// MARK: - Bayans

/// The bayans of one sheikh on an ayah.
private struct BayanGroup: Identifiable {
    let sheikh: BayanSheikh
    let links: [AyahBayanLink]
    var id: BayanSheikh { sheikh }
}

/// Every bayan on the surah, by sheikh, for a reader who would rather choose
/// one than follow the notes on the ayat. Opened from the reader's toolbar,
/// so the surah itself opens on its text.
private struct BayanListSheet: View {
    let links: [AyahBayanLink]
    let play: (AyahBayanLink) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(BayanSheikh.allCases, id: \.self) { sheikh in
                let own = links.filter { $0.sheikh == sheikh }
                if !own.isEmpty {
                    Section {
                        ForEach(own) { link in
                            Button {
                                DIHaptics.light()
                                play(link)
                                dismiss()
                            } label: {
                                HStack(spacing: DISpacing.sm) {
                                    Image(systemName: "play.circle.fill")
                                        .foregroundStyle(DIColor.primary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: link.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(DIColor.textPrimary)
                                            .multilineTextAlignment(.leading)
                                        Text(LocalizedStringKey("Ayat \(link.ayahStart)-\(link.ayahEnd)"))
                                            .font(.caption)
                                            .foregroundStyle(DIColor.textMuted)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(LocalizedStringKey(sheikh.tafsirTitle))
                    }
                }
            }
        }
        .navigationTitle(Text("Bayans on this surah"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
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
