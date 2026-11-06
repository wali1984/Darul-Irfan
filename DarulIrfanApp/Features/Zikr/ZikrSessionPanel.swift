import SwiftUI

/// An official zikr session other than Daily Zikr, on glass: the Tahajjud
/// zikr, held before Fajr at Dar-ul-Irfan and joined on Our Sheikh's live
/// stage with the app's own live sound (owner, 2026-11-06), and any further
/// session the administrators publish, joined through the channel's live
/// video in the app. Its countdown, this phone's time and Pakistan's, "Live
/// now" while it is, Join, and its bell (the reminder before each session).
struct ZikrSessionPanel: View {
    let session: ZikrSession
    /// The channel's live state, for a further session's live video.
    let live: LiveBroadcast
    /// Our Sheikh's own live Zikr; nil while it is not live.
    let sheikhLive: SheikhLiveZikr?
    /// The reminder before each session.
    let reminder: Binding<Bool>
    /// Plays the channel's live video in the app.
    let playVideo: (String) -> Void
    /// Opens Our Sheikh's live stage with the live sound.
    let joinSheikh: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme

    private var inUrdu: Bool { DIBrand.readsUrdu(locale) }
    private var isTahajjud: Bool { ZikrSessionJoin.isTahajjud(session) }
    /// Small gold text: darker on cream, brighter at night.
    private var accentText: Color { colorScheme == .dark ? DIColor.accent : Color(hex: 0x7A5A14) }

    var body: some View {
        // Re-read every thirty seconds: the countdown's state, and whether
        // the Zikr is live; the digits count each second by themselves.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            panel(at: context.date)
        }
    }

    private func panel(at now: Date) -> some View {
        let window = ZikrCountdown.window(for: session, at: now)
        let sheikhJoinable = ZikrSessionJoin.joinsSheikhStage(for: session, sheikh: sheikhLive, at: now)
        return VStack(alignment: .leading, spacing: 12) {
            header(window: window, now: now)
            if let window {
                Text(verbatim: ZikrTimeLine.text(for: window.start, session: session, locale: locale))
                    .diInterfaceFont(.footnote, weight: .medium)
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = session.displayAvailabilityNote(urdu: inUrdu) {
                Text(verbatim: note)
                    .diInterfaceFont(.caption)
                    .italic()
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if sheikhJoinable {
                Label("Live now", systemImage: "dot.radiowaves.left.and.right")
                    .diInterfaceFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DIColor.primary)
            }
            HStack(spacing: 10) {
                joinButton(sheikhJoinable: sheikhJoinable)
                bellButton
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .diGlassPanel(cornerRadius: 26)
    }

    // MARK: Header

    private func header(window: ZikrCountdown.Window?, now: Date) -> some View {
        HStack(spacing: 12) {
            orb
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: session.displayTitle(urdu: inUrdu))
                    .diInterfaceFont(.headline, weight: .heavy)
                    .foregroundStyle(DIColor.textPrimary)
                Text(verbatim: ZikrSessionJoin.subtitle(for: session))
                    .diInterfaceFont(.caption, weight: .medium)
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DISpacing.sm)
            if let window {
                let active = window.isActive(at: now)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(active ? "Zikr in progress" : "Next Zikr begins in")
                        .diInterfaceFont(.caption2, weight: .semibold)
                        .foregroundStyle(DIColor.textMuted)
                        .multilineTextAlignment(.trailing)
                    Text(active ? window.end : window.start, style: .timer)
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(accentText)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// The Tahajjud zikr's night-blue orb with a gold crescent; an emerald
    /// one for any other session.
    private var orb: some View {
        Image(systemName: isTahajjud ? "moon.fill" : "sparkles")
            .diInterfaceFont(.body, weight: .semibold)
            .foregroundStyle(DIColor.goldGlow)
            .frame(width: 42, height: 42)
            .background(
                Circle().fill(
                    RadialGradient(
                        colors: isTahajjud
                            ? [Color(hex: 0x2A4D7A), Color(hex: 0x16294A), Color(hex: 0x0B1630)]
                            : [Color(hex: 0x34B98A), Color(hex: 0x0B7250), Color(hex: 0x064B34)],
                        center: UnitPoint(x: 0.32, y: 0.26),
                        startRadius: 0,
                        endRadius: 30
                    )
                )
            )
            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
            .shadow(color: Color(hex: 0x0B1630).opacity(0.35), radius: 8, y: 6)
            .accessibilityHidden(true)
    }

    // MARK: Join and bell

    /// Always shown; greyed until the zikr is on: Our Sheikh's live Zikr
    /// before dawn for the Tahajjud zikr, the live video for any other session.
    private func joinButton(sheikhJoinable: Bool) -> some View {
        let videoID = ZikrSessionJoin.liveVideoID(for: session, live: live)
        let available = isTahajjud ? sheikhJoinable : videoID != nil
        return Button {
            DIHaptics.light()
            if isTahajjud {
                if sheikhJoinable { joinSheikh() }
            } else if let videoID {
                playVideo(videoID)
            }
        } label: {
            Label(isTahajjud ? "Join Tahajjud Zikr" : "Join Zikr on YouTube",
                  systemImage: isTahajjud ? "headphones" : "play.rectangle.fill")
                .diInterfaceFont(.subheadline, weight: .bold)
                .foregroundStyle(available ? Color.white : DIColor.textMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background { joinFill(available) }
                .contentShape(Capsule())
        }
        .buttonStyle(DIPressableStyle())
        .disabled(!available)
        .accessibilityHint(available ? Text("")
            : isTahajjud ? Text("Available when Tahajjud Zikr is live") : Text("Available when the zikr is live on YouTube"))
    }

    @ViewBuilder
    private func joinFill(_ available: Bool) -> some View {
        if available {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x13A06F), Color(hex: 0x0B7250)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
                .shadow(color: DIColor.primary.opacity(0.4), radius: 10, y: 8)
        } else {
            Capsule()
                .fill(DIColor.sandstone.opacity(0.7))
                .overlay(Capsule().stroke(DIColor.border, lineWidth: 1))
        }
    }

    /// The reminder before each session, switched on and off in one tap.
    private var bellButton: some View {
        let isOn = reminder.wrappedValue
        return Button {
            DIHaptics.soft()
            reminder.wrappedValue = !reminder.wrappedValue
        } label: {
            Image(systemName: isOn ? "bell.fill" : "bell")
                .diInterfaceFont(.body, weight: .semibold)
                .foregroundStyle(isOn ? DIColor.accent : DIColor.textMuted)
                .frame(width: 44, height: 44)
                .background(Circle().fill(DIColor.accent.opacity(0.14)))
                .overlay(Circle().stroke(DIColor.border, lineWidth: 1))
        }
        .buttonStyle(DIPressableStyle())
        .accessibilityLabel(Text("Remind me before each session"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
