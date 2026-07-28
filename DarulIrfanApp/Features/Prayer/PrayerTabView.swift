import SwiftUI

/// The Prayer tab — the app's flagship screen. Shows the place and dates,
/// a next-prayer hero with a live countdown, today's six times with per-prayer
/// alert bells, a Ramadan card during Ramadan, and the gentle prayer tracker.
struct PrayerTabView: View {
    private let dependencies: AppDependencies
    private let appState: AppState
    @State private var viewModel: PrayerViewModel
    @State private var isSearchPresented = false
    @Environment(\.scenePhase) private var scenePhase

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
        _viewModel = State(initialValue: PrayerViewModel(dependencies: dependencies, appState: appState))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DISpacing.md) {
                    // Living hero — time-of-day gradient, glowing seal, animated
                    // next-prayer countdown ring, dates, and the anchor verse.
                    TodayHeroView(
                        placeName: appState.activePlace?.name,
                        gregorian: viewModel.gregorianDateText,
                        hijri: viewModel.hijriDateText,
                        nextPrayerName: viewModel.nextPrayer.map {
                            String(localized: String.LocalizationValue($0.prayer.englishName))
                        },
                        nextPrayerTime: viewModel.nextPrayer?.time,
                        dayTimes: viewModel.todaySchedule?.orderedTimes.map { $0.time } ?? []
                    )
                    .diAppear()
                    .diParallaxHero()
                    if !viewModel.hasLoaded {
                        loadingView
                    } else if appState.activePlace != nil {
                        if let schedule = viewModel.todaySchedule {
                            DISectionHeader(titleKey: "Today's Times", systemImage: "clock")
                            timesCard(schedule: schedule)
                            if viewModel.isRamadan {
                                ramadanCard(schedule: schedule)
                            }
                            DISectionHeader(titleKey: "Prayer Tracker", systemImage: "checkmark.seal")
                            trackerCard
                            monthlyTimetableLink
                        } else {
                            DIEmptyState(
                                systemImage: "sun.horizon",
                                titleKey: "Prayer times unavailable",
                                messageKey: "Times could not be calculated for this location today. A different high-latitude rule in Settings may help."
                            )
                        }
                    } else {
                        locationNeededSection
                    }
                    TodayOfficialSection(dependencies: dependencies)
                    // Daily spiritual companion cards follow the time-sensitive
                    // prayer and official-live information.
                    TodayDailySection(appState: appState)
                }
                .padding(DISpacing.md)
                .diResponsiveWidth()
            }
            .diScreenBackground()
            .diPageHeading("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSearchPresented = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(Text("Search"))
                }
            }
            .sheet(isPresented: $isSearchPresented) {
                GlobalSearchView(dependencies: dependencies)
            }
            .task {
                await viewModel.refresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await viewModel.refresh() }
                }
            }
            .onChange(of: appState.settings) {
                Task { await viewModel.refresh() }
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.top, DISpacing.xl)
    }

    // MARK: - Today's times

    private func timesCard(schedule: PrayerDaySchedule) -> some View {
        DICard(padding: DISpacing.sm) {
            VStack(spacing: 0) {
                // Prayer.allCases is already in chronological order.
                ForEach(Prayer.allCases) { prayer in
                    if let time = schedule.time(for: prayer) {
                        timeRow(prayer: prayer, time: time)
                        if prayer != .isha {
                            Divider()
                                .overlay(DIColor.border)
                        }
                    }
                }
            }
        }
    }

    private func timeRow(prayer: Prayer, time: Date) -> some View {
        let isNext = viewModel.isNext(prayer: prayer, time: time)
        let isCurrent = viewModel.currentPrayer == prayer
        let style = viewModel.alertStyle(for: prayer)
        return HStack(spacing: DISpacing.sm) {
            Text(LocalizedStringKey(prayer.englishName))
                .font(.body.weight(isNext ? .semibold : .regular))
                .foregroundStyle(isCurrent ? DIColor.accent : DIColor.textPrimary)
            if isCurrent {
                DIPillBadge(text: String(localized: "Now"), color: DIColor.accent)
            }
            if isNext {
                DIPillBadge(text: String(localized: "Next"), color: DIColor.primary)
            }
            Spacer(minLength: DISpacing.sm)
            Text(viewModel.timeText(time))
                .font(.body.monospacedDigit().weight(isNext ? .semibold : .regular))
                .foregroundStyle(isNext ? DIColor.primary : (isCurrent ? DIColor.accent : DIColor.textPrimary))
            alertButton(prayer: prayer, style: style)
        }
        .padding(.horizontal, DISpacing.sm)
        .padding(.vertical, DISpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous)
                .fill(isNext ? DIColor.primary.opacity(0.08) : Color.clear)
        )
    }

    private func alertButton(prayer: Prayer, style: PrayerAlertStyle) -> some View {
        Button {
            Task { await viewModel.cycleAlertStyle(for: prayer) }
        } label: {
            Image(systemName: alertIconName(for: style))
                .font(.subheadline)
                .foregroundStyle(alertIconColor(for: style))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(prayer.englishName) alert: \(style.englishName)"))
        .accessibilityHint(Text("Double tap to change the alert style."))
    }

    private func alertIconName(for style: PrayerAlertStyle) -> String {
        switch style {
        case .off: return "bell.slash"
        case .silent: return "bell"
        case .defaultSound: return "bell.fill"
        case .azanClip: return "bell.and.waves.left.and.right"
        }
    }

    private func alertIconColor(for style: PrayerAlertStyle) -> Color {
        switch style {
        case .off, .silent: return DIColor.textMuted
        case .defaultSound: return DIColor.primary
        case .azanClip: return DIColor.accent
        }
    }

    // MARK: - Ramadan

    private func ramadanCard(schedule: PrayerDaySchedule) -> some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) {
                    Image(systemName: "moon.stars.fill")
                        .foregroundStyle(DIColor.accent)
                        .accessibilityHidden(true)
                    Text("Ramadan")
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                }
                if let target = viewModel.ramadanCountdown {
                    HStack(alignment: .firstTextBaseline) {
                        if target.kind == .suhoorEnds {
                            Text("Suhoor ends in")
                                .font(.subheadline)
                                .foregroundStyle(DIColor.textPrimary)
                        } else {
                            Text("Iftar in")
                                .font(.subheadline)
                                .foregroundStyle(DIColor.textPrimary)
                        }
                        Spacer()
                        Text(target.time, style: .timer)
                            .font(.title2.weight(.medium).monospacedDigit())
                            .foregroundStyle(DIColor.primary)
                    }
                }
                HStack {
                    if let fajr = schedule.time(for: .fajr) {
                        Text("Suhoor ends: \(viewModel.timeText(fajr))")
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                    }
                    Spacer()
                    if let maghrib = schedule.time(for: .maghrib) {
                        Text("Iftar: \(viewModel.timeText(maghrib))")
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tracker

    private var trackerCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                HStack(spacing: 0) {
                    ForEach(Prayer.obligatory) { prayer in
                        trackerCircle(prayer: prayer)
                    }
                }
                streakLine
                Divider()
                    .overlay(DIColor.border)
                NavigationLink {
                    PrayerTrackerDetailView(dependencies: dependencies, appState: appState)
                } label: {
                    HStack {
                        Text("View prayer history")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DIColor.primary)
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func trackerCircle(prayer: Prayer) -> some View {
        let completion = viewModel.completion(for: prayer)
        return Button {
            Task { await viewModel.cycleCompletion(for: prayer) }
        } label: {
            VStack(spacing: DISpacing.xs) {
                ZStack {
                    Circle()
                        .fill(PrayerTrackerPalette.fill(for: completion))
                    Circle()
                        .strokeBorder(PrayerTrackerPalette.stroke(for: completion), lineWidth: 1.5)
                    if let symbol = PrayerTrackerPalette.symbolName(for: completion) {
                        Image(systemName: symbol)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(PrayerTrackerPalette.symbolColor(for: completion))
                    }
                }
                .frame(width: 42, height: 42)
                Text(LocalizedStringKey(prayer.englishName))
                    .font(.caption2)
                    .foregroundStyle(DIColor.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(trackerAccessibilityLabel(prayer: prayer, completion: completion))
        .accessibilityHint(Text("Double tap to change how this prayer is marked."))
    }

    private func trackerAccessibilityLabel(prayer: Prayer, completion: PrayerCompletion) -> Text {
        switch completion {
        case .unmarked: return Text("\(prayer.englishName): not marked yet")
        case .prayed: return Text("\(prayer.englishName): prayed")
        case .jamaat: return Text("\(prayer.englishName): prayed in congregation")
        case .qaza: return Text("\(prayer.englishName): marked as Qaza")
        }
    }

    @ViewBuilder
    private var streakLine: some View {
        if let summary = viewModel.streakSummary, summary.currentStreakDays >= 2 {
            Text("MashaAllah — \(summary.currentStreakDays) days of consistent prayer.")
                .font(.footnote)
                .foregroundStyle(DIColor.primary)
        } else if let summary = viewModel.streakSummary, summary.currentStreakDays == 1 {
            Text("MashaAllah — a full day of prayer. Keep going gently.")
                .font(.footnote)
                .foregroundStyle(DIColor.primary)
        } else {
            Text("Every prayer you mark is a fresh beginning.")
                .font(.footnote)
                .foregroundStyle(DIColor.textMuted)
        }
    }

    // MARK: - Monthly timetable link

    private var monthlyTimetableLink: some View {
        NavigationLink {
            MonthlyTimetableView(dependencies: dependencies, appState: appState)
        } label: {
            DICard {
                HStack(spacing: DISpacing.sm) {
                    Image(systemName: "calendar")
                        .foregroundStyle(DIColor.accent)
                        .accessibilityHidden(true)
                    Text("Monthly Timetable")
                        .font(.body.weight(.medium))
                        .foregroundStyle(DIColor.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Location needed

    private var locationNeededSection: some View {
        DICard {
            VStack(spacing: DISpacing.md) {
                DIEmptyState(
                    systemImage: "location.slash",
                    titleKey: "A location is needed for prayer times",
                    messageKey: "Prayer times are calculated privately on your device once a location is set."
                )
                Button {
                    Task { await viewModel.requestDeviceLocation() }
                } label: {
                    if viewModel.isRequestingLocation {
                        ProgressView()
                            .tint(DIColor.onPrimary)
                    } else {
                        Text("Use My Current Location")
                    }
                }
                .buttonStyle(DIPrimaryButtonStyle())
                .disabled(viewModel.isRequestingLocation)

                if viewModel.locationRequestFailed {
                    Text("We couldn't determine your location. You can allow location access in iOS Settings, or choose a city from the More tab under Settings.")
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Prefer a specific city? You can choose one anytime from the More tab under Settings.")
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
