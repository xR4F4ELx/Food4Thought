import Testing
@testable import Food4ThoughtCore

/// The arithmetic behind the Home rings. Every figure on that screen is one of
/// these, so a wrong sign here is a wrong number on the screen the app opens on.
@Suite("Day progress")
struct DayProgressTests {

    private let macros = MacroTargets(proteinGrams: 114, carbsGrams: 254, fatGrams: 55)

    private func progress(consumed: NutritionFacts) -> DayProgress {
        DayProgress(target: 1965, macroTargets: macros, consumed: consumed)
    }

    // MARK: - Calories

    @Test("remaining leads, and is target minus consumed")
    func remainingIsTargetMinusConsumed() {
        // Arrange — 1d: 1,180 eaten against a 1,965 target.
        let day = progress(consumed: NutritionFacts(calories: 1180, protein: 62, carbs: 150, fat: 34))

        // Assert
        #expect(day.remainingKcal == 785)
        #expect(day.consumedKcal == 1180)
        #expect(day.isOverTarget == false)
    }

    @Test("over target the remaining figure goes negative rather than clamping to zero")
    func overTargetGoesNegative() {
        // 1e reads "−275 over today" — the sign is the whole message, so a
        // clamp at zero would erase it.
        let day = progress(consumed: NutritionFacts(calories: 2240, protein: 108, carbs: 291, fat: 52))

        #expect(day.remainingKcal == -275)
        #expect(day.isOverTarget)
    }

    @Test("exactly on target is not over")
    func exactlyOnTargetIsNotOver() {
        let day = progress(consumed: NutritionFacts(calories: 1965, protein: 0, carbs: 0, fat: 0))

        #expect(day.remainingKcal == 0)
        #expect(day.isOverTarget == false)
    }

    @Test("consumed calories round rather than truncate")
    func consumedRounds() {
        // The rollup rounds once, in recompute_balance. Truncating here would
        // put the ring a kcal away from the balance for no reason.
        let day = progress(consumed: NutritionFacts(calories: 1180.6, protein: 0, carbs: 0, fat: 0))

        #expect(day.consumedKcal == 1181)
    }

    // MARK: - Ring fractions

    @Test("the calorie ring fills proportionally and stops at full")
    func calorieFractionClamps() {
        #expect(progress(consumed: .zero).calorieFraction == 0)

        let half = progress(consumed: NutritionFacts(calories: 982.5, protein: 0, carbs: 0, fat: 0))
        #expect(abs(half.calorieFraction - 0.5) < 0.001)

        // Over target the ring is full and the number carries the overage —
        // a ring winding past 360° reads as less, not more.
        let over = progress(consumed: NutritionFacts(calories: 2240, protein: 0, carbs: 0, fat: 0))
        #expect(over.calorieFraction == 1)
    }

    @Test("a zero target cannot divide the ring by zero")
    func zeroTargetIsSafe() {
        // goal_sets carries a > 0 check, so this is defence against a decode
        // default rather than a state the database can hold.
        let day = DayProgress(
            target: 0,
            macroTargets: MacroTargets(proteinGrams: 0, carbsGrams: 0, fatGrams: 0),
            consumed: NutritionFacts(calories: 500, protein: 10, carbs: 10, fat: 10)
        )

        #expect(day.calorieFraction == 0)
        #expect(day.fraction(of: .protein) == 0)
    }

    // MARK: - Macros

    @Test("each macro reports its own consumed grams and fraction")
    func macroGramsAndFractions() {
        let day = progress(consumed: NutritionFacts(calories: 1180, protein: 62, carbs: 150, fat: 34))

        #expect(day.grams(of: .protein) == 62)
        #expect(day.grams(of: .carbs) == 150)
        #expect(day.grams(of: .fat) == 34)

        #expect(abs(day.fraction(of: .protein) - 62.0 / 114) < 0.001)
        #expect(abs(day.fraction(of: .carbs) - 150.0 / 254) < 0.001)
        #expect(abs(day.fraction(of: .fat) - 34.0 / 55) < 0.001)
    }

    @Test("a macro past its target is flagged so the ring can recolour")
    func macroOverTarget() {
        // 1e draws carbs in --over at 291 of 254 while protein and fat stay put.
        let day = progress(consumed: NutritionFacts(calories: 2240, protein: 108, carbs: 291, fat: 52))

        #expect(day.isOver(.carbs))
        #expect(day.isOver(.protein) == false)
        #expect(day.isOver(.fat) == false)
        #expect(day.fraction(of: .carbs) == 1)
    }

    @Test("a macro target of zero never reads as over")
    func zeroMacroTargetIsNotOver() {
        // Nothing to exceed, so flagging it would put a red ring on a target
        // the user was never set.
        let day = DayProgress(
            target: 1965,
            macroTargets: MacroTargets(proteinGrams: 0, carbsGrams: 254, fatGrams: 55),
            consumed: NutritionFacts(calories: 500, protein: 40, carbs: 10, fat: 10)
        )

        #expect(day.isOver(.protein) == false)
        #expect(day.fraction(of: .protein) == 0)
    }

    @Test("target grams round for display")
    func targetGramsRound() {
        let day = DayProgress(
            target: 1965,
            macroTargets: MacroTargets(proteinGrams: 113.6, carbsGrams: 254.4, fatGrams: 55),
            consumed: .zero
        )

        #expect(day.targetGrams(of: .protein) == 114)
        #expect(day.targetGrams(of: .carbs) == 254)
    }
}
