import Foundation
import XCTest
@testable import DarulIrfan

/// "Copy reference" on a search hit copies what a person is shown: the title
/// and page, speaker, day or venue, never the id the hit is kept under.
final class SearchReferenceTests: XCTestCase {

    private let locale = Locale(identifier: "en_US")

    private func reference(_ result: SearchResult, lecture: MediaItem? = nil, event: CommunityEvent? = nil) -> String {
        SearchReference.text(for: result, lecture: lecture, event: event, locale: locale)
    }

    private func lecture(speaker: String?, date: Date?) -> MediaItem {
        MediaItem(
            id: "lecture-3725-dawat-o-tabligh",
            title: "Dawat o Tabligh",
            language: "ur",
            speaker: speaker,
            date: date,
            durationSeconds: nil,
            mediaType: .audio,
            sourceUrl: "",
            streamUrl: nil,
            downloadUrl: nil,
            youtubeId: nil,
            year: nil,
            month: nil,
            category: .audioLectures,
            transcriptUrl: nil,
            rightsStatus: .linkOnly
        )
    }

    private func programme(start: Date?, end: Date? = nil, approximate: Bool = false, venue: String?) -> CommunityEvent {
        CommunityEvent(
            id: "seminar-3420-2025-09-07",
            kind: .other,
            title: "Conference",
            titleUrdu: nil,
            details: nil,
            startDate: start,
            endDate: end,
            datesAreApproximate: approximate,
            venue: venue,
            sourceUrl: nil,
            updatedAt: nil
        )
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        TestDates.make(year: year, month: month, day: day, hour: 0, timeZone: TestDates.utc)
    }

    // MARK: - Each kind

    func testAnAyahAndANarrationKeepTheirReferences() {
        let ayah = SearchResult(domain: .quran, itemID: "2:255", title: "Surah Al-Baqarah 2:255")
        XCTAssertEqual(reference(ayah), "Surah Al-Baqarah 2:255 — Quran 2:255")
        let narration = SearchResult(domain: .hadith, itemID: "bukhari|402.2|403", title: "Sahih al-Bukhari 402.2")
        XCTAssertEqual(reference(narration), "Sahih al-Bukhari 402.2")
    }

    func testABookPageIsItsTitleAndPage() {
        let work = "Dil Darwaza — Poems"
        let result = SearchResult(
            domain: .library,
            itemID: "bookpage|book-ocr-dil-darwaza|1200",
            title: work + SearchResult.pageSeparator + String(localized: "Page \(1200)")
        )
        XCTAssertEqual(result.workTitle, work, "Only the page is taken off, not a dash in the title")
        XCTAssertEqual(reference(result), String(localized: "\(work), p. \(1200)", locale: locale))
        XCTAssertTrue(reference(result).contains("1200"))
        XCTAssertFalse(reference(result).contains("book-ocr"))
    }

    func testACatalogueItemIsItsTitleAlone() {
        let result = SearchResult(domain: .library, itemID: "book-ocr-zikr-allah", title: "Zikr Allah — An Introduction")
        XCTAssertEqual(reference(result), "Zikr Allah — An Introduction")
    }

    func testALectureIsItsTitleSpeakerAndDay() {
        let result = SearchResult(domain: .media, itemID: "lecture-3725-dawat-o-tabligh", title: "Dawat o Tabligh")
        let speaker = "Hazrat Ameer Abdul Qadeer Awan (MZA)"
        XCTAssertEqual(
            reference(result, lecture: lecture(speaker: speaker, date: day(2026, 1, 2))),
            "Dawat o Tabligh — \(speaker) — Jan 2, 2026"
        )
        XCTAssertEqual(reference(result, lecture: lecture(speaker: "", date: nil)), "Dawat o Tabligh")
        XCTAssertEqual(reference(result), "Dawat o Tabligh")
    }

    func testAnEventIsItsTitleDaysAndVenue() {
        let result = SearchResult(domain: .events, itemID: "seminar-3420-2025-09-07", title: "Conference")
        let venue = "Test Hall"
        XCTAssertEqual(
            reference(result, event: programme(start: day(2025, 9, 7), venue: venue)),
            "Conference — September 7, 2025 — Test Hall"
        )
        XCTAssertEqual(
            reference(result, event: programme(start: day(2025, 9, 7), end: day(2025, 9, 9), venue: nil)),
            "Conference — September 7, 2025 – September 9, 2025"
        )
        // Days still to be announced are not copied, as they are not shown.
        XCTAssertEqual(
            reference(result, event: programme(start: day(2099, 9, 7), approximate: true, venue: venue)),
            "Conference — Test Hall"
        )
        XCTAssertEqual(reference(result), "Conference")
    }

    // MARK: - The search sheet

    /// The sheet's own model finds the speaker, day and venue of what it lists.
    @MainActor
    func testTheSheetCopiesWhatTheCatalogueHolds() async throws {
        let database = try await AppDatabase.inMemory()
        let media = MediaRepository(database: database)
        let events = EventsRepository(database: database)
        let item = lecture(speaker: "Hazrat Ameer Abdul Qadeer Awan (MZA)", date: day(2026, 1, 2))
        let event = programme(start: day(2025, 9, 7), venue: "Test Hall")
        try await media.upsertItems([item])
        try await events.upsertEvents([event])

        let lectureHit = SearchResult(domain: .media, itemID: item.id, title: item.title)
        let eventHit = SearchResult(domain: .events, itemID: event.id, title: event.title)
        let model = SearchViewModel(
            searchIndex: FixedSearchIndex(results: [lectureHit, eventHit]),
            contentRepository: ContentRepository(database: database),
            mediaRepository: media,
            eventsRepository: events
        )
        model.updateQuery("conference")
        model.searchNow()
        for _ in 0..<200 where model.phase == .searching {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.phase, .results)

        let shown = LanguageManager.locale(for: LanguageManager.current)
        let lectureText = model.reference(for: lectureHit)
        XCTAssertEqual(lectureText, SearchReference.text(for: lectureHit, lecture: item, event: nil, locale: shown))
        XCTAssertFalse(lectureText.contains(item.id))
        let eventText = model.reference(for: eventHit)
        XCTAssertEqual(eventText, SearchReference.text(for: eventHit, lecture: nil, event: event, locale: shown))
        XCTAssertFalse(eventText.contains(event.id))
    }
}

/// Answers every search with the same hits.
private struct FixedSearchIndex: SearchIndexServicing {
    let results: [SearchResult]

    func reindex(domains: [SearchDomain]) async throws {}

    func search(_ query: String, domains: [SearchDomain], limit: Int) async throws -> [SearchResult] {
        results
    }
}
