import SwiftUI

/// Every setting, in the order the redesign lists them: Language first, then
/// Location, Prayer calculation and Notifications (one screen for every
/// alert and reminder); then Appearance, the Hijri calendar, Content and
/// storage, Privacy and the licences.
enum SettingsEntry: String, CaseIterable, Identifiable {
    case language
    case location
    case prayerCalculation
    case notifications
    case appearance
    case hijriCalendar
    case contentStorage
    case privacy
    case licences

    var id: String { rawValue }

    /// The row's name: an English key the string catalogue translates.
    var title: String {
        switch self {
        case .language: return "Language"
        case .location: return "Location"
        case .prayerCalculation: return "Prayer calculation"
        case .notifications: return "Notifications"
        case .appearance: return "Appearance"
        case .hijriCalendar: return "Hijri Calendar"
        case .contentStorage: return "Content & Storage"
        case .privacy: return "Privacy"
        case .licences: return "Licences"
        }
    }

    var systemImage: String {
        switch self {
        case .language: return "globe"
        case .location: return "location.fill"
        case .prayerCalculation: return "clock.fill"
        case .notifications: return "bell.fill"
        case .appearance: return "circle.lefthalf.filled"
        case .hijriCalendar: return "moon.stars.fill"
        case .contentStorage: return "internaldrive.fill"
        case .privacy: return "lock.shield.fill"
        case .licences: return "doc.text.fill"
        }
    }

    /// Notifications, which gathers every alert, is the gold row.
    var isGold: Bool { self == .notifications }
}

/// The one place for settings: the Halqah tab shows this list at its root,
/// and `SettingsHomeView` on a page of its own. Each row glances at its
/// current value where that helps.
@MainActor
struct SettingsList: View {
    let dependencies: AppDependencies
    let appState: AppState
    /// The Halqah tab's own Halqah notices switch, so a change made in
    /// Notifications shows on the tab at once. Nil makes Notifications use
    /// one of its own.
    var halqahNotices: HalqahNoticesModel? = nil

    var body: some View {
        HalqahGlassList {
            ForEach(Array(SettingsEntry.allCases.enumerated()), id: \.element) { index, entry in
                if index > 0 {
                    HalqahRowDivider()
                }
                row(for: entry)
            }
        }
    }

    @ViewBuilder
    private func row(for entry: SettingsEntry) -> some View {
        switch entry {
        case .language:
            languageRow
        case .location:
            SettingsRowLink(entry: entry, value: locationValue) {
                LocationSettingsView(dependencies: dependencies, appState: appState)
            }
        case .prayerCalculation:
            SettingsRowLink(entry: entry, value: Text(LocalizedStringKey(appState.settings.calculation.method.englishName))) {
                CalculationSettingsView(appState: appState)
            }
        case .notifications:
            SettingsRowLink(entry: entry, value: Text("All in one place")) {
                NotificationSettingsView(dependencies: dependencies, appState: appState, halqahNotices: halqahNotices)
            }
        case .appearance:
            SettingsRowLink(entry: entry, value: themeValue) {
                AppearanceSettingsView(appState: appState)
            }
        case .hijriCalendar:
            SettingsRowLink(entry: entry, value: hijriValue) {
                HijriSettingsView(dependencies: dependencies, appState: appState)
            }
        case .contentStorage:
            SettingsRowLink(entry: entry, value: nil) {
                ContentStorageSettingsView(dependencies: dependencies, appState: appState)
            }
        case .privacy:
            // Official Alerts & Privacy and Privacy are one screen now: the
            // alerts went to Notifications, the Live Activity and the
            // diagnostics choice stayed with privacy.
            SettingsRowLink(entry: entry, value: nil) {
                PrivacySettingsView(appState: appState, dependencies: dependencies)
            }
        case .licences:
            // The notices are not optional: adhan-swift is MIT, the fonts are
            // OFL and the Fajr azan recording is CC BY 3.0, and each requires
            // its attribution to ship in the app.
            SettingsRowLink(entry: entry, value: nil) {
                AcknowledgementsView()
            }
        }
    }

    // MARK: - Language

    /// The app language, first and one tap away: a menu, as on Today. The
    /// whole app turns to the language chosen at once.
    private var languageRow: some View {
        Menu {
            Picker("Language", selection: languageBinding) {
                ForEach(AppLanguage.allCases) { language in
                    Text(LocalizedStringKey(language.displayName)).tag(language)
                }
            }
        } label: {
            HalqahListRowLabel(
                titleKey: LocalizedStringKey(SettingsEntry.language.title),
                systemImage: SettingsEntry.language.systemImage,
                value: Text(LocalizedStringKey(appState.settings.language.displayName)),
                chevronSymbol: "chevron.up.chevron.down"
            )
        }
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { appState.settings.language },
            set: { newValue in
                DIHaptics.light()
                Task { await appState.updateSettings { $0.language = newValue } }
            }
        )
    }

    // MARK: - Value summaries

    private var locationValue: Text {
        if let place = appState.activePlace {
            return Text(place.name)
        }
        return Text("Not set")
    }

    private var themeValue: Text {
        switch appState.settings.theme {
        case .system: return Text("System")
        case .light: return Text("Light")
        case .dark: return Text("Dark")
        }
    }

    private var hijriValue: Text {
        let offset = appState.settings.hijri.dayOffset
        if offset == 0 {
            return Text("No offset")
        }
        let value = offset.formatted(.number.sign(strategy: .always(includingZero: false)))
        if abs(offset) == 1 {
            return Text("\(value) day")
        }
        return Text("\(value) days")
    }
}

/// One settings row that opens its screen.
private struct SettingsRowLink<Destination: View>: View {
    let entry: SettingsEntry
    let value: Text?
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HalqahListRowLabel(
                titleKey: LocalizedStringKey(entry.title),
                systemImage: entry.systemImage,
                value: value,
                tint: entry.isGold ? .gold : .green
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { DIHaptics.soft() })
    }
}

/// The settings on a page of their own, for anything that links to
/// "Settings"; the Halqah tab shows the same list at its root.
@MainActor
struct SettingsHomeView: View {
    private let dependencies: AppDependencies
    private let appState: AppState

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
    }

    var body: some View {
        ScrollView {
            SettingsList(dependencies: dependencies, appState: appState)
                .padding(DISpacing.md)
                .diResponsiveWidth()
        }
        .diScreenBackground()
        .navigationTitle("Settings")
    }
}
