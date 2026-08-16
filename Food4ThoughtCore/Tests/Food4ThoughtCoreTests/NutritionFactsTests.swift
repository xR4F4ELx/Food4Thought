import Testing
@testable import Food4ThoughtCore

@Suite("NutritionFacts")
struct NutritionFactsTests {

    @Test("scaling multiplies every nutrient")
    func scalingMultipliesEveryNutrient() {
        // Arrange
        let per100g = NutritionFacts(calories: 165, protein: 31, carbs: 0, fat: 3.6)

        // Act
        let per240g = per100g.scaled(by: 2.4)

        // Assert
        #expect(abs(per240g.calories - 396) < 0.001)
        #expect(abs(per240g.protein - 74.4) < 0.001)
        #expect(abs(per240g.carbs - 0) < 0.001)
        #expect(abs(per240g.fat - 8.64) < 0.001)
    }

    @Test("scaling by zero is empty, not negative")
    func scalingByZero() {
        let scaled = NutritionFacts(calories: 165, protein: 31, carbs: 0, fat: 3.6).scaled(by: 0)
        #expect(scaled == .zero)
    }

    @Test("adding accumulates a meal")
    func addingAccumulates() {
        let rice = NutritionFacts(calories: 200, protein: 4, carbs: 44, fat: 0.5)
        let chicken = NutritionFacts(calories: 165, protein: 31, carbs: 0, fat: 3.6)

        let total = rice + chicken

        #expect(abs(total.calories - 365) < 0.001)
        #expect(abs(total.protein - 35) < 0.001)
    }

    @Test("negative nutrients are clamped away at the boundary")
    func negativesAreClamped() {
        // food_items has check constraints on every one of these columns, so a
        // negative would be rejected by the database anyway — better to never
        // build one.
        let facts = NutritionFacts(calories: -10, protein: -1, carbs: 5, fat: 2)

        #expect(facts.calories == 0)
        #expect(facts.protein == 0)
        #expect(facts.carbs == 5)
    }
}
