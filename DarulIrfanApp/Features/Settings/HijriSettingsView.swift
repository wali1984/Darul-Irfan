import SwiftUI

/// Hijri calendar settings: a ±2 day offset with a live preview of today's
/// Hijri date so the adjustment is immediately visible.
@MainActor
struct HijriSettingsView: View {
    private let dependencies: AppDependencies
    private let appState: AppState
    @State private var hijriPreview: String = ""
    @State private var calculatedPreview: String = ""
    @State private var previewNow = Date()

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
    }

    var body: some View {
        List {
            todaySection
            offsetSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Local moon sighting")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                previewNow = Date(); refreshPreview()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .onChange(of: appState.settings.hijri.dayOffset) {
            refreshPreview()
        }
        .onChange(of: appState.activePlace) { _, _ in refreshPreview() }
    }

    // MARK: - Today preview

    private var todaySection: some View {
        Section {
            LabeledContent("Gregorian") {
                Text(previewNow, format: Date.FormatStyle(date: .complete, time: .omitted, timeZone: appState.activePlace?.timeZone ?? .current))
            }
            .listRowBackground(DIColor.surface)

            LabeledContent("Calculated Hijri date") { Text(calculatedPreview).multilineTextAlignment(.trailing) }
                .listRowBackground(DIColor.surface)
            LabeledContent("Your local date") {
                Text(hijriPreview)
                    .foregroundStyle(DIColor.primary)
                    .multilineTextAlignment(.trailing)
            }
            .listRowBackground(DIColor.surface)
        } header: {
            SettingsSectionHeader(titleKey: "Today", systemImage: "calendar")
        }
    }

    // MARK: - Offset

    private var offsetSection: some View {
        Section {
            Stepper(value: offsetBinding, in: -2...2) {
                HStack {
                    Text("Date correction")
                        .foregroundStyle(DIColor.textPrimary)
                    Spacer(minLength: DISpacing.sm)
                    offsetLabel
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textMuted)
                        .monospacedDigit()
                }
            }
            .listRowBackground(DIColor.surface)
            Button("Use calculated date") { offsetBinding.wrappedValue = 0 }
                .disabled(appState.settings.hijri.dayOffset == 0)
                .listRowBackground(DIColor.surface)
        } header: {
            SettingsSectionHeader(titleKey: "Local moon sighting", systemImage: "plusminus.circle.fill")
        } footer: {
            Text("Adjust by up to two days if your local moon sighting differs from the calculated Umm al-Qura calendar. The Hijri dates and Islamic days across the app follow this setting.")
        }
    }

    private var offsetBinding: Binding<Int> {
        SettingsBinding.value(
            in: appState,
            get: { $0.hijri.dayOffset },
            set: { settings, offset in settings.hijri.dayOffset = offset }
        )
    }

    private var offsetLabel: Text {
        let offset = appState.settings.hijri.dayOffset
        if offset == 0 {
            return Text("No adjustment")
        }
        let value = offset.formatted(.number.sign(strategy: .always(includingZero: false)))
        if abs(offset) == 1 {
            return Text("\(value) day")
        }
        return Text("\(value) days")
    }

    private func refreshPreview() {
        hijriPreview = dependencies.hijri.hijriDateText(
            for: previewNow,
            offsetDays: appState.settings.hijri.dayOffset,
            locale: LanguageManager.locale(for: appState.settings.language),
            timeZone: appState.activePlace?.timeZone ?? .current
        )
        calculatedPreview = dependencies.hijri.hijriDateText(for: previewNow, offsetDays: 0, locale: LanguageManager.locale(for: appState.settings.language), timeZone: appState.activePlace?.timeZone ?? .current)
    }
}
