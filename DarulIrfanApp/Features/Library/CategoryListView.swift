import SwiftUI

/// Items within one library category, with language/type filters and
/// favorite toggles. A Books shelf of two categories ("Courses and
/// documents") lists both together under the shelf's name.
struct CategoryListView: View {
    let category: ContentCategory
    @Bindable var viewModel: LibraryViewModel
    /// Further categories listed with this one, under `shelfTitle`.
    var alsoListing: [ContentCategory] = []
    /// The shelf's own name when it lists more than one category.
    var shelfTitle: String? = nil

    @State private var items: [ContentItem] = []
    @State private var isLoading = true

    private var categories: [ContentCategory] {
        [category] + alsoListing
    }

    private var title: String {
        shelfTitle ?? category.englishName
    }

    private var hasActiveFilters: Bool {
        viewModel.languageFilter != nil || viewModel.typeFilter != nil
    }

    /// Reload key: changes whenever the category or either filter changes.
    private var reloadKey: String {
        let language = viewModel.languageFilter ?? "all"
        let type = viewModel.typeFilter?.rawValue ?? "all"
        let listed = categories.map(\.rawValue).joined(separator: ",")
        return "\(listed)|\(language)|\(type)"
    }

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView()
                    .tint(DIColor.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: DISpacing.md) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ContentItemRow(item: item, isFavorite: viewModel.isFavorite(item.id)) {
                                Task {
                                    await viewModel.toggleFavorite(contentItemID: item.id)
                                }
                            }
                            .diAppear(delay: min(Double(index) * 0.04, 0.4))
                        }
                    }
                    .padding(DISpacing.md)
                }
            }
        }
        .diScreenBackground()
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                filterMenu
            }
        }
        .task(id: reloadKey) {
            isLoading = true
            items = await viewModel.items(in: categories)
            isLoading = false
        }
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyState: some View {
        if hasActiveFilters {
            VStack(spacing: DISpacing.md) {
                DIEmptyState(
                    systemImage: "line.3.horizontal.decrease.circle",
                    titleKey: "No items match these filters",
                    messageKey: "Try choosing a different language or type."
                )
                Button("Clear filters") {
                    viewModel.languageFilter = nil
                    viewModel.typeFilter = nil
                }
                .buttonStyle(DISecondaryButtonStyle())
                .padding(.horizontal, DISpacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            DIEmptyState(
                systemImage: category.librarySymbol,
                titleKey: "Nothing here yet",
                messageKey: "Items in this section will appear automatically after the next verified content update."
            )
            .diOctagramWatermark(size: 260, opacity: 0.05)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Filters

    private var filterMenu: some View {
        Menu {
            Picker("Language", selection: $viewModel.languageFilter) {
                Text("All languages").tag(nil as String?)
                Text("English").tag("en" as String?)
                Text("Urdu").tag("ur" as String?)
                Text("Arabic").tag("ar" as String?)
            }
            Picker("Type", selection: $viewModel.typeFilter) {
                Text("All types").tag(nil as ContentType?)
                ForEach(ContentType.allCases, id: \.rawValue) { type in
                    Text(LocalizedStringKey(type.libraryDisplayName)).tag(type as ContentType?)
                }
            }
            if hasActiveFilters {
                Button("Clear filters") {
                    viewModel.languageFilter = nil
                    viewModel.typeFilter = nil
                }
            }
        } label: {
            Image(systemName: hasActiveFilters
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(Text("Filter"))
    }
}

// MARK: - Item row

/// One library item as an elevated live panel: a gradient medallion (gilded for
/// books/booklets/magazines), the title (with Urdu title trailing when present),
/// author and year, type + language badges, and a favorite star.
struct ContentItemRow: View {
    @Environment(\.locale) private var locale
    let item: ContentItem
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    private var subtitleText: String {
        var parts: [String] = []
        if let author = item.author, !author.isEmpty {
            parts.append(author)
        }
        if let publishedAt = item.publishedAt {
            // The catalogue gives the day as midnight UTC: read it in UTC, or
            // west of Greenwich a 1 January issue shows the year before.
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = .gmt
            parts.append(String(utc.component(.year, from: publishedAt)))
        }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        DIElevatedCard(glow: item.type.libraryAccent) {
            HStack(alignment: .top, spacing: DISpacing.md) {
                NavigationLink(value: LibraryRoute.item(id: item.id)) {
                    HStack(alignment: .top, spacing: DISpacing.md) {
                        LibraryMedallion(
                            systemImage: item.type.libraryIcon,
                            isSpecial: item.type.isFeaturedPublication,
                            diameter: 44
                        )
                        VStack(alignment: .leading, spacing: DISpacing.xs) {
                            VStack(alignment: .leading, spacing: DISpacing.xs) {
                                if locale.language.languageCode?.identifier == "ur",
                                   let titleUrdu = item.titleUrdu, !titleUrdu.isEmpty {
                                    Text(verbatim: titleUrdu)
                                        .font(DIFont.urduBody().weight(.semibold))
                                        .foregroundStyle(DIColor.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(verbatim: item.title)
                                        .font(.footnote)
                                        .foregroundStyle(DIColor.textMuted)
                                } else {
                                    Text(verbatim: item.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(DIColor.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    if let titleUrdu = item.titleUrdu, !titleUrdu.isEmpty {
                                        Text(verbatim: titleUrdu)
                                            .font(DIFont.urduBody(scale: 0.9))
                                            .foregroundStyle(DIColor.textMuted)
                                            .multilineTextAlignment(.trailing)
                                    }
                                }
                            }
                            if !subtitleText.isEmpty {
                                Text(verbatim: subtitleText)
                                    .font(.footnote)
                                    .foregroundStyle(DIColor.textMuted)
                            }
                            HStack(spacing: DISpacing.sm) {
                                DIPillBadge(text: String(localized: String.LocalizationValue(item.type.libraryDisplayName)), color: item.type.libraryAccent)
                                DIPillBadge(
                                    text: String(localized: String.LocalizationValue(LibraryLanguage.displayName(forCode: item.language))),
                                    color: DIColor.textMuted
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    DIHaptics.light()
                    onToggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.body)
                        .foregroundStyle(isFavorite ? DIColor.accent : DIColor.textMuted)
                        .padding(DISpacing.xs)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? Text("Remove from favorites") : Text("Add to favorites"))
            }
        }
    }
}
