import Foundation
import Observation

// MARK: - Display metadata for search domains

extension SearchDomain {
    /// Natural-English display name. Wrap in `LocalizedStringKey` at the call
    /// site so the String Catalog can translate it at runtime (CONTRACTS.md).
    var displayTitle: String {
        switch self {
        case .quran: return "Quran"
        case .library: return "Library"
        case .media: return "Media"
        case .events: return "Events"
        }
    }

    /// SF Symbol used for this domain in filter chips, section headers, rows.
    var iconName: String {
        switch self {
        case .quran: return "book.closed"
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

/// Drives the global search sheet: debounced querying, domain filtering,
/// grouping, and source-URL resolution for informational result rows.
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
    private let contentRepository: any ContentRepositoryProtocol
    private let mediaRepository: any MediaRepositoryProtocol
    private let eventsRepository: any EventsRepositoryProtocol

    // MARK: Observable state

    private(set) var query: String = ""
    /// nil means "All" domains.
    private(set) var selectedDomain: SearchDomain?
    private(set) var phase: Phase = .idle
    private(set) var groups: [SearchResultGroup] = []
    /// Website source URLs resolved for the current results, keyed by
    /// `SearchResult.id`. Quran results never have one.
    private(set) var sourceURLs: [String: URL] = [:]

    // MARK: Private state

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// Events/announcements are small lists without a by-ID fetch, so their
    /// source URLs are loaded once and cached for the sheet's lifetime.
    @ObservationIgnored private var eventSourceURLCache: [String: String]?

    private static let debounceNanoseconds: UInt64 = 300_000_000
    private static let resultLimit = 60

    init(
        searchIndex: any SearchIndexServicing,
        contentRepository: any ContentRepositoryProtocol,
        mediaRepository: any MediaRepositoryProtocol,
        eventsRepository: any EventsRepositoryProtocol
    ) {
        self.searchIndex = searchIndex
        self.contentRepository = contentRepository
        self.mediaRepository = mediaRepository
        self.eventsRepository = eventsRepository
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

    /// Called on every keystroke; schedules a debounced search.
    /// Urdu/Arabic text passes through unchanged — the FTS tokenizer handles
    /// diacritics, so no normalization happens here.
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

    func sourceURL(for result: SearchResult) -> URL? {
        sourceURLs[result.id]
    }

    /// Plain-text reference for the "Copy reference" context action:
    /// the title plus a locator (ayah reference or source URL when known).
    func reference(for result: SearchResult) -> String {
        var parts: [String] = [result.title]
        switch result.domain {
        case .quran:
            parts.append("Quran \(result.itemID)")
        case .library, .media, .events:
            if let url = sourceURLs[result.id] {
                parts.append(url.absoluteString)
            }
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
            sourceURLs = [:]
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

            let resolvedURLs = await resolveSourceURLs(for: results)
            if Task.isCancelled { return }

            groups = Self.grouped(results)
            sourceURLs = resolvedURLs
            phase = groups.isEmpty ? .empty : .results
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            groups = []
            sourceURLs = [:]
            phase = .failed
        }
    }

    /// Buckets results by domain in the fixed Quran/Library/Media/Events
    /// order, deduplicating IDs defensively so `ForEach` stays stable.
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

    // MARK: Source URL resolution

    /// Looks up website source URLs for library/media/events hits so rows can
    /// offer a link back to naqshbandiaowaisiah.org. Lookups are keyed reads
    /// through the database actor; failures simply leave the link out.
    private func resolveSourceURLs(for results: [SearchResult]) async -> [String: URL] {
        var urls: [String: URL] = [:]
        for result in results {
            if Task.isCancelled { return urls }
            switch result.domain {
            case .quran:
                continue
            case .library:
                if let item = try? await contentRepository.item(id: result.itemID),
                   let url = Self.webURL(from: item.sourceUrl) {
                    urls[result.id] = url
                }
            case .media:
                if let item = try? await mediaRepository.item(id: result.itemID),
                   let url = Self.webURL(from: item.sourceUrl) {
                    urls[result.id] = url
                }
            case .events:
                let map = await eventSourceURLMap()
                if let raw = map[result.itemID],
                   let url = Self.webURL(from: raw) {
                    urls[result.id] = url
                }
            }
        }
        return urls
    }

    private func eventSourceURLMap() async -> [String: String] {
        if let cached = eventSourceURLCache {
            return cached
        }
        var map: [String: String] = [:]
        if let events = try? await eventsRepository.events() {
            for event in events {
                if let url = event.sourceUrl {
                    map[event.id] = url
                }
            }
        }
        if let announcements = try? await eventsRepository.announcements(limit: 200) {
            for announcement in announcements {
                if let url = announcement.sourceUrl {
                    map[announcement.id] = url
                }
            }
        }
        eventSourceURLCache = map
        return map
    }

    /// Only http(s) URLs are surfaced as tappable links.
    private static func webURL(from raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw) else { return nil }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}
