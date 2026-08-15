import SwiftUI
import Food4ThoughtCore

struct GoalDirectionStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(title: OnboardingStep.goalDirection.title) {
            VStack(spacing: 12) {
                ForEach(GoalDirection.allCases, id: \.self) { direction in
                    OnboardingChoiceRow(
                        title: direction.onboardingLabel,
                        isSelected: viewModel.draft.direction == direction
                    ) {
                        viewModel.select { $0.direction = direction }
                    }
                }
            }
        }
    }
}

struct PaceStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(
            title: OnboardingStep.pace.title,
            subtitle: "You can change this whenever you like."
        ) {
            VStack(spacing: 12) {
                ForEach(GoalPace.allCases, id: \.self) { pace in
                    OnboardingChoiceRow(
                        title: pace.onboardingLabel,
                        caption: caption(for: pace),
                        isSelected: viewModel.draft.pace == pace
                    ) {
                        viewModel.select { $0.pace = pace }
                    }
                }
            }
        }
    }

    /// The projected rate comes from the stored target, so it reflects any
    /// clamping the calorie floors applied.
    private func caption(for pace: GoalPace) -> String {
        guard let plan = viewModel.planPreview(for: pace) else { return pace.onboardingCaption }
        let rate = abs(plan.projectedWeeklyWeightChangeKg)
        return "\(pace.onboardingCaption) · about \(rate.formatted(.number.precision(.fractionLength(2)))) kg a week at first"
    }
}

extension GoalDirection {
    var onboardingLabel: String {
        switch self {
        case .lose: "Lose weight"
        case .maintain: "Stay where I am"
        case .gain: "Gain weight"
        }
    }
}

extension GoalPace {
    var onboardingLabel: String {
        switch self {
        case .steady: "Steady"
        case .aggressive: "Aggressive"
        }
    }

    var onboardingCaption: String {
        switch self {
        case .steady: "Slower, easier to stick with"
        case .aggressive: "Faster, but expect more hunger"
        }
    }
}
