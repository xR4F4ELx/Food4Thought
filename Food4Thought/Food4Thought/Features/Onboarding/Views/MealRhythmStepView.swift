import SwiftUI
import Food4ThoughtCore

/// Feeds no part of the calorie math, but decides the home screen's meal slots
/// and the times local reminders fire — so it is worth the one tap.
struct MealRhythmStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(
            title: OnboardingStep.mealRhythm.title,
            subtitle: "Pick whichever is closest. You can reshape it later."
        ) {
            VStack(spacing: 12) {
                ForEach(MealSchedule.Preset.allCases, id: \.self) { preset in
                    OnboardingChoiceRow(
                        title: preset.displayName,
                        caption: preset.slotSummary,
                        isSelected: viewModel.draft.mealPreset == preset
                    ) {
                        viewModel.select { $0.mealPreset = preset }
                    }
                }
            }
        }
    }
}

private extension MealSchedule.Preset {
    /// e.g. "Breakfast · Lunch · Snack · Dinner"
    var slotSummary: String {
        schedule.slots.map(\.label).joined(separator: " · ")
    }
}
