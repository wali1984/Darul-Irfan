import SwiftUI

/// Per-prayer manual minute offsets (−30…+30) applied after calculation.
@MainActor
struct ManualOffsetsView: View {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var body: some View {
        List {
            Section {
                ForEach(Prayer.allCases) { prayer in
                    offsetRow(for: prayer)
                        .listRowBackground(DIColor.surface)
                }
            } footer: {
                Text("Offsets shift each calculated time by up to 30 minutes either way. Notifications and widgets update automatically.")
            }

            if hasAnyOffset {
                Section {
                    Button("Reset All Offsets", role: .destructive) {
                        Task {
                            await appState.updateSettings { settings in
                                settings.calculation.adjustments = .none
                            }
                        }
                    }
                    .listRowBackground(DIColor.surface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Manual Adjustments")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hasAnyOffset: Bool {
        Prayer.allCases.contains { prayer in
            appState.settings.calculation.adjustments.offset(for: prayer) != 0
        }
    }

    private func offsetRow(for prayer: Prayer) -> some View {
        let binding = SettingsBinding.value(
            in: appState,
            get: { $0.calculation.adjustments.offset(for: prayer) },
            set: { settings, minutes in
                settings.calculation.adjustments.setOffset(minutes, for: prayer)
            }
        )
        return Stepper(value: binding, in: -30...30) {
            HStack {
                Text(LocalizedStringKey(prayer.englishName))
                    .foregroundStyle(DIColor.textPrimary)
                Spacer(minLength: DISpacing.sm)
                offsetLabel(binding.wrappedValue)
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
                    .monospacedDigit()
            }
        }
    }

    private func offsetLabel(_ minutes: Int) -> Text {
        let value = minutes.formatted(.number.sign(strategy: .always(includingZero: false)))
        return Text("\(value) min")
    }
}
