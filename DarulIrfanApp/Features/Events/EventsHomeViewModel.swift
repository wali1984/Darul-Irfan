import Foundation
import Observation

/// State for the Events & Dar-ul-Irfan screen: community events and
/// announcements from the events repository, plus the bundled Dar-ul-Irfan
/// place information.
@Observable
@MainActor
final class EventsHomeViewModel {
    private let eventsRepository: any EventsRepositoryProtocol
    private let contentRepository: (any ContentRepositoryProtocol)?

    /// Dated programs still to come, soonest first.
    private(set) var upcoming: [CommunityEvent] = []
    /// The standing programs, announced without dates (Monthly Ijtema,
    /// Salana Ijtema, Ramadan Aitekaaf), in the catalogue's order.
    private(set) var regular: [CommunityEvent] = []
    /// Programs that have taken place, newest first.
    private(set) var past: [CommunityEvent] = []
    private(set) var announcements: [Announcement] = []
    /// Announcements that are library items, which open in full.
    private(set) var libraryAnnouncementIDs: Set<String> = []
    private(set) var place: DarulIrfanPlace?
    private(set) var isLoaded = false

    init(eventsRepository: any EventsRepositoryProtocol, contentRepository: (any ContentRepositoryProtocol)? = nil) {
        self.eventsRepository = eventsRepository
        self.contentRepository = contentRepository
    }

    func load() async {
        let fetchedEvents: [CommunityEvent]
        do {
            fetchedEvents = try await eventsRepository.events()
        } catch {
            fetchedEvents = []
        }

        // A program is upcoming until a day after its last day, whether or
        // not its dates are firm. Every seminar in the catalogue was marked
        // approximate, which used to keep them all as "upcoming", the oldest
        // (2020) first and without dates; past programs are now shown as
        // past, with their dates.
        let now = Date()
        upcoming = fetchedEvents
            .filter { $0.startDate != nil && !$0.hasEnded(at: now) }
            .sorted { lhs, rhs in
                let lhsDate = lhs.startDate ?? Date.distantFuture
                let rhsDate = rhs.startDate ?? Date.distantFuture
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return lhs.title < rhs.title
            }
        regular = fetchedEvents.filter { $0.startDate == nil }
        past = fetchedEvents
            .filter { $0.hasEnded(at: now) }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }

        let fetchedAnnouncements: [Announcement]
        do {
            fetchedAnnouncements = try await eventsRepository.announcements(limit: 20)
        } catch {
            fetchedAnnouncements = []
        }
        // The site's announcements are library items (16 of them); the
        // announcements file holds only the app's own welcome note.
        let library = (try? await contentRepository?.items(category: nil, type: .announcement, language: nil, limit: 50)) ?? []
        libraryAnnouncementIDs = Set(library.map(\.id))
        let fromLibrary = library.map { item in
            Announcement(
                id: item.id,
                title: item.title,
                body: item.excerpt ?? item.bodyPlainText.map { String($0.prefix(280)) },
                publishedAt: item.publishedAt ?? item.updatedAt,
                sourceUrl: item.sourceUrl
            )
        }
        var seen = Set<String>()
        announcements = (fetchedAnnouncements + fromLibrary)
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.publishedAt ?? Date.distantPast) > ($1.publishedAt ?? Date.distantPast) }

        place = SeedBundle.darulIrfanPlace()
        isLoaded = true
    }

    /// Every program on the screen, for a link that names one.
    var allEvents: [CommunityEvent] { upcoming + regular + past }
}

extension CommunityEvent {
    /// Event dates are calendar days, stored as midnight UTC
    /// ("2025-11-09T00:00:00Z"). They are read and shown as that day, not
    /// moved into the phone's time zone, where they fell a day early across
    /// the Americas.
    static let dayTimeZone = TimeZone(identifier: "UTC") ?? .current

    /// A program day as text, in the given date style.
    static func dayText(_ date: Date, _ style: Date.FormatStyle.DateStyle) -> String {
        date.formatted(Date.FormatStyle(date: style, time: .omitted, timeZone: dayTimeZone))
    }

    /// Over: its last (or only) day is before the person's today, and a
    /// whole day has passed since that day began, so a program is never past
    /// while its day lasts, in the phone's zone or in UTC. A program with no
    /// date is a standing one and never over.
    func hasEnded(at now: Date = Date()) -> Bool {
        guard let last = endDate ?? startDate else { return false }
        let beforeToday = DayKey.make(from: last, timeZone: Self.dayTimeZone) < DayKey.make(from: now)
        return beforeToday && last.addingTimeInterval(86_400) < now
    }
}
