import SwiftUI

/// Items within one library category, with language/type filters and
/// favorite toggles.
struct CategoryListView: View {
    let category: ContentCategory
    @Bindable var viewModel: LibraryViewModel

    @State private var items: [ContentItem] = []
    @State private var isLoading = true

    private var hasActiveFilters: Bool {
        viewModel.languageFilter != nil || viewModel.typeFilter != nil
    }

    /// Reload key: changes whenever the category or either filter changes.
    private var reloadKey: String {
        let language = viewModel.languageFilter ?? "all"
        let type = viewModel.typeFilter?.rawValue ?? "all"
        return "\(category.rawValue)|\(language)|\(type)"
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
        .navigationTitle(LocalizedStringKey(category.englishName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                filterMenu
            }
        }
        .task(id: reloadKey) {
            isLoading = true
            items = await viewModel.items(in: category)
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
    let item: ContentItem
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    private var subtitleText: String {
        var parts: [String] = []
        if let author = item.author, !author.isEmpty {
            parts.append(author)
        }
        if let publishedAt = item.publishedAt {
            parts.append(String(Calendar.current.component(.year, from: publishedAt)))
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
                            HStack(alignment: .firstTextBaseline, spacing: DISpacing.sm) {
                                Text(verbatim: item.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(DIColor.textPrimary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                if let titleUrdu = item.titleUrdu, !titleUrdu.isEmpty {
                                    Text(verbatim: titleUrdu)
                                        .font(DIFont.urduBody(scale: 0.9))
                                        .foregroundStyle(DIColor.textPrimary)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                            if !subtitleText.isEmpty {
                                Text(verbatim: subtitleText)
                                    .font(.footnote)
                                    .foregroundStyle(DIColor.textMuted)
                            }
                            HStack(spacing: DISpacing.sm) {
                                DIPillBadge(text: item.type.libraryDisplayName, color: item.type.libraryAccent)
                                DIPillBadge(
                                    text: LibraryLanguage.displayName(forCode: item.language),
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
