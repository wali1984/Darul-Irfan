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
    @State private var loadFailed = false
    @State private var attempt = 0

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
        return "\(listed)|\(language)|\(type)|\(attempt)"
    }

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView()
                    .tint(DIColor.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadFailed {
                VStack(spacing: DISpacing.md) {
                    DIEmptyState(systemImage: "book", titleKey: "Something went wrong",
                        messageKey: "Please try again in a moment.")
                    Button("Retry") { attempt += 1 }
                        .buttonStyle(DISecondaryButtonStyle())
                        .tint(DIColor.primary)
                }
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
        .libraryFavoriteFailure(viewModel)
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                filterMenu
            }
        }
        .task(id: reloadKey) {
            isLoading = true
            loadFailed = false
            defer { isLoading = false }
            do {
                let loaded = try await viewModel.items(in: categories)
                try Task.checkCancellation()
                items = loaded
            } catch is CancellationError {
                return
            } catch {
                loadFailed = true
            }
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
            if hasActiveFilters {
                Button("Clear filters") {
                    viewModel.languageFilter = nil
                    viewModel.typeFilter = nil
                }
            }
            if hasActiveFilters { Divider() }
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
                                    LibraryCatalogueText(text: titleUrdu, latinFont: .body, bold: true)
                                        .foregroundStyle(DIColor.textPrimary)
                                    LibraryCatalogueText(text: item.title, latinFont: .footnote, urduScale: 0.75)
                                        .foregroundStyle(DIColor.textMuted)
                                } else {
                                    LibraryCatalogueText(text: item.title, latinFont: .body, bold: true)
                                        .foregroundStyle(DIColor.textPrimary)
                                    if let titleUrdu = item.titleUrdu, !titleUrdu.isEmpty {
                                        LibraryCatalogueText(text: titleUrdu, latinFont: .footnote, urduScale: 0.9)
                                            .foregroundStyle(DIColor.textMuted)
                                    }
                                }
                            }
                            if !subtitleText.isEmpty {
                                LibraryCatalogueText(text: subtitleText, latinFont: .footnote, urduScale: 0.75)
                                    .foregroundStyle(DIColor.textMuted)
                            }
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: DISpacing.sm) { badges }
                                    .fixedSize(horizontal: true, vertical: false)
                                VStack(alignment: .leading, spacing: DISpacing.xs) { badges }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DIPressableStyle())

                LibraryFavoriteButton(isFavorite: isFavorite) {
                    DIHaptics.light()
                    onToggleFavorite()
                }
            }
        }
    }
    @ViewBuilder
    private var badges: some View {
        DIPillBadge(text: String(localized: String.LocalizationValue(item.type.libraryDisplayName)), color: item.type.isFeaturedPublication ? item.type.libraryAccent : DIColor.actionForeground)
        DIPillBadge(text: String(localized: String.LocalizationValue(LibraryLanguage.displayName(forCode: item.language))),
                    color: DIColor.textMuted)
    }

}

struct LibraryCatalogueText: View {
    let text: String
    let latinFont: Font
    var bold = false
    var urduScale: Double = 1

    var body: some View {
        let rtl = ScriptDirection.isRightToLeft(text, fallbackLanguage: nil)
        let font = rtl ? DIFont.urduBody(scale: urduScale) : latinFont
        Text(verbatim: text)
            .font(bold ? font.weight(.semibold) : font)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
    }
}
