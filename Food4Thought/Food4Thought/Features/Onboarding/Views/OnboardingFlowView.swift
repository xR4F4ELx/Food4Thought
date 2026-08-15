import SwiftUI

/// Container for the questionnaire: progress, back navigation, and the
/// continue button for the screens that don't auto-advance.
struct OnboardingFlowView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: OnboardingViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(for: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            // AppState arrives from the environment, so the view model can't be
            // built in an initialiser.
            if viewModel == nil {
                viewModel = OnboardingViewModel(appState: appState)
            }
        }
    }

    private func content(for viewModel: OnboardingViewModel) -> some View {
        VStack(spacing: 0) {
            header(for: viewModel)

            step(for: viewModel)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: viewModel.step)

            if viewModel.step.needsContinueButton {
                continueButton(for: viewModel)
            }
        }
    }

    private func header(for viewModel: OnboardingViewModel) -> some View {
        HStack(spacing: 12) {
            if viewModel.canGoBack {
                Button {
                    viewModel.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back")
            }

            ProgressView(value: min(viewModel.progress, 1))
                .progressViewStyle(.linear)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func step(for viewModel: OnboardingViewModel) -> some View {
        switch viewModel.step {
        case .aboutYou: AboutYouStepView(viewModel: viewModel)
        case .body: BodyStepView(viewModel: viewModel)
        case .activity: ActivityStepView(viewModel: viewModel)
        case .goalDirection: GoalDirectionStepView(viewModel: viewModel)
        case .pace: PaceStepView(viewModel: viewModel)
        case .mealRhythm: MealRhythmStepView(viewModel: viewModel)
        case .plan: PlanStepView(viewModel: viewModel)
        }
    }

    private func continueButton(for viewModel: OnboardingViewModel) -> some View {
        Button("Continue") {
            viewModel.advance()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .disabled(!viewModel.canAdvance)
        .padding(20)
        .background(.bar)
    }
}

private extension OnboardingStep {
    /// Only the screens that gather several fields at once need a confirm; the
    /// one-tap choice screens commit as they advance.
    var needsContinueButton: Bool {
        self == .aboutYou || self == .body
    }
}
