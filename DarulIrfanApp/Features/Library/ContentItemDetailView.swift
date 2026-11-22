import SwiftUI

/// Detail screen for one library item.
///
/// A book or publication - a work read as text or as printed pages, with no
/// article body - opens as a book page (boards/Book.dc.html): a cover made in
/// the Silsila's style, the title, author and chips, the gold "Keep reading"
/// at the page it was left on, the text and the printed pages, keeping it on
/// this phone, and the excerpt and dates. An Akram-ut-Tarajum volume's gold
/// button opens the Qur'an reader instead (`TarajumVolume`).
///
/// Everything else - articles, pages, notices - keeps the
/// metadata card, native reader, native image presentation,
/// downloadable files, and dates. Both open the app's one reader
/// (`BookReaderScreen`).
///
/// The library's Shajra page opens the app's own Shajra (`ShajraView`)
/// instead, wherever it is reached.
struct ContentItemDetailView: View {
    @Environment(\.locale) private var locale
    private let appState: AppState
    private let dependencies: AppDependencies
    private let libraryViewModel: LibraryViewModel
    @State private var viewModel: ContentItemDetailViewModel
    /// Where the work was left, for Keep reading.
    @State private var resume: BookResume?
    @ScaledMetric(relativeTo: .body) private var baseBodySize: CGFloat = 17

    init(
        itemID: String,
        dependencies: AppDependencies,
        appState: AppState,
        libraryViewModel: LibraryViewModel
    ) {
        self.appState = appState
        self.dependencies = dependencies
        self.libraryViewModel = libraryViewModel
        _viewModel = State(initialValue: ContentItemDetailViewModel(
            itemID: itemID,
            contentRepository: dependencies.contentRepository,
            downloadsRepository: dependencies.downloadsRepository,
            downloadManager: dependencies.downloadManager
        ))
    }

    var body: some View {
        // The Shajra is drawn in the app's theme now: search, topics and
        // Saved open it, as the Halqah and Zikr tabs do.
        if ShajraRoute.opensShajraView(itemID: viewModel.itemID) {
            ShajraView()
        } else {
            itemDetail
        }
    }

    /// The item's own page.
    private var itemDetail: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .tint(DIColor.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.loadFailed {
                VStack(spacing: DISpacing.md) {
                    Text("The archive could not be loaded right now. Please try again in a moment.")
                        .diInterfaceFont(.body)
                        .foregroundStyle(DIColor.textPrimary)
                    Button("Retry") { Task { await viewModel.load() } }
                        .buttonStyle(DISecondaryButtonStyle())
                }
                .padding(DISpacing.md)
                .diResponsiveWidth()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let item = viewModel.item {
                detailContent(for: item)
            } else {
                DIEmptyState(
                    systemImage: "questionmark.folder",
                    titleKey: "This item is unavailable",
                    messageKey: "It may have been moved in a recent content update. Please check the library again later."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .diScreenBackground()
        .libraryFavoriteFailure(libraryViewModel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                favoriteButton
            }
        }
        .task {
            // The favourites too: this screen is also opened from search and
            // from topics, whose library state had not read them, so a
            // starred work showed an empty star.
            await libraryViewModel.loadFavorites()
            await viewModel.loadIfNeeded()
            refreshResume()
        }
        // Back from the reader, the page it was left on has moved.
        .onAppear {
            refreshResume()
        }
        .onDisappear {
            viewModel.flushReadingProgress()
        }
    }

    private func refreshResume() {
        guard let item = viewModel.item else {
            resume = nil
            return
        }
        resume = BookReadingHistory.resume(
            itemID: item.id,
            hasPDF: hasReadablePDF(item),
            hasText: viewModel.bookPageCount > 0
        )
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var favoriteButton: some View {
        if let item = viewModel.item {
            let isFavorite = libraryViewModel.isFavorite(item.id)
            LibraryFavoriteButton(isFavorite: isFavorite) {
                Task {
                    await libraryViewModel.toggleFavorite(contentItemID: item.id)
                }
            }
        }
    }

    // MARK: - Content

    private func detailContent(for item: ContentItem) -> some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if isBookPage(item) {
                            bookPage(for: item)
                        } else {
                            itemPage(for: item)
                        }
                    }
                    .padding(DISpacing.md)
                    .diResponsiveWidth()
                    .background(scrollMetricsReader(viewportHeight: outer.size.height))
                }
                .coordinateSpace(.named("libraryDetailScroll"))
                .onPreferenceChange(LibraryScrollMetricsKey.self) { metrics in
                    let fraction = metrics.fraction
                    Task { @MainActor in
                        viewModel.scrollFractionChanged(fraction)
                    }
                }
                .task {
                    await restoreReadingPositionIfNeeded(proxy: proxy)
                }
            }
        }
    }

    /// Metadata, the native reader or the excerpt, files and dates: an
    /// article, a page, a notice.
    private func itemPage(for item: ContentItem) -> some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            detailHeader(for: item)
                .diAppear(delay: 0.03)
            // The text first wherever the work has text; its printed pages
            // are the second way in, and the first only when there is no text.
            if viewModel.bookPageCount > 0 {
                readTextButton(for: item).diAppear(delay: 0.06)
                if hasReadablePDF(item) {
                    printedPagesButton(for: item).diAppear(delay: 0.09)
                }
            } else if hasReadablePDF(item) {
                readInAppButton(for: item).diAppear(delay: 0.06)
            }
            nativeMediaSection(for: item)
            if viewModel.showsBody {
                readerCard(for: item)
                if [ContentCategory.tasawwuf, .tazkiyahNafs, .zikrAllah, .baiat].contains(item.category) {
                    MethodOfZikrLink(compact: true)
                }
            } else {
                excerptCard(for: item)
            }
            downloadsSection(for: item)
            dateSection(for: item)
        }
    }

    private func scrollMetricsReader(viewportHeight: CGFloat) -> some View {
        GeometryReader { inner in
            Color.clear.preference(
                key: LibraryScrollMetricsKey.self,
                value: LibraryScrollMetrics(
                    offsetY: -inner.frame(in: .named("libraryDetailScroll")).minY,
                    contentHeight: inner.size.height,
                    viewportHeight: viewportHeight
                )
            )
        }
    }

    private func restoreReadingPositionIfNeeded(proxy: ScrollViewProxy) async {
        let fraction = viewModel.initialReadingFraction
        let count = viewModel.bodyParagraphs.count
        guard viewModel.showsBody, fraction > 0.05, count > 1 else { return }
        // Give the reader a moment to lay out before jumping.
        try? await Task.sleep(nanoseconds: 350_000_000)
        let index = min(count - 1, max(0, Int(fraction * Double(count))))
        proxy.scrollTo("library-paragraph-\(index)", anchor: .top)
    }

    // MARK: - Read in app

    private func hasReadablePDF(_ item: ContentItem) -> Bool {
        item.downloadUrls.contains { $0.lowercased().hasSuffix(".pdf") }
    }

    /// The emerald button: the main way into a work, opening the app's
    /// reader (not an external viewer or a bare download).
    private func primaryReadButton(
        for item: ContentItem,
        mode: BookReaderMode,
        systemImage: String,
        title: Text,
        caption: Text,
        spokenLabel: Text
    ) -> some View {
        NavigationLink {
            reader(for: item, mode: mode, choice: readerChoice(of: mode, for: item))
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                    .fill(DIGradient.emerald)
                DIPatternTexture(tint: .white, opacity: 0.07)
                    .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous))
                HStack(spacing: DISpacing.md) {
                    Image(systemName: systemImage)
                        .diInterfaceFont(.title2)
                        .foregroundStyle(DIColor.onPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        title
                            .diInterfaceFont(.headline, design: .serif)
                            .foregroundStyle(DIColor.onPrimary)
                        caption
                            .diInterfaceFont(.caption)
                            .foregroundStyle(DIColor.onPrimary.opacity(0.85))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .diInterfaceFont(.footnote, weight: .semibold)
                        .foregroundStyle(DIColor.onPrimary.opacity(0.85))
                }
                .padding(DISpacing.md)
            }
            .shadow(color: DIColor.primaryDeep.opacity(0.3), radius: 10, y: 5)
        }
        .buttonStyle(DIPressableStyle())
        .simultaneousGesture(TapGesture().onEnded { DIHaptics.soft() })
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel)
    }

    /// A work that has text opens as text: this is its main button.
    private func readTextButton(for item: ContentItem) -> some View {
        primaryReadButton(
            for: item,
            mode: .text,
            systemImage: "text.book.closed.fill",
            title: Text("Read the text"),
            caption: Text("\(viewModel.bookPageCount) pages — searchable text"),
            spokenLabel: Text("Read the text, \(viewModel.bookPageCount) pages")
        )
    }

    /// A work with no text: its printed pages (the PDF, cached offline) are
    /// the main button.
    private func readInAppButton(for item: ContentItem) -> some View {
        primaryReadButton(
            for: item,
            mode: .pages,
            systemImage: "book.pages.fill",
            title: Text("Read in App"),
            caption: Text("Read the pages here — offline after first open"),
            spokenLabel: Text("Read in app")
        )
    }

    /// The second way in, under "Read the text": the same work as its printed
    /// pages (the PDF). Shown only beside the text, so a work with only a PDF
    /// keeps the emerald button. Opening it is the reader's choice of the
    /// printed pages, which "Keep reading" then follows.
    private func printedPagesButton(for item: ContentItem) -> some View {
        NavigationLink {
            reader(for: item, mode: .pages, choice: readerChoice(of: .pages, for: item))
        } label: {
            HStack(spacing: DISpacing.md) {
                Image(systemName: "doc.richtext")
                    .diInterfaceFont(.title3)
                    .foregroundStyle(DIColor.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("The printed pages")
                        .diInterfaceFont(.headline, design: .serif)
                        .foregroundStyle(DIColor.textPrimary)
                    Text("As published. Offline after the first open.")
                        .diInterfaceFont(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .diInterfaceFont(.footnote, weight: .semibold)
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(DISpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DIColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                    .stroke(DIColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(DIPressableStyle())
        .simultaneousGesture(TapGesture().onEnded { DIHaptics.soft() })
        .accessibilityElement(children: .combine)
    }

    /// The app's one reader, on the text or the printed pages. `choice` is
    /// for a button that asks for one way of reading (`readerChoice`): the
    /// reader notes it as it opens. The gold button gives none.
    private func reader(
        for item: ContentItem,
        mode: BookReaderMode,
        choice: BookReaderMode? = nil
    ) -> some View {
        BookReaderScreen(
            item: item,
            dependencies: dependencies,
            mode: mode,
            appState: appState,
            fontScale: appState.settings.readerFontScale.rawValue,
            choice: choice
        )
    }

    /// What a button for one way of reading says of the reader's choice: that
    /// way, on a work that has both its text and its printed pages, so "Keep
    /// reading" returns to it; nothing on a work with only one way to read.
    private func readerChoice(of mode: BookReaderMode, for item: ContentItem) -> BookReaderMode? {
        hasReadablePDF(item) && viewModel.bookPageCount > 0 ? mode : nil
    }

    // MARK: - Book page

    /// A work read as text or as printed pages, with no article body, or an
    /// Akram-ut-Tarajum volume.
    private func isBookPage(_ item: ContentItem) -> Bool {
        if TarajumVolume(item) != nil { return true }
        return !viewModel.showsBody && (hasReadablePDF(item) || viewModel.bookPageCount > 0)
    }

    private func bookPage(for item: ContentItem) -> some View {
        VStack(spacing: 18) {
            BookCoverView(item: item)
                .diAppear(delay: 0.02)
            bookTitleBlock(for: item)
                .diAppear(delay: 0.05)
            goldButton(for: item)
                .diAppear(delay: 0.08)
            readingTiles(for: item)
                .diAppear(delay: 0.11)
            nativeMediaSection(for: item)
            keepOnPhonePanel(for: item)
            excerptCard(for: item)
            dateSection(for: item)
        }
        .frame(maxWidth: .infinity)
        .diResponsiveWidth()
    }

    private func bookTitleBlock(for item: ContentItem) -> some View {
        let urdu = locale.language.languageCode?.identifier == "ur" ? item.titleUrdu.flatMap { $0.isEmpty ? nil : $0 } : nil
        return VStack(spacing: 6) {
            Text(verbatim: urdu ?? item.title)
                .font(urdu == nil ? .title2.weight(.heavy) : DIFont.urduBody(scale: 1.3).weight(.heavy))
                .foregroundStyle(DIColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let author = item.author, !author.isEmpty {
                Text(LocalizedStringKey(author))
                    .diInterfaceFont(.subheadline, weight: .semibold)
                    .foregroundStyle(ReadPalette.goldInk)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 6) {
                bookChip(Text(LocalizedStringKey(item.type.libraryDisplayName)))
                bookChip(Text(LocalizedStringKey(LibraryLanguage.displayName(forCode: item.language))))
                if let pages = chipPageCount(for: item) {
                    bookChip(Text("\(pages) pages"))
                }
            }
            .padding(.top, DISpacing.xs)
        }
        .frame(maxWidth: .infinity)
    }

    private func bookChip(_ text: Text) -> some View {
        text
            .diInterfaceFont(.caption, weight: .bold)
            .foregroundStyle(ReadPalette.emeraldInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(ReadPalette.chipTrack))
    }

    /// The pages of the text, or of the PDF once it has been opened.
    private func chipPageCount(for item: ContentItem) -> Int? {
        if viewModel.bookPageCount > 0 { return viewModel.bookPageCount }
        return BookReadingHistory.pageCount(itemID: item.id, mode: .pages)
    }

    /// The main way in: a volume of the translation to the Qur'an reader,
    /// any other work to the book reader.
    @ViewBuilder
    private func goldButton(for item: ContentItem) -> some View {
        if let volume = TarajumVolume(item) {
            translationButton(for: volume)
        } else {
            keepReadingButton(for: item)
        }
    }

    /// Gold, on an Akram-ut-Tarajum volume: its text is the translation in
    /// the Qur'an reader. The printed pages stay in the tile below.
    private func translationButton(for volume: TarajumVolume) -> some View {
        NavigationLink {
            TarajumVolumeReader(volume: volume, dependencies: dependencies, appState: appState)
        } label: {
            goldButtonLabel {
                Text("Read the text")
                    .diInterfaceFont(.headline, weight: .heavy)
                Text("In the Quran from Parah \(volume.parah), with the Urdu translation")
                    .diInterfaceFont(.footnote, weight: .semibold)
                    .opacity(0.8)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(DIPressableStyle())
        .simultaneousGesture(TapGesture().onEnded { DIHaptics.soft() })
        .accessibilityElement(children: .combine)
    }

    /// Gold: back to the page it was left on, or the first reading - the
    /// text, and the printed pages only for a work that has no text.
    private func keepReadingButton(for item: ContentItem) -> some View {
        let startMode = BookReadingHistory.startMode(resume: resume, hasText: viewModel.bookPageCount > 0)
        return NavigationLink {
            reader(for: item, mode: startMode)
        } label: {
            goldButtonLabel {
                if let resume {
                    Text("Keep reading")
                        .diInterfaceFont(.headline, weight: .heavy)
                    Group {
                        if let count = resume.pageCount {
                            Text("Page \(resume.page) of \(count)")
                        } else {
                            Text("Page \(resume.page)")
                        }
                    }
                    .diInterfaceFont(.footnote, weight: .semibold)
                    .opacity(0.8)
                    if let fraction = resume.fraction {
                        ReadProgressLight(
                            fraction: fraction,
                            height: 4,
                            track: Color(hex: 0x064B34).opacity(0.18),
                            colors: [Color(hex: 0x064B34), Color(hex: 0x064B34)],
                            glows: false
                        )
                        .padding(.top, 6)
                    }
                } else {
                    Text("Read in App")
                        .diInterfaceFont(.headline, weight: .heavy)
                    Group {
                        if viewModel.bookPageCount > 0 {
                            Text("\(viewModel.bookPageCount) pages — searchable text")
                        } else {
                            Text("Read the pages here — offline after first open")
                        }
                    }
                    .diInterfaceFont(.footnote, weight: .semibold)
                    .opacity(0.8)
                }
            }
        }
        .buttonStyle(DIPressableStyle())
        .simultaneousGesture(TapGesture().onEnded { DIHaptics.soft() })
        .accessibilityElement(children: .combine)
    }

    /// The gold button's face: the book, and the lines that say where it opens.
    private func goldButtonLabel<Lines: View>(@ViewBuilder lines: () -> Lines) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "book")
                .diInterfaceFont(.headline)
                .foregroundStyle(Color(hex: 0xFFE9A8))
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color(hex: 0x064B34)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                lines()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color(hex: 0x064B34))
        .padding(.vertical, DISpacing.md)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xFFE9A8), Color(hex: 0xE0B75F), Color(hex: 0xC99A3A)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: DIColor.goldGlow.opacity(0.45), radius: 14)
        )
        .readSheen(cornerRadius: 26, period: 4, strength: 0.5)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    /// The text, then the printed pages (the PDF), each opening the reader.
    /// On a work that has both, each tile is the reader's choice of that way.
    private func readingTiles(for item: ContentItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if viewModel.bookPageCount > 0 {
                NavigationLink {
                    reader(for: item, mode: .text, choice: readerChoice(of: .text, for: item))
                } label: {
                    readingTile(systemImage: "text.alignleft", titleKey: "The text", detail: textTileDetail)
                }
                .buttonStyle(DIPressableStyle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Read the text, \(viewModel.bookPageCount) pages"))
            }
            if hasReadablePDF(item) {
                NavigationLink {
                    reader(for: item, mode: .pages, choice: readerChoice(of: .pages, for: item))
                } label: {
                    readingTile(
                        systemImage: "doc.richtext",
                        titleKey: "The printed pages",
                        detail: pagesTileDetail(for: item)
                    )
                }
                .buttonStyle(DIPressableStyle())
                .accessibilityElement(children: .combine)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// What the printed pages are. On an Akram-ut-Tarajum volume, whose gold
    /// button opens the Qur'an, the page they were left on is said here: the
    /// Books page's "Keep reading" card names that page and leads here.
    private func pagesTileDetail(for item: ContentItem) -> Text {
        guard TarajumVolume(item) != nil, let resume else {
            return Text("As published. Offline after the first open.")
        }
        if let count = resume.pageCount {
            return Text("Page \(resume.page) of \(count)")
        }
        return Text("Page \(resume.page)")
    }

    /// How many pages the text has.
    private var textTileDetail: Text {
        Text("\(viewModel.bookPageCount) pages — searchable text")
    }

    private func readingTile(systemImage: String, titleKey: LocalizedStringKey, detail: Text) -> some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            Image(systemName: systemImage)
                .diInterfaceFont(.title3)
                .foregroundStyle(ReadPalette.emeraldInk)
                .accessibilityHidden(true)
            Text(titleKey)
                .diInterfaceFont(.subheadline, weight: .heavy)
                .foregroundStyle(DIColor.textPrimary)
                .multilineTextAlignment(.leading)
            detail
                .diInterfaceFont(.caption, weight: .medium)
                .foregroundStyle(DIColor.textMuted)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .diGlassPanel(cornerRadius: 22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Keep it on this phone (the PDF downloaded for offline reading, with
    /// every state a file row has), and any further files.
    @ViewBuilder
    private func keepOnPhonePanel(for item: ContentItem) -> some View {
        let primary = item.downloadUrls.first { $0.lowercased().hasSuffix(".pdf") }
        let others = item.downloadUrls.filter { $0 != primary }
        if primary != nil || !others.isEmpty {
            VStack(spacing: 0) {
                if let primary {
                    BookKeepOfflineRow(urlString: primary, viewModel: viewModel)
                }
                ForEach(Array(others.enumerated()), id: \.element) { index, urlString in
                    if primary != nil || index > 0 {
                        ReadRowRule()
                    }
                    LibraryDownloadRow(urlString: urlString, viewModel: viewModel)
                        .padding(.horizontal, 12)
                }
            }
            .padding(6)
            .diGlassPanel(cornerRadius: 24)
        }
    }

    // MARK: - Gradient header

    private func detailHeader(for item: ContentItem) -> some View {
        ZStack(alignment: .topLeading) {
            DIGradient.emerald
            DIOctagram(innerRatio: 0.5)
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 220, height: 220)
                .opacity(0.06)
                .offset(x: 96, y: -56)

            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.16))
                        Image(systemName: item.type.libraryIcon)
                            .diInterfaceFont(.headline)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                    Text(LocalizedStringKey(item.category.englishName))
                        .diInterfaceFont(.caption, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }

                Text(verbatim: item.title)
                    .diInterfaceFont(.title2, weight: .semibold, design: .serif)
                    .foregroundStyle(Color(hex: 0xFFE3A0))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let titleUrdu = item.titleUrdu, !titleUrdu.isEmpty {
                    Text(verbatim: titleUrdu)
                        .font(DIFont.urduBody())
                        .foregroundStyle(Color(hex: 0xFFE3A0))
                        .diGoldGlow(radius: 3, opacity: 0.25)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .rightToLeft)
                }

                HStack(spacing: DISpacing.sm) {
                    headerBadge(String(localized: String.LocalizationValue(item.type.libraryDisplayName)), systemImage: item.type.isFeaturedPublication ? "star.fill" : nil)
                    headerBadge(String(localized: String.LocalizationValue(LibraryLanguage.displayName(forCode: item.language))), systemImage: "character.book.closed")
                    Spacer(minLength: 0)
                }
                .padding(.top, DISpacing.xs)

                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    if let author = item.author, !author.isEmpty {
                        headerMetaRow(systemImage: "person", text: Text(LocalizedStringKey(author)))
                    }
                    if let publishedAt = item.publishedAt {
                        headerMetaRow(
                            systemImage: "calendar",
                            text: Text("Published \(publishedAt, format: Date.FormatStyle(timeZone: .gmt).day().month().year())")
                        )
                    }
                }
                .padding(.top, DISpacing.xs)
            }
            .padding(DISpacing.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg + 6, style: .continuous))
        .shadow(color: DIColor.primaryDeep.opacity(0.35), radius: 16, x: 0, y: 8)
    }

    private func headerBadge(_ text: String, systemImage: String?) -> some View {
        HStack(spacing: DISpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage).diInterfaceFont(.caption2)
            }
            Text(text).diInterfaceFont(.caption, weight: .semibold)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, DISpacing.sm)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.18)))
    }

    private func headerMetaRow(systemImage: String, text: Text) -> some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: systemImage)
                .diInterfaceFont(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 16)
                .accessibilityHidden(true)
            text
                .diInterfaceFont(.footnote)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.leading)
        }
    }

    // MARK: - Native reader

    private func isRightToLeft(_ item: ContentItem) -> Bool {
        ScriptDirection.readsRightToLeft(item.language)
    }

    private func bodyFont(for item: ContentItem) -> Font {
        let scale = appState.settings.readerFontScale.rawValue
        if item.language.lowercased().hasPrefix("ur") {
            return DIFont.urduBody(scale: scale)
        }
        return Font.system(size: baseBodySize * CGFloat(scale), design: .serif)
    }

    private func readerCard(for item: ContentItem) -> some View {
        DICard(padding: DISpacing.lg) {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                ForEach(Array(viewModel.bodyParagraphs.enumerated()), id: \.offset) { index, paragraph in
                    FormattedBookPage(
                        page: BookPageFormatter.articleParagraph(paragraph, itemID: item.id),
                        scale: appState.settings.readerFontScale.rawValue,
                        place: .article,
                        language: item.language
                    )
                        .id("library-paragraph-\(index)")
                }
            }
        }
        .environment(\.layoutDirection, isRightToLeft(item) ? .rightToLeft : .leftToRight)
    }

    // MARK: - Native media

    @ViewBuilder
    private func nativeMediaSection(for item: ContentItem) -> some View {
        let urls = item.mediaUrls.compactMap { nativeURL($0) }
        if !urls.isEmpty {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                DISectionHeader(titleKey: "Illustrations", systemImage: "photo.on.rectangle.angled")
                ForEach(urls, id: \.absoluteString) { url in
                    DICard(padding: DISpacing.sm) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFit()
                            case .failure:
                                DIEmptyState(
                                    systemImage: "photo",
                                    titleKey: "Illustration unavailable",
                                    messageKey: "Pull down later after the content archive refreshes."
                                )
                            default:
                                ProgressView()
                                    .frame(maxWidth: .infinity, minHeight: 180)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
                    }
                }
            }
        }
    }

    private func nativeURL(_ raw: String) -> URL? {
        URL(string: raw) ?? URL(string: raw.replacingOccurrences(of: " ", with: "%20"))
    }

    @ViewBuilder
    private func excerptCard(for item: ContentItem) -> some View {
        if let excerpt = item.excerpt, !excerpt.isEmpty {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text("Excerpt")
                        .diInterfaceFont(.caption, weight: .semibold)
                        .foregroundStyle(DIColor.textMuted)
                        .textCase(.uppercase)
                    Text(verbatim: excerpt)
                        .diInterfaceFont(.subheadline)
                        .foregroundStyle(DIColor.textPrimary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }

    // MARK: - Downloads

    @ViewBuilder
    private func downloadsSection(for item: ContentItem) -> some View {
        if !item.downloadUrls.isEmpty {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                DISectionHeader(titleKey: "Files", systemImage: "arrow.down.circle")
                DICard {
                    VStack(spacing: 0) {
                        ForEach(item.downloadUrls, id: \.self) { urlString in
                            LibraryDownloadRow(urlString: urlString, viewModel: viewModel)
                            if urlString != item.downloadUrls.last {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Content date

    /// The work's own date first: an Al-Murshid issue of 1981 used to show
    /// "Last updated" with the day the catalogue was built.
    private func dateSection(for item: ContentItem) -> some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                if let publishedAt = item.publishedAt {
                    Text("Published \(publishedAt, format: Date.FormatStyle(timeZone: .gmt).day().month().year())")
                        .diInterfaceFont(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                } else if let updatedAt = item.updatedAt {
                    Text("Last updated \(updatedAt, format: .dateTime.day().month().year())")
                        .diInterfaceFont(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                } else {
                    Text("Last updated date unavailable")
                        .diInterfaceFont(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
        }
    }
}

// MARK: - Download row

/// One downloadable file row: download, live progress with cancel, open the
/// local PDF, or remove the download.
struct LibraryDownloadRow: View {
    let urlString: String
    let viewModel: ContentItemDetailViewModel

    private var fileName: String {
        LibraryFileName.displayName(from: urlString)
    }

    private var state: ContentItemDetailViewModel.DownloadRowState {
        viewModel.downloadStates[urlString] ?? .notDownloaded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            HStack(spacing: DISpacing.sm) {
                Image(systemName: "doc")
                    .diInterfaceFont(.title3)
                    .foregroundStyle(DIColor.actionForeground)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    LibraryCatalogueText(text: fileName, latinFont: .subheadline, bold: true, urduScale: 0.8)
                        .foregroundStyle(DIColor.textPrimary)
                    subtitle
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            trailingControls.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, DISpacing.sm)
    }

    @ViewBuilder
    private var subtitle: some View {
        switch state {
        case .notDownloaded:
            Text("Available to download")
                .diInterfaceFont(.caption)
                .foregroundStyle(DIColor.textMuted)
        case .downloading:
            Text("Downloading…")
                .diInterfaceFont(.caption)
                .foregroundStyle(DIColor.textMuted)
        case .downloaded(let asset, _):
            if asset.byteSize > 0 {
                Text(verbatim: StorageSize.format(Int64(asset.byteSize)))
                    .diInterfaceFont(.caption)
                    .foregroundStyle(DIColor.textMuted)
            } else {
                Text("Downloaded")
                    .diInterfaceFont(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
        case .failed:
            Text("The download didn't finish. Please try again.")
                .diInterfaceFont(.caption)
                .foregroundStyle(DIColor.danger)
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        switch state {
        case .notDownloaded:
            Button {
                Task {
                    await viewModel.download(urlString: urlString)
                }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .diInterfaceFont(.title3)
                    .foregroundStyle(DIColor.actionForeground)
            }
            .buttonStyle(LibraryFileActionStyle())
            .accessibilityLabel(Text("Download file"))
        case .downloading:
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                HStack(spacing: DISpacing.sm) {
                    if let progress = viewModel.progressFraction(for: urlString) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(DIColor.primary)
                            .frame(width: 72)
                    } else {
                        ProgressView()
                            .tint(DIColor.primary)
                    }
                    Button {
                        viewModel.cancelDownload(urlString: urlString)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(DIColor.textMuted)
                    }
                    .buttonStyle(LibraryFileActionStyle())
                    .accessibilityLabel(Text("Cancel download"))
                }
            }
        case .downloaded(_, let localURL):
            HStack(spacing: DISpacing.md) {
                // A link that carries its own destination: this screen is
                // also pushed by search, a topic and the Quran tab, whose
                // stacks have no route for library values, so a value link
                // did nothing there.
                NavigationLink {
                    PDFViewerView(fileURL: localURL, title: fileName)
                } label: {
                    Text("Open PDF")
                        .diInterfaceFont(.subheadline, weight: .semibold)
                        .foregroundStyle(DIColor.actionForeground)
                }
                .buttonStyle(DICompactButtonStyle())
                Button(role: .destructive) {
                    Task {
                        await viewModel.deleteDownload(urlString: urlString)
                    }
                } label: {
                    Image(systemName: "trash")
                        .diInterfaceFont(.subheadline)
                        .foregroundStyle(DIColor.danger)
                }
                .buttonStyle(LibraryFileActionStyle())
                .accessibilityLabel(Text("Remove download"))
            }
        case .failed:
            Button {
                Task {
                    await viewModel.download(urlString: urlString)
                }
            } label: {
                Text("Try Again")
                    .diInterfaceFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DIColor.actionForeground)
            }
            .buttonStyle(DICompactButtonStyle())
            .accessibilityLabel(Text("Try downloading again"))
        }
    }
}

// MARK: - Keep it on this phone

/// The book page's "Keep it on this phone": the work's PDF downloaded for
/// reading offline, with a file row's states - download, live progress with
/// cancel, open or remove, try again.
struct BookKeepOfflineRow: View {
    let urlString: String
    let viewModel: ContentItemDetailViewModel

    private var fileName: String {
        LibraryFileName.displayName(from: urlString)
    }

    private var state: ContentItemDetailViewModel.DownloadRowState {
        viewModel.downloadStates[urlString] ?? .notDownloaded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.to.line")
                    .diInterfaceFont(.title3)
                    .foregroundStyle(ReadPalette.goldLine)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep it on this phone")
                        .diInterfaceFont(.subheadline, weight: .bold)
                        .foregroundStyle(DIColor.textPrimary)
                    subtitle
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer(minLength: 0)
                trailingControls
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var subtitle: some View {
        switch state {
        case .notDownloaded:
            Text("The PDF, for reading offline")
                .diInterfaceFont(.caption, weight: .medium)
                .foregroundStyle(DIColor.textMuted)
        case .downloading:
            Text("Downloading…")
                .diInterfaceFont(.caption, weight: .medium)
                .foregroundStyle(DIColor.textMuted)
        case .downloaded(let asset, _):
            if asset.byteSize > 0 {
                Text(verbatim: StorageSize.format(Int64(asset.byteSize)))
                    .diInterfaceFont(.caption, weight: .medium)
                    .foregroundStyle(DIColor.textMuted)
            } else {
                Text("Downloaded")
                    .diInterfaceFont(.caption, weight: .medium)
                    .foregroundStyle(DIColor.textMuted)
            }
        case .failed:
            Text("The download didn't finish. Please try again.")
                .diInterfaceFont(.caption)
                .foregroundStyle(DIColor.danger)
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        switch state {
        case .notDownloaded:
            Button {
                Task {
                    await viewModel.download(urlString: urlString)
                }
            } label: {
                Text("Download")
                    .diInterfaceFont(.footnote, weight: .bold)
            }
            .buttonStyle(DICompactButtonStyle())
            .accessibilityLabel(Text("Download file"))
        case .downloading:
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                HStack(spacing: DISpacing.sm) {
                    if let progress = viewModel.progressFraction(for: urlString) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(DIColor.primary)
                            .frame(width: 72)
                    } else {
                        ProgressView()
                            .tint(DIColor.primary)
                    }
                    Button {
                        viewModel.cancelDownload(urlString: urlString)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(DIColor.textMuted)
                    }
                    .buttonStyle(LibraryFileActionStyle())
                    .accessibilityLabel(Text("Cancel download"))
                }
            }
        case .downloaded(_, let localURL):
            HStack(spacing: DISpacing.md) {
                NavigationLink {
                    PDFViewerView(fileURL: localURL, title: fileName)
                } label: {
                    Text("Open PDF")
                        .diInterfaceFont(.subheadline, weight: .semibold)
                        .foregroundStyle(DIColor.actionForeground)
                }
                .buttonStyle(DICompactButtonStyle())
                Button(role: .destructive) {
                    Task {
                        await viewModel.deleteDownload(urlString: urlString)
                    }
                } label: {
                    Image(systemName: "trash")
                        .diInterfaceFont(.subheadline)
                        .foregroundStyle(DIColor.danger)
                }
                .buttonStyle(LibraryFileActionStyle())
                .accessibilityLabel(Text("Remove download"))
            }
        case .failed:
            Button {
                Task {
                    await viewModel.download(urlString: urlString)
                }
            } label: {
                Text("Try Again")
                    .diInterfaceFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DIColor.actionForeground)
            }
            .buttonStyle(DICompactButtonStyle())
            .accessibilityLabel(Text("Try downloading again"))
        }
    }
}

// MARK: - Scroll metrics

/// Geometry sample used to derive the reader's scroll fraction.
private struct LibraryScrollMetrics: Equatable {
    var offsetY: CGFloat = 0
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0

    var fraction: Double {
        let scrollable = contentHeight - viewportHeight
        guard scrollable > 1 else { return 0 }
        return min(max(Double(offsetY / scrollable), 0), 1)
    }
}

private struct LibraryScrollMetricsKey: PreferenceKey {
    static var defaultValue: LibraryScrollMetrics = LibraryScrollMetrics()

    static func reduce(value: inout LibraryScrollMetrics, nextValue: () -> LibraryScrollMetrics) {
        value = nextValue()
    }
}
