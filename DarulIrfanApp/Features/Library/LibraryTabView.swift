import SwiftUI

/// The Silsila's library, which is the Read tab's Books: the work read last
/// (with the Silsila's seal), the Silsila's publications, and its Qur'an
/// translation and tafsir volumes, as tiles. A shelf opens its list - with
/// the language and type filters - or, holding one item, that item.
///
/// The library's About pages and Teachings went to Halqah, and its news
/// (announcements, press releases) to Discover › Updates. Favourites are in
/// Read › Saved, and library search is the toolbar's Search.
@MainActor
struct LibraryTabView: View {
    private let dependencies: AppDependencies
    private let appState: AppState
    private let readerSelection: Binding<ReadSection>?
    private let onShowAllReaders: (() -> Void)?
    @State private var viewModel: LibraryViewModel
    @State private var isShowingSearch = false
    /// The work read last, for Keep reading.
    @State private var lastBook: LastBook?

    init(
        dependencies: AppDependencies,
        appState: AppState,
        readerSelection: Binding<ReadSection>? = nil,
        onShowAllReaders: (() -> Void)? = nil
    ) {
        self.dependencies = dependencies
        self.appState = appState
        self.readerSelection = readerSelection
        self.onShowAllReaders = onShowAllReaders
        _viewModel = State(initialValue: LibraryViewModel(contentRepository: dependencies.contentRepository))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DISpacing.md) {
                    if let readerSelection {
                        ReadSectionPicker(selection: readerSelection)
                    }
                    if let lastBook {
                        keepReadingCard(lastBook)
                            .diAppear()
                    }
                    if viewModel.loadFailed {
                        VStack(alignment: .leading, spacing: DISpacing.sm) {
                            Text("The library could not be refreshed. Your saved items are still available.")
                                .font(.callout)
                            Button("Retry") { Task { await viewModel.reloadHome() } }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isLoading)
                        }
                    }
                    if viewModel.hasLoadedCounts {
                        if hasShelves {
                            shelfSection("The Silsila's publications", shelves: LibraryShelf.publications)
                            shelfSection("Qur'an translation and tafsir", shelves: LibraryShelf.quranVolumes)
                        } else {
                            DIEmptyState(
                                systemImage: "books.vertical",
                                titleKey: "The library is being prepared",
                                messageKey: "Books, articles, and announcements will appear here after the first verified content update."
                            )
                            .diOctagramWatermark(size: 260, opacity: 0.05)
                            .diAppear(delay: 0.1)
                        }
                    } else if !viewModel.loadFailed {
                        loadingSection
                    }
                }
                .padding(.horizontal, DISpacing.md)
                .padding(.top, DISpacing.sm)
                .padding(.bottom, DISpacing.xl)
                .diResponsiveWidth()
            }
            .diScreenBackground()
            .diPageHeading("Library", hidden: readerSelection != nil)
            .toolbar {
                // Under Read, the reader's toolbar has Saved and Search.
                if readerSelection == nil {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            DIHaptics.light()
                            isShowingSearch = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel(Text("Search"))

                        NavigationLink(value: LibraryRoute.favorites) {
                            Image(systemName: "heart")
                        }
                        .accessibilityLabel(Text("Favorites"))
                    }
                }
            }
            // Inside the stack so it lands in this reader's navigation bar.
            .modifier(OptionalReaderSwitch(
                selection: readerSelection,
                onShowAll: onShowAllReaders
            ))
            .navigationDestination(for: LibraryRoute.self) { route in
                LibraryDestination(
                    route: route,
                    dependencies: dependencies,
                    appState: appState,
                    viewModel: viewModel
                )
            }
            .navigationDestination(for: LibraryShelf.self) { shelf in
                CategoryListView(
                    category: shelf.primaryCategory,
                    viewModel: viewModel,
                    alsoListing: Array(shelf.categories.dropFirst()),
                    shelfTitle: shelf.title
                )
            }
            .sheet(isPresented: $isShowingSearch) {
                GlobalSearchView(dependencies: dependencies, appState: appState)
            }
            .task {
                await viewModel.loadHomeIfNeeded()
            }
            // Back from a book, where it was left has moved.
            .onAppear {
                Task { await refreshLastBook() }
            }
            .refreshable {
                await viewModel.reloadHome()
            }
        }
    }

    private var hasShelves: Bool {
        (LibraryShelf.publications + LibraryShelf.quranVolumes).contains { viewModel.count(for: $0) > 0 }
    }

    // MARK: - Keep reading

    /// The work read last and where it was left.
    private struct LastBook: Equatable {
        let item: ContentItem
        let resume: BookResume?
    }

    /// The emerald card with the Silsila's seal. It opens the book's page,
    /// whose gold button takes the reader back to the page they were on.
    private func keepReadingCard(_ last: LastBook) -> some View {
        NavigationLink(value: LibraryRoute.item(id: last.item.id)) {
            HStack(spacing: DISpacing.md) {
                DILivingSealMark(diameter: 50)
                VStack(alignment: .leading, spacing: 3) {
                    ReadCaps("Keep reading", color: Color(hex: 0xFFE3A0))
                    bookTitle(last.item)
                    if let detail = detailLine(last) {
                        detail
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DIHeroBackground(cornerRadius: 28))
            .readSheen(cornerRadius: 28)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(DIPressableStyle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func bookTitle(_ item: ContentItem) -> some View {
        if let urdu = item.titleUrdu, !urdu.isEmpty {
            Text(verbatim: urdu)
                .font(DIFont.urduBody(scale: 1.1))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .environment(\.layoutDirection, .rightToLeft)
        } else {
            Text(verbatim: item.title)
                .font(.headline.weight(.heavy))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    /// "Page 12 of 576 · the author", from what is known.
    private func detailLine(_ last: LastBook) -> Text? {
        var parts: [String] = []
        if let resume = last.resume {
            if let count = resume.pageCount {
                parts.append(String(localized: "Page \(resume.page) of \(count)"))
            } else {
                parts.append(String(localized: "Page \(resume.page)"))
            }
        }
        if let author = last.item.author, !author.isEmpty {
            parts.append(author)
        }
        return parts.isEmpty ? nil : Text(verbatim: parts.joined(separator: " · "))
    }

    private func refreshLastBook() async {
        guard let id = BookReadingHistory.lastItemID(),
              let item = try? await dependencies.contentRepository.item(id: id) else {
            lastBook = nil
            return
        }
        let pageCount = (try? await dependencies.contentRepository.bookPageCount(bookID: item.id)) ?? 0
        let resume = BookReadingHistory.resume(
            itemID: item.id,
            hasPDF: BookReadingHistory.hasPDF(item),
            hasText: pageCount > 0
        )
        lastBook = LastBook(item: item, resume: resume)
    }

    // MARK: - Shelves

    @ViewBuilder
    private func shelfSection(_ titleKey: LocalizedStringKey, shelves: [LibraryShelf]) -> some View {
        let visible = shelves.filter { viewModel.count(for: $0) > 0 }
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                ReadGroupTitle(titleKey: titleKey)
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(visible) { shelf in
                        shelfLink(shelf)
                    }
                }
            }
        }
    }

    /// A shelf of one item opens it; a shelf of one category its list; a
    /// shelf of two the list of both.
    @ViewBuilder
    private func shelfLink(_ shelf: LibraryShelf) -> some View {
        switch viewModel.target(for: shelf) {
        case .item(let id):
            NavigationLink(value: LibraryRoute.item(id: id)) { shelfTile(shelf) }
                .buttonStyle(DIPressableStyle())
                .simultaneousGesture(TapGesture().onEnded { DIHaptics.light() })
        case .category(let category):
            NavigationLink(value: LibraryRoute.category(category)) { shelfTile(shelf) }
                .buttonStyle(DIPressableStyle())
                .simultaneousGesture(TapGesture().onEnded { DIHaptics.light() })
        case .shelf:
            NavigationLink(value: shelf) { shelfTile(shelf) }
                .buttonStyle(DIPressableStyle())
                .simultaneousGesture(TapGesture().onEnded { DIHaptics.light() })
        }
    }

    private func shelfTile(_ shelf: LibraryShelf) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ReadOrb(systemImage: shelf.systemImage, gold: shelf.isGold)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(shelf.title))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                shelfCount(shelf)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .diGlassPanel(cornerRadius: 22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// The count in the shelf's own word; a shelf of one names its item.
    @ViewBuilder
    private func shelfCount(_ shelf: LibraryShelf) -> some View {
        let count = viewModel.count(for: shelf)
        if let sole = viewModel.soleItem(for: shelf.categories) {
            Text(verbatim: sole.title)
        } else {
            switch shelf.noun {
            case .titles: Text("\(count) titles")
            case .issues: Text("\(count) issues")
            case .articles: Text("\(count) articles")
            case .collections: Text("\(count) collections")
            case .items: Text("\(count) items")
            }
        }
    }

    private var loadingSection: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(spacing: DISpacing.md) {
                DISealEmblem(diameter: 64, glow: true)
                    .diBreathingGlow()
                ProgressView("Loading the library…")
                    .tint(DIColor.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DISpacing.xl)
    }
}

// MARK: - Featured card

/// Elevated, gilded card for the About Silsila and Sheikh pages - a live panel
/// with an emerald medallion, spring press feedback, and a gold edge glow.
struct LibraryFeaturedCard: View {
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey
    let systemImage: String

    var body: some View {
        DIElevatedCard(glow: DIColor.accent) {
            HStack(spacing: DISpacing.md) {
                LibraryMedallion(systemImage: systemImage, isSpecial: false, breathing: true)

                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text(titleKey)
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(subtitleKey)
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Category card

/// One category as an elevated live panel: a gradient medallion (gilded for
/// publications), the category name, item count, and a chevron.
struct LibraryCategoryRow: View {
    let category: ContentCategory
    let count: Int

    var body: some View {
        DIElevatedCard(glow: category.libraryAccent) {
            HStack(spacing: DISpacing.md) {
                LibraryMedallion(
                    systemImage: category.librarySymbol,
                    isSpecial: category.isPublicationCategory,
                    diameter: 44,
                    breathing: true
                )

                Text(LocalizedStringKey(category.englishName))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: DISpacing.sm)

                if count > 0 {
                    Text(verbatim: "\(count)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(category.libraryAccent)
                        .padding(.horizontal, DISpacing.sm)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(category.libraryAccent.opacity(0.12))
                        )
                        .accessibilityLabel(Text("\(count) items"))
                }

                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
    }
}
