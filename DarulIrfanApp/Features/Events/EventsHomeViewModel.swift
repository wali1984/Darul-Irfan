import Foundation
import Observation

/// State for the Events & Dar-ul-Irfan screen: community events and
/// announcements from the events repository, plus the bundled Dar-ul-Irfan
/// place information.
@Observable
@MainActor
final class EventsHomeViewModel {
    private let eventsRepository: any EventsRepositoryProtocol

    private(set) var events: [CommunityEvent] = []
    private(set) var announcements: [Announcement] = []
    private(set) var place: DarulIrfanPlace?
    private(set) var isLoaded = false

    init(eventsRepository: any EventsRepositoryProtocol) {
        self.eventsRepository = eventsRepository
    }

    func load() async {
        let fetchedEvents: [CommunityEvent]
        do {
            fetchedEvents = try await eventsRepository.events()
        } catch {
            fetchedEvents = []
        }

        // Keep events with approximate/unknown dates visible; hide events
        // whose concrete dates ended more than a day ago.
        let cutoff = Date().addingTimeInterval(-86_400)
        events = fetchedEvents
            .filter { event in
                guard !event.datesAreApproximate,
                      let effectiveEnd = event.endDate ?? event.startDate else { return true }
                return effectiveEnd >= cutoff
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.startDate ?? Date.distantFuture
                let rhsDate = rhs.startDate ?? Date.distantFuture
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return lhs.title < rhs.title
            }

        let fetchedAnnouncements: [Announcement]
        do {
            fetchedAnnouncements = try await eventsRepository.announcements(limit: 20)
        } catch {
            fetchedAnnouncements = []
        }
        announcements = fetchedAnnouncements.sorted {
            ($0.publishedAt ?? Date.distantPast) > ($1.publishedAt ?? Date.distantPast)
        }

        place = SeedBundle.darulIrfanPlace()
        isLoaded = true
    }
}
