import SwiftUI

/// Bookmarked ayahs grouped by surah. Pushed from the Quran tab toolbar;
/// tapping a bookmark opens the reader scrolled to that ayah, and rows can be
/// removed with a swipe.
struct BookmarksListView: View {
    let viewModel: QuranViewModel

    var body: some View {
        Group {
            if viewModel.bookmarksBySurah.isEmpty {
                DIEmptyState(
                    systemImage: "bookmark",
                    titleKey: "No bookmarks yet",
                    messageKey: "While reading, tap the bookmark icon on any ayah and it will be kept here for you."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                bookmarksList
            }
        }
        .diScreenBackground()
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.refreshReaderState() }
    }

    private var bookmarksList: some View {
        List {
            ForEach(viewModel.bookmarksBySurah) { group in
                Section {
                    ForEach(group.bookmarks) { bookmark in
                        NavigationLink(
                            value: QuranRoute.reader(surah: group.surah, focusAyah: bookmark.ayahNumber)
                        ) {
                            bookmarkRow(bookmark)
                        }
                    }
                    .onDelete { offsets in
                        let items = offsets.compactMap { index -> QuranBookmark? in
                            guard group.bookmarks.indices.contains(index) else { return nil }
                            return group.bookmarks[index]
                        }
                        Task {
                            for item in items {
                                await viewModel.removeBookmark(item)
                            }
                        }
                    }
                    .listRowBackground(DIColor.surface)
                } header: {
                    Text("\(group.surah.id). \(group.surah.nameTransliterated)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DIColor.textMuted)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func bookmarkRow(_ bookmark: QuranBookmark) -> some View {
        VStack(alignment: .leading, spacing: DISpacing.xs) {
            Text("Ayah \(bookmark.ayahNumber)")
                .font(.headline)
                .foregroundStyle(DIColor.textPrimary)
            if let note = bookmark.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
            }
            Text("Saved \(bookmark.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(DIColor.textMuted)
        }
        .padding(.vertical, DISpacing.xs)
    }
}
