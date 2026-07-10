import Foundation
import Observation

/// State for the Library tab: per-category item counts for the home screen,
/// the user's favorites, and the active language/type filters shared by the
/// category lists. Item lists themselves are queried lazily, per category,
/// when a category screen appears.
@Observable
@MainActor
final class LibraryViewModel {
    private let contentRepository: any ContentRepositoryProtocol

    /// Item counts per category, filled progressively while the home loads.
    private(set) var categoryCounts: [ContentCategory: Int] = [:]
    private(set) var hasLoadedCounts = false

    /// Favorites keyed by content item ID for O(1) star lookups.
    private(set) var favoritesByContentID: [String: Favorite] = [:]

    /// Active filters applied to category item lists ("en"/"ur"/"ar", nil = all).
    var languageFilter: String?
    var typeFilter: ContentType?

    init(contentRepository: any ContentRepositoryProtocol) {
        self.contentRepository = contentRepository
    }

    // MARK: - Derived state

    var totalItemCount: Int {
        categoryCounts.values.reduce(0, +)
    }

    func count(for category: ContentCategory) -> Int {
        categoryCounts[category] ?? 0
    }

    /// Categories with no items yet, tucked behind the "More categories"
    /// disclosure on the home screen. Featured categories are excluded because
    /// their cards are always visible.
    var hiddenCategories: [ContentCategory] {
        guard hasLoadedCounts else { return [] }
        return LibraryCategoryGroup.groups
            .flatMap { $0.categories }
            .filter { count(for: $0) == 0 && !LibraryCategoryGroup.featuredCategories.contains($0) }
    }

    func isFavorite(_ contentItemID: String) -> Bool {
        favoritesByContentID[contentItemID] != nil
    }

    // MARK: - Loading

    func loadHomeIfNeeded() async {
        guard !hasLoadedCounts else { return }
        await reloadHome()
    }

    func reloadHome() async {
        await loadFavorites()
        for category in ContentCategory.allCases {
            let items = (try? await contentRepository.items(
                category: category,
                type: nil,
                language: nil,
                limit: 5000
            )) ?? []
            categoryCounts[category] = items.count
        }
        hasLoadedCounts = true
    }

    func loadFavorites() async {
        let all = (try? await contentRepository.favorites()) ?? []
        var map: [String: Favorite] = [:]
        for favorite in all {
            if let contentItemID = favorite.contentItemID {
                map[contentItemID] = favorite
            }
        }
        favoritesByContentID = map
    }

    // MARK: - Favorites

    func toggleFavorite(contentItemID: String) async {
        if let existing = favoritesByContentID[contentItemID] {
            favoritesByContentID[contentItemID] = nil
            do {
                try await contentRepository.removeFavorite(id: existing.id)
            } catch {
                await loadFavorites()
            }
        } else {
            let favorite = Favorite(
                id: UUID(),
                contentItemID: contentItemID,
                mediaItemID: nil,
                createdAt: Date()
            )
            favoritesByContentID[contentItemID] = favorite
            do {
                try await contentRepository.addFavorite(favorite)
            } catch {
                await loadFavorites()
            }
        }
    }

    // MARK: - Item queries

    /// Items for one category with the active filters applied, newest first.
    func items(in category: ContentCategory) async -> [ContentItem] {
        let fetched = (try? await contentRepository.items(
            category: category,
            type: typeFilter,
            language: languageFilter,
            limit: 500
        )) ?? []
        return fetched.sorted { lhs, rhs in
            if let left = lhs.publishedAt, let right = rhs.publishedAt, left != right {
                return left > right
            }
            if lhs.publishedAt != nil && rhs.publishedAt == nil { return true }
            if lhs.publishedAt == nil && rhs.publishedAt != nil { return false }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    /// Favorited content items, most recently favorited first.
    func favoriteItems() async -> [ContentItem] {
        await loadFavorites()
        let ordered = favoritesByContentID.values.sorted { $0.createdAt > $1.createdAt }
        var items: [ContentItem] = []
        for favorite in ordered {
            guard let contentItemID = favorite.contentItemID else { continue }
            do {
                if let item = try await contentRepository.item(id: contentItemID) {
                    items.append(item)
                }
            } catch {
                continue
            }
        }
        return items
    }
}
