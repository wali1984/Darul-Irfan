import EventKit
import Foundation
import Observation

/// State for one event's detail screen: add-to-calendar via EventKit
/// (write-only access, iOS 17) and a local reminder via the notification
/// scheduler. Both actions are offered only when the event has concrete
/// (non-approximate) dates.
@Observable
@MainActor
final class EventDetailViewModel {
    enum CalendarAddState: Equatable {
        case idle
        case working
        case added
        case failed
    }

    let event: CommunityEvent
    private let notifications: any NotificationScheduling

    private(set) var calendarState: CalendarAddState = .idle
    private(set) var isReminderScheduled: Bool
    var showCalendarDeniedAlert = false
    var showNotificationsDeniedAlert = false

    init(event: CommunityEvent, notifications: any NotificationScheduling) {
        self.event = event
        self.notifications = notifications
        self.isReminderScheduled = UserDefaults.standard.bool(forKey: Self.reminderKey(for: event.id))
    }

    var hasConcreteDates: Bool {
        !event.datesAreApproximate && event.startDate != nil
    }

    /// When the reminder would fire: a day before the event, or an hour
    /// before if the event is closer than that. Nil when the event has
    /// already begun (the reminder action is hidden then).
    var reminderFireDate: Date? {
        guard let start = event.startDate else { return nil }
        let now = Date()
        let dayBefore = start.addingTimeInterval(-24 * 3_600)
        if dayBefore > now { return dayBefore }
        let hourBefore = start.addingTimeInterval(-3_600)
        if hourBefore > now { return hourBefore }
        return nil
    }

    var canOfferReminder: Bool {
        hasConcreteDates && (isReminderScheduled || reminderFireDate != nil)
    }

    func addToCalendar() async {
        guard hasConcreteDates, let start = event.startDate else { return }
        // iOS terminates apps that request calendar access without the usage
        // string in Info.plist; degrade to the denied path instead of crashing
        // if the key is ever missing from a build.
        guard Bundle.main.object(forInfoDictionaryKey: "NSCalendarsWriteOnlyAccessUsageDescription") != nil else {
            showCalendarDeniedAlert = true
            return
        }
        calendarState = .working
        let store = EKEventStore()
        do {
            let granted = try await store.requestWriteOnlyAccessToEvents()
            guard granted else {
                calendarState = .idle
                showCalendarDeniedAlert = true
                return
            }
            let calendarEvent = EKEvent(eventStore: store)
            calendarEvent.title = event.title
            calendarEvent.startDate = start
            calendarEvent.endDate = event.endDate ?? start.addingTimeInterval(2 * 3_600)
            calendarEvent.notes = event.details
            calendarEvent.location = event.venue
            calendarEvent.calendar = store.defaultCalendarForNewEvents
            try store.save(calendarEvent, span: .thisEvent)
            calendarState = .added
        } catch {
            calendarState = .failed
        }
    }

    func toggleReminder() async {
        let key = Self.reminderKey(for: event.id)
        if isReminderScheduled {
            await notifications.cancelReminder(id: key)
            isReminderScheduled = false
            UserDefaults.standard.set(false, forKey: key)
        } else {
            guard let fireDate = reminderFireDate else { return }
            let granted = await notifications.requestPermission()
            guard granted else {
                showNotificationsDeniedAlert = true
                return
            }
            let body: String
            if let venue = event.venue {
                body = String(localized: "Upcoming program at \(venue).")
            } else {
                body = String(localized: "An upcoming Dar-ul-Irfan program.")
            }
            await notifications.scheduleReminder(
                id: key,
                title: event.title,
                body: body,
                at: fireDate
            )
            isReminderScheduled = true
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    private static func reminderKey(for eventID: String) -> String {
        "eventReminder.\(eventID)"
    }
}
