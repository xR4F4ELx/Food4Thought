import Testing
@testable import Food4ThoughtCore

@Suite("PortionStepper")
struct PortionStepperTests {

    private func gramFood(servingGrams: Double = 100) -> FoodItem {
        FoodItem(
            id: .external("1"),
            source: .usdaFDC,
            externalID: "1",
            name: "Chicken breast, grilled",
            brand: nil,
            serving: Serving(amount: servingGrams, unit: "g"),
            facts: NutritionFacts(calories: 165, protein: 31, carbs: 0, fat: 3.6)
        )
    }

    private func bowlFood() -> FoodItem {
        FoodItem(
            id: .external("2"),
            source: .userCustom,
            externalID: nil,
            name: "Chicken rice bowl",
            brand: nil,
            serving: Serving(amount: 1, unit: "bowl"),
            facts: NutritionFacts(calories: 620, protein: 42, carbs: 68, fat: 16)
        )
    }

    @Test("a gram food opens on the user's usual serving, not on 1")
    func opensOnUsualServing() {
        // The whole point of the 2d sheet: the common case needs no adjustment.
        let stepper = PortionStepper(food: gramFood(), usualServings: 3.2)

        #expect(stepper.unit == .grams)
        #expect(abs(stepper.value - 320) < 0.001)
        #expect(stepper.displayValue == "320")
    }

    @Test("with no history a gram food opens on one serving")
    func fallsBackToOneServing() {
        let stepper = PortionStepper(food: gramFood(servingGrams: 118), usualServings: nil)

        #expect(abs(stepper.value - 118) < 0.001)
    }

    @Test("grams step in tens")
    func gramsStepInTens() {
        let stepper = PortionStepper(food: gramFood(), usualServings: 3.2)

        #expect(abs(stepper.incremented().value - 330) < 0.001)
        #expect(abs(stepper.decremented().value - 310) < 0.001)
    }

    @Test("stepping down stops above zero — a zero-quantity entry is rejected by the schema")
    func decrementClampsAboveZero() {
        var stepper = PortionStepper(food: gramFood(servingGrams: 10), usualServings: 1)
        #expect(abs(stepper.value - 10) < 0.001)

        stepper = stepper.decremented().decremented()

        #expect(stepper.value > 0)
        #expect(abs(stepper.value - 10) < 0.001)
    }

    @Test("a non-mass food steps in half servings and says so")
    func servingFoodStepsInHalves() {
        let stepper = PortionStepper(food: bowlFood(), usualServings: 1)

        #expect(stepper.unit == .servings(label: "bowl"))
        #expect(stepper.displayValue == "1")
        #expect(stepper.displayUnit == "bowl")

        let bigger = stepper.incremented()
        #expect(abs(bigger.value - 1.5) < 0.001)
        #expect(bigger.displayValue == "1.5")
        #expect(bigger.displayUnit == "bowls")
    }

    @Test("half servings never step below half")
    func servingsClampAtHalf() {
        let stepper = PortionStepper(food: bowlFood(), usualServings: 0.5)

        #expect(abs(stepper.decremented().value - 0.5) < 0.001)
    }

    @Test("macros recompute live from the stepped quantity")
    func factsFollowTheQuantity() {
        // 320 g of a food whose facts are quoted per 100 g.
        let stepper = PortionStepper(food: gramFood(servingGrams: 100), usualServings: 3.2)

        let facts = stepper.facts

        #expect(abs(stepper.servings - 3.2) < 0.001)
        #expect(abs(facts.calories - 528) < 0.001)
    }

    @Test("a whole-serving quantity drops the decimal point")
    func wholeServingsFormatCleanly() {
        let stepper = PortionStepper(food: bowlFood(), usualServings: 2)
        #expect(stepper.displayValue == "2")
    }
}
