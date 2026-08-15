/// A computed target set, matching one row of `goal_sets`.
///
/// Every intermediate figure is kept, not just the calorie target, so the plan
/// screen can explain where the number came from and a historical goal set
/// stays explainable long after the inputs have changed.
public struct GoalPlan: Equatable, Sendable {
    public let basalMetabolicRate: Double
    public let totalDailyEnergyExpenditure: Double
    /// Informational only — never drives calorie or macro logic.
    public let bodyMassIndex: Double
    /// Whole calories, because this is the number shown to the user and stored.
    public let dailyCalorieTarget: Int
    public let macros: MacroTargets

    public init(
        basalMetabolicRate: Double,
        totalDailyEnergyExpenditure: Double,
        bodyMassIndex: Double,
        dailyCalorieTarget: Int,
        macros: MacroTargets
    ) {
        self.basalMetabolicRate = basalMetabolicRate
        self.totalDailyEnergyExpenditure = totalDailyEnergyExpenditure
        self.bodyMassIndex = bodyMassIndex
        self.dailyCalorieTarget = dailyCalorieTarget
        self.macros = macros
    }
}
