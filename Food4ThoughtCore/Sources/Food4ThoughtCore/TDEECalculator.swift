public enum TDEECalculator {
    private static let fatShareOfCalories = 0.25
    private static let minimumFatGramsPerKilogram = 0.6
    private static let caloriesPerGramProtein = 4.0
    private static let caloriesPerGramCarbohydrate = 4.0
    private static let caloriesPerGramFat = 9.0

    public static func basalMetabolicRate(
        weightKg: Double,
        heightCm: Double,
        age: Int,
        sex: BiologicalSex
    ) -> Double {
        10 * weightKg + 6.25 * heightCm - 5 * Double(age) + sex.mifflinStJeorOffset
    }

    /// Informational only — never drive calorie or macro logic off BMI.
    public static func bodyMassIndex(weightKg: Double, heightCm: Double) -> Double {
        let heightMetres = heightCm / 100
        return weightKg / (heightMetres * heightMetres)
    }

    public static func totalDailyEnergyExpenditure(bmr: Double, activityLevel: ActivityLevel) -> Double {
        bmr * activityLevel.multiplier
    }

    public static func dailyCalorieTarget(
        tdee: Double,
        bmr: Double,
        goal: GoalType,
        sex: BiologicalSex
    ) -> Double {
        let adjusted = tdee * goal.calorieMultiplier
        return max(adjusted, bmr, sex.minimumDailyCalories)
    }

    public static func macroTargets(
        calorieTarget: Double,
        weightKg: Double,
        goal: GoalType
    ) -> MacroTargets {
        let fatGrams = max(
            calorieTarget * fatShareOfCalories / caloriesPerGramFat,
            minimumFatGramsPerKilogram * weightKg
        )
        let fatCalories = fatGrams * caloriesPerGramFat

        // At very high body weight the calorie target is set by the BMR floor
        // while protein and fat are set per-kilogram, so those two floors can
        // together demand more than the target allows. Protein yields rather
        // than fat: the fat floor is hormonal, whereas anyone in that range is
        // already getting 400g+ of protein and loses nothing practical here.
        // Without this the split silently overshoots its own calorie headline.
        let proteinCalorieBudget = max(0, calorieTarget - fatCalories)
        let proteinGrams = min(
            goal.proteinGramsPerKilogram * weightKg,
            proteinCalorieBudget / caloriesPerGramProtein
        )

        let remainingCalories = calorieTarget
            - proteinGrams * caloriesPerGramProtein
            - fatCalories

        return MacroTargets(
            proteinGrams: proteinGrams,
            carbsGrams: max(0, remainingCalories / caloriesPerGramCarbohydrate),
            fatGrams: fatGrams
        )
    }
}
