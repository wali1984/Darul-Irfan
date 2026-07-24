import ActivityKit
import SwiftUI
import WidgetKit

struct PrayerActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "moon.stars.fill").foregroundStyle(WidgetPalette.gold)
                VStack(alignment: .leading) {
                    Text(context.state.prayerName).font(.headline)
                    Text(context.state.prayerTime, style: .timer).font(.title3.monospacedDigit())
                }
                Spacer()
                Text(context.attributes.placeName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding()
            .activityBackgroundTint(WidgetPalette.cream)
            .activitySystemActionForegroundColor(WidgetPalette.emerald)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.prayerName, systemImage: "moon.stars.fill")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.prayerTime, style: .timer).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let following = context.state.followingPrayerName, let time = context.state.followingPrayerTime {
                        Text("Then \(following) at \(time.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                    }
                }
            } compactLeading: {
                Image(systemName: "moon.stars.fill")
            } compactTrailing: {
                Text(context.state.prayerTime, style: .timer).monospacedDigit()
            } minimal: {
                Image(systemName: "moon.stars.fill")
            }
            .keylineTint(WidgetPalette.gold)
        }
    }
}
