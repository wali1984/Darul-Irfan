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
}
