import ActivityKit
import Foundation

@MainActor
final class PrayerLiveActivityCoordinator {
    func update(upcoming: [WidgetPrayerTime], placeName: String, enabled: Bool) async {
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled,
              let next = upcoming.first(where: { $0.isObligatory && $0.time > Date() }) else {
            await endAll()
            return
        }
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
        if let activity = Activity<PrayerActivityAttributes>.activities.first {
            await activity.update(content)
        } else {
            _ = try? Activity.request(
                attributes: PrayerActivityAttributes(placeName: placeName),
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
