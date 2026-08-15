import Foundation
import Food4ThoughtCore

/// Everything the questionnaire gathers, ready to persist in one call.
struct OnboardingSubmission: Equatable, Sendable {
    let inputs: GoalInputs

    /// The plan exactly as the user saw it on the final screen, carried rather
    /// than recomputed at save time so the targets they agreed to are the ones
    /// that get stored.
    let plan: GoalPlan

    let mealSchedule: MealSchedule

    /// Optional: onboarding does not ask for it, since it feeds none of the
    /// math. Settings can fill it in later without touching this type.
    let displayName: String?

    init(
        inputs: GoalInputs,
        plan: GoalPlan,
        mealSchedule: MealSchedule,
        displayName: String? = nil
    ) {
        self.inputs = inputs
        self.plan = plan
        self.mealSchedule = mealSchedule
        self.displayName = displayName
    }
}
