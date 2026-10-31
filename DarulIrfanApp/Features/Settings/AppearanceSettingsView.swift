import SwiftUI

/// Appearance settings: theme, reader text size and the Urdu lettering.
/// The app language is the first row of Settings now (and stays on Today).
@MainActor
struct AppearanceSettingsView: View {
    private let appState: AppState
    @AppStorage(AppFonts.nastaliqPreferenceKey) private var urduNastaliq = false

    init(appState: AppState) {
        self.appState = appState
    }

    var body: some View {
        List {
            themeSection
            readerScaleSection
            if AppFonts.appleNastaliqName != nil {
                urduLetteringSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .toggleStyle(SwitchToggleStyle(tint: DIColor.primary))
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Theme

    private var themeSection: some View {
        Section {
            Picker("Theme", selection: themeBinding) {
                ForEach(AppTheme.allCases) { theme in
                    Text(LocalizedStringKey(theme.settingsDisplayName)).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(DIColor.surface)
        } header: {
            SettingsSectionHeader(titleKey: "Theme", systemImage: "circle.lefthalf.filled")
        } footer: {
            Text("System follows your device's light or dark appearance.")
        }
    }

    private var themeBinding: Binding<AppTheme> {
        SettingsBinding.value(
            in: appState,
            get: { $0.theme },
            set: { settings, theme in settings.theme = theme }
        )
    }

    // MARK: - Reader text size

    private var readerScaleSection: some View {
        Section {
            Picker(selection: readerScaleBinding) {
                ForEach(ReaderFontScale.allCases) { scale in
                    Text(LocalizedStringKey(scale.settingsDisplayName)).tag(scale)
                }
            } label: {
                Text("Reader Text Size")
                    .foregroundStyle(DIColor.textPrimary)
            }
            .listRowBackground(DIColor.surface)
        } header: {
            SettingsSectionHeader(titleKey: "Reading", systemImage: "textformat.size")
        } footer: {
            Text("Applies to the Quran and Library reading screens, on top of your system text size.")
        }
    }

    // MARK: - Urdu lettering

    /// Offered only where Apple's own Nastaliq is on the device.
    private var urduLetteringSection: some View {
        Section {
            Toggle(isOn: $urduNastaliq) {
                Text("Urdu in Nastaliq")
                    .foregroundStyle(DIColor.textPrimary)
            }
            .tint(DIColor.primary)
            .listRowBackground(DIColor.surface)
        } footer: {
            Text("Off shows Urdu in the standard lettering, which always joins. Turn it on for Nastaliq; reopen a page to see the change.")
        }
    }

    private var readerScaleBinding: Binding<ReaderFontScale> {
        SettingsBinding.value(
            in: appState,
            get: { $0.readerFontScale },
            set: { settings, scale in settings.readerFontScale = scale }
        )
    }
}

// MARK: - Display names (kept file-private to avoid clashing with other features)

private extension AppTheme {
    var settingsDisplayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

private extension ReaderFontScale {
    var settingsDisplayName: String {
        switch self {
        case .small: return "Small"
        case .standard: return "Standard"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }
}
