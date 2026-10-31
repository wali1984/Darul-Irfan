import SwiftUI

/// A screen of the app that global search finds by its name, under "In the
/// app": the everyday tools, the private groups and each settings screen.
/// Each opens the screen it names, as the button that leads to it does.
enum SearchAppDestination: String, CaseIterable, Identifiable {
    case qibla
    case tasbih
    case duas
    case names
    case islamicDays
    case myDay
    case focus
    case notes
    case fasting
    case timetable
    case tools
    case privateGroups
    case settings
    case language
    case location
    case calculation
    case manualOffsets
    case notifications
    case appearance
    case hijri
    case contentStorage
    case officialAlerts
    case privacy
    case about

    var id: String { rawValue }

    /// The names it is shown and found by, as keys of the string catalogue:
    /// the name on its button, then the title of its screen.
    var nameKeys: [String] {
        switch self {
        case .qibla: return ["Qibla", "Qibla Compass"]
        case .tasbih: return ["Tasbih", "Tasbih Counters"]
        case .duas: return ["Duas"]
        case .names: return ["99 Names", "99 Names of Allah"]
        case .islamicDays: return ["Islamic days"]
        case .myDay: return ["My Day"]
        case .focus: return ["Your Daily Personal Zikr", "Focus timer"]
        case .notes: return ["Private notes"]
        case .fasting: return ["Fasting record"]
        case .timetable: return ["Monthly timetable"]
        case .tools: return ["All tools", "Tools"]
        case .privateGroups: return ["Private groups"]
        case .settings: return ["Settings"]
        case .language: return ["Language", "App Language"]
        case .location: return ["Location"]
        // "Prayer calculation" is the row's name in the redesigned Settings.
        case .calculation: return ["Calculation", "Prayer calculation"]
        case .manualOffsets: return ["Manual Adjustments", "Per-Prayer Offsets"]
        case .notifications: return ["Notifications"]
        case .appearance: return ["Appearance"]
        case .hijri: return ["Hijri Calendar"]
        case .contentStorage: return ["Content & Storage"]
        case .officialAlerts: return ["Official Alerts & Privacy"]
        case .privacy: return ["Privacy"]
        case .about: return ["About"]
        }
    }

    var titleKey: LocalizedStringKey {
        LocalizedStringKey(nameKeys.first ?? rawValue)
    }

    var systemImage: String {
        switch self {
        case .qibla: return "location.north.line"
        case .tasbih: return "hand.tap"
        case .duas: return "hands.and.sparkles"
        case .names: return "sparkles"
        case .islamicDays: return "star.circle"
        case .myDay: return "checklist"
        case .focus: return "timer"
        case .notes: return "note.text"
        case .fasting: return "moon.haze"
        case .timetable: return "calendar"
        case .tools: return "square.grid.2x2"
        case .privateGroups: return "lock.shield"
        case .settings: return "gearshape"
        case .language: return "character.bubble"
        case .location: return "location.fill"
        case .calculation: return "sun.and.horizon.fill"
        case .manualOffsets: return "slider.horizontal.3"
        case .notifications: return "bell.fill"
        case .appearance: return "paintbrush.fill"
        case .hijri: return "moon.stars.fill"
        case .contentStorage: return "internaldrive.fill"
        case .officialAlerts: return "dot.radiowaves.left.and.right"
        case .privacy: return "hand.raised.fill"
        case .about: return "info.circle.fill"
        }
    }

    /// Where it lives, shown under its name.
    var areaKey: LocalizedStringKey {
        switch self {
        case .privateGroups, .about:
            return "Halqah"
        case .settings, .language, .location, .calculation, .manualOffsets, .notifications, .appearance,
             .hijri, .contentStorage, .officialAlerts, .privacy:
            return "Settings"
        default:
            return "Tools"
        }
    }

    /// Whether this build offers it.
    var isAvailable: Bool {
        self != .privateGroups || MemberGroupsFeature.isEnabled
    }

    // MARK: Matching

    /// The destinations whose name holds the query, in English, in the app's
    /// language or in Urdu, however it was typed: any case, with or without
    /// accents or harakat, on an Arabic or an Urdu keyboard. Two letters at
    /// least, so one letter does not list half the app.
    static func matches(
        for query: String,
        names: (SearchAppDestination) -> [String] = SearchAppDestination.localizedNames
    ) -> [SearchAppDestination] {
        let needle = fold(query)
        guard needle.count >= 2 else { return [] }
        return allCases.filter { destination in
            destination.isAvailable && names(destination).contains { fold($0).contains(needle) }
        }
    }

    /// Its names as written in the catalogue, in the app's language and in
    /// Urdu.
    static func localizedNames(_ destination: SearchAppDestination) -> [String] {
        destination.nameKeys.flatMap { key -> [String] in
            var names = [key, String(localized: String.LocalizationValue(key))]
            if let bundle = urduBundle {
                names.append(bundle.localizedString(forKey: key, value: nil, table: nil))
            }
            return names
        }
    }

    /// The Urdu strings, whatever the app's language.
    private static let urduBundle: Bundle? = Bundle.main
        .path(forResource: "ur", ofType: "lproj")
        .flatMap { Bundle(path: $0) }

    /// The form names and queries are compared in.
    static func fold(_ text: String) -> String {
        SearchNormalizer.normalize(text)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The screen a destination names, built as its own button builds it.
@MainActor
struct SearchAppDestinationScreen: View {
    let destination: SearchAppDestination
    let dependencies: AppDependencies
    let appState: AppState

    var body: some View {
        switch destination {
        case .qibla:
            QiblaCompassView(dependencies: dependencies, appState: appState)
        case .tasbih:
            TasbihListView(trackerRepository: dependencies.trackerRepository, devotionalMetrics: dependencies.devotionalMetrics)
        case .duas:
            DuasView()
        case .names:
            NamesOfAllahView()
        case .islamicDays:
            IslamicDaysView(hijri: dependencies.hijri, appState: appState)
        case .myDay:
            MyDayView(dependencies: dependencies, appState: appState)
        case .focus:
            FocusTimerView(dependencies: dependencies, appState: appState)
        case .notes:
            NotesView()
        case .fasting:
            FastingView(dependencies: dependencies, appState: appState)
        case .timetable:
            MonthlyTimetableView(dependencies: dependencies, appState: appState)
        case .tools:
            ToolsView(dependencies: dependencies, appState: appState)
        case .privateGroups:
            GroupsHomeView(dependencies: dependencies)
        case .settings, .language:
            // Language is the first row of Settings.
            SettingsHomeView(dependencies: dependencies, appState: appState)
        case .location:
            LocationSettingsView(dependencies: dependencies, appState: appState)
        case .calculation:
            CalculationSettingsView(appState: appState)
        case .manualOffsets:
            ManualOffsetsView(appState: appState)
        case .notifications:
            NotificationSettingsView(dependencies: dependencies, appState: appState)
        case .appearance:
            AppearanceSettingsView(appState: appState)
        case .hijri:
            HijriSettingsView(dependencies: dependencies, appState: appState)
        case .contentStorage:
            ContentStorageSettingsView(dependencies: dependencies, appState: appState)
        case .officialAlerts:
            // The official alerts live on the one Notifications screen now.
            NotificationSettingsView(dependencies: dependencies, appState: appState)
        case .privacy:
            PrivacySettingsView(appState: appState, dependencies: dependencies)
        case .about:
            AboutView()
        }
    }
}

/// One "In the app" result: the screen's glyph, its name and where it lives.
struct SearchAppDestinationRow: View {
    let destination: SearchAppDestination

    var body: some View {
        DIElevatedCard(padding: DISpacing.md) {
            HStack(spacing: DISpacing.md) {
                Image(systemName: destination.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(DiscoverStyle.orb(gold: false)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.titleKey)
                        .font(.headline)
                        .foregroundStyle(DIColor.textPrimary)
                    Text(destination.areaKey)
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
