import SwiftUI

/// An official zikr session other than Daily Zikr, on glass: the Tahajjud
/// zikr, held before Fajr at Dar-ul-Irfan and joined in the Paltalk room, and
/// any further session the administrators publish, joined through the
/// channel's live video in the app. Its countdown, this phone's time and
/// Pakistan's, the room's listeners while it is open, Join, and its bell
/// (the reminder before each session).
struct ZikrSessionPanel: View {
    let session: ZikrSession
    /// The official live state: the open Paltalk room, or the live video.
    let live: LiveBroadcast
    /// The reminder before each session.
    let reminder: Binding<Bool>
    /// Plays the channel's live video in the app.
    let playVideo: (String) -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme

    private var inUrdu: Bool { DIBrand.readsUrdu(locale) }
    private var joinsOnPaltalk: Bool { ZikrSessionJoin.joinsOnPaltalk(session) }
    /// Small gold text: darker on cream, brighter at night.
    private var accentText: Color { colorScheme == .dark ? DIColor.accent : Color(hex: 0x7A5A14) }

    var body: some View {
        // Re-read every thirty seconds: the countdown's state, and whether
        // the room is open; the digits count each second by themselves.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            panel(at: context.date)
        }
    }

    private func panel(at now: Date) -> some View {
        let window = ZikrCountdown.window(for: session, at: now)
        let room = ZikrSessionJoin.openRoom(for: session, live: live, at: now)
        return VStack(alignment: .leading, spacing: 12) {
            header(window: window, now: now)
            if let window {
                Text(verbatim: ZikrTimeLine.text(for: window.start, session: session, locale: locale))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = session.displayAvailabilityNote(urdu: inUrdu) {
                Text(verbatim: note)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let room {
                Label("Live on Paltalk now · \(room.listeners) listening", systemImage: "person.3.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DIColor.primary)
            }
            HStack(spacing: 10) {
                joinButton(room: room)
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
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(DIColor.textPrimary)
                Text(verbatim: ZikrSessionJoin.subtitle(for: session))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DISpacing.sm)
            if let window {
                let active = window.isActive(at: now)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(active ? "Zikr in progress" : "Zikr begins in")
                        .font(.caption2.weight(.semibold))
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
        Image(systemName: joinsOnPaltalk ? "moon.fill" : "sparkles")
            .font(.body.weight(.semibold))
            .foregroundStyle(DIColor.goldGlow)
            .frame(width: 42, height: 42)
            .background(
                Circle().fill(
                    RadialGradient(
                        colors: joinsOnPaltalk
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

    /// Always shown; greyed until the zikr is on: the open room for the
    /// Tahajjud zikr, the live video for any other session.
    private func joinButton(room: LiveRoom?) -> some View {
        let videoID = ZikrSessionJoin.liveVideoID(for: session, live: live)
        let available = joinsOnPaltalk ? room != nil : videoID != nil
        return Button {
            DIHaptics.light()
            if let url = room?.url {
                openURL(url)
            } else if let videoID {
                playVideo(videoID)
            }
        } label: {
            Label(joinsOnPaltalk ? "Join Zikr on Paltalk" : "Join Zikr on YouTube",
                  systemImage: joinsOnPaltalk ? "headphones" : "play.rectangle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(available ? Color.white : DIColor.textMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background { joinFill(available) }
                .contentShape(Capsule())
        }
        .buttonStyle(DIPressableStyle())
        .disabled(!available)
        .accessibilityHint(available ? Text("")
            : joinsOnPaltalk ? Text("Available when the Paltalk room is open") : Text("Available when the zikr is live on YouTube"))
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
                .font(.body.weight(.semibold))
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
