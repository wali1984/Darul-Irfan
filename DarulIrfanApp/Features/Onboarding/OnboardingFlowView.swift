import SwiftUI

/// First-run flow: welcome → language → location → calculation →
/// notifications → finish. Presented full-screen by RootView until
/// `settings.hasCompletedOnboarding` is true.
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
        .animation(.easeInOut(duration: 0.3), value: viewModel.step)
        .diScreenBackground()
    }

    // MARK: - Top bar (back / skip)

    private var topBar: some View {
        HStack {
            if viewModel.step != .welcome {
                Button {
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
                Capsule()
                    .fill(step == viewModel.step ? DIColor.accent : DIColor.border)
                    .frame(width: step == viewModel.step ? 22 : 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(viewModel.step.rawValue + 1) of \(OnboardingStep.allCases.count)"))
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch viewModel.step {
        case .welcome:
            Button("Get Started") {
                viewModel.advance()
            }
            .buttonStyle(DIPrimaryButtonStyle())

        case .language:
            Button("Continue") {
                viewModel.advance()
            }
            .buttonStyle(DIPrimaryButtonStyle())

        case .location:
            Button("Continue") {
                viewModel.advance()
            }
            .buttonStyle(DIPrimaryButtonStyle())
            .disabled(!viewModel.hasSelectedPlace)
            .opacity(viewModel.hasSelectedPlace ? 1.0 : 0.5)

        case .calculation:
            Button("Continue") {
                Task { await viewModel.commitCalculationAndAdvance() }
            }
            .buttonStyle(DIPrimaryButtonStyle())

        case .notifications:
            Button("Continue") {
                viewModel.advance()
            }
            .buttonStyle(DIPrimaryButtonStyle())

        case .finish:
            Button {
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
