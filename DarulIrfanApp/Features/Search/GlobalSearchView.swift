import SwiftUI

/// Global search across Quran, Library, Media, and Events. Presented as a
/// sheet from feature toolbars; owns its own NavigationStack.
///
/// A custom prominent search field is used instead of `.searchable` so the
/// field is immediately visible and focused inside the sheet, keeps a plain
/// keyboard suited to English/Urdu/Arabic input, and lays out safely in both
/// LTR and RTL app languages.
@MainActor
struct GlobalSearchView: View {
    @State private var viewModel: SearchViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFieldFocused: Bool

    init(dependencies: AppDependencies) {
        _viewModel = State(initialValue: SearchViewModel(
            searchIndex: dependencies.searchIndex,
            contentRepository: dependencies.contentRepository,
            mediaRepository: dependencies.mediaRepository,
            eventsRepository: dependencies.eventsRepository
        ))
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { viewModel.query },
            set: { viewModel.updateQuery($0) }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                domainChips
                content
            }
            .diScreenBackground()
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
        .tint(DIColor.primary)
        .onAppear {
            isSearchFieldFocused = true
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DIColor.textMuted)
                .accessibilityHidden(true)

            TextField(
                "Search Quran, library, media, and events",
                text: queryBinding
            )
            .focused($isSearchFieldFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit {
                viewModel.searchNow()
            }
            .foregroundStyle(DIColor.textPrimary)

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.clearQuery()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DIColor.textMuted)
                }
                .accessibilityLabel("Clear search text")
            }
        }
        .padding(.horizontal, DISpacing.md)
        .frame(minHeight: 46)
        .background(DIColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                .stroke(DIColor.border, lineWidth: 1)
        )
        .padding(.horizontal, DISpacing.md)
        .padding(.top, DISpacing.sm)
    }

    // MARK: - Domain filter chips

    private var domainChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DISpacing.sm) {
                DomainFilterChip(
                    titleKey: "All",
                    systemImage: nil,
                    isSelected: viewModel.selectedDomain == nil
                ) {
                    viewModel.selectDomain(nil)
                }
                ForEach(SearchDomain.allCases) { domain in
                    DomainFilterChip(
                        titleKey: LocalizedStringKey(domain.displayTitle),
                        systemImage: domain.iconName,
                        isSelected: viewModel.selectedDomain == domain
                    ) {
                        viewModel.selectDomain(domain)
                    }
                }
            }
            .padding(.horizontal, DISpacing.md)
            .padding(.vertical, DISpacing.sm)
        }
    }

    // MARK: - Results / states

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            stateContainer {
                DIEmptyState(
                    systemImage: "magnifyingglass",
                    titleKey: "Search Darul Irfan",
                    messageKey: "Find ayahs, articles, books, lectures, and events. You can search in English, Urdu, or Arabic."
                )
            }
        case .searching:
            if viewModel.hasResults {
                // Keep the previous results visible while the new query runs.
                resultsList
                    .opacity(0.6)
                    .overlay(alignment: .top) {
                        ProgressView()
                            .padding(DISpacing.md)
                    }
            } else {
                stateContainer {
                    ProgressView("Searching…")
                        .tint(DIColor.primary)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
        case .results:
            resultsList
        case .empty:
            stateContainer {
                if viewModel.selectedDomain == nil {
                    DIEmptyState(
                        systemImage: "text.magnifyingglass",
                        titleKey: "No results found",
                        messageKey: "Try a different word or a shorter phrase."
                    )
                } else {
                    DIEmptyState(
                        systemImage: "text.magnifyingglass",
                        titleKey: "No results found",
                        messageKey: "Try a different word, or switch to All to search every section."
                    )
                }
            }
        case .failed:
            stateContainer {
                DIEmptyState(
                    systemImage: "exclamationmark.circle",
                    titleKey: "Search is unavailable right now",
                    messageKey: "Please try again in a moment."
                )
            }
        }
    }

    /// Centers a state view in the remaining space, keeping it scrollable so
    /// large Dynamic Type sizes never clip.
    private func stateContainer<StateContent: View>(
        @ViewBuilder _ stateContent: () -> StateContent
    ) -> some View {
        ScrollView {
            stateContent()
                .frame(maxWidth: .infinity)
                .padding(.top, DISpacing.xl)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var resultsList: some View {
        List {
            ForEach(viewModel.groups) { group in
                Section {
                    ForEach(group.results) { result in
                        SearchResultRow(
                            result: result,
                            sourceURL: viewModel.sourceURL(for: result),
                            reference: viewModel.reference(for: result)
                        )
                        .listRowBackground(DIColor.surface)
                    }
                } header: {
                    HStack(spacing: DISpacing.xs) {
                        Image(systemName: group.domain.iconName)
                            .foregroundStyle(DIColor.accent)
                            .accessibilityHidden(true)
                        Text(LocalizedStringKey(group.domain.displayTitle))
                            .foregroundStyle(DIColor.textMuted)
                    }
                    .font(.footnote.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }
}

// MARK: - Filter chip

/// Selectable capsule chip in the DIPillBadge visual family.
private struct DomainFilterChip: View {
    let titleKey: LocalizedStringKey
    let systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DISpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
                Text(titleKey)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, DISpacing.sm + DISpacing.xs)
            .padding(.vertical, DISpacing.xs + 2)
            .background(isSelected ? DIColor.primary : DIColor.primary.opacity(0.14))
            .foregroundStyle(isSelected ? DIColor.onPrimary : DIColor.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
