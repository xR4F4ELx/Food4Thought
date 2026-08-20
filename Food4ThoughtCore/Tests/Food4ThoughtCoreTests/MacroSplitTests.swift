import Testing
@testable import Food4ThoughtCore

@Suite("Macro split")
struct MacroSplitTests {

    @Test("shares are of energy, not of weight")
    func splitIsByCalories() throws {
        // 50 g of each: by weight that is a third each, but fat carries more
        // than twice the energy of the other two, so by calories it is nearly
        // half the day.
        let split = try #require(MacroSplit(proteinGrams: 50, carbsGrams: 50, fatGrams: 50))

        #expect(abs(split.fat - 0.529) < 0.001)
        #expect(abs(split.protein - 0.235) < 0.001)
        #expect(abs(split.carbs - 0.235) < 0.001)
    }

    @Test("the three shares account for the whole day")
    func sharesSumToOne() throws {
        let split = try #require(MacroSplit(proteinGrams: 130, carbsGrams: 210, fatGrams: 62))

        #expect(abs(split.protein + split.carbs + split.fat - 1) < 0.0001)
    }

    @Test("a day with nothing logged has no split, rather than a split of zero")
    func emptyDayHasNoSplit() {
        // Drawn as an empty bar it would imply a day that was recorded and
        // contained nothing, which is a different claim from "not logged".
        #expect(MacroSplit(proteinGrams: 0, carbsGrams: 0, fatGrams: 0) == nil)
    }

    @Test("a day of one macro is all of that macro")
    func singleMacroDay() throws {
        let split = try #require(MacroSplit(proteinGrams: 0, carbsGrams: 100, fatGrams: 0))

        #expect(split.carbs == 1)
        #expect(split.protein == 0)
        #expect(split.fat == 0)
    }

    @Test("percentages add up to 100 even when the arithmetic says 99")
    func roundedPercentagesReconcile() throws {
        // A third each rounds to 33/33/33, and a reader who adds them finds 99.
        let even = try #require(MacroSplit(proteinGrams: 100, carbsGrams: 100, fatGrams: 400 / 9))
        let percentages = even.roundedPercentages

        #expect(percentages.protein + percentages.carbs + percentages.fat == 100)
    }

    @Test("every split reconciles to 100, whatever the inputs")
    func allSplitsReconcile() throws {
        let cases: [(Double, Double, Double)] = [
            (130, 210, 62), (1, 1, 1), (7, 300, 3), (0, 1, 99), (55.5, 12.25, 88.125)
        ]

        for (protein, carbs, fat) in cases {
            let split = try #require(MacroSplit(proteinGrams: protein, carbsGrams: carbs, fatGrams: fat))
            let percentages = split.roundedPercentages

            #expect(percentages.protein + percentages.carbs + percentages.fat == 100)
        }
    }

    @Test("negative grams cannot drag a share below zero")
    func negativesAreClamped() throws {
        let split = try #require(MacroSplit(proteinGrams: -20, carbsGrams: 100, fatGrams: 0))

        #expect(split.protein == 0)
        #expect(split.carbs == 1)
    }
}
