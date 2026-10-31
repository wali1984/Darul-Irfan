import SwiftUI

/// Detail screen for one library item.
///
/// A book or publication - a work read as printed pages or as text, with no
/// article body - opens as a book page (boards/Book.dc.html): a cover made in
/// the Silsila's style, the title, author and chips, the gold "Keep reading"
/// at the page it was left on, the printed pages and the text, keeping it on
/// this phone, the rights line, and the excerpt and dates.
///
/// Everything else - articles, pages, notices, archive records - keeps the
/// metadata card, rights-aware native reader, native image presentation,
/// downloadable files, and dates. Both open the app's one reader
/// (`BookReaderScreen`).
///
/// The library's Shajra page opens the app's own Shajra (`ShajraView`)
/// instead, wherever it is reached.
struct ContentItemDetailView: View {
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
            await viewModel.load()
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
            Button {
                Task {
                    await libraryViewModel.toggleFavorite(contentItemID: item.id)
                }
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? DIColor.accent : DIColor.primary)
            }
            .accessibilityLabel(isFavorite ? Text("Remove from favorites") : Text("Add to favorites"))
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
    /// article, a page, a notice, an archive record.
    private func itemPage(for item: ContentItem) -> some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            detailHeader(for: item)
                .diAppear(delay: 0.03)
            if hasReadablePDF(item) {
                readInAppButton(for: item).diAppear(delay: 0.06)
            }
            if viewModel.bookPageCount > 0 {
                readTextButton(for: item).diAppear(delay: 0.09)
            }
            nativeMediaSection(for: item)
            if viewModel.showsBody {
                readerCard(for: item)
            } else {
                excerptCard(for: item)
                // Only when there is nothing to read here at all:
                // a work whose text opens above is not a bare
                // archive record.
                if !hasReadablePDF(item) && item.mediaUrls.isEmpty && viewModel.bookPageCount == 0 {
                    nativeAvailabilityCard
                }
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

    /// Primary CTA: read the work's actual pages inside the app (cached
    /// offline), not an external viewer or a bare download.
    private func readInAppButton(for item: ContentItem) -> some View {
        NavigationLink {
            reader(for: item, mode: .pages)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                    .fill(DIGradient.emerald)
                DIPatternTexture(tint: .white, opacity: 0.07)
                    .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous))
                HStack(spacing: DISpacing.md) {
                    Image(systemName: "book.pages.fill")
                        .font(.title2)
                        .foregroundStyle(DIColor.onPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Read in App")
                            .font(DIFont.subheading)
                            .foregroundStyle(DIColor.onPrimary)
                        Text("Read the pages here — offline after first open")
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
        .simultaneousGesture(TapGesture().onEnded { DIHaptics.soft() })
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Read in app"))
    }

    /// Secondary entry: the work's machine-read text layer. Shown only when
    /// pages exist, so a PDF-only work is unchanged. Deliberately quieter than
    /// "Read in App" — the PDF is the authoritative copy and this text has not
    /// been proofread.
    private func readTextButton(for item: ContentItem) -> some View {
        NavigationLink {
            reader(for: item, mode: .text)
        } label: {
            HStack(spacing: DISpacing.md) {
                Image(systemName: "text.book.closed")
                    .font(.title3)
                    .foregroundStyle(DIColor.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Read the text")
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                    Group {
                        if viewModel.machineReadPageCount >= viewModel.bookPageCount {
                            Text("\(viewModel.bookPageCount) pages — searchable, machine-read, not yet proofread")
                        } else if viewModel.machineReadPageCount > 0 {
                            // Mostly re-read from the scan: say how much is not.
                            Text("\(viewModel.bookPageCount) pages — searchable text; \(viewModel.machineReadPageCount) still machine-read")
                        } else {
                            Text("\(viewModel.bookPageCount) pages — searchable text")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DIColor.textMuted)
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
        .accessibilityLabel(viewModel.bookTextIsMachineRead
            ? Text("Read the text, \(viewModel.bookPageCount) pages, machine-read and not yet proofread")
            : Text("Read the text, \(viewModel.bookPageCount) pages"))
    }

    /// The app's one reader, on the printed pages or the text.
    private func reader(for item: ContentItem, mode: BookReaderMode) -> some View {
        BookReaderScreen(
            item: item,
            dependencies: dependencies,
            mode: mode,
            appState: appState,
            fontScale: appState.settings.readerFontScale.rawValue
        )
    }

    // MARK: - Book page

    /// A work read as printed pages or as text, with no article body.
    private func isBookPage(_ item: ContentItem) -> Bool {
        !viewModel.showsBody && (hasReadablePDF(item) || viewModel.bookPageCount > 0)
    }

    private func bookPage(for item: ContentItem) -> some View {
        VStack(spacing: 18) {
            BookCoverView(item: item)
                .diAppear(delay: 0.02)
            bookTitleBlock(for: item)
                .diAppear(delay: 0.05)
            keepReadingButton(for: item)
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
        VStack(spacing: 6) {
            Text(verbatim: item.title)
                .font(.title2.weight(.heavy))
                .foregroundStyle(DIColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let author = item.author, !author.isEmpty {
                Text(verbatim: author)
                    .font(.subheadline.weight(.semibold))
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
            .font(.caption.weight(.bold))
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

    /// Gold: back to the page it was left on, or the first reading.
    private func keepReadingButton(for item: ContentItem) -> some View {
        let startMode: BookReaderMode = resume?.mode ?? (hasReadablePDF(item) ? .pages : .text)
        return NavigationLink {
            reader(for: item, mode: startMode)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "book")
                    .font(.headline)
                    .foregroundStyle(Color(hex: 0xFFE9A8))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color(hex: 0x064B34)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let resume {
                        Text("Keep reading")
                            .font(.headline.weight(.heavy))
                        Group {
                            if let count = resume.pageCount {
                                Text("Page \(resume.page) of \(count)")
                            } else {
                                Text("Page \(resume.page)")
                            }
                        }
                        .font(.footnote.weight(.semibold))
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
                            .font(.headline.weight(.heavy))
                        Group {
                            if hasReadablePDF(item) {
                                Text("Read the pages here — offline after first open")
                            } else {
                                Text("\(viewModel.bookPageCount) pages — searchable text")
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .opacity(0.8)
                    }
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
        .buttonStyle(DIPressableStyle())
        .simultaneousGesture(TapGesture().onEnded { DIHaptics.soft() })
        .accessibilityElement(children: .combine)
    }

    /// The printed pages (the PDF) and the text, each opening the reader.
    private func readingTiles(for item: ContentItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if hasReadablePDF(item) {
                NavigationLink {
                    reader(for: item, mode: .pages)
                } label: {
                    readingTile(
                        systemImage: "doc.richtext",
                        titleKey: "The printed pages",
                        detail: Text("As published. Offline after the first open.")
                    )
                }
                .buttonStyle(DIPressableStyle())
                .accessibilityElement(children: .combine)
            }
            if viewModel.bookPageCount > 0 {
                NavigationLink {
                    reader(for: item, mode: .text)
                } label: {
                    readingTile(systemImage: "text.alignleft", titleKey: "The text", detail: textTileDetail)
                }
                .buttonStyle(DIPressableStyle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(viewModel.bookTextIsMachineRead
                    ? Text("Read the text, \(viewModel.bookPageCount) pages, machine-read and not yet proofread")
                    : Text("Read the text, \(viewModel.bookPageCount) pages"))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The text's pages and how much of it is still machine-read, as the
    /// text has always said.
    private var textTileDetail: Text {
        if viewModel.machineReadPageCount >= viewModel.bookPageCount {
            return Text("\(viewModel.bookPageCount) pages — searchable, machine-read, not yet proofread")
        }
        if viewModel.machineReadPageCount > 0 {
            // Mostly re-read from the scan: say how much is not.
            return Text("\(viewModel.bookPageCount) pages — searchable text; \(viewModel.machineReadPageCount) still machine-read")
        }
        return Text("\(viewModel.bookPageCount) pages — searchable text")
    }

    private func readingTile(systemImage: String, titleKey: LocalizedStringKey, detail: Text) -> some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(ReadPalette.emeraldInk)
                .accessibilityHidden(true)
            Text(titleKey)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(DIColor.textPrimary)
                .multilineTextAlignment(.leading)
            detail
                .font(.caption.weight(.medium))
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
    /// every state a file row has), any further files, and the rights line.
    @ViewBuilder
    private func keepOnPhonePanel(for item: ContentItem) -> some View {
        let primary = item.downloadUrls.first { $0.lowercased().hasSuffix(".pdf") }
        let others = item.downloadUrls.filter { $0 != primary }
        let showsRights = item.rightsStatus == .permissionConfirmed
        if primary != nil || !others.isEmpty || showsRights {
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
                if showsRights {
                    if primary != nil || !others.isEmpty {
                        ReadRowRule()
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield")
                            .font(.title3)
                            .foregroundStyle(ReadPalette.goldLine)
                            .accessibilityHidden(true)
                        Text("Shared with the Silsila's permission")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DIColor.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 52)
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
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                    Text(LocalizedStringKey(item.category.englishName))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }

                Text(verbatim: item.title)
                    .font(DIFont.heading)
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
                        headerMetaRow(systemImage: "person", text: Text(verbatim: author))
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
                Image(systemName: systemImage).font(.caption2)
            }
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, DISpacing.sm)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.18)))
    }

    private func headerMetaRow(systemImage: String, text: Text) -> some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 16)
                .accessibilityHidden(true)
            text
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.leading)
        }
    }

    // MARK: - Native reader

    private func isRightToLeft(_ item: ContentItem) -> Bool {
        let code = item.language.lowercased()
        return code.hasPrefix("ur") || code.hasPrefix("ar")
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
                    FormattedBookPage(page: BookPageFormatter.articleParagraph(paragraph), scale: appState.settings.readerFontScale.rawValue)
                        .id("library-paragraph-\(index)")
                }
            }
        }
        .environment(\.layoutDirection, isRightToLeft(item) ? .rightToLeft : .leftToRight)
    }

    // MARK: - Native media and availability

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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DIColor.textMuted)
                        .textCase(.uppercase)
                    Text(verbatim: excerpt)
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textPrimary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }

    private var nativeAvailabilityCard: some View {
        DIElevatedCard(glow: DIColor.primary) {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.md) {
                    LibraryMedallion(systemImage: "arrow.triangle.2.circlepath", diameter: 40, breathing: true)
                    Text("Archive record")
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                        .multilineTextAlignment(.leading)
                }
                Text("This item is preserved in the Darul Irfan archive. Any verified native text, artwork, audio, or document added later will appear here automatically.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
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
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                } else if let updatedAt = item.updatedAt {
                    Text("Last updated \(updatedAt, format: .dateTime.day().month().year())")
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                } else {
                    Text("Last updated date unavailable")
                        .font(.footnote)
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
        HStack(spacing: DISpacing.sm) {
            Image(systemName: "doc")
                .font(.title3)
                .foregroundStyle(DIColor.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: fileName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DIColor.textPrimary)
                    .lineLimit(2)
                subtitle
            }
            Spacer(minLength: DISpacing.sm)
            trailingControls
        }
        .padding(.vertical, DISpacing.sm)
    }

    @ViewBuilder
    private var subtitle: some View {
        switch state {
        case .notDownloaded:
            Text("Available to download")
                .font(.caption)
                .foregroundStyle(DIColor.textMuted)
        case .downloading:
            Text("Downloading…")
                .font(.caption)
                .foregroundStyle(DIColor.textMuted)
        case .downloaded(let asset, _):
            if asset.byteSize > 0 {
                Text(verbatim: asset.byteSize.formatted(.byteCount(style: .file)))
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
            } else {
                Text("Downloaded")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
        case .failed:
            Text("The download didn't finish. Please try again.")
                .font(.caption)
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
                    .font(.title3)
                    .foregroundStyle(DIColor.primary)
            }
            .buttonStyle(.plain)
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
                    .buttonStyle(.plain)
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.primary)
                }
                .buttonStyle(.plain)
                Button(role: .destructive) {
                    Task {
                        await viewModel.deleteDownload(urlString: urlString)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundStyle(DIColor.danger)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove download"))
            }
        case .failed:
            Button {
                Task {
                    await viewModel.download(urlString: urlString)
                }
            } label: {
                Text("Try Again")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DIColor.primary)
            }
            .buttonStyle(.plain)
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
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.to.line")
                .font(.title3)
                .foregroundStyle(ReadPalette.goldLine)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Keep it on this phone")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DIColor.textPrimary)
                subtitle
            }
            Spacer(minLength: DISpacing.sm)
            trailingControls
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
    }

    @ViewBuilder
    private var subtitle: some View {
        switch state {
        case .notDownloaded:
            Text("The PDF, for reading offline")
                .font(.caption.weight(.medium))
                .foregroundStyle(DIColor.textMuted)
        case .downloading:
            Text("Downloading…")
                .font(.caption.weight(.medium))
                .foregroundStyle(DIColor.textMuted)
        case .downloaded(let asset, _):
            if asset.byteSize > 0 {
                Text(verbatim: asset.byteSize.formatted(.byteCount(style: .file)))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
            } else {
                Text("Downloaded")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
            }
        case .failed:
            Text("The download didn't finish. Please try again.")
                .font(.caption)
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
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color(hex: 0x13A06F), Color(hex: 0x0B7250)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
            }
            .buttonStyle(.plain)
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
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Cancel download"))
                }
            }
        case .downloaded(_, let localURL):
            HStack(spacing: DISpacing.md) {
                NavigationLink {
                    PDFViewerView(fileURL: localURL, title: fileName)
                } label: {
                    Text("Open PDF")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ReadPalette.emeraldInk)
                }
                .buttonStyle(.plain)
                Button(role: .destructive) {
                    Task {
                        await viewModel.deleteDownload(urlString: urlString)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundStyle(DIColor.danger)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove download"))
            }
        case .failed:
            Button {
                Task {
                    await viewModel.download(urlString: urlString)
                }
            } label: {
                Text("Try Again")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ReadPalette.emeraldInk)
            }
            .buttonStyle(.plain)
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
