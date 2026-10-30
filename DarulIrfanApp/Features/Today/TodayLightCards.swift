import SwiftUI

// Today's Light (board Main): the six daily cards in one place, each with
// its content as before, its Share, and one way on to where it lives. The
// content is `TodayDailyViewModel`'s, chosen exactly as before.

/// The six daily cards, in the switch's order.
enum TodayLightKind: String, CaseIterable, Identifiable, Hashable {
    case ayah, hadith, saying, dua, zikr, name

    var id: String { rawValue }

    /// The switch's short name.
    var segmentTitle: LocalizedStringKey {
        switch self {
        case .ayah: return "Ayah"
        case .hadith: return "Hadith"
        case .saying: return "Saying"
        case .dua: return "Dua"
        case .zikr: return "Zikr"
        case .name: return "Name"
        }
    }
}

// MARK: - Shared pieces

/// A daily card's head: its title in small gold capitals, and Share when the
/// card can be shared. The head is the same height on every card, so the
/// cards line up when switched.
struct TodayLightCardHeader: View {
    let titleKey: LocalizedStringKey
    var onShare: (() -> Void)? = nil
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(TodayPalette.accent)
                .frame(width: 7, height: 7)
                .shadow(color: TodayPalette.accent, radius: 4)
                .accessibilityHidden(true)
            Text(titleKey)
                .font(.caption2.weight(.heavy))
                .tracking(DIBrand.readsUrdu(locale) ? 0 : 1.7)
                .textCase(.uppercase)
                .foregroundStyle(TodayPalette.goldText)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DISpacing.sm)
            if let onShare {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TodayPalette.emerald)
                        .frame(width: 44, height: 44)
                        .background(TodayPalette.glassFill, in: Circle())
                        .overlay(Circle().stroke(TodayPalette.glassEdge, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(DIPressableStyle())
                .accessibilityLabel(Text("Share"))
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The daily card's surface: warm paper, a gold glow breathing at its top
/// and the octagram turning slowly in its corner.
struct TodayLightCardBackground: View {
    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [TodayPalette.cardTop, TodayPalette.cardBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 0) {
                RadialGradient(
                    colors: [TodayPalette.cardGlow, Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 160
                )
                .frame(width: 320, height: 220)
                .scaleEffect(breathing ? 1.08 : 1)
                .opacity(breathing ? 1 : 0.55)
                .offset(y: -120)
                Spacer(minLength: 0)
            }
            // The glow is wider than a small phone's card; the frame keeps
            // it from widening the surface, and the clip trims it.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            TodayTurningOctagram(size: 300, color: TodayPalette.accent, lineWidth: 1.8, period: 120)
                .opacity(0.16)
                .offset(x: 120, y: 120)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

/// Urdu in Nastaliq right to left, English left to right, whatever the
/// app's own layout is.
struct TodayTranslationText: View {
    let text: String
    let urdu: Bool
    var small = false

    var body: some View {
        if urdu {
            Text(verbatim: text)
                .font(DIFont.urduBody(scale: small ? 0.85 : 1.0))
                .foregroundStyle(DIColor.textPrimary)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .rightToLeft)
        } else {
            Text(verbatim: text)
                .font(small ? Font.subheadline : Font.body.weight(.medium))
                .foregroundStyle(DIColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}

/// A card's reference line, in emerald.
private struct TodayReferenceText: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(TodayPalette.emerald)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A card's last line: its reference, and the way on beside it, or under it
/// at the largest text sizes. The layout follows the text size alone, so a
/// link keeps its identity, and the page it opened stays open.
private struct TodayCardFooter<Action: View>: View {
    let reference: String?
    @ViewBuilder var action: () -> Action
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DISpacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DISpacing.sm))
        layout {
            if let reference {
                TodayReferenceText(text: reference)
            }
            if !stacked {
                Spacer(minLength: DISpacing.sm)
            }
            action()
        }
    }
}

// MARK: - Ayah

/// Ayah of the Day: the mushaf's Arabic, the Silsila's translation with its
/// reference, then Open in the Quran, Tafsir and Bayan. A picture published
/// for the day takes the verse's place and keeps the three.
struct TodayAyahCard: View {
    let ayah: DailyAyah?
    let silsila: TodayDailyViewModel.SilsilaAyah?
    /// The bundled translation, until the Silsila's is read.
    let fallbackTranslation: String?
    let readsUrdu: Bool
    let picture: DailyMediaItem?
    let onShare: (() -> Void)?
    let onTafsir: () -> Void
    let onBayan: ((AyahBayanLink) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TodayLightCardHeader(titleKey: "Ayah of the Day", onShare: onShare)
            if let picture {
                DailyPicture(item: picture)
            } else if let ayah {
                Text(verbatim: silsila?.arabic ?? ayah.arabic)
                    .font(DIFont.quranArabic(scale: 1.05))
                    .foregroundStyle(TodayPalette.arabicInk)
                    .diGoldGlow(radius: 10, opacity: 0.35)
                    .lineSpacing(10)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.layoutDirection, .rightToLeft)
                TodayOrnamentRule()
                if let translation = silsila?.translation ?? fallbackTranslation {
                    TodayTranslationText(text: translation, urdu: silsila?.isUrdu ?? readsUrdu)
                }
                // Whose translation it is, and exactly where it is from.
                VStack(alignment: .leading, spacing: 2) {
                    TodayReferenceText(text: silsila?.reference ?? ayah.reference)
                    if let silsila {
                        Text(verbatim: [silsila.surahNameArabic, silsila.translationEdition]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                    }
                }
            }
            Spacer(minLength: 0)
            if let ayah {
                actions(ayah)
            }
        }
    }

    private func actions(_ ayah: DailyAyah) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DISpacing.sm) {
                openButton(ayah, expands: true)
                tafsirButton
                bayanButton
            }
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                openButton(ayah, expands: true)
                HStack(spacing: DISpacing.sm) {
                    tafsirButton
                    bayanButton
                }
            }
        }
    }

    private func openButton(_ ayah: DailyAyah, expands: Bool) -> some View {
        Button {
            DIHaptics.soft()
            DeepLinkRouter.shared.open(.quranAyah(surah: ayah.surah, ayah: ayah.ayahStart))
        } label: {
            TodayPill(titleKey: "Open in the Quran", systemImage: "book.closed", kind: .emerald, expands: expands)
        }
        .buttonStyle(DIPressableStyle())
    }

    private var tafsirButton: some View {
        Button {
            DIHaptics.soft()
            onTafsir()
        } label: {
            TodayPill(titleKey: "Tafsir", kind: .glass)
        }
        .buttonStyle(DIPressableStyle())
    }

    @ViewBuilder
    private var bayanButton: some View {
        if let bayan = silsila?.bayan, let onBayan {
            Button {
                DIHaptics.soft()
                onBayan(bayan)
            } label: {
                TodayPill(titleKey: "Bayan", systemImage: "play.fill", kind: .glass)
            }
            .buttonStyle(DIPressableStyle())
            .accessibilityLabel(Text(verbatim: bayan.title))
        }
    }
}

// MARK: - Hadith

/// Hadith of the Day: the narration in the reading language and its Arabic,
/// its reference, and Read in full at that narration. A picture published
/// for the day takes the narration's place and keeps Read in full.
struct TodayHadithCard: View {
    let hadith: TodayDailyViewModel.HadithOfTheDay?
    let readsUrdu: Bool
    let picture: DailyMediaItem?
    let onShare: (() -> Void)?
    let appState: AppState
    let dependencies: AppDependencies?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TodayLightCardHeader(titleKey: "Hadith of the Day", onShare: onShare)
            if let picture {
                DailyPicture(item: picture)
            } else if let hadith {
                if let translation = hadith.translation {
                    TodayTranslationText(text: translation, urdu: hadith.translationIsUrdu)
                        .lineLimit(10)
                }
                if let arabic = hadith.arabic, !arabic.isEmpty {
                    Text(verbatim: arabic)
                        .font(DIFont.quranArabic(scale: 0.7))
                        .foregroundStyle(TodayPalette.arabicSoft)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
            Spacer(minLength: 0)
            if let hadith {
                TodayCardFooter(reference: picture == nil ? reference(hadith) : nil) {
                    readInFull(hadith)
                }
            }
        }
    }

    private func reference(_ hadith: TodayDailyViewModel.HadithOfTheDay) -> String {
        let title = hadith.book.map { readsUrdu ? $0.titleUrdu : $0.titleEnglish } ?? ""
        return "\(title) \(hadith.number)"
    }

    @ViewBuilder
    private func readInFull(_ hadith: TodayDailyViewModel.HadithOfTheDay) -> some View {
        if let book = hadith.book, let dependencies {
            NavigationLink {
                HadithBookView(book: book, repository: dependencies.hadithRepository, appState: appState, initialHadith: hadith.id)
            } label: {
                TodayPill(titleKey: "Read in full", kind: .emerald)
            }
            .buttonStyle(DIPressableStyle())
        }
    }
}

// MARK: - Saying

/// Aqwal-e-Sheikh: the saying, large, and whose it is. Share only. A
/// picture published for the day takes the saying's place.
struct TodaySayingCard: View {
    let aqwal: DailyInspiration?
    let picture: DailyMediaItem?
    let onShare: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TodayLightCardHeader(titleKey: "Aqwal-e-Sheikh", onShare: onShare)
            if let picture {
                DailyPicture(item: picture)
                Spacer(minLength: 0)
            } else if let aqwal {
                Text(verbatim: "\u{201C}")
                    .font(.system(size: 72, weight: .regular, design: .serif))
                    .foregroundStyle(TodayPalette.accent)
                    .diGoldGlow(radius: 10, opacity: 0.6)
                    .frame(height: 40, alignment: .top)
                    .accessibilityHidden(true)
                Text(aqwal.text)
                    .font(.system(.title3, design: .serif))
                    .italic()
                    .foregroundStyle(DIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    TodayGoldMedallion()
                    Text(aqwal.attribution)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DIColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Spacer(minLength: 0)
            }
        }
    }
}

/// The small gold medallion with the octagram, beside a saying's author.
struct TodayGoldMedallion: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0xFFE9A8), Color(hex: 0xE4BE5E), Color(hex: 0xB48A2C), Color(hex: 0x7A5A14)],
                        center: UnitPoint(x: 0.32, y: 0.28),
                        startRadius: 0,
                        endRadius: 26
                    )
                )
            Circle()
                .stroke(Color(hex: 0xFFE9A8).opacity(0.5), lineWidth: 2)
            Rectangle()
                .stroke(Color(hex: 0x5A400C), lineWidth: 1.3)
                .frame(width: 13, height: 13)
            Rectangle()
                .stroke(Color(hex: 0x5A400C), lineWidth: 1.3)
                .frame(width: 13, height: 13)
                .rotationEffect(.degrees(45))
        }
        .frame(width: 38, height: 38)
        .shadow(color: Color.black.opacity(0.25), radius: 7, y: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Dua

/// Dua of the Day: its name, the Arabic, the translation and its source,
/// and Open Duas.
struct TodayDuaCard: View {
    let dua: Dua?
    let readsUrdu: Bool
    let translation: String?
    let onShare: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TodayLightCardHeader(titleKey: "Dua of the Day", onShare: onShare)
            if let dua {
                Text(verbatim: dua.displayTitle(urdu: readsUrdu))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(DIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(dua.arabic)
                    .font(DIFont.quranArabic(scale: 0.9))
                    .foregroundStyle(TodayPalette.arabicInk)
                    .diGoldGlow(radius: 8, opacity: 0.3)
                    .lineSpacing(8)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.layoutDirection, .rightToLeft)
                if let translation {
                    Text(translation)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DIColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                TodayCardFooter(reference: dua.source) {
                    NavigationLink {
                        DuasView()
                    } label: {
                        TodayPill(titleKey: "Open Duas", kind: .emerald)
                    }
                    .buttonStyle(DIPressableStyle())
                }
            } else {
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Zikr

/// Zikr of the Day: the words inside a slowly turning gold ring with the
/// count, the transliteration and meaning, the source, and Count with
/// Tasbih, which opens the counters.
struct TodayZikrCard: View {
    let dhikr: DailyDhikr?
    let onShare: (() -> Void)?
    let dependencies: AppDependencies?

    var body: some View {
        VStack(spacing: 12) {
            TodayLightCardHeader(titleKey: "Zikr of the Day", onShare: onShare)
            if let dhikr {
                TodayZikrRing(arabic: dhikr.arabic, count: dhikr.count)
                    .padding(.top, 6)
                Text(dhikr.transliteration)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(dhikr.meaning)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                TodayCardFooter(reference: dhikr.source) {
                    if let dependencies {
                        NavigationLink {
                            TasbihListView(
                                trackerRepository: dependencies.trackerRepository,
                                devotionalMetrics: dependencies.devotionalMetrics
                            )
                        } label: {
                            TodayPill(titleKey: "Count with Tasbih", systemImage: "hand.tap", kind: .gold)
                        }
                        .buttonStyle(DIPressableStyle())
                    }
                }
            } else {
                Spacer(minLength: 0)
            }
        }
    }
}

/// The zikr's words in a gold ring that turns slowly, with the count below.
struct TodayZikrRing: View {
    let arabic: String
    let count: Int
    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(TodayPalette.accent.opacity(0.15), lineWidth: 4)
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    AngularGradient(
                        colors: [TodayPalette.accent.opacity(0.1), TodayPalette.accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(turning ? 270 : -90))
                .accessibilityHidden(true)
            Text(arabic)
                .font(DIFont.quranArabic(scale: 1.6))
                .foregroundStyle(TodayPalette.arabicInk)
                .diGoldGlow(radius: 10, opacity: 0.4)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 26)
                .environment(\.layoutDirection, .rightToLeft)
            VStack {
                Spacer(minLength: 0)
                Text(verbatim: "\u{00D7}\(count)")
                    .font(.subheadline.weight(.heavy).monospacedDigit())
                    .foregroundStyle(TodayGradients.onGold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(TodayGradients.gold, in: Capsule())
                    .shadow(color: DIColor.goldGlow.opacity(0.5), radius: 8)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: 200, height: 200)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) {
                turning = true
            }
        }
    }
}

// MARK: - Name

/// Name of the Day: the Name in large Arabic in a turning octagram, its
/// transliteration and meaning, and All 99 Names.
struct TodayNameCard: View {
    let name: NameOfAllah?
    let meaning: String?
    let onShare: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            TodayLightCardHeader(titleKey: "Name of the Day", onShare: onShare)
            if let name {
                ZStack {
                    TodayTurningOctagram(size: 220, color: TodayPalette.accent, lineWidth: 1.5, period: 60)
                        .opacity(0.55)
                    Circle()
                        .stroke(TodayPalette.accent.opacity(0.4), lineWidth: 1)
                        .frame(width: 130, height: 130)
                    Text(name.arabic)
                        .font(DIFont.quranArabic(scale: 2.2))
                        .foregroundStyle(TodayPalette.arabicInk)
                        .diGoldGlow(radius: 12, opacity: 0.45)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 30)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                .frame(width: 220, height: 220)
                Text(name.transliteration)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.center)
                if let meaning {
                    Text(meaning)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(DIColor.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    NavigationLink {
                        NamesOfAllahView()
                    } label: {
                        TodayPill(titleKey: "All 99 Names", kind: .emerald)
                    }
                    .buttonStyle(DIPressableStyle())
                }
            } else {
                Spacer(minLength: 0)
            }
        }
    }
}
