import Foundation

extension TDEECalculator {
    /// Runs the whole chain — BMR, TDEE, calorie target, macro split — in the
    /// one order that keeps the pieces consistent with each other.
    ///
    /// `asOf` and `calendar` are injectable so age derivation is testable and
    /// so a user who crosses a birthday mid-session gets a deterministic result.
    public static func plan(
        for inputs: GoalInputs,
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> GoalPlan {
        let age = calendar.dateComponents([.year], from: inputs.birthDate, to: asOf).year ?? 0

        let bmr = basalMetabolicRate(
            weightKg: inputs.weightKg,
            heightCm: inputs.heightCm,
            age: age,
            sex: inputs.sex
        )
        let tdee = totalDailyEnergyExpenditure(bmr: bmr, activityLevel: inputs.activityLevel)
        let target = dailyCalorieTarget(tdee: tdee, bmr: bmr, goal: inputs.goal, sex: inputs.sex)

        // Round before splitting macros, not after: the stored target is an
        // integer, and complete_onboarding rejects a submission whose macros do
        // not add up to it.
        let roundedTarget = Int(target.rounded())

        return GoalPlan(
            basalMetabolicRate: bmr,
            totalDailyEnergyExpenditure: tdee,
            bodyMassIndex: bodyMassIndex(weightKg: inputs.weightKg, heightCm: inputs.heightCm),
            dailyCalorieTarget: roundedTarget,
            macros: macroTargets(
                calorieTarget: Double(roundedTarget),
                weightKg: inputs.weightKg,
                goal: inputs.goal
            )
        )
    }
}
