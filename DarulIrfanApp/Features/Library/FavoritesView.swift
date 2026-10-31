import SwiftUI

/// The user's favorited library items, most recently favorited first.
struct FavoritesView: View {
    let viewModel: LibraryViewModel

    @State private var items: [ContentItem] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView()
                    .tint(DIColor.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadFailed {
                VStack(spacing: DISpacing.md) {
                    DIEmptyState(systemImage: "heart", titleKey: "Something went wrong",
                        messageKey: "Please try again in a moment.")
                    Button("Retry") { attempt += 1 }
                        .buttonStyle(.bordered)
                        .tint(DIColor.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                DIEmptyState(
                    systemImage: "heart",
                    titleKey: "No favorites yet",
                    messageKey: "Tap the star on any library item to keep it here for quick access."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: DISpacing.md) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ContentItemRow(item: item, isFavorite: viewModel.isFavorite(item.id)) {
                                Task {
                                    if await viewModel.toggleFavorite(contentItemID: item.id) {
                                        items.removeAll { $0.id == item.id }
                                    }
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
        .navigationTitle("Favorites")
        .task(id: attempt) {
            isLoading = true
            loadFailed = false
            defer { isLoading = false }
            do {
                items = try await viewModel.favoriteItems()
            } catch is CancellationError {
                return
            } catch {
                loadFailed = true
            }
        }
    }
}
