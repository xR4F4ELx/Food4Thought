/// Roughly the energy stored in a kilogram of body mass. The linear rule
/// overstates loss across months as expenditure adapts, so this is only
/// honest as a short-horizon "at first" figure.
private let caloriesPerKilogramOfBodyMass = 7700.0
private let daysPerWeek = 7.0

extension GoalPlan {
    /// Negative for loss, positive for gain.
    ///
    /// Derived from the stored calorie target rather than the goal's
    /// multiplier: `dailyCalorieTarget` floors at BMR and at an absolute
    /// minimum, so for a small or light person an aggressive deficit can be
    /// clamped back to nearly the same number as a steady one. Projecting off
    /// the multiplier would promise a rate the app will not deliver.
    public var projectedWeeklyWeightChangeKg: Double {
        let dailyBalance = Double(dailyCalorieTarget) - totalDailyEnergyExpenditure
        return dailyBalance * daysPerWeek / caloriesPerKilogramOfBodyMass
    }
}
