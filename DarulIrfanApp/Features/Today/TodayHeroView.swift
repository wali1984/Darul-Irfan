import SwiftUI

/// Today's prayer card (board Main): the Darul Irfan wordmark, a greeting
/// and the place, the living Silsila seal, the next prayer with its
/// countdown and ring, the five prayers to mark with a tap (not marked,
/// prayed, in congregation, qaza), and the way to every time and alert.
/// During Ramadan the Suhoor or Iftar countdown takes the countdown line.
/// The hierarchy adapts to accessibility text sizes without shrinking labels.
@MainActor
struct TodayHeroView: View {
    let viewModel: PrayerViewModel
    let dependencies: AppDependencies
    let appState: AppState

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .largeTitle) private var prayerNameSize: CGFloat = 28

    private var timeZone: TimeZone {
        appState.activePlace?.timeZone ?? .current
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .center, spacing: 12) {
                header(at: context.date)
                if !viewModel.hasLoaded {
                    ProgressView()
                        .tint(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if appState.activePlace == nil {
                    TodayHeroLocationPrompt(viewModel: viewModel)
                } else if let schedule = viewModel.todaySchedule {
                    if let next = viewModel.nextPrayer {
                        nextPrayerRow(next, now: context.date)
                    }
                    TodayHeroPrayerChips(viewModel: viewModel, schedule: schedule)
                } else {
                    unavailable
                }
                // One footer in one place whatever the state above it: the
                // page it opens stays open while the card changes beneath.
                if viewModel.hasLoaded {
                    footer
                }
                Text(DIBrand.anchorVerseArabic)
                    .font(DIFont.quranArabic(scale: 1.08))
                    .lineSpacing(8)
                    .environment(\.layoutDirection, .rightToLeft)
                    .diGoldTextShimmer(highlight: Color(hex: 0xFFF7DA))
                    .foregroundStyle(Color(hex: 0xFFE3A0))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { TodayHeroSurface(date: context.date, timeZone: timeZone) }
        }
    }

    // MARK: - Header

    private func header(at date: Date) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("DARUL IRFAN")
                        .font(.caption2.weight(.heavy))
                        .tracking(DIBrand.readsUrdu(locale) ? 0 : 3)
                        .foregroundStyle(Color(hex: 0xFFE3A0))
                        .diGoldGlow(radius: 5, opacity: 0.55)
                    Text(LocalizedStringKey(DIGradient.greeting(for: date, timeZone: timeZone)))
                        .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.88))
                }
                Spacer(minLength: 0)
                DILivingSealMark(diameter: dynamicTypeSize.isAccessibilitySize ? 52 : 68).accessibilityHidden(true)
            }
            .environment(\.layoutDirection, .leftToRight)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: viewModel.gregorianShortText).font(.footnote).foregroundStyle(.white.opacity(0.92))
                    Text(verbatim: viewModel.hijriDateText).font(.caption).foregroundStyle(Color(hex: 0xE9CE86))
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(date, format: Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)).font(.headline.weight(.medium)).monospacedDigit().foregroundStyle(.white)
                    if let place = appState.activePlace {
                        HStack(alignment: .top, spacing: 6) {
                            Text(verbatim: place.name).font(.caption).foregroundStyle(.white.opacity(0.78))
                                .fixedSize(horizontal: false, vertical: true)
                            TodayWeatherView(latitude: place.latitude, longitude: place.longitude, city: place.name, timeZone: timeZone)
                        }
                    }
                }
            }
        }
    }

    private func nextPrayerRow(_ next: NextPrayerInfo, now: Date) -> some View {
        VStack(spacing: 8) {
            Text("Next prayer").font(.footnote.weight(.medium)).foregroundStyle(.white.opacity(0.82))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { prayerName(next); prayerTime(next) }
                VStack(spacing: 4) { prayerName(next); prayerTime(next) }
            }
            countdownLine(to: next.time, now: now)
            GeometryReader { geometry in
                let fraction = min(1, max(0, viewModel.nextPrayerProgress(at: now)))
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule().fill(Color(hex: 0xE9CE86)).frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 2).padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
    }
    private func prayerName(_ next: NextPrayerInfo) -> some View {
        Text(LocalizedStringKey(next.prayer.englishName)).font(.system(size: prayerNameSize, weight: .semibold)).foregroundStyle(.white)
    }
    private func prayerTime(_ next: NextPrayerInfo) -> some View {
        Text(next.time, format: Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)).font(.subheadline).monospacedDigit().foregroundStyle(Color(hex: 0xE9CE86))
    }

    /// The live countdown to the next prayer; in Ramadan, to the end of
    /// Suhoor or to Iftar. VoiceOver reads the stable prayer and time
    /// instead: a changing second counter interrupts navigation.
    private func countdownLine(to time: Date, now: Date) -> some View {
        HStack(spacing: 7) {
            if let ramadan = viewModel.ramadanCountdown {
                Image(systemName: "moon.stars.fill")
                Group {
                    if ramadan.kind == .suhoorEnds {
                        Text("Suhoor ends in")
                    } else {
                        Text("Iftar in")
                    }
                }
                .font(.subheadline.weight(.semibold))
                timer(to: ramadan.time, now: now)
            } else {
                timer(to: time, now: now)
            }
        }
        .font(.system(size: viewModel.ramadanCountdown == nil ? 40 : 24, weight: .light))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func timer(to target: Date, now: Date) -> some View {
        if scenePhase == .active && target > now {
            Text(timerInterval: now...target, countsDown: true)
                .monospacedDigit()
                .fixedSize()
        } else {
            Text("Prayer time")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Unavailable

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Prayer times unavailable", systemImage: "sun.horizon")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Times could not be calculated for this location today. A different high-latitude rule in Settings may help.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Footer

    /// Side by side, or stacked at the largest text sizes. The layout is
    /// chosen by text size alone, so the link keeps its identity (and the
    /// page it opened) as the counts change.
    private var footer: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DISpacing.sm))
        return layout {
            prayedLine
            if !stacked {
                Spacer(minLength: DISpacing.sm)
            }
            allTimesLink
        }
        .padding(.horizontal, 2)
    }

    /// "1 of 5 prayed · 4-day streak": today's marks and the gentle streak.
    private var prayedLine: some View {
        let count = viewModel.completedPrayerCount
        let streak = viewModel.streakSummary?.currentStreakDays ?? 0
        return Group {
            if streak >= 1 {
                Text("\(count) of 5 prayed · \(streak)-day streak")
            } else {
                Text("\(count) of 5 prayed")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.85))
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Opens the Prayer times page: every time with its bell, the method,
    /// the Ramadan card, the tracker for earlier days, the timetable.
    private var allTimesLink: some View {
        NavigationLink {
            PrayerTimesView(viewModel: viewModel, dependencies: dependencies, appState: appState)
        } label: {
            HStack(spacing: 4) {
                Text("All times and alerts")
                Image(systemName: "chevron.forward")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.footnote.weight(.bold))
            .foregroundStyle(Color(hex: 0xFFE3A0))
            .diGoldGlow(radius: 5, opacity: 0.45)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The five prayers

/// The five prayers of the day on the prayer card, with their times. The
/// next one glows; a tap moves its mark on (not marked, prayed, in
/// congregation, qaza, and round again), saved as the tracker always has.
@MainActor
struct TodayHeroPrayerChips: View {
    let viewModel: PrayerViewModel
    let schedule: PrayerDaySchedule
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 6))
        layout {
            ForEach(Prayer.obligatory) { prayer in
                chip(prayer)
            }
        }
    }

    private func chip(_ prayer: Prayer) -> some View {
        let time = schedule.time(for: prayer)
        let isNext = time.map { viewModel.isNext(prayer: prayer, time: $0) } ?? false
        let mark = viewModel.completion(for: prayer)
        return Button {
            DIHaptics.soft()
            Task { await viewModel.cycleCompletion(for: prayer) }
        } label: {
            VStack(spacing: 3) {
                Text(LocalizedStringKey(prayer.englishName))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(isNext ? 1 : 0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let time {
                    Text(verbatim: viewModel.timeText(time))
                        .font(.footnote.weight(.bold).monospacedDigit())
                        .foregroundStyle(isNext ? DIColor.goldGlow : Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                PrayerMarkBadge(mark: mark, surface: .hero, size: 18, emphasised: isNext)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 9)
            .padding(.bottom, 8)
            .padding(.horizontal, 2)
            .background(chipFill(isNext), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isNext ? DIColor.goldGlow.opacity(0.85) : Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: isNext ? DIColor.goldGlow.opacity(0.18) : Color.clear, radius: 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(DIPressableStyle())
        .accessibilityLabel(PrayerMarkText.accessibilityLabel(prayer: prayer, completion: mark))
        .accessibilityValue(time.map { Text(verbatim: viewModel.timeText($0)) } ?? Text(verbatim: ""))
        .accessibilityHint(Text("Double tap to change how this prayer is marked."))
    }

    private func chipFill(_ isNext: Bool) -> AnyShapeStyle {
        if isNext {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(Color.white.opacity(0.08))
    }
}

// MARK: - Before a place is set

/// The prayer card before a place is set: why one is needed, and the button
/// that finds the phone's location. Choosing a city stays in Settings.
@MainActor
struct TodayHeroLocationPrompt: View {
    let viewModel: PrayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            Label("Set your location to see prayer times", systemImage: "location.circle")
                .font(.headline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("Prayer times are calculated privately on your device once a location is set.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await viewModel.requestDeviceLocation() }
            } label: {
                Group {
                    if viewModel.isRequestingLocation {
                        ProgressView()
                            .tint(TodayGradients.onGold)
                    } else {
                        Text("Use My Current Location")
                    }
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TodayGradients.onGold)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(TodayGradients.gold, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(DIPressableStyle())
            .disabled(viewModel.isRequestingLocation)
            Group {
                if viewModel.locationRequestFailed {
                    Text("We couldn't determine your location. You can allow location access in iOS Settings, or choose a city in the Halqah tab under Settings.")
                } else {
                    Text("Prefer a specific city? You can choose one anytime in the Halqah tab under Settings.")
                }
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Surface

/// The prayer card's surface: the emerald hero with its drifting aurora,
/// and the gold octagram turning slowly at its corner.
struct TodayHeroSurface: View {
    var date = Date()
    var timeZone = TimeZone.current
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30).fill(DIGradient.hero(for: date, timeZone: timeZone))
                .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color(hex: 0xE9CE86).opacity(0.25), lineWidth: 1))
            TodayTurningOctagram(size: 180, color: DIColor.goldGlow, lineWidth: 2, period: 180)
                .opacity(0.045)
                .offset(x: 50, y: -50)
                // Takes the card's size whatever the octagram's, so it never
                // widens the surface; the clip trims it.
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topTrailing)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Ring

/// The next prayer's ring: how far the time has run since the last prayer,
/// a light at the arc's end, and the next prayer's time inside.
struct TodayPrayerRing: View {
    let progress: Double
    let time: Date
    let timeZone: TimeZone
    var diameter: CGFloat = 92

    var body: some View {
        let value = min(max(progress.isFinite ? progress : 0, 0), 1)
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 6)
            Circle()
                .trim(from: 0, to: value)
                .stroke(
                    AngularGradient(
                        colors: [DIColor.goldGlow.opacity(0.35), DIColor.goldGlow],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityHidden(true)
            Circle()
                .fill(Color(hex: 0xFFF4CF))
                .frame(width: 9, height: 9)
                .diBreathingGlow(color: DIColor.goldGlow, maxRadius: 8)
                .offset(y: -diameter / 2)
                .rotationEffect(.degrees(360 * value))
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityHidden(true)
            Text(time, style: .time)
                .environment(\.timeZone, timeZone)
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 10)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// The ring's arithmetic, apart from the view so it is tested.
enum TodayHeroMath {
    /// How far the time has run (0...1) from the last of `earlierTimes` at
    /// or before `now` (or `dayStart`, before the day's first time) to
    /// `next`.
    static func ringProgress(now: Date, next: Date, earlierTimes: [Date], dayStart: Date) -> Double {
        let start = earlierTimes.filter { $0 <= now }.max() ?? dayStart
        let span = next.timeIntervalSince(start)
        guard span > 0 else { return 0 }
        return min(max(now.timeIntervalSince(start) / span, 0), 1)
    }
}
