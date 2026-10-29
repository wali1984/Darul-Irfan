import ActivityKit
import Foundation

@MainActor
final class PrayerLiveActivityCoordinator {
    func update(upcoming: [WidgetPrayerTime], placeName: String, timeZoneIdentifier: String, enabled: Bool) async {
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled,
              let next = upcoming.first(where: { $0.isObligatory && $0.time > Date() }) else {
            await endAll()
            return
        }
        let attributes = PrayerActivityAttributes(placeName: placeName, timeZoneIdentifier: timeZoneIdentifier)
        let following = upcoming.first(where: { $0.isObligatory && $0.time > next.time })
        let state = PrayerActivityAttributes.ContentState(
            prayerName: next.displayName,
            prayerTime: next.time,
            followingPrayerName: following?.displayName,
            followingPrayerTime: following?.time
        )
        // iOS cannot schedule a local state mutation at the prayer boundary.
        // Mark the activity stale exactly then so its UI stops presenting the
        // old prayer as upcoming until the app or a future APNs update runs.
        let content = ActivityContent(state: state, staleDate: next.time)
        // An activity's attributes are fixed when it starts, so after a move
        // to another place it would keep the old place's name and clock: end
        // it and start one for the new place.
        if let activity = Activity<PrayerActivityAttributes>.activities.first,
           activity.attributes.placeName == attributes.placeName,
           activity.attributes.timeZoneIdentifier == attributes.timeZoneIdentifier {
            await activity.update(content)
        } else {
            await endAll()
            _ = try? Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        }
    }

    func endAll() async {
        let final = PrayerActivityAttributes.ContentState(
            prayerName: "Open Darul Irfan",
            prayerTime: Date(),
            followingPrayerName: nil,
            followingPrayerTime: nil
        )
        for activity in Activity<PrayerActivityAttributes>.activities {
            await activity.end(ActivityContent(state: final, staleDate: Date()), dismissalPolicy: .immediate)
        }
    }
}
