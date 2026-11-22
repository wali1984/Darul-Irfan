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

// MARK: - Copy reference

/// The text "Copy reference" puts on the pasteboard: what a person is shown
/// of the hit, never the id it is kept under.
enum SearchReference {
    /// - Parameters:
    ///   - lecture: The catalogue entry of a media hit, for its speaker and day.
    ///   - event: The programme of an events hit, for its days and venue.
    ///   - locale: Writes the days.
    static func text(for result: SearchResult, lecture: MediaItem?, event: CommunityEvent?, locale: Locale) -> String {
        var parts: [String] = [result.title]
        switch result.domain {
        case .quran:
            if let reference = result.ayahReference {
                parts.append("\(String(localized: "Quran", locale: locale)) \(reference.surah):\(reference.ayah)")
            }
        case .hadith:
            // The title is the reference: the collection and the number.
            break
        case .library:
            // A work's title is its reference; a page of its text adds the page.
            if let page = result.bookPage {
                // As text: a number would be grouped ("1,200"), and a page is not.
                parts = [String(localized: "\(result.workTitle), p. \(String(page.page))", locale: locale)]
            }
        case .media:
            if let speaker = lecture?.speaker, !speaker.isEmpty {
                parts.append(speaker)
            }
            if let date = lecture?.date {
                // Read in UTC, as the lecture's row shows it.
                parts.append(date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: .gmt)))
            }
        case .events:
            if let event {
                if let dates = datesText(of: event, locale: locale) {
                    parts.append(dates)
                }
                if let venue = event.venue, !venue.isEmpty {
                    parts.append(String(localized: String.LocalizationValue(venue), locale: locale))
                }
            }
        }
        return parts.joined(separator: " — ")
    }

    /// The days the programme's own screen shows: none while they are only
    /// approximate, unless it has taken place.
    private static func datesText(of event: CommunityEvent, locale: Locale) -> String? {
        guard let start = event.startDate, !event.datesAreApproximate || event.hasEnded() else { return nil }
        let first = CommunityEvent.dayText(start, .long, locale: locale)
        guard let end = event.endDate, end > start else { return first }
        return "\(first) – \(CommunityEvent.dayText(end, .long, locale: locale))"
    }
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
    private let mediaRepository: any MediaRepositoryProtocol
    private let eventsRepository: any EventsRepositoryProtocol

    // MARK: Observable state

    private(set) var query: String = ""
    /// nil means "All" domains.
    private(set) var selectedDomain: SearchDomain?
    private(set) var phase: Phase = .idle
    private(set) var groups: [SearchResultGroup] = []
    /// What "Copy reference" adds to the lectures and programmes found, by id.
    private var lectures: [String: MediaItem] = [:]
    private var programmes: [String: CommunityEvent] = [:]

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
        self.mediaRepository = mediaRepository
        self.eventsRepository = eventsRepository
        // Preserve the dependency-injection contract while result navigation
        // is resolved by the presenting view instead of external URLs.
        _ = contentRepository
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
    /// the title plus what names the hit to a reader (`SearchReference`).
    func reference(for result: SearchResult) -> String {
        SearchReference.text(
            for: result,
            lecture: lectures[result.itemID],
            event: programmes[result.itemID],
            locale: LanguageManager.locale(for: LanguageManager.current)
        )
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
            let foundLectures = await loadLectures(among: results)
            let foundProgrammes = await loadProgrammes(among: results)
            if Task.isCancelled { return }

            lectures = foundLectures
            programmes = foundProgrammes
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

    /// The catalogue entries of the media hits. One that cannot be read
    /// leaves its reference as the title alone.
    private func loadLectures(among results: [SearchResult]) async -> [String: MediaItem] {
        var found: [String: MediaItem] = [:]
        for result in results where result.domain == .media {
            if let item = try? await mediaRepository.item(id: result.itemID) {
                found[result.itemID] = item
            }
        }
        return found
    }

    /// The programmes of the events hits, likewise.
    private func loadProgrammes(among results: [SearchResult]) async -> [String: CommunityEvent] {
        guard results.contains(where: { $0.domain == .events }),
              let events = try? await eventsRepository.events() else { return [:] }
        return Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
