import SwiftUI

/// Hijri calendar settings: a ±2 day offset with a live preview of today's
/// Hijri date so the adjustment is immediately visible.
@MainActor
struct HijriSettingsView: View {
    private let dependencies: AppDependencies
    private let appState: AppState
    @State private var hijriPreview: String = ""

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
        .navigationTitle("Hijri Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshPreview()
        }
        .onChange(of: appState.settings.hijri.dayOffset) {
            refreshPreview()
        }
    }

    // MARK: - Today preview

    private var todaySection: some View {
        Section {
            LabeledContent("Gregorian") {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide).year())
            }
            .listRowBackground(DIColor.surface)

            LabeledContent("Hijri") {
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
                    Text("Day Offset")
                        .foregroundStyle(DIColor.textPrimary)
                    Spacer(minLength: DISpacing.sm)
                    offsetLabel
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textMuted)
                        .monospacedDigit()
                }
            }
            .listRowBackground(DIColor.surface)
        } header: {
            SettingsSectionHeader(titleKey: "Day Offset", systemImage: "plusminus.circle.fill")
        } footer: {
            Text("Adjust by up to two days if your local moon sighting differs from the calculated Umm al-Qura calendar. Islamic day reminders follow this setting.")
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
            for: Date(),
            offsetDays: appState.settings.hijri.dayOffset,
            locale: Locale.current
        )
    }
}
