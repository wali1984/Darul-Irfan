import SwiftUI

/// The Prayer times page (board Prayer), pushed from Today's prayer card
/// ("All times and alerts"): the place and date with Change; the day's six
/// times with each alert bell, the next one lit, then how the times are
/// calculated and whether alerts will arrive; the Ramadan card in Ramadan;
/// the prayer tracker for any day up to today; and the monthly timetable
/// and Qibla. Without a place, or when the times cannot be calculated, it
/// says so as the Prayer tab always has.
@MainActor
struct PrayerTimesView: View {
    let viewModel: PrayerViewModel
    let dependencies: AppDependencies
    let appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                placeLine
                content
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .background { TodayPageGlow() }
        .diScreenBackground()
        .diPageHeading("Prayer times")
        .toolbar {
            if viewModel.todaySchedule != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: viewModel.todayShareText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(Text("Share today's times"))
                }
            }
        }
        .task { await viewModel.reloadTrackerWeek() }
        .refreshable {
            await viewModel.refresh()
            await viewModel.reloadTrackerWeek()
        }
    }

    // MARK: - Place and date

    /// "Lahore · Friday, 30 October", and Change, which opens the location
    /// settings.
    private var placeLine: some View {
        HStack(spacing: DISpacing.sm) {
            Text(verbatim: placeAndDate)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DIColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                LocationSettingsView(dependencies: dependencies, appState: appState)
            } label: {
                Text("Change")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TodayPalette.emerald)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.top, -DISpacing.sm)
    }

    private var placeAndDate: String {
        [appState.activePlace?.name ?? "", viewModel.gregorianShortText]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, DISpacing.xl)
        } else {
            if appState.activePlace == nil {
                PrayerLocationNeededCard(viewModel: viewModel)
            } else if let schedule = viewModel.todaySchedule {
                PrayerTimesListCard(viewModel: viewModel, schedule: schedule, dependencies: dependencies, appState: appState)
                    .diAppear()
                if viewModel.isRamadan {
                    PrayerRamadanCard(viewModel: viewModel, schedule: schedule)
                        .diAppear(delay: 0.04)
                }
            } else {
                DIEmptyState(
                    systemImage: "sun.horizon",
                    titleKey: "Prayer times unavailable",
                    messageKey: "Times could not be calculated for this location today. A different high-latitude rule in Settings may help."
                )
                .todayGlass(cornerRadius: 26)
            }
            // The tracker needs no times: prayers can be marked wherever
            // the phone is.
            PrayerWeekTrackerCard(viewModel: viewModel, dependencies: dependencies, appState: appState)
                .diAppear(delay: 0.08)
            PrayerTimesShortcuts(dependencies: dependencies, appState: appState)
                .diAppear(delay: 0.12)
        }
    }
}

// MARK: - Times

/// The day's six times, the next one lit with a sheen, each with its alert
/// bell (off, silent, sound, azan), then the method line, the method
/// suggestion when it applies, and whether the alerts will arrive.
@MainActor
struct PrayerTimesListCard: View {
    let viewModel: PrayerViewModel
    let schedule: PrayerDaySchedule
    let dependencies: AppDependencies
    let appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Prayer.allCases is already in chronological order.
            ForEach(Prayer.allCases) { prayer in
                if let time = schedule.time(for: prayer) {
                    row(prayer: prayer, time: time)
                }
            }
            footer
        }
        .padding(6)
        .todayGlass(cornerRadius: 26)
    }

    private func row(prayer: Prayer, time: Date) -> some View {
        let isNext = viewModel.isNext(prayer: prayer, time: time)
        let isCurrent = viewModel.currentPrayer == prayer
        return HStack(spacing: 12) {
            HStack(spacing: DISpacing.sm) {
                Text(LocalizedStringKey(prayer.englishName))
                    .font(.body.weight(isNext ? .heavy : .semibold))
                    .foregroundStyle(isNext ? Color.white : DIColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if isCurrent {
                    badge(Text("Now"), ink: Color.white, fill: AnyShapeStyle(Color(hex: 0xB48A2C)))
                }
                if isNext {
                    badge(Text("Next"), ink: TodayGradients.onGold, fill: AnyShapeStyle(TodayGradients.gold))
                }
            }
            Spacer(minLength: DISpacing.sm)
            Text(verbatim: viewModel.timeText(time))
                .font(.body.weight(.bold).monospacedDigit())
                .foregroundStyle(isNext ? Color(hex: 0xFFE3A0) : DIColor.textPrimary)
                .lineLimit(1)
            PrayerAlertBell(viewModel: viewModel, prayer: prayer, onEmerald: isNext)
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(minHeight: 56)
        .background { rowBackground(isNext) }
    }

    private func badge(_ text: Text, ink: Color, fill: AnyShapeStyle) -> some View {
        text
            .font(.caption2.weight(.heavy))
            .textCase(.uppercase)
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(fill, in: Capsule())
    }

    @ViewBuilder
    private func rowBackground(_ isNext: Bool) -> some View {
        if isNext {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(TodayGradients.nextRow)
                .diShimmer()
                .shadow(color: Color(hex: 0x0B7250).opacity(0.45), radius: 11, y: 8)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DISpacing.xs) {
            TodayMethodLine(appState: appState, showsPlace: false)
            TodayMethodSuggestion(appState: appState)
            TodayReminderStatus(dependencies: dependencies, appState: appState)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TodayPalette.rowEdge)
                .frame(height: 1)
        }
        .padding(.top, DISpacing.xs)
    }
}

/// A prayer's alert bell: a tap moves it on (Off, Silent, Default Sound,
/// Azan Clip, and round again) and saves it, which reschedules the alerts.
@MainActor
struct PrayerAlertBell: View {
    let viewModel: PrayerViewModel
    let prayer: Prayer
    /// On the lit row of the next prayer the bell is white.
    var onEmerald = false

    var body: some View {
        let style = viewModel.alertStyle(for: prayer)
        let styleName = String(localized: String.LocalizationValue(style.englishName))
        let name = String(localized: String.LocalizationValue(prayer.englishName))
        Button {
            DIHaptics.soft()
            Task { await viewModel.cycleAlertStyle(for: prayer) }
        } label: {
            Image(systemName: Self.iconName(for: style))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(onEmerald ? Color.white : Self.iconColor(for: style))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(name) alert: \(styleName)"))
        .accessibilityHint(Text("Double tap to change the alert style."))
    }

    static func iconName(for style: PrayerAlertStyle) -> String {
        switch style {
        case .off: return "bell.slash"
        case .silent: return "bell"
        case .defaultSound: return "bell.fill"
        case .azanClip: return "bell.and.waves.left.and.right"
        }
    }

    static func iconColor(for style: PrayerAlertStyle) -> Color {
        switch style {
        case .off, .silent: return DIColor.textMuted
        case .defaultSound: return TodayPalette.emerald
        case .azanClip: return TodayPalette.accent
        }
    }
}

// MARK: - Ramadan

/// During Ramadan: the countdown to the end of Suhoor or to Iftar, and
/// both of today's times.
@MainActor
struct PrayerRamadanCard: View {
    let viewModel: PrayerViewModel
    let schedule: PrayerDaySchedule

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            HStack(spacing: DISpacing.sm) {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(TodayPalette.accent)
                    .accessibilityHidden(true)
                Text("Ramadan")
                    .font(.title3.weight(.heavy))
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
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(TodayPalette.emerald)
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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayGlass(cornerRadius: 26)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Location needed

/// Before a place is set: why one is needed, Use My Current Location, and
/// where a city can be chosen instead.
@MainActor
struct PrayerLocationNeededCard: View {
    let viewModel: PrayerViewModel

    var body: some View {
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
                Text("We couldn't determine your location. You can allow location access in iOS Settings, or choose a city in the Halqah tab under Settings.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .multilineTextAlignment(.center)
            } else {
                Text("Prefer a specific city? You can choose one anytime in the Halqah tab under Settings.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DISpacing.md)
        .frame(maxWidth: .infinity)
        .todayGlass(cornerRadius: 26)
    }
}

// MARK: - Timetable and Qibla

/// The month's timetable (emerald) and the Qibla (gold), side by side.
@MainActor
struct PrayerTimesShortcuts: View {
    let dependencies: AppDependencies
    let appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink {
                MonthlyTimetableView(dependencies: dependencies, appState: appState)
            } label: {
                shortcut(titleKey: "Monthly timetable", systemImage: "calendar", gold: false)
            }
            .buttonStyle(DIPressableStyle())
            NavigationLink {
                QiblaCompassView(dependencies: dependencies, appState: appState)
            } label: {
                shortcut(titleKey: "Qibla", systemImage: "location.north.line", gold: true)
            }
            .buttonStyle(DIPressableStyle())
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func shortcut(titleKey: LocalizedStringKey, systemImage: String, gold: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .accessibilityHidden(true)
            Text(titleKey)
                .font(.subheadline.weight(.bold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(gold ? TodayGradients.onGold : Color.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 60, maxHeight: .infinity)
        .background(
            gold ? AnyShapeStyle(TodayGradients.gold) : AnyShapeStyle(TodayGradients.emerald),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .shadow(color: gold ? DIColor.goldGlow.opacity(0.35) : Color(hex: 0x0B7250).opacity(0.4), radius: 10, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
