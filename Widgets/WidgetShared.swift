import CoreText
import SwiftUI
import WidgetKit

// Pieces every widget in this extension shares: the seal in each rendering
// mode, the live countdown, the place's clock and the app's language, and the
// mushaf face for the Ayah of the Day.

// MARK: - Seal

/// The Silsila's seal. In full colour it is the original emblem; on the Lock
/// Screen, in StandBy at night and on a tinted Home Screen iOS draws widgets
/// in one tone, so the seal's own monochrome cut (BrandEmblemMono, made from
/// the same artwork) is drawn in the system's tone instead of a grey blot.
struct WidgetSeal: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let size: CGFloat

    var body: some View {
        Group {
            if renderingMode == .fullColor {
                Image("BrandEmblem")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image("BrandEmblemMono")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .scaledToFit()
                    .widgetAccentable()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Place and language

private struct WidgetPlaceModifier: ViewModifier {
    let snapshot: PrayerWidgetSnapshot?

    func body(content: Content) -> some View {
        content
            // Times on the place's clock, as the app shows them.
            .environment(\.timeZone, snapshot?.timeZone ?? .current)
            // The app's language, with Western digits, and its direction.
            .transformEnvironment(\.locale) { locale in
                if let chosen = snapshot?.displayLocale { locale = chosen }
            }
            .transformEnvironment(\.layoutDirection) { direction in
                if let rtl = snapshot?.readsRightToLeft { direction = rtl ? .rightToLeft : .leftToRight }
            }
    }
}

extension View {
    /// The place's clock and the app's language for everything inside.
    func widgetPlace(_ snapshot: PrayerWidgetSnapshot?) -> some View {
        modifier(WidgetPlaceModifier(snapshot: snapshot))
    }
}

// MARK: - Countdown

/// A countdown to the next prayer that iOS keeps ticking on its own and that
/// stops at 0:00 instead of counting up past the azan.
struct WidgetCountdown: View {
    let interval: ClosedRange<Date>

    var body: some View {
        Text(timerInterval: interval, countsDown: true)
            .monospacedDigit()
    }
}

/// A ring that empties as the next prayer draws near, iOS animating it
/// between entries (Lock Screen circular, StandBy).
struct WidgetCountdownRing: View {
    let interval: ClosedRange<Date>
    var lineWidth: CGFloat = 4

    var body: some View {
        ProgressView(timerInterval: interval, countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.circular)
        .widgetAccentable()
    }
}

// MARK: - Mushaf face

/// The reader's IndoPak mushaf face, bundled into this extension too
/// (project.yml) so the Ayah of the Day is never drawn in a face that turns
/// its waqf signs into boxes. Registered for this process on first use.
enum WidgetFonts {
    static let quranArabic: String = {
        if let url = Bundle.main.url(forResource: "AlQuran-IndoPak-QuranWBW", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return "AlQuran-IndoPak-by-QuranWBW"
    }()

    static func quran(size: CGFloat) -> Font {
        .custom(quranArabic, fixedSize: size)
    }
}

// MARK: - Shared rows

/// The five prayers of the day, the next one on a gold ground.
struct WidgetFivePrayers: View {
    @Environment(\.colorScheme) private var colorScheme

    let prayers: [WidgetPrayerTime]
    let date: Date
    var rowFont: Font = .caption

    var body: some View {
        let next = prayers.first { $0.time > date }
        VStack(spacing: 2) {
            ForEach(prayers, id: \.time) { prayer in
                let isNext = prayer == next
                HStack(spacing: 6) {
                    Text(prayer.displayName)
                        .foregroundStyle(isNext
                            ? WidgetPalette.emeraldTone(for: colorScheme)
                            : WidgetPalette.textTone(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Text(prayer.time, style: .time)
                        .monospacedDigit()
                        .foregroundStyle(WidgetPalette.textTone(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .font(rowFont.weight(isNext ? .semibold : .regular))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isNext ? WidgetPalette.goldTone(for: colorScheme).opacity(0.22) : Color.clear)
                )
                .widgetAccentable(isNext)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// "Zikr live · 12:34" while a session runs, else when the next one begins.
struct WidgetZikrLine: View {
    @Environment(\.colorScheme) private var colorScheme

    let session: WidgetZikrSession
    let date: Date

    var body: some View {
        let active = session.isActive(at: date)
        HStack(spacing: 5) {
            Image(systemName: active ? "dot.radiowaves.left.and.right" : "heart.fill")
                .foregroundStyle(WidgetPalette.goldTone(for: colorScheme))
                .accessibilityHidden(true)
            Text(active ? LocalizedStringKey("Zikr in progress") : LocalizedStringKey("Next Zikr"))
                .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
            Text(verbatim: session.title)
                .foregroundStyle(WidgetPalette.textTone(for: colorScheme))
                .lineLimit(1)
            Spacer(minLength: 4)
            if active {
                WidgetCountdown(interval: date...max(date, session.endsAt))
                    .foregroundStyle(WidgetPalette.emeraldTone(for: colorScheme))
                    .frame(maxWidth: 64, alignment: .trailing)
            } else {
                Text(session.startsAt, style: .time)
                    .foregroundStyle(WidgetPalette.textTone(for: colorScheme))
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// Ayah of the Day in the space given: the Arabic and its translation when
/// both fit, else the Arabic alone, else the translation. The Arabic is
/// shown whole or not at all, never cut short.
struct WidgetAyahBlock: View {
    @Environment(\.colorScheme) private var colorScheme

    let ayah: WidgetDailyAyah
    var arabicSize: CGFloat = 20
    var translationLines = 4

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 6) {
                arabic
                translation(lines: nil)
                reference
            }
            VStack(spacing: 6) {
                arabic
                reference
            }
            VStack(spacing: 4) {
                translation(lines: translationLines)
                reference
            }
            reference
        }
        .frame(maxWidth: .infinity)
    }

    private var arabic: some View {
        Text(verbatim: ayah.arabic)
            .font(WidgetFonts.quran(size: arabicSize))
            .foregroundStyle(WidgetPalette.textTone(for: colorScheme))
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .environment(\.layoutDirection, .rightToLeft)
    }

    @ViewBuilder
    private func translation(lines: Int?) -> some View {
        if let text = ayah.translation, !text.isEmpty {
            Text(verbatim: text)
                .font(.caption)
                .foregroundStyle(WidgetPalette.textTone(for: colorScheme))
                .multilineTextAlignment(.center)
                .lineLimit(lines)
                .fixedSize(horizontal: false, vertical: lines == nil)
                .frame(maxWidth: .infinity)
                .environment(\.layoutDirection, ayah.languageCode == "ur" ? .rightToLeft : .leftToRight)
        }
    }

    private var reference: some View {
        Text(verbatim: ayah.reference)
            .font(.caption2)
            .foregroundStyle(WidgetPalette.goldTone(for: colorScheme))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .widgetAccentable()
    }
}
