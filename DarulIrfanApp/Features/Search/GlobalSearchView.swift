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

    /// Inviting starter topics shown on the idle prompt. Tapping one runs the
    /// search — the same path as typing it.
    private let suggestions = ["Zikr", "Tasawwuf", "Tazkiyah", "Ramadan", "Salah", "Naqshbandia"]

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
                .font(.body.weight(.semibold))
                .foregroundStyle(isSearchFieldFocused ? DIColor.primary : DIColor.textMuted)
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
            .tint(DIColor.primary)
            .foregroundStyle(DIColor.textPrimary)

            if !viewModel.query.isEmpty {
                Button {
                    DIHaptics.light()
                    viewModel.clearQuery()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(DIColor.textMuted)
                }
                .accessibilityLabel("Clear search text")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, DISpacing.md)
        .frame(minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                .fill(DIColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: isSearchFieldFocused
                            ? [DIColor.primary.opacity(0.9), DIColor.accent.opacity(0.65)]
                            : [DIColor.accent.opacity(0.35), DIColor.border.opacity(0.5)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: isSearchFieldFocused ? 1.6 : 1
                )
        )
        .shadow(
            color: (isSearchFieldFocused ? DIColor.primary : Color.black)
                .opacity(isSearchFieldFocused ? 0.18 : 0.08),
            radius: isSearchFieldFocused ? 12 : 8, x: 0, y: 4
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSearchFieldFocused)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.query.isEmpty)
        .padding(.horizontal, DISpacing.md)
        .padding(.top, DISpacing.md)
        .padding(.bottom, DISpacing.xs)
    }

    // MARK: - Domain filter chips

    private var domainChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DISpacing.sm) {
                DomainFilterChip(
                    titleKey: "All",
                    systemImage: "square.grid.2x2",
                    isSelected: viewModel.selectedDomain == nil
                ) {
                    DIHaptics.light()
                    viewModel.selectDomain(nil)
                }
                ForEach(SearchDomain.allCases) { domain in
                    DomainFilterChip(
                        titleKey: LocalizedStringKey(domain.displayTitle),
                        systemImage: domain.iconName,
                        isSelected: viewModel.selectedDomain == domain
                    ) {
                        DIHaptics.light()
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
            idlePrompt
        case .searching:
            if viewModel.hasResults {
                // Keep the previous results visible while the new query runs.
                resultsList
                    .opacity(0.55)
                    .overlay(alignment: .top) {
                        refreshingBadge
                    }
            } else {
                SearchSkeletonView()
            }
        case .results:
            resultsList
        case .empty:
            brandedState(
                systemImage: "text.magnifyingglass",
                titleKey: "No results found",
                messageKey: viewModel.selectedDomain == nil
                    ? "Try a different word or a shorter phrase."
                    : "Try a different word, or switch to All to search every section."
            )
        case .failed:
            brandedState(
                systemImage: "exclamationmark.circle",
                titleKey: "Search is unavailable right now",
                messageKey: "Please try again in a moment."
            )
        }
    }

    // MARK: Idle — branded prompt

    private var idlePrompt: some View {
        ScrollView {
            VStack(spacing: DISpacing.lg) {
                DISealEmblem(diameter: 96, glow: true)
                    .diBreathingGlow(color: DIColor.goldGlow, maxRadius: 18)
                    .padding(.top, DISpacing.xl)

                VStack(spacing: DISpacing.sm) {
                    Text("Search Darul Irfan")
                        .font(DIFont.heading)
                        .foregroundStyle(DIColor.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Find ayahs, articles, books, lectures, and events. You can search in English, Urdu, or Arabic.")
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DISpacing.lg)
                }

                DIJaliDivider()
                    .padding(.horizontal, DISpacing.xl)

                VStack(spacing: DISpacing.md) {
                    Text("Try searching for")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DIColor.textMuted)
                        .textCase(.uppercase)
                        .kerning(0.5)
                    suggestionRows
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, DISpacing.xl)
            .diOctagramWatermark(size: 340, opacity: 0.05)
            .diAppear()
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // Two centered rows of starter chips; scales down before it ever overflows.
    private var suggestionRows: some View {
        let columns = 3
        let rows = stride(from: 0, to: suggestions.count, by: columns).map { start in
            Array(suggestions[start..<min(start + columns, suggestions.count)])
        }
        return VStack(spacing: DISpacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, rowItems in
                HStack(spacing: DISpacing.sm) {
                    ForEach(rowItems, id: \.self) { topic in
                        SuggestionChip(text: topic) { applySuggestion(topic) }
                    }
                }
            }
        }
        .padding(.horizontal, DISpacing.md)
    }

    private func applySuggestion(_ topic: String) {
        DIHaptics.light()
        isSearchFieldFocused = true
        viewModel.updateQuery(topic)
        viewModel.searchNow()
    }

    // MARK: Empty / failed — branded state

    private func brandedState(
        systemImage: String,
        titleKey: LocalizedStringKey,
        messageKey: LocalizedStringKey
    ) -> some View {
        ScrollView {
            DIEmptyState(
                systemImage: systemImage,
                titleKey: titleKey,
                messageKey: messageKey
            )
            .frame(maxWidth: .infinity)
            .padding(.top, DISpacing.xl)
            .diOctagramWatermark(size: 300, opacity: 0.04)
            .diAppear()
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: Results

    private var refreshingBadge: some View {
        HStack(spacing: DISpacing.sm) {
            ProgressView()
                .controlSize(.small)
                .tint(DIColor.primary)
            Text("Searching…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DIColor.textMuted)
        }
        .padding(.horizontal, DISpacing.md)
        .padding(.vertical, DISpacing.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, DISpacing.sm)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DISpacing.lg) {
                ForEach(Array(viewModel.groups.enumerated()), id: \.element.id) { groupIndex, group in
                    VStack(alignment: .leading, spacing: DISpacing.sm) {
                        groupHeader(group)
                        ForEach(Array(group.results.enumerated()), id: \.element.id) { rowIndex, result in
                            SearchResultRow(
                                result: result,
                                reference: viewModel.reference(for: result)
                            )
                            .diAppear(delay: min(Double(groupIndex) * 0.06 + Double(rowIndex) * 0.04, 0.5))
                        }
                    }
                }
            }
            .padding(.horizontal, DISpacing.md)
            .padding(.top, DISpacing.sm)
            .padding(.bottom, DISpacing.xl)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func groupHeader(_ group: SearchResultGroup) -> some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: group.domain.iconName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DIColor.primary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous)
                        .fill(DIColor.primary.opacity(0.12))
                )
                .accessibilityHidden(true)

            Text(LocalizedStringKey(group.domain.displayTitle))
                .font(DIFont.subheading)
                .foregroundStyle(DIColor.textPrimary)

            Spacer(minLength: 0)

            DIPillBadge(text: "\(group.results.count)", color: DIColor.accent)
        }
        .padding(.horizontal, DISpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Filter chip

/// Selectable capsule chip with an emerald-gradient selected state and a
/// spring press response.
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
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
                Text(titleKey)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, DISpacing.md)
            .padding(.vertical, DISpacing.sm)
            .foregroundStyle(isSelected ? DIColor.onPrimary : DIColor.primary)
            .background(chipBackground)
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : DIColor.primary.opacity(0.25), lineWidth: 1)
            )
            .shadow(
                color: isSelected ? DIColor.primaryDeep.opacity(0.3) : .clear,
                radius: isSelected ? 6 : 0, x: 0, y: 3
            )
        }
        .buttonStyle(DIPressableStyle())
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    @ViewBuilder
    private var chipBackground: some View {
        if isSelected {
            Capsule().fill(DIGradient.emerald)
        } else {
            Capsule().fill(DIColor.primary.opacity(0.10))
        }
    }
}

// MARK: - Suggestion chip

/// A gold-ringed starter topic on the idle prompt.
private struct SuggestionChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(text))
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, DISpacing.md)
                .padding(.vertical, DISpacing.sm)
                .foregroundStyle(DIColor.primary)
                .background(Capsule().fill(DIColor.surface))
                .overlay(Capsule().stroke(DIColor.accent.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(DIPressableStyle())
    }
}

// MARK: - Loading skeleton

/// A tasteful shimmering placeholder shown while the first results are loading,
/// in place of a bare spinner.
private struct SearchSkeletonView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DISpacing.md) {
                ForEach(0..<5, id: \.self) { index in
                    skeletonRow
                        .diAppear(delay: Double(index) * 0.05)
                }
            }
            .padding(.horizontal, DISpacing.md)
            .padding(.top, DISpacing.sm)
        }
        .scrollDisabled(true)
        .accessibilityLabel("Searching")
    }

    private var skeletonRow: some View {
        HStack(alignment: .top, spacing: DISpacing.md) {
            RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous)
                .fill(DIColor.sandstone)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                bar(width: nil, height: 15)
                bar(width: 240, height: 11)
                bar(width: 160, height: 11)
            }
            Spacer(minLength: 0)
        }
        .padding(DISpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                .fill(DIColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                .stroke(DIColor.border.opacity(0.5), lineWidth: 1)
        )
        .diShimmer()
    }

    /// A single placeholder bar. `width == nil` stretches to fill the row.
    @ViewBuilder
    private func bar(width: CGFloat?, height: CGFloat) -> some View {
        if let width {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(DIColor.sandstone)
                .frame(width: width, height: height)
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(DIColor.sandstone)
                .frame(maxWidth: .infinity)
                .frame(height: height)
        }
    }
}
