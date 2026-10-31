import SwiftUI

// The Silsila on the Halqah tab: the library's About and Teachings pages,
// which leave Discover's library for here, then About Darul Irfan.

// MARK: - Entries

/// One of the Silsila's pages on the Halqah tab: a library category.
struct SilsilaEntry: Identifiable, Equatable {
    let category: ContentCategory
    /// The row's name: an English key the string catalogue translates.
    let title: String
    let systemImage: String
    var isGold = false

    var id: String { category.rawValue }

    /// The Shajra row opens the app's own Shajra (`ShajraView`), drawn in
    /// the app's theme, rather than the library's page.
    var opensShajra: Bool { category == .shajra }

    /// About the Silsila, its two Sheikhs and the Shajra: the library's
    /// About group.
    static let about: [SilsilaEntry] = [
        SilsilaEntry(category: .aboutSilsila, title: "About the Silsila", systemImage: "star.fill", isGold: true),
        SilsilaEntry(category: .sheikhAbdulQadeerAwan, title: "Hazrat Ameer Abdul Qadeer Awan (MZA)", systemImage: "person.fill"),
        SilsilaEntry(category: .sheikhMuhammadAkramAwan, title: "Hazrat Ameer Muhammad Akram Awan (RA)", systemImage: "person.fill"),
        SilsilaEntry(category: .shajra, title: "Shajra", systemImage: "arrow.triangle.branch", isGold: true),
    ]

    /// The library's Teachings group, as one list.
    static let teachings: [SilsilaEntry] = [
        SilsilaEntry(category: .tasawwuf, title: "Tasawwuf", systemImage: "sparkles"),
        SilsilaEntry(category: .tazkiyahNafs, title: "Tazkiyah-e-Nafs", systemImage: "heart.fill"),
        SilsilaEntry(category: .zikrAllah, title: "The Need for Zikr", systemImage: "moon.stars.fill"),
        SilsilaEntry(category: .baiat, title: "Bai'at", systemImage: "checkmark.seal.fill"),
        SilsilaEntry(category: .methodOfZikr, title: "Method of Zikr", systemImage: "list.bullet.rectangle.fill"),
    ]
}

/// What a Silsila row opens.
enum SilsilaOpening: Equatable {
    /// The category's only page, opened directly: no list of one.
    case item(String)
    /// The category's pages, to choose from.
    case list
    /// Nothing yet (before the bundled content is imported).
    case empty

    static func forItems(withIDs ids: [String]) -> SilsilaOpening {
        guard let first = ids.first else { return .empty }
        return ids.count == 1 ? .item(first) : .list
    }
}

// MARK: - Section

/// The Silsila's rows on the Halqah tab: About the Silsila, the two
/// Sheikhs, the Shajra, the Teachings, and About Darul Irfan.
@MainActor
struct SilsilaSection: View {
    let dependencies: AppDependencies
    let appState: AppState
    let library: LibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            HalqahSectionLabel(titleKey: "Silsila")
            HalqahGlassList {
                ForEach(Array(SilsilaEntry.about.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        HalqahRowDivider()
                    }
                    SilsilaEntryLink(entry: entry, dependencies: dependencies, appState: appState, library: library)
                }
                HalqahRowDivider()
                NavigationLink {
                    SilsilaTeachingsView(dependencies: dependencies, appState: appState, library: library)
                } label: {
                    HalqahListRowLabel(titleKey: "Teachings", systemImage: "book.closed.fill")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("silsila-teachings")
                HalqahRowDivider()
                NavigationLink {
                    AboutView()
                } label: {
                    HalqahListRowLabel(titleKey: "About Darul Irfan", systemImage: "info.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("silsila-about-app")
            }
        }
    }
}

/// A row that opens one of the Silsila's categories.
@MainActor
private struct SilsilaEntryLink: View {
    let entry: SilsilaEntry
    let dependencies: AppDependencies
    let appState: AppState
    let library: LibraryViewModel

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HalqahListRowLabel(
                titleKey: LocalizedStringKey(entry.title),
                systemImage: entry.systemImage,
                tint: entry.isGold ? .gold : .green
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("silsila-" + entry.id)
    }

    /// The Shajra opens at once, drawn in the app; any other category opens
    /// its page, or its pages to choose from.
    @ViewBuilder
    private var destination: some View {
        if entry.opensShajra {
            ShajraView()
        } else {
            SilsilaCategoryDestination(entry: entry, dependencies: dependencies, appState: appState, library: library)
        }
    }
}

// MARK: - Teachings

/// The Silsila's teachings in one list: Tasawwuf, Tazkiyah-e-Nafs, The Need
/// for Zikr, Bai'at and the Method of Zikr.
@MainActor
struct SilsilaTeachingsView: View {
    let dependencies: AppDependencies
    let appState: AppState
    let library: LibraryViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: DISpacing.lg) {
                VStack(spacing: 12) {
                    DILivingSealMark(diameter: 64).accessibilityHidden(true)
                    Text("Teachings").font(.title2.bold()).foregroundStyle(Color(hex: 0xFFE3A0))
                    Text("Silsila Naqshbandia Owaisiah").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                }
                .multilineTextAlignment(.center)
                .padding(28)
                .frame(maxWidth: .infinity)
                .background(DIGradient.emerald)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .diAppear()
                HalqahGlassList {
                ForEach(Array(SilsilaEntry.teachings.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        HalqahRowDivider()
                    }
                    SilsilaEntryLink(entry: entry, dependencies: dependencies, appState: appState, library: library)
                }
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .navigationTitle("Teachings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - A category's page

/// What a Silsila row opens: the category's only page directly, or its pages
/// to choose from when it holds several.
@MainActor
struct SilsilaCategoryDestination: View {
    let entry: SilsilaEntry
    let dependencies: AppDependencies
    let appState: AppState
    let library: LibraryViewModel
    @State private var items: [ContentItem]?

    var body: some View {
        Group {
            if let items {
                switch SilsilaOpening.forItems(withIDs: items.map(\.id)) {
                case .item(let id):
                    ContentItemDetailView(itemID: id, dependencies: dependencies, appState: appState, libraryViewModel: library)
                case .list:
                    SilsilaItemList(entry: entry, items: items, dependencies: dependencies, appState: appState, library: library)
                case .empty:
                    DIEmptyState(
                        systemImage: entry.systemImage,
                        titleKey: "Nothing here yet",
                        messageKey: "Items in this section will appear automatically after the next verified content update."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .diScreenBackground()
                    .navigationTitle(LocalizedStringKey(entry.title))
                    .navigationBarTitleDisplayMode(.inline)
                }
            } else {
                ProgressView()
                    .tint(DIColor.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .diScreenBackground()
            }
        }
        .task {
            guard items == nil else { return }
            items = await library.items(in: entry.category)
        }
    }
}

/// A Silsila category's pages, when it holds more than one.
@MainActor
private struct SilsilaItemList: View {
    let entry: SilsilaEntry
    let items: [ContentItem]
    let dependencies: AppDependencies
    let appState: AppState
    let library: LibraryViewModel

    var body: some View {
        ScrollView {
            HalqahGlassList {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        HalqahRowDivider()
                    }
                    NavigationLink {
                        ContentItemDetailView(itemID: item.id, dependencies: dependencies, appState: appState, libraryViewModel: library)
                    } label: {
                        SilsilaItemRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .navigationTitle(LocalizedStringKey(entry.title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One page of a category: its title, and its Urdu title when it has one.
private struct SilsilaItemRow: View {
    let item: ContentItem

    var body: some View {
        HStack(spacing: 12) {
            HalqahRowTile(systemImage: "doc.text.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DIColor.textPrimary)
                if let titleUrdu = item.titleUrdu, !titleUrdu.isEmpty {
                    Text(verbatim: titleUrdu)
                        .font(DIFont.urduBody(scale: 0.85))
                        .foregroundStyle(DIColor.textMuted)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DISpacing.sm)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.bold))
                .foregroundStyle(DIColor.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }
}
