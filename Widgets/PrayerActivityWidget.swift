import ActivityKit
import SwiftUI
import WidgetKit

struct PrayerActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerActivityAttributes.self) { context in
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(WidgetPalette.emerald.opacity(0.10))
                    Circle().stroke(WidgetPalette.gold.opacity(0.55), lineWidth: 1)
                    Image("BrandEmblem")
                        .resizable()
                        .scaledToFit()
                        .padding(3)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    if context.isStale {
                        Text("Prayer time reached")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Next Prayer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(context.state.prayerName)
                        .font(.headline)
                        .foregroundStyle(WidgetPalette.emerald)
                    if context.isStale {
                        Text("Open Darul Irfan to continue")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WidgetPalette.gold)
                    } else {
                        PrayerActivityCountdown(target: context.state.prayerTime)
                            .font(.title3.weight(.semibold).monospacedDigit())
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(context.state.prayerTime, style: .time)
                        .font(.headline.monospacedDigit())
                    Text(context.attributes.placeName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding()
            .activityBackgroundTint(WidgetPalette.cream)
            .activitySystemActionForegroundColor(WidgetPalette.emerald)
            .widgetURL(URL(string: "darulirfan://today"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.prayerName, systemImage: "moon.stars.fill")
                        .foregroundStyle(WidgetPalette.gold)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.isStale {
                        Image(systemName: "arrow.clockwise")
                    } else {
                        PrayerActivityCountdown(target: context.state.prayerTime)
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if context.isStale {
                            Text("Open Darul Irfan to continue")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(context.attributes.placeName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let following = context.state.followingPrayerName,
                           let time = context.state.followingPrayerTime {
                            Text("Then \(following) at \(time.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "moon.stars.fill")
            } compactTrailing: {
                if context.isStale {
                    Image(systemName: "arrow.clockwise")
                } else {
                    PrayerActivityCountdown(target: context.state.prayerTime)
                        .monospacedDigit()
                }
            } minimal: {
                Image(systemName: "moon.stars.fill")
            }
            .widgetURL(URL(string: "darulirfan://today"))
            .keylineTint(WidgetPalette.gold)
        }
    }
}

private struct PrayerActivityCountdown: View {
    let target: Date

    var body: some View {
        // Clamp at zero after the boundary. A Date-style timer would begin
        // counting upward if iOS cannot refresh the Live Activity immediately.
        Text(timerInterval: min(Date(), target)...target, countsDown: true)
    }
}
