import Testing
@testable import Food4ThoughtCore

private let tolerance = 0.01

private func expectClose(
    _ actual: Double,
    _ expected: Double,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        abs(actual - expected) < tolerance,
        "expected \(expected), got \(actual)",
        sourceLocation: sourceLocation
    )
}

@Suite("Basal metabolic rate — Mifflin-St Jeor")
struct BasalMetabolicRateTests {
    @Test("male: 10w + 6.25h - 5a + 5")
    func maleReferenceValue() {
        // Arrange: 25yo male, 80kg, 180cm
        // Act
        let bmr = TDEECalculator.basalMetabolicRate(weightKg: 80, heightCm: 180, age: 25, sex: .male)
        // Assert: 800 + 1125 - 125 + 5
        expectClose(bmr, 1805)
    }

    @Test("female: 10w + 6.25h - 5a - 161")
    func femaleReferenceValue() {
        let bmr = TDEECalculator.basalMetabolicRate(weightKg: 65, heightCm: 165, age: 30, sex: .female)
        // 650 + 1031.25 - 150 - 161
        expectClose(bmr, 1370.25)
    }

    @Test("the male and female formulas differ by exactly 166 kcal at identical inputs")
    func sexOffsetIsConstant() {
        let male = TDEECalculator.basalMetabolicRate(weightKg: 70, heightCm: 170, age: 40, sex: .male)
        let female = TDEECalculator.basalMetabolicRate(weightKg: 70, heightCm: 170, age: 40, sex: .female)
        expectClose(male - female, 166)
    }
}

@Suite("Body mass index")
struct BodyMassIndexTests {
    @Test("divides weight by height in metres squared")
    func referenceValue() {
        let bmi = TDEECalculator.bodyMassIndex(weightKg: 80, heightCm: 180)
        expectClose(bmi, 24.6913)
    }
}

@Suite("Total daily energy expenditure")
struct TotalDailyEnergyExpenditureTests {
    @Test("multiplies BMR by the activity multiplier", arguments: [
        (ActivityLevel.sedentary, 1.2),
        (.lightlyActive, 1.375),
        (.moderatelyActive, 1.55),
        (.veryActive, 1.725),
        (.extremelyActive, 1.9)
    ])
    func appliesMultiplier(level: ActivityLevel, multiplier: Double) {
        let tdee = TDEECalculator.totalDailyEnergyExpenditure(bmr: 2000, activityLevel: level)
        expectClose(tdee, 2000 * multiplier)
    }
}

@Suite("Daily calorie target")
struct DailyCalorieTargetTests {
    // 25yo male, 80kg, 180cm, moderately active: BMR 1805, TDEE 2797.75
    private let bmr = 1805.0
    private let tdee = 2797.75

    @Test("maintain returns TDEE unchanged")
    func maintain() {
        let target = TDEECalculator.dailyCalorieTarget(tdee: tdee, bmr: bmr, goal: .maintain, sex: .male)
        expectClose(target, 2797.75)
    }

    @Test("loseWeight applies a 15% deficit")
    func loseWeight() {
        let target = TDEECalculator.dailyCalorieTarget(tdee: tdee, bmr: bmr, goal: .loseWeight, sex: .male)
        expectClose(target, 2378.0875)
    }

    @Test("cut applies a more aggressive 20% deficit")
    func cut() {
        let target = TDEECalculator.dailyCalorieTarget(tdee: tdee, bmr: bmr, goal: .cut, sex: .male)
        expectClose(target, 2238.2)
    }

    @Test("leanBulk applies a 10% surplus")
    func leanBulk() {
        let target = TDEECalculator.dailyCalorieTarget(tdee: tdee, bmr: bmr, goal: .leanBulk, sex: .male)
        expectClose(target, 3077.525)
    }

    @Test("gainWeight applies a 15% surplus")
    func gainWeight() {
        let target = TDEECalculator.dailyCalorieTarget(tdee: tdee, bmr: bmr, goal: .gainWeight, sex: .male)
        expectClose(target, 3217.4125)
    }

    @Test("never drops below BMR even on an aggressive cut")
    func bmrFloorBinds() {
        // 30yo male, 100kg, 190cm, sedentary: BMR 2042.5, TDEE 2451
        // A 20% cut would give 1960.8, which is below BMR.
        let target = TDEECalculator.dailyCalorieTarget(tdee: 2451, bmr: 2042.5, goal: .cut, sex: .male)
        expectClose(target, 2042.5)
    }

    @Test("never drops below the absolute female floor of 1200 kcal")
    func femaleAbsoluteFloorBinds() {
        // 50yo female, 50kg, 150cm, sedentary: BMR 1026.5, TDEE 1231.8
        // A 20% cut gives 985.44; BMR (1026.5) is itself below the 1200 floor.
        let target = TDEECalculator.dailyCalorieTarget(tdee: 1231.8, bmr: 1026.5, goal: .cut, sex: .female)
        expectClose(target, 1200)
    }

    @Test("never drops below the absolute male floor of 1500 kcal")
    func maleAbsoluteFloorBinds() {
        let target = TDEECalculator.dailyCalorieTarget(tdee: 1600, bmr: 1333, goal: .cut, sex: .male)
        expectClose(target, 1500)
    }

    @Test("floors never inflate a surplus goal")
    func floorsDoNotApplyUpward() {
        let target = TDEECalculator.dailyCalorieTarget(tdee: 3000, bmr: 1800, goal: .leanBulk, sex: .male)
        expectClose(target, 3300)
    }
}

@Suite("Macro targets")
struct MacroTargetsTests {
    @Test("maintain: 1.8 g/kg protein, 25% of calories from fat, carbs take the remainder")
    func maintainSplit() {
        let macros = TDEECalculator.macroTargets(calorieTarget: 2797.75, weightKg: 80, goal: .maintain)
        expectClose(macros.proteinGrams, 144)          // 1.8 * 80
        expectClose(macros.fatGrams, 77.7152)          // 0.25 * 2797.75 / 9
        expectClose(macros.carbsGrams, 380.5781)       // remainder / 4
    }

    @Test("protein scales with goal aggressiveness", arguments: [
        (GoalType.cut, 2.2),
        (.loseWeight, 2.0),
        (.maintain, 1.8),
        (.leanBulk, 1.6),
        (.gainWeight, 1.6)
    ])
    func proteinPerKilogram(goal: GoalType, gramsPerKg: Double) {
        let macros = TDEECalculator.macroTargets(calorieTarget: 2500, weightKg: 75, goal: goal)
        expectClose(macros.proteinGrams, gramsPerKg * 75)
    }

    @Test("fat is floored at 0.6 g/kg for hormonal health")
    func fatFloorBinds() {
        // 25% of 1500 kcal is 41.67 g for a 100 kg person — below the 60 g floor.
        let macros = TDEECalculator.macroTargets(calorieTarget: 1500, weightKg: 100, goal: .cut)
        expectClose(macros.fatGrams, 60)
    }

    @Test("carbs are floored at zero rather than going negative")
    func carbsNeverNegative() {
        // 120 kg on a 1500 kcal cut: protein 264 g (1056 kcal) + fat 72 g (648 kcal)
        // already exceeds the calorie target.
        let macros = TDEECalculator.macroTargets(calorieTarget: 1500, weightKg: 120, goal: .cut)
        #expect(macros.carbsGrams == 0)
    }

    @Test("macros never total more calories than the target, even when floors bind")
    func macrosNeverExceedTarget() {
        // A reachable worst case, unlike the 120 kg / 1500 kcal input above:
        // 50yo male, 200 kg, 170 cm, sedentary on a cut.
        //   BMR  2817.5, TDEE 3381, 20% cut → 2704.8, floored back up to BMR.
        // At that target the protein floor (2.2 g/kg = 440 g, 1760 kcal) and the
        // fat floor (0.6 g/kg = 120 g, 1080 kcal) already total 2840 kcal, so
        // carbs clamp to zero and the split overshoots its own headline number.
        let target = TDEECalculator.dailyCalorieTarget(
            tdee: 3381, bmr: 2817.5, goal: .cut, sex: .male
        )
        let macros = TDEECalculator.macroTargets(calorieTarget: target, weightKg: 200, goal: .cut)

        let total = macros.proteinGrams * 4 + macros.carbsGrams * 4 + macros.fatGrams * 9
        #expect(
            total <= target + tolerance,
            "macros total \(total) kcal against a \(target) kcal target"
        )
    }

    @Test("macro calories reconcile to the calorie target when no floor binds")
    func macrosReconcileToTarget() {
        let target = 2797.75
        let macros = TDEECalculator.macroTargets(calorieTarget: target, weightKg: 80, goal: .maintain)
        let total = macros.proteinGrams * 4 + macros.carbsGrams * 4 + macros.fatGrams * 9
        expectClose(total, target)
    }
}
