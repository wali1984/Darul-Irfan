import SwiftUI

/// Ayah-by-ayah reader for one surah. Shows Arabic with word-by-word recitation
/// highlighting, the Akram-ut-Tarajum translation, and an expandable tafsir
/// (Asrar-at-Tanzil / Akram-ut-Tafaseer) selected from a segmented control.
struct SurahReaderView: View {
    private let appState: AppState
    private let focusAyah: Int?
    @State private var viewModel: SurahReaderViewModel
    @State private var player = RecitationPlayer()
    @State private var speaker = TranslationSpeaker()
    @State private var hasScrolledToFocus = false

    init(surah: QuranSurah, focusAyah: Int?, dependencies: AppDependencies, appState: AppState) {
        self.appState = appState
        self.focusAyah = focusAyah
        let langCode = appState.settings.language.forcedLocaleIdentifier ?? "en"
        _viewModel = State(initialValue: SurahReaderViewModel(
            surah: surah,
            repository: dependencies.quranRepository,
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
                    ToolbarItem(placement: .topBarTrailing) {
                        readerOptionsMenu
                    }
                }
            }
            .task { await viewModel.load() }
            .onDisappear {
                player.stop()
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
                    messageKey: "Offline text packs arrive through content updates. Until then, you can read this surah on quran.com."
                )
                if let url = URL(string: "https://quran.com/\(viewModel.surah.id)") {
                    Link(destination: url) {
                        Label("Read on quran.com", systemImage: "safari")
                    }
                    .buttonStyle(DISecondaryButtonStyle())
                    .padding(.horizontal, DISpacing.xl)
                }
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
                    if viewModel.recitation != nil {
                        recitationBar
                    }
                    contentModeSelector
                    if viewModel.contentMode.isTafsir
                        && !viewModel.hasTafsirForMode
                        && !viewModel.tafsirEditionPointers.isEmpty {
                        tafsirPointerCard
                    }
                    ForEach(viewModel.ayahs, id: \.ayahNumber) { ayah in
                        AyahCardView(
                            ayah: ayah,
                            viewModel: viewModel,
                            player: player,
                            speaker: speaker,
                            fontScale: appState.settings.readerFontScale.rawValue
                        )
                        .id(ayah.ayahNumber)
                        .onAppear { viewModel.ayahBecameVisible(ayah.ayahNumber) }
                    }
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

    private var revelationPlaceName: String {
        switch viewModel.surah.revelationPlace {
        case .makkah: return String(localized: "Makkah")
        case .madinah: return String(localized: "Madinah")
        }
    }

    /// Whole-surah recitation control + reciter credit.
    private var recitationBar: some View {
        let isThisSurah = player.currentSurah == viewModel.surah.id
        let isPlaying = player.isPlaying && isThisSurah
        return DICard(padding: DISpacing.sm) {
            HStack(spacing: DISpacing.md) {
                Button {
                    guard let recitation = viewModel.recitation else { return }
                    if isPlaying {
                        player.pause()
                    } else if isThisSurah {
                        speaker.stop()
                        player.resume()
                    } else {
                        speaker.stop()
                        player.start(surah: viewModel.surah.id, recitation: recitation, fromAyah: 1)
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(DIColor.primary)
                }
                .accessibilityLabel(isPlaying ? Text("Pause recitation") : Text("Play recitation"))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Recitation")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.textPrimary)
                    Text(RecitationProvider.shared.reciterName)
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                Spacer(minLength: 0)
                if isPlaying {
                    Image(systemName: "waveform")
                        .foregroundStyle(DIColor.accent)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                }
            }
        }
    }

    /// Segmented control choosing translation-only vs a tafsir edition.
    private var contentModeSelector: some View {
        Picker("View", selection: contentModeBinding) {
            ForEach(QuranContentMode.allCases) { mode in
                Text(mode.shortTitle).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    /// Shown when a tafsir mode is selected but its text is not on device for
    /// this surah — links to the source pages on the website.
    private var tafsirPointerCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Tafsir arriving")
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                Text("This tafsir for this surah is being added to the app. Until then you can read it on naqshbandiaowaisiah.org.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
                ForEach(viewModel.tafsirEditionPointers) { edition in
                    if let sourceUrl = edition.sourceUrl, let url = URL(string: sourceUrl) {
                        Link(destination: url) {
                            Label {
                                Text("\(edition.title) — Read on naqshbandiaowaisiah.org")
                            } icon: {
                                Image(systemName: "safari")
                            }
                            .font(.footnote)
                        }
                        .tint(DIColor.primary)
                    }
                }
            }
        }
    }

    // MARK: - Toolbar

    private var readerOptionsMenu: some View {
        Menu {
            Picker("Text Size", selection: fontScaleBinding) {
                ForEach(ReaderFontScale.allCases) { scale in
                    Text(LocalizedStringKey(scale.readerDisplayName)).tag(scale)
                }
            }
            Toggle("Show translation", isOn: showTranslationBinding)
            if viewModel.availableTranslationEditions.count > 1 {
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

    private var showTranslationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showTranslation },
            set: { viewModel.showTranslation = $0 }
        )
    }

    private var contentModeBinding: Binding<QuranContentMode> {
        Binding(
            get: { viewModel.contentMode },
            set: { viewModel.contentMode = $0 }
        )
    }
}

// MARK: - Ayah card

private struct AyahCardView: View {
    let ayah: QuranAyah
    let viewModel: SurahReaderViewModel
    let player: RecitationPlayer
    let speaker: TranslationSpeaker
    let fontScale: Double

    @ScaledMetric(relativeTo: .body) private var bodyBaseSize: CGFloat = 17
    @State private var tafsirExpanded = true

    private var isSounding: Bool {
        player.isSounding(surah: ayah.surahNumber, ayah: ayah.ayahNumber)
    }

    private var isSpeaking: Bool {
        speaker.isSounding(surah: ayah.surahNumber, ayah: ayah.ayahNumber)
    }

    var body: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                header
                arabicText
                if viewModel.showTranslation,
                   let translation = viewModel.translation(for: ayah.ayahNumber) {
                    Divider()
                    translationView(translation)
                }
                if viewModel.contentMode.isTafsir,
                   let entry = viewModel.tafsirEntry(startingAt: ayah.ayahNumber) {
                    Divider()
                    tafsirDisclosure(entry)
                }
                Divider()
                shellsRow
            }
        }
        .overlay(alignment: .leading) {
            if isSounding || isSpeaking {
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
        if let recitation = viewModel.recitation {
            Button {
                if isSounding {
                    player.pause()
                } else {
                    speaker.stop()
                    player.start(surah: ayah.surahNumber, recitation: recitation, fromAyah: ayah.ayahNumber)
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
        .lineSpacing(CGFloat(16 * fontScale))
        .foregroundStyle(DIColor.textPrimary)
        .diGoldGlow(radius: 5, opacity: 0.18)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.layoutDirection, .rightToLeft)
    }

    /// Joins the recitation words, tinting the one currently sounding.
    private func highlightedArabic(words: [RecitationWord]) -> AttributedString {
        let highlight = isSounding ? player.currentWordPosition : nil
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
        VStack(alignment: .leading, spacing: DISpacing.xs) {
            if let edition = viewModel.edition(id: translation.editionID) {
                Text(edition.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DIColor.textMuted)
            }
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
                if !entry.text.isEmpty {
                    bodyText(entry.text, languageCode: edition?.language)
                }
                if let sourceUrl = entry.sourceUrl, let url = URL(string: sourceUrl) {
                    Link(destination: url) {
                        Label("Source on naqshbandiaowaisiah.org", systemImage: "safari")
                            .font(.footnote)
                    }
                    .tint(DIColor.textMuted)
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

    // MARK: Shells (prepared for later)

    private var shellsRow: some View {
        VStack(alignment: .leading, spacing: DISpacing.xs) {
            HStack(spacing: DISpacing.sm) {
                if let audio = translationAudio {
                    Button {
                        player.stop()
                        speaker.toggle(
                            text: audio.text,
                            language: audio.language,
                            surah: ayah.surahNumber,
                            ayah: ayah.ayahNumber
                        )
                    } label: {
                        shellChip(
                            isSpeaking ? "Stop" : "Translation audio",
                            isSpeaking ? "stop.fill" : "speaker.wave.2",
                            enabled: true
                        )
                    }
                    .accessibilityLabel(
                        isSpeaking
                            ? Text("Stop translation audio")
                            : Text("Play translation audio for Ayah \(ayah.ayahNumber)")
                    )
                } else {
                    shellChip("Translation audio", "speaker.wave.2", enabled: false)
                }
                shellChip("Video lectures", "play.rectangle", enabled: false)
                shellChip("Sheikh audio", "person.wave.2", enabled: false)
            }
            Text("Translation audio reads our own translation aloud in your device's voice. Video lectures and the Sheikh's own recitation are coming — and you'll be able to add your own recordings.")
                .font(.caption2)
                .foregroundStyle(DIColor.textMuted)
        }
    }

    /// The on-screen translation text + a device voice language, when both a
    /// translation and a usable voice are available for this ayah.
    private var translationAudio: (text: String, language: String)? {
        guard viewModel.showTranslation,
              let translation = viewModel.translation(for: ayah.ayahNumber),
              !translation.text.isEmpty else { return nil }
        let editionLanguage = viewModel.edition(id: translation.editionID)?.language
        let voiceLanguage = Self.voiceLanguage(for: editionLanguage ?? "ur")
        guard TranslationSpeaker.hasVoice(for: voiceLanguage) else { return nil }
        return (translation.text, voiceLanguage)
    }

    /// Maps a content language code to a BCP-47 voice tag the synthesizer knows.
    private static func voiceLanguage(for code: String) -> String {
        switch code {
        case "ur": return "ur-PK"
        case "ar": return "ar-SA"
        case "en": return "en-US"
        default: return code
        }
    }

    private func shellChip(_ label: String, _ icon: String, enabled: Bool) -> some View {
        Label(label, systemImage: icon)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, DISpacing.sm)
            .padding(.vertical, 5)
            .background(Capsule().fill(enabled ? DIColor.primary.opacity(0.12) : DIColor.sandstone.opacity(0.45)))
            .overlay(Capsule().stroke(enabled ? DIColor.primary.opacity(0.4) : DIColor.textMuted.opacity(0.25), lineWidth: 1))
            .foregroundStyle(enabled ? DIColor.primary : DIColor.textMuted)
    }

    // MARK: Language-aware body text

    @ViewBuilder
    private func bodyText(_ text: String, languageCode: String?) -> some View {
        if languageCode == "ur" || languageCode == "ar" {
            Text(text)
                .font(DIFont.urduBody(scale: fontScale))
                .lineSpacing(CGFloat(8 * fontScale))
                .foregroundStyle(DIColor.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .rightToLeft)
        } else {
            Text(text)
                .font(.system(size: bodyBaseSize * CGFloat(fontScale)))
                .lineSpacing(CGFloat(4 * fontScale))
                .foregroundStyle(DIColor.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
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
