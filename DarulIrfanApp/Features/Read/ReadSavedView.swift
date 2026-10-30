import SwiftUI

/// Read › Saved: what the reader has kept, in one place. Qur'an bookmarks,
/// library favourites and private notes (with the notes written on an ayah),
/// each opening its own existing screen.
@MainActor
struct ReadSavedView: View {
    let dependencies: AppDependencies
    let appState: AppState
    /// Opens a bookmarked ayah in the Quran reader; the Read tab closes Saved first.
    let onOpenAyah: (QuranAyahLink) -> Void

    @State private var quran: QuranViewModel
    @State private var library: LibraryViewModel
    @State private var notes = MyDayStore.shared
    @Environment(\.dismiss) private var dismiss

    init(
        dependencies: AppDependencies,
        appState: AppState,
        onOpenAyah: @escaping (QuranAyahLink) -> Void
    ) {
        self.dependencies = dependencies
        self.appState = appState
        self.onOpenAyah = onOpenAyah
        _quran = State(initialValue: QuranViewModel(repository: dependencies.quranRepository))
        _library = State(initialValue: LibraryViewModel(contentRepository: dependencies.contentRepository))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    NavigationLink {
                        BookmarksListView(viewModel: quran, onOpen: { surah, ayah in
                            onOpenAyah(QuranAyahLink(surah: surah.id, ayah: ayah))
                        })
                    } label: {
                        savedRow(
                            systemImage: "bookmark.fill",
                            title: "Bookmarks",
                            detail: Text("\(quran.bookmarks.count) ayahs"),
                            gold: false
                        )
                    }
                    .buttonStyle(.plain)

                    ReadRowRule()

                    NavigationLink {
                        FavoritesView(viewModel: library)
                    } label: {
                        savedRow(
                            systemImage: "star.fill",
                            title: "Favorites",
                            detail: Text("\(library.favoritesCount) items"),
                            gold: true
                        )
                    }
                    .buttonStyle(.plain)

                    ReadRowRule()

                    NavigationLink {
                        NotesView()
                    } label: {
                        savedRow(
                            systemImage: "note.text",
                            title: "Private notes",
                            detail: Text("\(notes.document.notes.count) items"),
                            gold: false
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(6)
                .diGlassPanel(cornerRadius: 24)
                .padding(DISpacing.md)
                .diResponsiveWidth()
            }
            .diScreenBackground()
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
            // A favourite opens its book page or article here, as a search
            // result does in the search sheet.
            .navigationDestination(for: LibraryRoute.self) { route in
                LibraryDestination(
                    route: route,
                    dependencies: dependencies,
                    appState: appState,
                    viewModel: library
                )
            }
            .onAppear { notes.loadIfNeeded() }
            .task {
                await quran.load()
                await library.loadFavorites()
            }
        }
        .tint(DIColor.primary)
    }

    private func savedRow(systemImage: String, title: LocalizedStringKey, detail: Text, gold: Bool) -> some View {
        HStack(spacing: 14) {
            ReadOrb(systemImage: systemImage, gold: gold)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DIColor.textPrimary)
                detail
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DIColor.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
