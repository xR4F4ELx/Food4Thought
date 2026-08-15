import Foundation
import Food4ThoughtCore

/// Answers gathered so far. Every field is optional until its screen is done,
/// which is what lets the flow validate one step at a time instead of failing
/// at the end.
struct OnboardingDraft: Equatable, Sendable {
    var birthDate: Date?
    var sex: BiologicalSex?
    var heightCm: Double?
    var weightKg: Double?
    var activityLevel: ActivityLevel?
    var direction: GoalDirection?

    /// Defaulted rather than optional: the pace screen is skipped for maintain
    /// and when both paces would land on the same number, so this needs a value
    /// even when the user is never asked.
    var pace: GoalPace = .steady

    /// Preselected so the meal screen costs one tap, not a decision.
    var mealPreset: MealSchedule.Preset = .threeMeals

    /// Non-nil only once every field the math needs has an answer.
    var goalInputs: GoalInputs? {
        guard let birthDate, let sex, let heightCm, let weightKg,
              let activityLevel, let direction
        else { return nil }

        return GoalInputs(
            birthDate: birthDate,
            sex: sex,
            heightCm: heightCm,
            weightKg: weightKg,
            activityLevel: activityLevel,
            goal: GoalType(direction: direction, pace: pace)
        )
    }
}
