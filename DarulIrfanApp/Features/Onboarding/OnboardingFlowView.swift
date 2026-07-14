import SwiftUI

/// First-run flow: welcome → language → location → calculation →
/// notifications → finish. Presented full-screen by RootView until
/// `settings.hasCompletedOnboarding` is true.
///
/// Visual language mirrors the flagship "Today" hero: a living time-of-day
/// emerald gradient welcomes the user, then the practical setup steps sit on
/// the warm cream canvas with elevated, springy selection cards.
@MainActor
struct OnboardingFlowView: View {
    private let onComplete: () -> Void
    @State private var viewModel: OnboardingViewModel

    init(dependencies: AppDependencies, appState: AppState, onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        _viewModel = State(initialValue: OnboardingViewModel(
            location: dependencies.location,
            notifications: dependencies.notifications,
            appState: appState
        ))
    }

    /// The welcome page owns the full-bleed emerald hero; every other page
    /// sits on the calm cream canvas.
    private var isWelcome: Bool { viewModel.step == .welcome }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                stepContent
                    .padding(.horizontal, DISpacing.md)
                    .padding(.bottom, DISpacing.lg)
                    .id(viewModel.step)
                    .transition(.opacity)
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundLayer)
        .animation(.easeInOut(duration: 0.35), value: viewModel.step)
    }

    // MARK: - Living background

    /// Crossfades between the emerald welcome hero and the cream setup canvas
    /// as the flow advances, so the transition into the app feels continuous.
    private var backgroundLayer: some View {
        ZStack {
            DIColor.background
            ZStack {
                DIGradient.hero()
                DIPatternTexture(tint: .white, opacity: 0.07)
                DIOctagram(innerRatio: 0.5)
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: 340, height: 340)
                    .opacity(0.06)
                    .offset(x: 120, y: -70)
                DIOctagram(innerRatio: 0.5)
                    .stroke(Color.white, lineWidth: 1)
                    .frame(width: 200, height: 200)
                    .opacity(0.05)
                    .offset(x: -130, y: 240)
            }
            .opacity(isWelcome ? 1 : 0)
        }
        .ignoresSafeArea()
    }

    // MARK: - Top bar (back / skip)

    private var topBar: some View {
        HStack {
            if viewModel.step != .welcome {
                Button {
                    DIHaptics.light()
                    viewModel.goBack()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DIColor.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("Back"))
            }
            Spacer()
            if viewModel.step.isSkippable {
                Button("Skip") {
                    DIHaptics.light()
                    viewModel.advance()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DIColor.textMuted)
                .padding(.horizontal, DISpacing.sm)
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, DISpacing.sm)
        .frame(minHeight: 44)
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .welcome:
            OnboardingWelcomeStep()
        case .language:
            OnboardingLanguageStep(viewModel: viewModel)
        case .location:
            OnboardingLocationStep(viewModel: viewModel)
        case .calculation:
            OnboardingCalculationStep(viewModel: viewModel)
        case .notifications:
            OnboardingNotificationsStep(viewModel: viewModel)
        case .finish:
            OnboardingFinishStep(viewModel: viewModel)
        }
    }

    // MARK: - Footer (progress dots + primary action)

    private var footer: some View {
        VStack(spacing: DISpacing.md) {
            progressDots
            primaryButton
        }
        .padding(.horizontal, DISpacing.md)
        .padding(.top, DISpacing.sm)
        .padding(.bottom, DISpacing.md)
    }

    private var progressDots: some View {
        HStack(spacing: DISpacing.sm) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                let isCurrent = step == viewModel.step
                Capsule()
                    .fill(isCurrent ? AnyShapeStyle(DIGradient.goldSheen)
                                    : AnyShapeStyle(isWelcome ? Color.white.opacity(0.28) : DIColor.border))
                    .frame(width: isCurrent ? 24 : 8, height: 8)
                    .diGoldGlow(radius: isCurrent ? 6 : 0, opacity: isCurrent ? 0.6 : 0)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(viewModel.step.rawValue + 1) of \(OnboardingStep.allCases.count)"))
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch viewModel.step {
        case .welcome:
            // A gilded CTA that pops off the emerald hero — the invitation in.
            Button {
                DIHaptics.soft()
                viewModel.advance()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(DIColor.primaryDeep)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        DIGradient.goldSheen,
                        in: RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                    )
                    .diShimmer()
                    .diGoldGlow(radius: 16, opacity: 0.5)
            }
            .buttonStyle(DIPressableStyle())

        case .language:
            Button("Continue") {
                DIHaptics.soft()
                viewModel.advance()
            }
            .buttonStyle(DIPrimaryButtonStyle())

        case .location:
            Button("Continue") {
                DIHaptics.soft()
                viewModel.advance()
            }
            .buttonStyle(DIPrimaryButtonStyle())
            .disabled(!viewModel.hasSelectedPlace)
            .opacity(viewModel.hasSelectedPlace ? 1.0 : 0.5)

        case .calculation:
            Button("Continue") {
                DIHaptics.soft()
                Task { await viewModel.commitCalculationAndAdvance() }
            }
            .buttonStyle(DIPrimaryButtonStyle())

        case .notifications:
            Button("Continue") {
                DIHaptics.soft()
                viewModel.advance()
            }
            .buttonStyle(DIPrimaryButtonStyle())

        case .finish:
            Button {
                DIHaptics.success()
                Task {
                    await viewModel.completeOnboarding()
                    onComplete()
                }
            } label: {
                if viewModel.isFinishing {
                    ProgressView()
                        .tint(DIColor.onPrimary)
                } else {
                    Text("Begin")
                }
            }
            .buttonStyle(DIPrimaryButtonStyle())
            .disabled(viewModel.isFinishing)
        }
    }
}
