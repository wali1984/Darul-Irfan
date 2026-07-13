import SwiftUI

// Individual onboarding pages. The location page lives in its own file
// (OnboardingLocationStep.swift) because it carries the manual city search.
//
// Visual language: the welcome is a reverent full-bleed emerald hero (matching
// the flagship "Today" screen), then each setup page uses elevated, springy
// selection cards on the warm cream canvas with staggered entrance motion.

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

// MARK: - Shared selection card

/// An elevated, springy selection row: a tinted leading badge, title + subtitle,
/// and an animated tick. Selected state lifts the card with an emerald→gold edge
/// and a soft glow. Used by the language and Asr choices so selection feels
/// consistent and delightful throughout onboarding.
private struct OnboardingChoiceCard<Leading: View>: View {
    let isSelected: Bool
    let title: Text
    let subtitle: Text
    @ViewBuilder var leading: () -> Leading
    let action: () -> Void

    var body: some View {
        Button {
            DIHaptics.soft()
            action()
        } label: {
            HStack(spacing: DISpacing.md) {
                leading()
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(.headline)
                        .foregroundStyle(DIColor.textPrimary)
                    subtitle
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                }
                Spacer(minLength: 0)
                selectionTick
            }
            .padding(DISpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                    .fill(DIColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                    .stroke(
                        isSelected
                            ? AnyShapeStyle(LinearGradient(
                                colors: [DIColor.primary, DIColor.accent],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(DIColor.border),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: isSelected ? DIColor.primary.opacity(0.20) : Color.black.opacity(0.05),
                    radius: isSelected ? 12 : 6, x: 0, y: isSelected ? 6 : 3)
        }
        .buttonStyle(DIPressableStyle())
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var selectionTick: some View {
        ZStack {
            Circle()
                .stroke(DIColor.border, lineWidth: 1.5)
                .opacity(isSelected ? 0 : 1)
            Circle()
                .fill(DIColor.primary)
                .opacity(isSelected ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(DIColor.onPrimary)
                .opacity(isSelected ? 1 : 0)
                .scaleEffect(isSelected ? 1 : 0.4)
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}

/// A small rounded, tinted tile that holds a glyph on the leading edge of a card.
private struct OnboardingBadge<Glyph: View>: View {
    var tint: Color = DIColor.primary
    @ViewBuilder var glyph: () -> Glyph

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous)
                .fill(tint.opacity(0.12))
            glyph()
        }
        .frame(width: 46, height: 46)
        .accessibilityHidden(true)
    }
}

// MARK: - 1. Welcome

/// The first moment: a full-bleed emerald hero (the flow supplies the living
/// gradient background) carrying the glowing seal, the wordmark, the tagline,
/// and the app's anchoring verse. Everything springs gently into place.
struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: DISpacing.lg) {
            seal
                .diAppear(delay: 0.05)

            VStack(spacing: DISpacing.xs) {
                Text(DIBrand.wordmark)
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .foregroundStyle(DIColor.onPrimary)
                    .tracking(1.5)
                    .accessibilityAddTraits(.isHeader)

                Text(verbatim: "دارالعرفان")
                    .font(DIFont.urduBody(scale: 1.15))
                    .foregroundStyle(DIColor.accent)
                    .environment(\.layoutDirection, .rightToLeft)

                Text(DIBrand.tagline)
                    .font(.callout.italic())
                    .foregroundStyle(DIColor.onPrimary.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .diAppear(delay: 0.15)

            DIJaliDivider(tint: DIColor.accent, opacity: 0.55)
                .padding(.horizontal, DISpacing.xl)
                .diAppear(delay: 0.25)

            anchorVerse
                .diAppear(delay: 0.35)

            Text("Accurate prayer times, the Holy Quran with translation and tafsir, lectures and books from the Naqshbandia Owaisiah library, and guidance for daily zikr — together in one calm companion.")
                .font(.subheadline)
                .foregroundStyle(DIColor.onPrimary.opacity(0.82))
                .multilineTextAlignment(.center)
                .padding(.horizontal, DISpacing.sm)
                .diAppear(delay: 0.45)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DISpacing.xl)
        .padding(.bottom, DISpacing.md)
    }

    private var seal: some View {
        ZStack {
            // A soft gold halo that fades fully to clear at its edge.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [DIColor.goldGlow.opacity(0.32), Color.clear],
                        center: .center, startRadius: 0, endRadius: 130
                    )
                )
                .frame(width: 260, height: 260)
                .blur(radius: 4)
            DISealEmblem(diameter: 132, glow: true)
                .diBreathingGlow(color: DIColor.goldGlow, maxRadius: 28)
        }
        .frame(height: 224)
    }

    private var anchorVerse: some View {
        VStack(spacing: DISpacing.sm) {
            Text(DIBrand.anchorVerseArabic)
                .font(DIFont.quranArabic(scale: 0.85))
                .foregroundStyle(DIColor.onPrimary)
                .diGoldGlow(radius: 14, opacity: 0.55)
                .environment(\.layoutDirection, .rightToLeft)
                .multilineTextAlignment(.center)

            Text(DIBrand.anchorVerseEnglish)
                .font(.callout.italic())
                .foregroundStyle(DIColor.onPrimary.opacity(0.9))
                .multilineTextAlignment(.center)

            Text(DIBrand.anchorVerseReference)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DIColor.accent)
                .tracking(0.5)
        }
        .padding(.horizontal, DISpacing.sm)
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
            .diAppear()

            VStack(spacing: DISpacing.sm) {
                ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element.id) { index, language in
                    OnboardingChoiceCard(
                        isSelected: viewModel.selectedLanguage == language,
                        title: Text(LocalizedStringKey(language.displayName)),
                        subtitle: subtitle(for: language),
                        leading: { languageBadge(language) },
                        action: { Task { await viewModel.selectLanguage(language) } }
                    )
                    .diAppear(delay: 0.08 * Double(index + 1))
                }
            }
        }
    }

    @ViewBuilder
    private func languageBadge(_ language: AppLanguage) -> some View {
        OnboardingBadge {
            switch language {
            case .system:
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(DIColor.primary)
            case .english:
                Text(verbatim: "A")
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundStyle(DIColor.primary)
            case .urdu:
                Text(verbatim: "اُ")
                    .font(DIFont.urduBody(scale: 1.05))
                    .foregroundStyle(DIColor.primary)
            }
        }
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
            .diAppear()

            methodCard
                .diAppear(delay: 0.1)

            asrSection
                .diAppear(delay: 0.2)
        }
    }

    private var methodCard: some View {
        DIElevatedCard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Label {
                    Text("Calculation Method")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.textPrimary)
                } icon: {
                    Image(systemName: "globe.asia.australia.fill")
                        .foregroundStyle(DIColor.accent)
                }
                Picker("Calculation Method", selection: $viewModel.selectedMethod) {
                    ForEach(Self.methodChoices) { method in
                        Text(LocalizedStringKey(method.englishName)).tag(method)
                    }
                }
                .pickerStyle(.menu)
                .tint(DIColor.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(methodExplanationKey)
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.selectedMethod)
            }
        }
    }

    private var asrSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            Text("Asr Method")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DIColor.textPrimary)
                .padding(.horizontal, DISpacing.xs)

            // Hanafi first: it is the preselected default.
            ForEach([AsrMethodChoice.hanafi, AsrMethodChoice.shafi]) { method in
                OnboardingChoiceCard(
                    isSelected: viewModel.selectedAsrMethod == method,
                    title: Text(LocalizedStringKey(method.englishName)),
                    subtitle: asrExplanation(for: method),
                    leading: { asrBadge(method) },
                    action: { viewModel.selectedAsrMethod = method }
                )
            }
        }
    }

    private func asrBadge(_ method: AsrMethodChoice) -> some View {
        OnboardingBadge(tint: DIColor.accent) {
            Image(systemName: method == .hanafi ? "sun.min.fill" : "sun.max.fill")
                .font(.title3)
                .foregroundStyle(DIColor.accent)
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

    private func asrExplanation(for method: AsrMethodChoice) -> Text {
        switch method {
        case .hanafi: return Text("Asr begins when a shadow reaches twice an object's length.")
        case .shafi: return Text("Asr begins when a shadow equals an object's length.")
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
            .diAppear()

            illustrationCard
                .diAppear(delay: 0.1)

            actionArea
                .diAppear(delay: 0.2)
        }
    }

    private var illustrationCard: some View {
        DIElevatedCard {
            VStack(spacing: DISpacing.md) {
                ZStack {
                    Circle()
                        .fill(DIColor.accent.opacity(0.14))
                        .frame(width: 84, height: 84)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(DIColor.primary)
                        .symbolRenderingMode(.hierarchical)
                }
                .diBreathingGlow(color: DIColor.goldGlow, maxRadius: 14)
                .accessibilityHidden(true)

                Text("Darul Irfan can play a short, gentle azan clip when each prayer time arrives.")
                    .font(.body)
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text("By default, Fajr, Dhuhr, Asr, Maghrib, and Isha each use the azan clip, and sunrise stays silent. You can adjust every prayer's alert in Settings.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        switch viewModel.notificationPhase {
        case .idle, .requesting:
            Button {
                DIHaptics.soft()
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
                glow: true,
                messageKey: "Prayer alerts are on. You'll be reminded gently at each prayer time."
            )

        case .denied:
            statusRow(
                systemImage: "bell.slash",
                tint: DIColor.textMuted,
                glow: false,
                messageKey: "Notifications are off for now. Prayer times will always be available in the app, and you can enable alerts later in the iPhone Settings app."
            )
        }
    }

    private func statusRow(systemImage: String, tint: Color, glow: Bool, messageKey: LocalizedStringKey) -> some View {
        DIElevatedCard(glow: glow ? DIColor.primary : nil) {
            HStack(alignment: .top, spacing: DISpacing.sm) {
                Image(systemName: systemImage)
                    .font(.title3)
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
            crest
                .diAppear(delay: 0.05)

            VStack(spacing: DISpacing.sm) {
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
            .diAppear(delay: 0.15)

            summaryCard
                .diAppear(delay: 0.25)
        }
    }

    private var crest: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [DIColor.goldGlow.opacity(0.30), Color.clear],
                        center: .center, startRadius: 0, endRadius: 110
                    )
                )
                .frame(width: 220, height: 220)
                .blur(radius: 4)
            DISealEmblem(diameter: 108, glow: true)
                .diBreathingGlow(color: DIColor.goldGlow, maxRadius: 24)
        }
        .frame(height: 200)
        .padding(.top, DISpacing.md)
    }

    private var summaryCard: some View {
        DIElevatedCard {
            VStack(spacing: DISpacing.sm) {
                summaryRow(systemImage: "mappin.and.ellipse", titleKey: "Location", value: locationValue)
                rowDivider
                summaryRow(
                    systemImage: "sun.and.horizon",
                    titleKey: "Calculation",
                    value: Text(LocalizedStringKey(viewModel.savedMethod.englishName))
                )
                rowDivider
                summaryRow(
                    systemImage: "clock",
                    titleKey: "Asr Method",
                    value: Text(LocalizedStringKey(viewModel.savedAsrMethod.englishName))
                )
                rowDivider
                summaryRow(systemImage: "bell", titleKey: "Alerts", value: alertsValue)
            }
        }
    }

    private var rowDivider: some View {
        Divider().overlay(DIColor.border)
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
