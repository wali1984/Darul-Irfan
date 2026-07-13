import SwiftUI

/// Library tab root: a living emerald hero, featured Silsila/Sheikh pages, a
/// grouped browser of elevated category cards, favorites, and navigation into
/// category lists, item details, and PDFs.
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
                    libraryHero
                        .diAppear()
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
                            .diOctagramWatermark(size: 260, opacity: 0.05)
                            .diAppear(delay: 0.1)
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

    // MARK: - Living hero

    private var libraryHero: some View {
        ZStack {
            DIGradient.hero()
            DIOctagram(innerRatio: 0.5)
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 260, height: 260)
                .opacity(0.06)
                .offset(x: 96, y: -64)

            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: DISpacing.xs) {
                        Text("Library")
                            .font(DIFont.heading)
                            .foregroundStyle(.white)
                        Text("Books, articles, and teachings of the Silsila")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: DISpacing.sm)
                    DISealEmblem(diameter: 52, glow: true)
                        .diBreathingGlow(color: DIColor.goldGlow, maxRadius: 14)
                }

                if viewModel.hasLoadedCounts && viewModel.totalItemCount > 0 {
                    HStack(spacing: DISpacing.sm) {
                        heroStat(icon: "books.vertical.fill", value: "\(viewModel.totalItemCount)", label: "Items")
                        if viewModel.favoritesCount > 0 {
                            heroStat(icon: "heart.fill", value: "\(viewModel.favoritesCount)", label: "Favorites")
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, DISpacing.xs)
                }

                Text(DIBrand.anchorVerseArabic)
                    .font(DIFont.quranArabic(scale: 0.62))
                    .foregroundStyle(.white)
                    .diGoldGlow(radius: 10, opacity: 0.45)
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, DISpacing.xs)
            }
            .padding(DISpacing.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg + 6, style: .continuous))
        .shadow(color: DIColor.primaryDeep.opacity(0.35), radius: 18, x: 0, y: 10)
    }

    private func heroStat(icon: String, value: String, label: String) -> some View {
        HStack(spacing: DISpacing.xs) {
            Image(systemName: icon).font(.caption2)
            Text(value).font(.subheadline.weight(.bold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.8))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, DISpacing.sm)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.14)))
    }

    // MARK: - Featured

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Featured", systemImage: "sparkles")
            ForEach(Array(Self.featuredEntries.enumerated()), id: \.element.category) { index, entry in
                NavigationLink(value: LibraryRoute.category(entry.category)) {
                    LibraryFeaturedCard(
                        titleKey: entry.title,
                        subtitleKey: entry.subtitle,
                        systemImage: entry.icon
                    )
                }
                .buttonStyle(DIPressableStyle())
                .simultaneousGesture(TapGesture().onEnded { DIHaptics.light() })
                .diAppear(delay: 0.05 + Double(index) * 0.05)
            }
        }
    }

    private struct FeaturedEntry {
        let category: ContentCategory
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
        let icon: String
    }

    private static let featuredEntries: [FeaturedEntry] = [
        FeaturedEntry(
            category: .aboutSilsila,
            title: "Silsila Naqshbandia Owaisiah",
            subtitle: "About the order, its lineage, and its method",
            icon: "book.closed"
        ),
        FeaturedEntry(
            category: .sheikhAbdulQadeerAwan,
            title: "Hazrat Ameer Abdul Qadeer Awan",
            subtitle: "Sheikh-e-Silsila Naqshbandia Owaisiah (MZA)",
            icon: "person.crop.circle"
        ),
        FeaturedEntry(
            category: .sheikhMuhammadAkramAwan,
            title: "Hazrat Ameer Muhammad Akram Awan",
            subtitle: "Former Sheikh-e-Silsila (RA)",
            icon: "person.crop.circle"
        )
    ]

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
                    ForEach(Array(visible.enumerated()), id: \.element) { index, category in
                        NavigationLink(value: LibraryRoute.category(category)) {
                            LibraryCategoryRow(category: category, count: viewModel.count(for: category))
                        }
                        .buttonStyle(DIPressableStyle())
                        .simultaneousGesture(TapGesture().onEnded { DIHaptics.light() })
                        .diAppear(delay: Double(index) * 0.04)
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
                            NavigationLink(value: LibraryRoute.category(category)) {
                                HStack(spacing: DISpacing.sm) {
                                    Image(systemName: category.librarySymbol)
                                        .foregroundStyle(category.libraryAccent)
                                        .frame(width: 28)
                                        .accessibilityHidden(true)
                                    Text(LocalizedStringKey(category.englishName))
                                        .font(.body)
                                        .foregroundStyle(DIColor.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: DISpacing.sm)
                                    Image(systemName: "chevron.forward")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(DIColor.textMuted)
                                        .accessibilityHidden(true)
                                }
                                .padding(.vertical, DISpacing.sm)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if category != hidden.last {
                                Divider().padding(.leading, 40)
                            }
                        }
                    }
                    .padding(.top, DISpacing.xs)
                } label: {
                    Label("More categories", systemImage: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(DIColor.textPrimary)
                }
                .tint(DIColor.textMuted)
            }
            .diAppear(delay: 0.1)
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

/// Elevated, gilded card for the About Silsila and Sheikh pages — a live panel
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
