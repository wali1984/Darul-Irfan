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
        .navigationTitle("Calculation")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Method

    private var methodSection: some View {
        Section {
            Picker("Calculation Method", selection: methodBinding) {
                ForEach(CalculationMethodChoice.allCases) { method in
                    Text(LocalizedStringKey(method.englishName)).tag(method)
                }
            }
            .pickerStyle(.navigationLink)
            .listRowBackground(DIColor.surface)
        } footer: {
            Text("Choose the convention used by your local community. University of Islamic Sciences, Karachi is common in Pakistan.")
        }
    }

    private var methodBinding: Binding<CalculationMethodChoice> {
        SettingsBinding.value(
            in: appState,
            get: { $0.calculation.method },
            set: { settings, method in settings.calculation.method = method }
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
            Text("Custom Angles")
        } footer: {
            Text("When the Isha interval is set, Isha is that many minutes after Maghrib and the Isha angle is not used.")
        }
    }

    private func angleStepper(_ titleKey: LocalizedStringKey, value: Binding<Double>) -> some View {
        Stepper(value: value, in: 4.0...24.0, step: 0.5) {
            HStack {
                Text(titleKey)
                    .foregroundStyle(DIColor.textPrimary)
                Spacer(minLength: DISpacing.sm)
                Text(verbatim: "\(value.wrappedValue.formatted(.number.precision(.fractionLength(1))))°")
                    .foregroundStyle(DIColor.textMuted)
                    .monospacedDigit()
            }
        }
    }

    private var ishaIntervalStepper: some View {
        let binding = SettingsBinding.value(
            in: appState,
            get: { $0.calculation.customAngles.ishaIntervalMinutes },
            set: { settings, minutes in settings.calculation.customAngles.ishaIntervalMinutes = minutes }
        )
        return Stepper(value: binding, in: 0...120, step: 5) {
            HStack {
                Text("Isha Interval")
                    .foregroundStyle(DIColor.textPrimary)
                Spacer(minLength: DISpacing.sm)
                if binding.wrappedValue == 0 {
                    Text("Off")
                        .foregroundStyle(DIColor.textMuted)
                } else {
                    Text("\(binding.wrappedValue) min")
                        .foregroundStyle(DIColor.textMuted)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Asr & high latitude

    private var juristicSection: some View {
        Section {
            Picker("Asr Method", selection: asrBinding) {
                ForEach(AsrMethodChoice.allCases) { method in
                    Text(LocalizedStringKey(method.englishName)).tag(method)
                }
            }
            .listRowBackground(DIColor.surface)

            Picker("High Latitude Rule", selection: highLatitudeBinding) {
                ForEach(HighLatitudeRuleChoice.allCases) { rule in
                    Text(LocalizedStringKey(rule.englishName)).tag(rule)
                }
            }
            .listRowBackground(DIColor.surface)
        } footer: {
            Text("The high-latitude rule adjusts Fajr and Isha in places where twilight lasts unusually long. Automatic follows the recommended rule for your location.")
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
        } footer: {
            Text("Fine-tune each prayer by a few minutes to match your local mosque timetable.")
        }
    }

    private var adjustedPrayerCount: Int {
        Prayer.allCases.filter { prayer in
            calculation.adjustments.offset(for: prayer) != 0
        }.count
    }
}
