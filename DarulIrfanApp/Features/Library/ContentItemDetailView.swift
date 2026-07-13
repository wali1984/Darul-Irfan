import SwiftUI

/// Detail screen for one library item: metadata card, rights-aware native
/// reader (or an official-website link for items without stored text, such
/// as PDF publications and any link-only item), downloadable files, and the
/// source link with last-updated date.
struct ContentItemDetailView: View {
    private let appState: AppState
    private let libraryViewModel: LibraryViewModel
    @State private var viewModel: ContentItemDetailViewModel
    @State private var isShowingSource = false
    @ScaledMetric(relativeTo: .body) private var baseBodySize: CGFloat = 17

    init(
        itemID: String,
        dependencies: AppDependencies,
        appState: AppState,
        libraryViewModel: LibraryViewModel
    ) {
        self.appState = appState
        self.libraryViewModel = libraryViewModel
        _viewModel = State(initialValue: ContentItemDetailViewModel(
            itemID: itemID,
            contentRepository: dependencies.contentRepository,
            downloadsRepository: dependencies.downloadsRepository,
            downloadManager: dependencies.downloadManager
        ))
    }

    var body: some View {
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
        .sheet(isPresented: $isShowingSource) {
            if let url = viewModel.sourceURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .task {
            await viewModel.load()
        }
        .onDisappear {
            viewModel.flushReadingProgress()
        }
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
                    VStack(alignment: .leading, spacing: DISpacing.md) {
                        detailHeader(for: item)
                            .diAppear(delay: 0.03)
                        if viewModel.showsBody {
                            readerCard(for: item)
                        } else {
                            excerptCard(for: item)
                            officialSiteCard(for: item)
                        }
                        downloadsSection(for: item)
                        sourceSection(for: item)
                    }
                    .padding(DISpacing.md)
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

    // MARK: - Gradient header

    private func detailHeader(for item: ContentItem) -> some View {
        ZStack(alignment: .topLeading) {
            DIGradient.hero()
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
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let titleUrdu = item.titleUrdu, !titleUrdu.isEmpty {
                    Text(verbatim: titleUrdu)
                        .font(DIFont.urduBody())
                        .foregroundStyle(.white)
                        .diGoldGlow(radius: 8, opacity: 0.35)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .environment(\.layoutDirection, .rightToLeft)
                }

                HStack(spacing: DISpacing.sm) {
                    headerBadge(item.type.libraryDisplayName, systemImage: item.type.isFeaturedPublication ? "star.fill" : nil)
                    headerBadge(LibraryLanguage.displayName(forCode: item.language), systemImage: "character.book.closed")
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
                            text: Text("Published \(publishedAt, format: .dateTime.day().month().year())")
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
                    Text(verbatim: paragraph)
                        .font(bodyFont(for: item))
                        .foregroundStyle(DIColor.textPrimary)
                        .lineSpacing(5)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("library-paragraph-\(index)")
                }
            }
        }
        .environment(\.layoutDirection, isRightToLeft(item) ? .rightToLeft : .leftToRight)
    }

    // MARK: - Link-only presentation

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

    private func officialSiteCard(for item: ContentItem) -> some View {
        DIElevatedCard(glow: DIColor.primary) {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.md) {
                    LibraryMedallion(systemImage: "globe", diameter: 40, breathing: true)
                    Text("Available on the official website")
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                        .multilineTextAlignment(.leading)
                }
                Text("The full text of this item is available on the official Naqshbandia Owaisiah website.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
                if viewModel.sourceURL != nil {
                    Button {
                        DIHaptics.light()
                        isShowingSource = true
                    } label: {
                        Text("Read on naqshbandiaowaisiah.org")
                    }
                    .buttonStyle(DIPrimaryButtonStyle())
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

    // MARK: - Source & last updated

    private func sourceSection(for item: ContentItem) -> some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                if viewModel.sourceURL != nil {
                    Button {
                        DIHaptics.light()
                        isShowingSource = true
                    } label: {
                        Label("View source on naqshbandiaowaisiah.org", systemImage: "safari")
                            .font(.subheadline)
                            .foregroundStyle(DIColor.primary)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
                if let updatedAt = item.updatedAt {
                    Text("Last updated \(updatedAt, format: .dateTime.day().month().year())")
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                } else if let publishedAt = item.publishedAt {
                    Text("Published \(publishedAt, format: .dateTime.day().month().year())")
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
                NavigationLink(value: LibraryRoute.pdf(url: localURL, title: fileName)) {
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
