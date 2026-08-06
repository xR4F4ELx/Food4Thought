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
        let proteinGrams = goal.proteinGramsPerKilogram * weightKg
        let fatGrams = max(
            calorieTarget * fatShareOfCalories / caloriesPerGramFat,
            minimumFatGramsPerKilogram * weightKg
        )
        let remainingCalories = calorieTarget
            - proteinGrams * caloriesPerGramProtein
            - fatGrams * caloriesPerGramFat

        return MacroTargets(
            proteinGrams: proteinGrams,
            carbsGrams: max(0, remainingCalories / caloriesPerGramCarbohydrate),
            fatGrams: fatGrams
        )
    }
}
