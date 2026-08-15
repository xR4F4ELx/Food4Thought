import SwiftUI
import Food4ThoughtCore

struct ActivityStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(
            title: OnboardingStep.activity.title,
            subtitle: "Count training, not daily steps."
        ) {
            VStack(spacing: 12) {
                ForEach(ActivityLevel.allCases, id: \.self) { level in
                    OnboardingChoiceRow(
                        title: level.onboardingLabel,
                        isSelected: viewModel.draft.activityLevel == level
                    ) {
                        viewModel.select { $0.activityLevel = level }
                    }
                }
            }
        }
    }
}

extension ActivityLevel {
    /// Situations rather than adjectives: "moderately active" means nothing,
    /// but people can place themselves in a described week.
    var onboardingLabel: String {
        switch self {
        case .sedentary: "Desk job, little exercise"
        case .lightlyActive: "Light exercise 1–3 days a week"
        case .moderatelyActive: "Desk job, but I train 3–5 days a week"
        case .veryActive: "Hard training 6–7 days a week"
        case .extremelyActive: "Physical job, or training twice a day"
        }
    }
}
