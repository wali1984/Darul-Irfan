import SwiftUI

/// Bookmarked ayahs grouped by surah. Opened from Read › Saved (and still
/// routable in the Quran reader's stack); tapping a bookmark opens the reader
/// scrolled to that ayah, and rows can be removed with a swipe.
struct BookmarksListView: View {
    let viewModel: QuranViewModel
    /// Set where the list is shown outside the Quran reader's stack (Read ›
    /// Saved, a sheet): a bookmark then opens through this, since a link to
    /// the reader there would have no route to follow.
    var onOpen: ((QuranSurah, Int) -> Void)? = nil

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
                        if let onOpen {
                            Button {
                                DIHaptics.soft()
                                onOpen(group.surah, bookmark.ayahNumber)
                            } label: {
                                HStack(spacing: DISpacing.sm) {
                                    bookmarkRow(bookmark)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.forward")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(DIColor.textMuted)
                                        .accessibilityHidden(true)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(
                                value: QuranRoute.reader(surah: group.surah, focusAyah: bookmark.ayahNumber)
                            ) {
                                bookmarkRow(bookmark)
                            }
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
