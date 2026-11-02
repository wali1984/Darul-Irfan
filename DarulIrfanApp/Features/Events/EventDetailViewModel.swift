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
    private let now: () -> Date
    private var reminderRevision = 0
    private(set) var scheduledReminderDate: Date?

    private(set) var calendarState: CalendarAddState = .idle
    private(set) var isReminderScheduled: Bool
    var showCalendarDeniedAlert = false
    var showNotificationsDeniedAlert = false
    private(set) var reminderWorking = false
    private(set) var reminderFailed = false

    init(event: CommunityEvent, notifications: any NotificationScheduling, now: @escaping () -> Date = Date.init) {
        self.event = event
        self.notifications = notifications
        self.now = now
        self.isReminderScheduled = UserDefaults.standard.bool(forKey: Self.reminderKey(for: event.id))
    }

    var hasConcreteDates: Bool {
        !event.datesAreApproximate && event.startDate != nil
    }

    /// The program has taken place: its date is shown, with nothing to add
    /// to a calendar or be reminded of.
    var hasEnded: Bool { event.hasEnded() }

    /// When the reminder would fire: a day before the event, or an hour
    /// before if the event is closer than that. Nil when the event has
    /// already begun (the reminder action is hidden then).
    var reminderFireDate: Date? {
        guard let start = event.startDate else { return nil }
        let now = now()
        let dayBefore = start.addingTimeInterval(-24 * 3_600)
        if dayBefore > now { return dayBefore }
        let hourBefore = start.addingTimeInterval(-3_600)
        if hourBefore > now { return hourBefore }
        return nil
    }

    var canOfferReminder: Bool {
        hasConcreteDates && (isReminderScheduled || reminderFireDate != nil)
    }

    /// Resolve saved flags against real pending requests; never invent a new fire date.
    func refreshReminderStatus() async {
        guard !reminderWorking else { return }
        let revision = reminderRevision
        let pending = await notifications.pendingReminderDate(id: Self.reminderKey(for: event.id))
        guard !reminderWorking, revision == reminderRevision else { return }
        scheduledReminderDate = pending.flatMap { $0 > now() ? $0 : nil }
        isReminderScheduled = scheduledReminderDate != nil
        UserDefaults.standard.set(isReminderScheduled, forKey: Self.reminderKey(for: event.id))
    }

    func addToCalendar() async {
        guard hasConcreteDates, calendarState != .working, calendarState != .added, let start = event.startDate else { return }
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
        guard !reminderWorking else { return }
        reminderRevision += 1
        reminderWorking = true
        reminderFailed = false
        defer { reminderWorking = false }
        let key = Self.reminderKey(for: event.id)
        if isReminderScheduled {
            await notifications.cancelReminder(id: key)
            scheduledReminderDate = nil
            isReminderScheduled = false
            UserDefaults.standard.set(false, forKey: key)
        } else {
            guard reminderFireDate != nil else { return }
            let granted = await notifications.requestPermission()
            guard granted else {
                showNotificationsDeniedAlert = true
                return
            }
            // The permission prompt can remain open across a reminder cutoff.
            // Match Android's callback: calculate from the current clock only
            // after permission returns, never submit a stale trigger.
            guard let fireDate = reminderFireDate else {
                reminderFailed = true
                return
            }
            let body: String
            if let venue = event.venue {
                body = String(localized: "Upcoming program at \(venue).")
            } else {
                body = String(localized: "An upcoming Dar-ul-Irfan program.")
            }
            let accepted = await notifications.scheduleReminder(
                id: key,
                title: event.title,
                body: body,
                at: fireDate
            )
            guard accepted else {
                reminderFailed = true
                return
            }
            let pending = await notifications.pendingReminderDate(id: key)
            scheduledReminderDate = pending.flatMap { $0 > now() ? $0 : nil }
            isReminderScheduled = scheduledReminderDate != nil
            reminderFailed = !isReminderScheduled
            UserDefaults.standard.set(isReminderScheduled, forKey: key)
        }
    }

    private static func reminderKey(for eventID: String) -> String {
        "eventReminder.\(eventID)"
    }
}
