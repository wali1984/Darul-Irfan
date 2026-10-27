import SwiftUI

/// A focus session for study, reading or work, which knows the prayer
/// times: before starting it says whether the next prayer falls inside the
/// session, and offers to end the session at the prayer instead.
@MainActor
struct FocusTimerView: View {
    let dependencies: AppDependencies
    let appState: AppState

    @State private var minutes = 25
    @State private var endsAt: Date?
    @State private var pausedRemaining: TimeInterval?
    @State private var stopsAtPrayer = true

    private static let choices = [10, 15, 25, 45, 60, 90]
    private static let reminderID = "focus-session"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                DICard {
                    VStack(spacing: DISpacing.md) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(timeText(at: context.date))
                                .font(.system(size: 56, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(DIColor.textPrimary)
                                .frame(maxWidth: .infinity)
                                .onChange(of: remaining(at: context.date) <= 0) { _, finished in
                                    if finished, endsAt != nil { finish() }
                                }
                        }
                        controls
                    }
                }

                if endsAt == nil && pausedRemaining == nil {
                    DICard {
                        VStack(alignment: .leading, spacing: DISpacing.sm) {
                            DISectionHeader(titleKey: "Length", systemImage: "hourglass")
                            Picker("Minutes", selection: $minutes) {
                                ForEach(Self.choices, id: \.self) { value in
                                    Text("\(value) min").tag(value)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }

                prayerNotice
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .diPageHeading("Focus timer")
    }

    // MARK: Prayer awareness

    private var nextPrayer: NextPrayerInfo? {
        guard let place = appState.activePlace else { return nil }
        return dependencies.prayerCalculation.nextPrayer(
            after: Date(), at: place, preferences: appState.settings.calculation
        )
    }

    /// The prayer that falls inside a session of the chosen length, if any.
    private var prayerInsideSession: NextPrayerInfo? {
        guard let next = nextPrayer, next.prayer != .sunrise else { return nil }
        let end = endsAt ?? Date().addingTimeInterval(TimeInterval(minutes * 60))
        return next.time < end ? next : nil
    }

    @ViewBuilder
    private var prayerNotice: some View {
        if let next = nextPrayer {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    let name = String(localized: String.LocalizationValue(next.prayer.englishName))
                    Label {
                        Text("\(name) at \(next.time.formatted(date: .omitted, time: .shortened))")
                    } icon: {
                        Image(systemName: "bell")
                    }
                    .font(.subheadline.weight(.semibold))
                    if prayerInsideSession != nil {
                        Text("\(name) falls inside this session.")
                            .font(.subheadline)
                            .foregroundStyle(DIColor.accent)
                        Toggle("End the session at \(name)", isOn: $stopsAtPrayer)
                            .disabled(endsAt != nil)
                    } else {
                        Text("The session ends before the next prayer.")
                            .font(.subheadline)
                            .foregroundStyle(DIColor.textMuted)
                    }
                }
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: DISpacing.md) {
            if endsAt != nil {
                Button("Pause") { pause() }
                    .buttonStyle(.bordered)
            } else {
                Button(pausedRemaining == nil ? "Start" : "Resume") { start() }
                    .buttonStyle(.borderedProminent)
            }
            if endsAt != nil || pausedRemaining != nil {
                Button("Reset", role: .destructive) { reset() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func remaining(at date: Date) -> TimeInterval {
        if let endsAt { return max(0, endsAt.timeIntervalSince(date)) }
        return pausedRemaining ?? TimeInterval(minutes * 60)
    }

    private func timeText(at date: Date) -> String {
        let total = Int(remaining(at: date).rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func start() {
        DIHaptics.light()
        var end = Date().addingTimeInterval(pausedRemaining ?? TimeInterval(minutes * 60))
        if stopsAtPrayer, let prayer = prayerInsideSession, prayer.time < end {
            end = prayer.time
        }
        endsAt = end
        pausedRemaining = nil
        // A notification marks the end even if the phone is locked or the
        // app is closed.
        let notifications = dependencies.notifications
        Task {
            await notifications.scheduleReminder(
                id: Self.reminderID,
                title: String(localized: "Focus session complete"),
                body: String(localized: "Your focus session has ended."),
                at: end
            )
        }
    }

    private func pause() {
        guard let endsAt else { return }
        pausedRemaining = max(0, endsAt.timeIntervalSinceNow)
        self.endsAt = nil
        cancelReminder()
    }

    private func reset() {
        endsAt = nil
        pausedRemaining = nil
        cancelReminder()
    }

    private func finish() {
        endsAt = nil
        pausedRemaining = nil
        DIHaptics.success()
    }

    private func cancelReminder() {
        let notifications = dependencies.notifications
        Task { await notifications.cancelReminder(id: Self.reminderID) }
    }
}
