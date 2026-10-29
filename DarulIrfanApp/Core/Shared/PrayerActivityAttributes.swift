import ActivityKit
import Foundation

struct PrayerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var prayerName: String
        var prayerTime: Date
        var followingPrayerName: String?
        var followingPrayerTime: Date?
    }

    var placeName: String
    /// Time zone of the place, so the activity shows times on that place's
    /// clock as the app does. Nil for activities started by earlier builds.
    var timeZoneIdentifier: String? = nil

    /// The place's time zone (the phone's when none was recorded).
    var timeZone: TimeZone {
        timeZoneIdentifier.flatMap { TimeZone(identifier: $0) } ?? .current
    }
}
