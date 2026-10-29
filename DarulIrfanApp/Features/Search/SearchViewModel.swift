import Foundation
import Observation

// MARK: - Display metadata for search domains

extension SearchDomain {
    /// Natural-English display name. Wrap in `LocalizedStringKey` at the call
    /// site so the String Catalog can translate it at runtime (CONTRACTS.md).
    var displayTitle: String {
        switch self {
        case .quran: return "Quran"
        case .hadith: return "Hadith"
        case .library: return "Library"
        case .media: return "Media"
        case .events: return "Events"
        }
    }

    /// SF Symbol used for this domain in filter chips, section headers, rows.
    var iconName: String {
        switch self {
        case .quran: return "book.closed"
        case .hadith: return "text.book.closed"
        case .library: return "books.vertical"
        case .media: return "play.circle"
        case .events: return "calendar"
        }
    }
}

// MARK: - Result grouping

/// Search results for one domain, kept in the service's relevance order.
struct SearchResultGroup: Identifiable, Equatable {
    let domain: SearchDomain
    let results: [SearchResult]

    var id: String { domain.rawValue }
}

// MARK: - View model

/// Drives the global search sheet: debounced querying, domain filtering, and
/// grouping for native informational result rows.
@Observable @MainActor
final class SearchViewModel {
    /// What the results area should currently show.
    enum Phase: Equatable {
        /// No query entered yet.
        case idle
        /// Waiting out the debounce or a query is in flight.
        case searching
        /// A completed search produced hits (`groups` is non-empty).
        case results
        /// A completed search produced no hits.
        case empty
        /// The search index threw an error.
        case failed
    }

    // MARK: Dependencies

    // `let` constants are never observation-tracked, so no annotation needed.
    private let searchIndex: any SearchIndexServicing

    // MARK: Observable state

    private(set) var query: String = ""
    /// nil means "All" domains.
    private(set) var selectedDomain: SearchDomain?
    private(set) var phase: Phase = .idle
    private(set) var groups: [SearchResultGroup] = []

    // MARK: Private state

    @ObservationIgnored private var searchTask: Task<Void, Never>?

    private static let debounceNanoseconds: UInt64 = 300_000_000
    /// Results per section. Each section has its own limit, so under "All" a
    /// common word's Qur'an hits cannot crowd out the books and lectures.
    private static let resultLimit = 25

    init(
        searchIndex: any SearchIndexServicing,
        contentRepository: any ContentRepositoryProtocol,
        mediaRepository: any MediaRepositoryProtocol,
        eventsRepository: any EventsRepositoryProtocol
    ) {
        self.searchIndex = searchIndex
        // Preserve the dependency-injection contract while result navigation
        // is resolved by the presenting view instead of external URLs.
        _ = contentRepository
        _ = mediaRepository
        _ = eventsRepository
    }

    // MARK: Derived

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasResults: Bool { !groups.isEmpty }

    private var activeDomains: [SearchDomain] {
        if let selectedDomain {
            return [selectedDomain]
        }
        return SearchDomain.allCases
    }

    // MARK: Intents

    /// Called on every keystroke; schedules a debounced search. The search
    /// index folds the query itself (Arabic harakat dropped, Arabic and Urdu
    /// letter forms matched - `SearchNormalizer`), so it is passed on as
    /// typed.
    func updateQuery(_ newValue: String) {
        guard newValue != query else { return }
        query = newValue
        performSearch(afterNanoseconds: Self.debounceNanoseconds)
    }

    /// Called when the user taps the keyboard's Search key.
    func searchNow() {
        performSearch(afterNanoseconds: 0)
    }

    /// Selects a domain filter chip (nil = All) and re-runs immediately.
    func selectDomain(_ domain: SearchDomain?) {
        guard domain != selectedDomain else { return }
        selectedDomain = domain
        performSearch(afterNanoseconds: 0)
    }

    /// Clears the query and returns to the idle state.
    func clearQuery() {
        query = ""
        performSearch(afterNanoseconds: 0)
    }

    // MARK: Row helpers

    /// Plain-text reference for the "Copy reference" context action:
    /// the title plus a locator (ayah reference or source URL when known).
    func reference(for result: SearchResult) -> String {
        var parts: [String] = [result.title]
        switch result.domain {
        case .quran:
            if let reference = result.ayahReference {
                parts.append("Quran \(reference.surah):\(reference.ayah)")
            }
        case .hadith:
            // The title is the reference: the collection and the number.
            break
        case .library:
            if let page = result.bookPage {
                parts.append("\(page.bookID), p. \(page.page)")
            } else {
                parts.append(result.itemID)
            }
        case .media, .events:
            parts.append(result.itemID)
        }
        return parts.joined(separator: " — ")
    }

    // MARK: Search pipeline

    private func performSearch(afterNanoseconds delay: UInt64) {
        searchTask?.cancel()
        searchTask = nil

        let queryText = trimmedQuery
        guard !queryText.isEmpty else {
            groups = []
            phase = .idle
            return
        }

        phase = .searching
        let domains = activeDomains
        searchTask = Task { [weak self] in
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return // cancelled while debouncing
                }
            }
            guard let self, !Task.isCancelled else { return }
            await self.executeSearch(queryText: queryText, domains: domains)
        }
    }

    private func executeSearch(queryText: String, domains: [SearchDomain]) async {
        do {
            let results = try await searchIndex.search(
                queryText,
                domains: domains,
                limit: Self.resultLimit
            )
            if Task.isCancelled { return }

            groups = Self.grouped(results)
            phase = groups.isEmpty ? .empty : .results
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            groups = []
            phase = .failed
        }
    }

    /// Buckets results by domain in the fixed Quran/Hadith/Library/Media/
    /// Events order, deduplicating IDs defensively so `ForEach` stays stable.
    private static func grouped(_ results: [SearchResult]) -> [SearchResultGroup] {
        var seenIDs = Set<String>()
        var buckets: [SearchDomain: [SearchResult]] = [:]
        for result in results {
            guard seenIDs.insert(result.id).inserted else { continue }
            buckets[result.domain, default: []].append(result)
        }
        return SearchDomain.allCases.compactMap { domain in
            guard let hits = buckets[domain], !hits.isEmpty else { return nil }
            return SearchResultGroup(domain: domain, results: hits)
        }
    }

}
