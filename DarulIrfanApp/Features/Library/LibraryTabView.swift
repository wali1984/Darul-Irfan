import SwiftUI

/// Library tab root: featured Silsila/Sheikh pages, grouped category browser,
/// favorites, and navigation into category lists, item details, and PDFs.
struct LibraryTabView: View {
    private let dependencies: AppDependencies
    private let appState: AppState
    @State private var viewModel: LibraryViewModel
    @State private var isShowingSearch = false
    @State private var isMoreExpanded = false

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
        _viewModel = State(initialValue: LibraryViewModel(contentRepository: dependencies.contentRepository))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DISpacing.lg) {
                    featuredSection
                    if viewModel.hasLoadedCounts {
                        if viewModel.totalItemCount > 0 {
                            categorySections
                            moreCategoriesSection
                        } else {
                            DIEmptyState(
                                systemImage: "books.vertical",
                                titleKey: "The library is being prepared",
                                messageKey: "Books, articles, and announcements will appear here after the first content update. Until then, the full collection is available at naqshbandiaowaisiah.org."
                            )
                        }
                    } else {
                        loadingSection
                    }
                }
                .padding(DISpacing.md)
            }
            .diScreenBackground()
            .navigationTitle("Library")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
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
            .navigationDestination(for: LibraryRoute.self) { route in
                destination(for: route)
            }
            .sheet(isPresented: $isShowingSearch) {
                GlobalSearchView(dependencies: dependencies)
            }
            .task {
                await viewModel.loadHomeIfNeeded()
            }
            .refreshable {
                await viewModel.reloadHome()
            }
        }
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(for route: LibraryRoute) -> some View {
        switch route {
        case .category(let category):
            CategoryListView(category: category, viewModel: viewModel)
        case .item(let id):
            ContentItemDetailView(
                itemID: id,
                dependencies: dependencies,
                appState: appState,
                libraryViewModel: viewModel
            )
        case .favorites:
            FavoritesView(viewModel: viewModel)
        case .pdf(let url, let title):
            PDFViewerView(fileURL: url, title: title)
        }
    }

    // MARK: - Featured

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Featured", systemImage: "sparkles")

            NavigationLink(value: LibraryRoute.category(.aboutSilsila)) {
                LibraryFeaturedCard(
                    titleKey: "Silsila Naqshbandia Owaisiah",
                    subtitleKey: "About the order, its lineage, and its method",
                    systemImage: "book.closed"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: LibraryRoute.category(.sheikhAbdulQadeerAwan)) {
                LibraryFeaturedCard(
                    titleKey: "Hazrat Ameer Abdul Qadeer Awan",
                    subtitleKey: "Sheikh-e-Silsila Naqshbandia Owaisiah (MZA)",
                    systemImage: "person.crop.circle"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: LibraryRoute.category(.sheikhMuhammadAkramAwan)) {
                LibraryFeaturedCard(
                    titleKey: "Hazrat Ameer Muhammad Akram Awan",
                    subtitleKey: "Former Sheikh-e-Silsila (RA)",
                    systemImage: "person.crop.circle"
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Category groups

    private var categorySections: some View {
        ForEach(LibraryCategoryGroup.groups) { group in
            let visible = group.categories.filter { viewModel.count(for: $0) > 0 }
            if !visible.isEmpty {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    DISectionHeader(
                        titleKey: LocalizedStringKey(group.title),
                        systemImage: group.systemImage
                    )
                    DICard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(visible) { category in
                                LibraryCategoryRow(category: category, count: viewModel.count(for: category))
                                if category != visible.last {
                                    Divider().padding(.leading, 52)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var moreCategoriesSection: some View {
        let hidden = viewModel.hiddenCategories
        if !hidden.isEmpty {
            DICard {
                DisclosureGroup(isExpanded: $isMoreExpanded) {
                    VStack(spacing: 0) {
                        ForEach(hidden) { category in
                            LibraryCategoryRow(category: category, count: 0)
                            if category != hidden.last {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                } label: {
                    Label("More categories", systemImage: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(DIColor.textPrimary)
                }
                .tint(DIColor.textMuted)
            }
        }
    }

    private var loadingSection: some View {
        HStack {
            Spacer(minLength: 0)
            ProgressView("Loading the library…")
                .tint(DIColor.primary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, DISpacing.xl)
    }
}

// MARK: - Featured card

/// Elegant serif-headed card for the About Silsila and Sheikh pages.
struct LibraryFeaturedCard: View {
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey
    let systemImage: String

    var body: some View {
        DICard {
            HStack(spacing: DISpacing.md) {
                ZStack {
                    Circle()
                        .fill(DIColor.accent.opacity(0.16))
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(DIColor.accent)
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

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

// MARK: - Category row

/// One tappable row in the grouped category browser.
struct LibraryCategoryRow: View {
    let category: ContentCategory
    let count: Int

    var body: some View {
        NavigationLink(value: LibraryRoute.category(category)) {
            HStack(spacing: DISpacing.sm) {
                Image(systemName: category.librarySymbol)
                    .foregroundStyle(DIColor.primary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(LocalizedStringKey(category.englishName))
                    .font(.body)
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: DISpacing.sm)
                if count > 0 {
                    Text(verbatim: "\(count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(DIColor.textMuted)
                }
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DISpacing.md)
            .padding(.vertical, DISpacing.sm + DISpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
