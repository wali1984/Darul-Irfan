import SwiftUI

/// Appearance settings: theme, app language, and reader text size.
@MainActor
struct AppearanceSettingsView: View {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var body: some View {
        List {
            themeSection
            languageSection
            readerScaleSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .diScreenBackground()
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
            Text("Theme")
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

    // MARK: - Language

    private var languageSection: some View {
        Section {
            Picker(selection: languageBinding) {
                ForEach(AppLanguage.allCases) { language in
                    Text(LocalizedStringKey(language.displayName)).tag(language)
                }
            } label: {
                Text("App Language")
                    .foregroundStyle(DIColor.textPrimary)
            }
            .listRowBackground(DIColor.surface)
        } header: {
            Text("Language")
        } footer: {
            Text("Urdu applies a right-to-left layout across the app.")
        }
    }

    private var languageBinding: Binding<AppLanguage> {
        SettingsBinding.value(
            in: appState,
            get: { $0.language },
            set: { settings, language in settings.language = language }
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
            Text("Reading")
        } footer: {
            Text("Applies to the Quran and Library reading screens, on top of your system text size.")
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
