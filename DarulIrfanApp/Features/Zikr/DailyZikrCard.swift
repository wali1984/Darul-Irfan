import AudioToolbox
import SwiftUI

/// Daily Zikr on the Zikr tab: one card for the broadcast and its session,
/// where a live card and a "Daily Zikr" schedule card used to stand one under
/// the other with two Join buttons and two bells.
///
/// Before the session, the time left on a ring, in this phone's time and
/// Pakistan's; while it is live, "On air now" and the host's cue. One Join,
/// greyed until the channel is live and then gold, playing in the app (Daily
/// Zikr is YouTube only). One Reminders menu holding both existing choices,
/// and the recorded zikr folded under Join. The screen keeps the live state
/// current (`ZikrHomeViewModel.followLive`), so the card does not ask itself.
struct DailyZikrCard: View {
    let broadcast: LiveBroadcast
    /// Daily Zikr's session in the schedule, for the countdown and the
    /// reminder before it; nil when the schedule has none.
    let session: ZikrSession?
    /// The channel's recordings of earlier sessions, newest first.
    let recordings: [OfficialFeedItem]
    /// The official "Daily Zikr has started" notification (push).
    let alertsWhenLive: Binding<Bool>
    /// The local reminder before each session; nil without a session.
    let reminderBeforeSession: Binding<Bool>?
    /// Plays what Join offers: the live video, or the room's relayed sound.
    let join: (LiveSource) -> Void
    /// Plays one recording.
    let playRecording: (OfficialFeedItem) -> Void

    @State private var showsRecordings = false
    @Environment(\.locale) private var locale

    private var isLive: Bool { broadcast.state == .live }
    private var inUrdu: Bool { DIBrand.readsUrdu(locale) }
    private var source: LiveSource? { DailyZikrPresentation.joinSource(for: broadcast) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            headline
            if isLive {
                onAirPanel
                if let cue = broadcast.cue {
                    ZikrCueBanner(cue: cue)
                }
            } else if let session {
                DailyZikrCountdown(session: session)
            }
            if broadcast.state == .scheduled, let start = broadcast.scheduledStart {
                Label(start.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            if let note = DailyZikrPresentation.note(for: broadcast) {
                Text(verbatim: note)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            joinButton
            if source == nil {
                // Says only what the channel reports: nothing here claims the
                // zikr is on before its live video is.
                Text("Daily Zikr appears here, live, when the session begins. Turn on a reminder below to be told when.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DailyZikrRemindersMenu(alertsWhenLive: alertsWhenLive, reminderBeforeSession: reminderBeforeSession)
            if !recordings.isEmpty {
                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 1)
                    .accessibilityHidden(true)
                recordingsList
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .onChange(of: broadcast.cue) { old, new in
            // A new latifa or muraqaba while the card is on screen: a chime
            // over the stream, since the mic may have dropped as it changed.
            if old != nil, let new, new != old {
                AudioServicesPlaySystemSound(1013)
                DIHaptics.success()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DISpacing.sm) {
            if isLive {
                DILivePulse(color: Color(hex: 0xFF5C5C), size: 9)
            }
            Text("Daily Zikr")
                .font(.caption.weight(.heavy))
                .tracking(inUrdu ? 0 : 1.7)
                .textCase(.uppercase)
                .foregroundStyle(Color(hex: 0xFFE3A0))
            Spacer(minLength: DISpacing.sm)
            Text(LocalizedStringKey(DailyZikrPresentation.statusKey(for: broadcast.state)))
                .font(.caption2.weight(.heavy))
                .tracking(inUrdu ? 0 : 0.6)
                .foregroundStyle(isLive ? Color(hex: 0x064B34) : Color.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isLive ? Color.white : Color.white.opacity(0.14), in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }

    private var headline: some View {
        let name = DailyZikrPresentation.headline(for: broadcast)
        let subtitle = DailyZikrPresentation.subtitle(host: name.host, durationMinutes: session?.durationMinutes)
        return VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: name.title)
                .font(.title3.weight(.heavy))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(verbatim: subtitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Live

    private var onAirPanel: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(DIColor.goldGlow)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("On air now")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(verbatim: DailyZikrPresentation.onAirDetail(startedAt: broadcast.startedAt))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Join

    /// Always shown; greyed until the channel is live with something the app
    /// can play, then gold.
    private var joinButton: some View {
        let source = self.source
        let available = source != nil
        return Button {
            guard let source else { return }
            DIHaptics.light()
            join(source)
        } label: {
            Label("Join Daily Zikr", systemImage: source?.kind == .ownedStream ? "headphones" : "play.rectangle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(available ? Color(hex: 0x064B34) : Color.white.opacity(0.62))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background { joinFill(available) }
                .contentShape(Capsule())
        }
        .buttonStyle(DIPressableStyle())
        .disabled(!available)
        .accessibilityHint(available ? Text("") : Text("Available when Daily Zikr is live"))
    }

    @ViewBuilder
    private func joinFill(_ available: Bool) -> some View {
        if available {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xFFE9A8), Color(hex: 0xE0B75F), Color(hex: 0xC99A3A)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Capsule().stroke(Color(hex: 0xFFE9A8).opacity(0.9), lineWidth: 1))
                .diShimmer()
                .shadow(color: DIColor.goldGlow.opacity(0.55), radius: 13)
        } else {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 1))
        }
    }

    // MARK: Recorded zikr

    /// Earlier sessions to play, folded away until opened. Every recording
    /// carries the same title, so each is named by when it was streamed.
    private var recordingsList: some View {
        DisclosureGroup(isExpanded: $showsRecordings) {
            VStack(spacing: 0) {
                ForEach(recordings) { item in
                    Button {
                        DIHaptics.light()
                        playRecording(item)
                    } label: {
                        ZikrRecordingRow(item: item)
                    }
                    .buttonStyle(.plain)
                    if item.id != recordings.last?.id {
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.top, DISpacing.xs)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.body.weight(.semibold))
                    .accessibilityHidden(true)
                Text("Recorded zikr")
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: DISpacing.sm)
                if !showsRecordings {
                    Text(verbatim: "\(recordings.count)")
                        .font(.caption.weight(.semibold))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(.white)
            .frame(minHeight: 44)
        }
        .tint(Color.white.opacity(0.75))
    }

    // MARK: Surface

    /// The emerald hero surface with its aurora, a slowly turning gold
    /// octagram, and a gold edge while live.
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        return ZStack {
            DIHeroBackground(cornerRadius: 30)
            ZikrTurningOctagram(size: 240)
                .offset(x: 80, y: -70)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .clipShape(shape)
            if isLive {
                shape.stroke(Color(hex: 0xE0B75F).opacity(0.65), lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Countdown

/// The time left before Daily Zikr, on a gold ring that fills through the
/// day, then this phone's time and Pakistan's. The digits count each second;
/// the rest is re-read every thirty.
private struct DailyZikrCountdown: View {
    let session: ZikrSession
    @Environment(\.locale) private var locale

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let window = ZikrCountdown.window(for: session, at: context.date) {
                let active = window.isActive(at: context.date)
                HStack(spacing: DISpacing.md) {
                    ZikrCountdownRing(progress: ZikrCountdown.ringProgress(window, at: context.date), active: active)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(active ? "Zikr in progress" : "Zikr begins in")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.82))
                        Text(active ? window.end : window.start, style: .timer)
                            .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                            .foregroundStyle(DIColor.goldGlow)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                            .diGoldGlow(radius: 10, opacity: 0.7)
                        Text(verbatim: ZikrTimeLine.text(for: window.start, session: session, locale: locale))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A small gold ring that fills as Daily Zikr comes near, with a glowing bead
/// at its tip and the night's crescent inside. It fills clockwise in both
/// reading directions, as a clock's hand turns.
private struct ZikrCountdownRing: View {
    let progress: Double
    let active: Bool
    var diameter: CGFloat = 78

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 5)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [DIColor.goldGlow.opacity(0.25), DIColor.goldGlow]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(max(1, shown * 360))
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(Color(hex: 0xFFF4CF))
                .frame(width: 8, height: 8)
                .diBreathingGlow(color: DIColor.goldGlow, maxRadius: 8)
                .offset(y: -diameter / 2)
                .rotationEffect(.degrees(shown * 360))
            Image(systemName: active ? "dot.radiowaves.left.and.right" : "moon.fill")
                .font(.title3)
                .foregroundStyle(DIColor.goldGlow)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
        .onAppear { update(progress) }
        .onChange(of: progress) { _, value in update(value) }
    }

    private func update(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        if reduceMotion {
            shown = clamped
        } else {
            withAnimation(.easeInOut(duration: 0.9)) { shown = clamped }
        }
    }
}

// MARK: - Reminders

/// One menu for Daily Zikr's two existing choices: the official notification
/// when it goes live (push), and the reminder before each session (local).
/// Each stays the setting it was; the menu only puts them together.
private struct DailyZikrRemindersMenu: View {
    let alertsWhenLive: Binding<Bool>
    let reminderBeforeSession: Binding<Bool>?

    private var summary: String {
        ZikrReminderSummary.text(
            beforeEachSession: reminderBeforeSession?.wrappedValue,
            whenLive: alertsWhenLive.wrappedValue
        )
    }

    var body: some View {
        Menu {
            Toggle(isOn: alertsWhenLive) {
                Label("When it goes live", systemImage: "bell.badge")
            }
            if let reminderBeforeSession {
                Toggle(isOn: reminderBeforeSession) {
                    Label("\(ZikrReminders.leadMinutes) minutes before each session", systemImage: "clock")
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bell")
                    .font(.body.weight(.semibold))
                    .accessibilityHidden(true)
                Text("Reminders")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: DISpacing.sm)
                HStack(spacing: 6) {
                    Text(verbatim: summary)
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .opacity(0.8)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(minHeight: 44)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
            }
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Reminders"))
        .accessibilityValue(Text(verbatim: summary))
    }
}

// MARK: - Pieces

/// The host's current latifa or muraqaba, exactly as written in the room.
private struct ZikrCueBanner: View {
    let cue: LiveCue

    var body: some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: "bell.and.waves.left.and.right.fill")
                .font(.title3)
                .foregroundStyle(DIColor.primaryDeep)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: cue.text)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DIColor.primaryDeep)
                Text("Now in the zikr · \(cue.at.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(DIColor.primaryDeep.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .padding(DISpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DIGradient.goldSheen, in: RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// One recorded session: a gold play mark, its day, and the time it was
/// streamed.
private struct ZikrRecordingRow: View {
    let item: OfficialFeedItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.fill")
                .font(.caption2)
                .foregroundStyle(Color(hex: 0x064B34))
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFFE9A8), Color(hex: 0xE0B75F)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .shadow(color: DIColor.goldGlow.opacity(0.35), radius: 6)
                .accessibilityHidden(true)
            Text(item.publishedAt, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: DISpacing.sm)
            Text(item.publishedAt, format: .dateTime.hour().minute())
                .font(.footnote.monospacedDigit())
                .opacity(0.75)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 9)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
