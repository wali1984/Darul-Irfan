import SwiftUI

/// Appearance settings: theme, reader text size and the Urdu lettering.
/// The app language is the first row of Settings now (and stays on Today).
@MainActor
struct AppearanceSettingsView: View {
    private let appState: AppState
    @AppStorage(AppFonts.nastaliqPreferenceKey) private var urduNastaliq = true

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
            DISegmentedControl(items: AppTheme.allCases, title: { LocalizedStringKey($0.settingsDisplayName) }, selection: themeBinding)
                .accessibilityLabel(Text("Theme"))
            .listRowBackground(DIColor.surface)
        } header: {
            SettingsSectionHeader(titleKey: "Theme", systemImage: "circle.lefthalf.filled")
        } footer: {
            Text("Auto uses sunrise and sunset at your selected location. Light or Dark stays on permanently. Without solar times, Auto follows your phone.")
                .foregroundStyle(DIColor.textMuted)
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
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Reader Text Size").foregroundStyle(DIColor.textPrimary)
                Menu {
                    Picker("Reader Text Size", selection: readerScaleBinding) {
                        ForEach(ReaderFontScale.allCases) { scale in
                            Text(LocalizedStringKey(scale.settingsDisplayName)).tag(scale)
                        }
                    }
                } label: {
                    Label(LocalizedStringKey(readerScaleBinding.wrappedValue.settingsDisplayName), systemImage: "chevron.up.chevron.down")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(DISecondaryButtonStyle())
                .accessibilityLabel(Text("Reader Text Size"))
                .accessibilityValue(Text(LocalizedStringKey(readerScaleBinding.wrappedValue.settingsDisplayName)))
            }
            .listRowBackground(DIColor.surface)
        } header: {
            SettingsSectionHeader(titleKey: "Reading", systemImage: "textformat.size")
        } footer: {
            Text("Applies to the Quran and Library reading screens, on top of your system text size.")
                .foregroundStyle(DIColor.textMuted)
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
                .foregroundStyle(DIColor.textMuted)
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
        case .automatic: return "Auto"
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
