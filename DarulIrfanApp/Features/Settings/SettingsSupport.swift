import SwiftUI

/// A lifted section header for the settings Forms: a small gold accent glyph
/// beside a warm, non-shouty label (no forced uppercase), so grouped lists read
/// as part of the reverent design system rather than a stock iOS Form.
struct SettingsSectionHeader: View {
    let titleKey: LocalizedStringKey
    let systemImage: String

    var body: some View {
        HStack(spacing: DISpacing.xs) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DIColor.accent)
                .accessibilityHidden(true)
            Text(titleKey)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DIColor.textMuted)
        }
        .textCase(nil)
        .padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A slim branded banner for settings screens — an emerald gradient strip with
/// a faint octagram watermark and the seal, giving the Form a premium opening
/// without a full hero.
struct SettingsBrandBanner: View {
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey

    var body: some View {
        ZStack {
            DIGradient.emerald
            DIOctagram(innerRatio: 0.5)
                .stroke(Color.white, lineWidth: 1.2)
                .frame(width: 150, height: 150)
                .opacity(0.07)
                .offset(x: 120, y: -20)
                .accessibilityHidden(true)

            HStack(spacing: DISpacing.md) {
                DISealEmblem(diameter: 46, glow: true)
                    .diBreathingGlow(color: DIColor.goldGlow, maxRadius: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleKey)
                        .font(DIFont.subheading)
                        .foregroundStyle(.white)
                    Text(subtitleKey)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
            }
            .padding(DISpacing.md)
        }
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous))
        .shadow(color: DIColor.primaryDeep.opacity(0.30), radius: 12, x: 0, y: 6)
        .accessibilityElement(children: .combine)
    }
}

/// Builds SwiftUI bindings whose writes flow through
/// `AppState.updateSettings`, so every settings mutation is persisted and
/// triggers the notification/widget side effects in one place.
enum SettingsBinding {
    @MainActor
    static func value<Value>(
        in appState: AppState,
        get: @escaping (AppSettings) -> Value,
        set: @escaping (inout AppSettings, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { get(appState.settings) },
            set: { newValue in
                Task { @MainActor in
                    await appState.updateSettings { settings in
                        set(&settings, newValue)
                    }
                }
            }
        )
    }
}
