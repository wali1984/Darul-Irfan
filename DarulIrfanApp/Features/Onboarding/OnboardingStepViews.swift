import SwiftUI

// Individual onboarding pages. The location page lives in its own file
// (OnboardingLocationStep.swift) because it carries the manual city search.

// MARK: - Shared step header

struct OnboardingStepHeader: View {
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.xs) {
            Text(titleKey)
                .font(DIFont.heading)
                .foregroundStyle(DIColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(subtitleKey)
                .font(.subheadline)
                .foregroundStyle(DIColor.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DISpacing.sm)
    }
}

// MARK: - 1. Welcome

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: DISpacing.lg) {
            hero

            Text("Accurate prayer times and gentle azan reminders, the Holy Quran with translation and tafsir, lectures and books from the Naqshbandia Owaisiah library, and guidance for daily zikr — together in one calm companion.")
                .font(.body)
                .foregroundStyle(DIColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DISpacing.sm)
        }
        .padding(.top, DISpacing.md)
    }

    private var hero: some View {
        VStack(spacing: DISpacing.md) {
            ZStack {
                Circle()
                    .stroke(DIColor.accent.opacity(0.45), lineWidth: 1.5)
                    .frame(width: 124, height: 124)
                Circle()
                    .fill(DIColor.onPrimary.opacity(0.06))
                    .frame(width: 106, height: 106)
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(DIColor.accent)
            }
            .accessibilityHidden(true)

            Text("Darul Irfan")
                .font(.system(.largeTitle, design: .serif).weight(.semibold))
                .foregroundStyle(DIColor.onPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(verbatim: "دارالعرفان")
                .font(DIFont.urduBody(scale: 1.1))
                .foregroundStyle(DIColor.accent)
                .environment(\.layoutDirection, .rightToLeft)

            Text("Light of Sacred Knowledge")
                .font(.callout.italic())
                .foregroundStyle(DIColor.onPrimary.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DISpacing.xl)
        .padding(.horizontal, DISpacing.lg)
        .background(DIColor.primaryDeep)
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous))
    }
}

// MARK: - 2. Language

struct OnboardingLanguageStep: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: DISpacing.md) {
            OnboardingStepHeader(
                titleKey: "Choose Your Language",
                subtitleKey: "You can change this anytime in Settings."
            )

            ForEach(AppLanguage.allCases) { language in
                languageCard(language)
            }
        }
    }

    private func languageCard(_ language: AppLanguage) -> some View {
        let isSelected = viewModel.selectedLanguage == language
        return Button {
            Task { await viewModel.selectLanguage(language) }
        } label: {
            HStack(spacing: DISpacing.md) {
                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text(LocalizedStringKey(language.displayName))
                        .font(.headline)
                        .foregroundStyle(DIColor.textPrimary)
                    subtitle(for: language)
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? DIColor.primary : DIColor.border)
                    .accessibilityHidden(true)
            }
            .padding(DISpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DIColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                    .stroke(isSelected ? DIColor.primary : DIColor.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func subtitle(for language: AppLanguage) -> Text {
        switch language {
        case .system: return Text("Follow your iPhone's language")
        case .english: return Text("Use English throughout the app")
        case .urdu: return Text("Use Urdu throughout the app")
        }
    }
}

// MARK: - 4. Calculation

struct OnboardingCalculationStep: View {
    @Bindable var viewModel: OnboardingViewModel

    /// Custom angles need their own editor; that lives in Settings, so the
    /// onboarding picker offers the named methods only.
    private static let methodChoices: [CalculationMethodChoice] =
        CalculationMethodChoice.allCases.filter { $0 != .custom }

    var body: some View {
        VStack(spacing: DISpacing.md) {
            OnboardingStepHeader(
                titleKey: "Prayer Time Calculation",
                subtitleKey: "These defaults suit most people. You can fine-tune angles and minute offsets later in Settings."
            )

            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    Text("Calculation Method")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.textPrimary)
                    Picker("Calculation Method", selection: $viewModel.selectedMethod) {
                        ForEach(Self.methodChoices) { method in
                            Text(LocalizedStringKey(method.englishName)).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(DIColor.primary)
                    Text(methodExplanationKey)
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                }
            }

            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    Text("Asr Method")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.textPrimary)
                    Picker("Asr Method", selection: $viewModel.selectedAsrMethod) {
                        // Hanafi first: it is the preselected default.
                        ForEach([AsrMethodChoice.hanafi, AsrMethodChoice.shafi]) { method in
                            Text(LocalizedStringKey(method.englishName)).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(asrExplanationKey)
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
        }
    }

    private var methodExplanationKey: LocalizedStringKey {
        switch viewModel.selectedMethod {
        case .karachi: return "Used across Pakistan, India, Bangladesh, and Afghanistan."
        case .muslimWorldLeague: return "A widely accepted worldwide standard."
        case .northAmerica: return "Common across the United States and Canada."
        case .egyptian: return "Used in Egypt and much of Africa."
        case .ummAlQura: return "The method used in Makkah and Saudi Arabia."
        case .moonsightingCommittee: return "Based on observed twilight across the seasons."
        case .dubai: return "Used in the United Arab Emirates."
        case .kuwait: return "Used in Kuwait."
        case .qatar: return "Used in Qatar."
        case .singapore: return "Used in Singapore and parts of Southeast Asia."
        case .tehran: return "Used in Iran."
        case .turkey: return "Used by Turkey's Diyanet."
        case .custom: return "Custom twilight angles, set in Settings."
        }
    }

    private var asrExplanationKey: LocalizedStringKey {
        switch viewModel.selectedAsrMethod {
        case .hanafi: return "Asr begins when a shadow reaches twice an object's length."
        case .shafi: return "Asr begins when a shadow equals an object's length."
        }
    }
}

// MARK: - 5. Notifications

struct OnboardingNotificationsStep: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: DISpacing.md) {
            OnboardingStepHeader(
                titleKey: "Prayer Alerts",
                subtitleKey: "A gentle azan at each prayer time, only if you'd like."
            )

            DICard {
                VStack(alignment: .leading, spacing: DISpacing.md) {
                    HStack(alignment: .top, spacing: DISpacing.md) {
                        Image(systemName: "bell.badge")
                            .font(.title2)
                            .foregroundStyle(DIColor.accent)
                            .accessibilityHidden(true)
                        Text("Darul Irfan can play a short, gentle azan clip when each prayer time arrives.")
                            .font(.body)
                            .foregroundStyle(DIColor.textPrimary)
                    }
                    Text("By default, Fajr, Dhuhr, Asr, Maghrib, and Isha each use the azan clip, and sunrise stays silent. You can adjust every prayer's alert in Settings.")
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                }
            }

            switch viewModel.notificationPhase {
            case .idle, .requesting:
                Button {
                    Task { await viewModel.requestNotificationPermission() }
                } label: {
                    if viewModel.notificationPhase == .requesting {
                        ProgressView()
                            .tint(DIColor.primary)
                    } else {
                        Label("Enable Prayer Alerts", systemImage: "bell")
                    }
                }
                .buttonStyle(DISecondaryButtonStyle())
                .disabled(viewModel.notificationPhase == .requesting)

            case .granted:
                statusRow(
                    systemImage: "checkmark.circle.fill",
                    tint: DIColor.primary,
                    messageKey: "Prayer alerts are on. You'll be reminded gently at each prayer time."
                )

            case .denied:
                statusRow(
                    systemImage: "bell.slash",
                    tint: DIColor.textMuted,
                    messageKey: "Notifications are off for now. Prayer times will always be available in the app, and you can enable alerts later in the iPhone Settings app."
                )
            }
        }
    }

    private func statusRow(systemImage: String, tint: Color, messageKey: LocalizedStringKey) -> some View {
        DICard {
            HStack(alignment: .top, spacing: DISpacing.sm) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(messageKey)
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textPrimary)
            }
        }
    }
}

// MARK: - 6. Finish

struct OnboardingFinishStep: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: DISpacing.lg) {
            VStack(spacing: DISpacing.md) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(DIColor.primary)
                    .accessibilityHidden(true)
                    .padding(.top, DISpacing.lg)
                Text("You're All Set")
                    .font(DIFont.heading)
                    .foregroundStyle(DIColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("May Darul Irfan bring light and peace to your days.")
                    .font(.callout)
                    .foregroundStyle(DIColor.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            DICard {
                VStack(spacing: DISpacing.sm) {
                    summaryRow(systemImage: "mappin.and.ellipse", titleKey: "Location", value: locationValue)
                    Divider()
                    summaryRow(
                        systemImage: "sun.and.horizon",
                        titleKey: "Calculation",
                        value: Text(LocalizedStringKey(viewModel.savedMethod.englishName))
                    )
                    Divider()
                    summaryRow(
                        systemImage: "clock",
                        titleKey: "Asr Method",
                        value: Text(LocalizedStringKey(viewModel.savedAsrMethod.englishName))
                    )
                    Divider()
                    summaryRow(systemImage: "bell", titleKey: "Alerts", value: alertsValue)
                }
            }
        }
    }

    private var locationValue: Text {
        if let name = viewModel.activePlaceName {
            return Text(verbatim: name)
        }
        return Text("Not set yet")
    }

    private var alertsValue: Text {
        switch viewModel.notificationPhase {
        case .granted: return Text("On")
        default: return Text("Off — enable anytime in Settings")
        }
    }

    private func summaryRow(systemImage: String, titleKey: LocalizedStringKey, value: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DISpacing.sm) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(DIColor.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(titleKey)
                .font(.subheadline)
                .foregroundStyle(DIColor.textMuted)
            Spacer(minLength: DISpacing.sm)
            value
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DIColor.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}
