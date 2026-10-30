import SwiftUI

// "Your practice" on the Zikr tab: two glass tiles, Tasbih (the counters)
// and the Method of Zikr (the illustrated method). The Zikr tab wraps each
// in its link.

/// The counters, with the one used last on a ring.
struct ZikrTasbihTile: View {
    let practice: ZikrPracticeSummary?

    var body: some View {
        ZikrPracticeTile(titleKey: "Tasbih", subtitleKey: "Count your personal zikr") {
            ZikrTasbihRing(practice: practice)
        }
    }
}

/// The illustrated Method of Zikr.
struct ZikrMethodTile: View {
    var body: some View {
        ZikrPracticeTile(titleKey: "Method of Zikr", subtitleKey: "Zikr-e Khafi Qalbi, illustrated") {
            ZikrMethodMedallion()
        }
    }
}

/// A glass tile: its mark, then its name and line. As tall as its
/// neighbour, so the pair lines up.
private struct ZikrPracticeTile<Mark: View>: View {
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey
    @ViewBuilder var mark: () -> Mark

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            mark()
            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.callout.weight(.heavy))
                    .foregroundStyle(DIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitleKey)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DISpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .diGlassPanel(cornerRadius: 24)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// An emerald-to-gold ring: the last counter's count and its way to the
/// target, a full ring for an open-ended one, a hand without counters.
private struct ZikrTasbihRing: View {
    let practice: ZikrPracticeSummary?

    private var fill: Double {
        guard let practice else { return 1 }
        return practice.progress ?? 1
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(DIColor.primary.opacity(0.12), lineWidth: 5)
            Circle()
                .trim(from: 0, to: fill)
                .stroke(
                    AngularGradient(colors: [Color(hex: 0x13A06F), DIColor.goldGlow], center: .center),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .environment(\.layoutDirection, .leftToRight)
            if let practice {
                Text(verbatim: "\(practice.count)")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy).monospacedDigit())
                    .foregroundStyle(DIColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(7)
            } else {
                Image(systemName: "hand.tap.fill")
                    .font(.headline)
                    .foregroundStyle(DIColor.primary)
            }
        }
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)
    }
}

/// A gold medallion with the octagram, for the Method of Zikr.
private struct ZikrMethodMedallion: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0xFFE9A8), Color(hex: 0xE4BE5E), Color(hex: 0xB48A2C), Color(hex: 0x7A5A14)],
                        center: UnitPoint(x: 0.32, y: 0.28),
                        startRadius: 0,
                        endRadius: 38
                    )
                )
            ZikrOctagramOutline()
                .stroke(Color(hex: 0x5A400C), lineWidth: 1.8)
                .frame(width: 27, height: 27)
            Circle()
                .fill(Color(hex: 0x5A400C))
                .frame(width: 5, height: 5)
        }
        .frame(width: 52, height: 52)
        .overlay(Circle().stroke(Color(hex: 0xFFE9A8).opacity(0.5), lineWidth: 2))
        .shadow(color: Color(hex: 0x7A5A14).opacity(0.3), radius: 9, y: 8)
        .accessibilityHidden(true)
    }
}
