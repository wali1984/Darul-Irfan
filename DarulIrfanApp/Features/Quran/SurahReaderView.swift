import SwiftUI

/// Ayah-by-ayah reader for one surah. Shows Arabic text with the user's
/// reader font scale, an optional offline translation, and an optional tafsir
/// section (stored entries plus link-only pointers to the website). Surahs
/// whose text pack is not on device get a gentle explanation with a link to
/// read on quran.com.
struct SurahReaderView: View {
    private let appState: AppState
    private let focusAyah: Int?
    @State private var viewModel: SurahReaderViewModel
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
                    if viewModel.showTafsir && !viewModel.tafsirEditionPointers.isEmpty {
                        tafsirPointerCard
                    }
                    ForEach(viewModel.ayahs, id: \.ayahNumber) { ayah in
                        AyahCardView(
                            ayah: ayah,
                            viewModel: viewModel,
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
        // Give the lazy stack one runloop tick to lay out before scrolling.
        DispatchQueue.main.async {
            proxy.scrollTo(focusAyah, anchor: .top)
        }
    }

    private var surahHeader: some View {
        DICard {
            VStack(spacing: DISpacing.sm) {
                Text(viewModel.surah.nameArabic)
                    .font(DIFont.quranArabic(scale: 1.1))
                    .foregroundStyle(DIColor.primary)
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

    /// Shown when tafsir is toggled on and editions exist whose full text is
    /// not stored in the app — the website publishes it only as image-scan
    /// PDF booklets, so the app links to the per-surah source pages.
    private var tafsirPointerCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Tafsir on the website")
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                Text("Full tafsir of this surah is published on naqshbandiaowaisiah.org and is not stored in the app yet.")
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
            if viewModel.translationEdition != nil {
                Toggle("Show translation", isOn: showTranslationBinding)
            }
            if viewModel.availableTranslationEditions.count > 1 {
                Picker("Translation", selection: editionBinding) {
                    ForEach(viewModel.availableTranslationEditions) { edition in
                        Text(edition.title).tag(edition.id)
                    }
                }
            }
            if viewModel.hasAnyTafsir {
                Toggle("Show tafsir", isOn: showTafsirBinding)
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

    private var showTafsirBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showTafsir },
            set: { viewModel.showTafsir = $0 }
        )
    }
}

// MARK: - Ayah card

private struct AyahCardView: View {
    let ayah: QuranAyah
    let viewModel: SurahReaderViewModel
    let fontScale: Double

    /// Base size for English translation/tafsir body text; scales with
    /// Dynamic Type on top of the reader's own font-scale setting.
    @ScaledMetric(relativeTo: .body) private var bodyBaseSize: CGFloat = 17

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
                if viewModel.showTafsir {
                    let entries = viewModel.tafsir(for: ayah.ayahNumber)
                    if !entries.isEmpty {
                        Divider()
                        tafsirSection(entries)
                    }
                }
            }
        }
    }

    // MARK: Header (per-ayah toolbar)

    private var header: some View {
        HStack(spacing: DISpacing.md) {
            Text("Ayah \(ayah.ayahNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DIColor.textMuted)
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

    // MARK: Arabic

    private var arabicText: some View {
        Text(ayah.textArabic)
            .font(DIFont.quranArabic(scale: fontScale))
            .lineSpacing(CGFloat(12 * fontScale))
            .foregroundStyle(DIColor.textPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .rightToLeft)
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

    // MARK: Tafsir

    private func tafsirSection(_ entries: [QuranTafsir]) -> some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            Text("Tafsir")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(DIColor.textMuted)
            ForEach(entries) { entry in
                tafsirEntryView(entry)
            }
        }
    }

    @ViewBuilder
    private func tafsirEntryView(_ entry: QuranTafsir) -> some View {
        let edition = viewModel.edition(id: entry.editionID)
        VStack(alignment: .leading, spacing: DISpacing.xs) {
            if let edition {
                Text(edition.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DIColor.primary)
            }
            if entry.ayahStart != entry.ayahEnd {
                Text("On Ayahs \(entry.ayahStart)–\(entry.ayahEnd)")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
            if !entry.text.isEmpty {
                bodyText(entry.text, languageCode: edition?.language)
            }
            if let sourceUrl = entry.sourceUrl, let url = URL(string: sourceUrl) {
                Link(destination: url) {
                    Label("Read on naqshbandiaowaisiah.org", systemImage: "safari")
                        .font(.footnote)
                }
                .tint(DIColor.primary)
            }
        }
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
    /// Natural-English display name; wrapped in `LocalizedStringKey` at the
    /// call site so the String Catalog can translate it.
    var readerDisplayName: String {
        switch self {
        case .small: return "Small"
        case .standard: return "Standard"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }
}
