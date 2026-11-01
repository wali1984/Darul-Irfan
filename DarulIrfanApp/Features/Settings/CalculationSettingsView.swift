import SwiftUI

/// Prayer calculation settings: method, custom angles, Asr juristic method,
/// high-latitude rule, and a link to per-prayer manual offsets.
@MainActor
struct CalculationSettingsView: View {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    private var calculation: PrayerCalculationPreferences {
        appState.settings.calculation
    }

    var body: some View {
        List {
            methodSection
            if calculation.method == .custom {
                customAnglesSection
            }
            juristicSection
            offsetsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .toggleStyle(SwitchToggleStyle(tint: DIColor.primary))
        .navigationTitle("Calculation")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Method

    private var methodSection: some View {
        Section {
            NavigationLink {
                CalculationMethodChoicesView(appState: appState)
            } label: {
                HStack {
                    Text("Calculation Method")
                    Spacer(minLength: DISpacing.sm)
                    Text(LocalizedStringKey(calculation.method.englishName))
                        .foregroundStyle(DIColor.textMuted)
                        .multilineTextAlignment(.trailing)
                }
            }
            .listRowBackground(DIColor.surface)
        } header: {
            SettingsSectionHeader(titleKey: "Method", systemImage: "sun.and.horizon.fill")
        } footer: {
            Text("Choose the convention used by your local community. University of Islamic Sciences, Karachi is common in Pakistan.")
                .foregroundStyle(DIColor.textMuted)
        }
    }

    private var methodBinding: Binding<CalculationMethodChoice> {
        SettingsBinding.value(
            in: appState,
            get: { $0.calculation.method },
            set: { settings, method in
                settings.calculation.method = method
                settings.calculation.methodConfirmed = true
            }
        )
    }

    // MARK: - Custom angles

    private var customAnglesSection: some View {
        Section {
            angleStepper(
                "Fajr Angle",
                value: SettingsBinding.value(
                    in: appState,
                    get: { $0.calculation.customAngles.fajrAngle },
                    set: { settings, angle in settings.calculation.customAngles.fajrAngle = angle }
                )
            )
            .listRowBackground(DIColor.surface)

            angleStepper(
                "Isha Angle",
                value: SettingsBinding.value(
                    in: appState,
                    get: { $0.calculation.customAngles.ishaAngle },
                    set: { settings, angle in settings.calculation.customAngles.ishaAngle = angle }
                )
            )
            .disabled(calculation.customAngles.ishaIntervalMinutes > 0)
            .listRowBackground(DIColor.surface)

            ishaIntervalStepper
                .listRowBackground(DIColor.surface)
        } header: {
            SettingsSectionHeader(titleKey: "Custom Angles", systemImage: "angle")
        } footer: {
            Text("When the Isha interval is set, Isha is that many minutes after Maghrib and the Isha angle is not used.")
                .foregroundStyle(DIColor.textMuted)
        }
    }

    private func angleStepper(_ titleKey: LocalizedStringKey, value: Binding<Double>) -> some View {
        SettingsAdjustmentRow(
            title: Text(titleKey),
            value: Text(verbatim: "\(value.wrappedValue.formatted(.number.precision(.fractionLength(1))))\u{00B0}"),
            canDecrease: value.wrappedValue > 4, canIncrease: value.wrappedValue < 24,
            decrease: { value.wrappedValue = max(4, value.wrappedValue - 0.5) },
            increase: { value.wrappedValue = min(24, value.wrappedValue + 0.5) }
        )
    }

    private var ishaIntervalStepper: some View {
        let binding = SettingsBinding.value(
            in: appState,
            get: { $0.calculation.customAngles.ishaIntervalMinutes },
            set: { settings, minutes in settings.calculation.customAngles.ishaIntervalMinutes = minutes }
        )
        return SettingsAdjustmentRow(
            title: Text("Isha Interval"),
            value: binding.wrappedValue == 0 ? Text("Off") : Text("\(binding.wrappedValue) min"),
            canDecrease: binding.wrappedValue > 0, canIncrease: binding.wrappedValue < 120,
            decrease: { binding.wrappedValue = max(0, binding.wrappedValue - 5) },
            increase: { binding.wrappedValue = min(120, binding.wrappedValue + 5) }
        )
    }

    // MARK: - Asr & high latitude

    private var juristicSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Asr Method").foregroundStyle(DIColor.textPrimary)
                Menu {
                    Picker("Asr Method", selection: asrBinding) {
                        ForEach(AsrMethodChoice.allCases) { method in
                            Text(LocalizedStringKey(method.englishName)).tag(method)
                        }
                    }
                } label: {
                    Label(LocalizedStringKey(calculation.asrMethod.englishName), systemImage: "chevron.up.chevron.down")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(DISecondaryButtonStyle())
                .accessibilityLabel(Text("Asr Method"))
                .accessibilityValue(Text(LocalizedStringKey(calculation.asrMethod.englishName)))
            }
            .listRowBackground(DIColor.surface)

            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("High Latitude Rule").foregroundStyle(DIColor.textPrimary)
                Menu {
                    Picker("High Latitude Rule", selection: highLatitudeBinding) {
                        ForEach(HighLatitudeRuleChoice.allCases) { rule in
                            Text(LocalizedStringKey(rule.englishName)).tag(rule)
                        }
                    }
                } label: {
                    Label(LocalizedStringKey(calculation.highLatitudeRule.englishName), systemImage: "chevron.up.chevron.down")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(DISecondaryButtonStyle())
                .accessibilityLabel(Text("High Latitude Rule"))
                .accessibilityValue(Text(LocalizedStringKey(calculation.highLatitudeRule.englishName)))
            }
            .listRowBackground(DIColor.surface)
        } header: {
            SettingsSectionHeader(titleKey: "Asr & High Latitude", systemImage: "moon.circle.fill")
        } footer: {
            Text("The high-latitude rule adjusts Fajr and Isha in places where twilight lasts unusually long. Automatic follows the recommended rule for your location.")
                .foregroundStyle(DIColor.textMuted)
        }
    }

    private var asrBinding: Binding<AsrMethodChoice> {
        SettingsBinding.value(
            in: appState,
            get: { $0.calculation.asrMethod },
            set: { settings, method in settings.calculation.asrMethod = method }
        )
    }

    private var highLatitudeBinding: Binding<HighLatitudeRuleChoice> {
        SettingsBinding.value(
            in: appState,
            get: { $0.calculation.highLatitudeRule },
            set: { settings, rule in settings.calculation.highLatitudeRule = rule }
        )
    }

    // MARK: - Manual offsets

    private var offsetsSection: some View {
        Section {
            NavigationLink {
                ManualOffsetsView(appState: appState)
            } label: {
                HStack {
                    Text("Manual Adjustments")
                        .foregroundStyle(DIColor.textPrimary)
                    Spacer(minLength: DISpacing.sm)
                    if adjustedPrayerCount == 0 {
                        Text("None")
                            .font(.subheadline)
                            .foregroundStyle(DIColor.textMuted)
                    } else {
                        Text("\(adjustedPrayerCount) set")
                            .font(.subheadline)
                            .foregroundStyle(DIColor.textMuted)
                    }
                }
            }
            .listRowBackground(DIColor.surface)
        } header: {
            SettingsSectionHeader(titleKey: "Adjustments", systemImage: "slider.horizontal.3")
        } footer: {
            Text("Fine-tune each prayer by a few minutes to match your local mosque timetable.")
                .foregroundStyle(DIColor.textMuted)
        }
    }

    private var adjustedPrayerCount: Int {
        Prayer.allCases.filter { prayer in
            calculation.adjustments.offset(for: prayer) != 0
        }.count
    }
}

/// Branded choice list with an explicit accessible selected state.
private struct CalculationMethodChoicesView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false

    var body: some View {
        ScrollView {
            VStack(spacing: DISpacing.sm) {
                ForEach(CalculationMethodChoice.allCases) { method in
                    let selected = appState.settings.calculation.method == method
                    Button {
                        choosing = true
                        DIHaptics.soft()
                        Task {
                            await appState.updateSettings { settings in
                                settings.calculation.method = method
                                settings.calculation.methodConfirmed = true
                            }
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: DISpacing.sm) {
                            Text(LocalizedStringKey(method.englishName))
                                .fixedSize(horizontal: false, vertical: true)
                            if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DISecondaryButtonStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .disabled(choosing)
                }
            }
            .padding(DISpacing.md)
        }
        .navigationTitle("Calculation Method")
        .navigationBarTitleDisplayMode(.inline)
        .diScreenBackground()
    }
}
