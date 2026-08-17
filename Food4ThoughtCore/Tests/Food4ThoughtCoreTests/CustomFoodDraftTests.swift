import Foundation
import Testing
@testable import Food4ThoughtCore

@Suite("CustomFoodDraft")
struct CustomFoodDraftTests {

    private func valid() -> CustomFoodDraft {
        CustomFoodDraft(
            name: "Mum's adobo",
            brand: "",
            servingAmount: "250",
            servingUnit: "g",
            calories: "420",
            protein: "28",
            carbs: "12",
            fat: "26"
        )
    }

    @Test("a complete draft becomes a user_custom food quoted per serving")
    func completeDraftValidates() throws {
        let item = try #require(valid().validated)

        #expect(item.source == .userCustom)
        #expect(item.externalID == nil)
        #expect(item.name == "Mum's adobo")
        #expect(item.serving == Serving(amount: 250, unit: "g"))
        #expect(abs(item.facts.calories - 420) < 0.001)
        #expect(abs(item.facts.protein - 28) < 0.001)
    }

    @Test("name and calories are the only required fields — everything else has a sane default")
    func macrosDefaultToZero() throws {
        var draft = valid()
        draft.protein = ""
        draft.carbs = ""
        draft.fat = ""

        let item = try #require(draft.validated)

        #expect(item.facts.protein == 0)
        #expect(item.facts.carbs == 0)
        #expect(abs(item.facts.calories - 420) < 0.001)
    }

    @Test("a blank serving falls back to one serving rather than blocking the save")
    func blankServingFallsBack() throws {
        var draft = valid()
        draft.servingAmount = ""
        draft.servingUnit = ""

        let item = try #require(draft.validated)

        #expect(item.serving == Serving(amount: 1, unit: "serving"))
    }

    @Test("a nameless food is rejected — food_items requires a name")
    func blankNameIsRejected() {
        var draft = valid()
        draft.name = "   "

        #expect(draft.validated == nil)
        #expect(draft.problem == .missingName)
    }

    @Test("calories must be a number, since the whole entry is built on it")
    func nonNumericCaloriesRejected() {
        var draft = valid()
        draft.calories = "about 400"

        #expect(draft.validated == nil)
        #expect(draft.problem == .invalidCalories)
    }

    @Test("blank calories are rejected rather than silently logged as zero")
    func blankCaloriesRejected() {
        var draft = valid()
        draft.calories = ""

        #expect(draft.problem == .invalidCalories)
    }

    @Test("a negative number is rejected at the boundary, not by the check constraint")
    func negativeCaloriesRejected() {
        var draft = valid()
        draft.calories = "-5"

        #expect(draft.problem == .invalidCalories)
    }

    @Test("a zero serving is rejected — it would make every scaled quantity meaningless")
    func zeroServingRejected() {
        var draft = valid()
        draft.servingAmount = "0"

        #expect(draft.problem == .invalidServing)
    }

    @Test("a comma decimal is read as a decimal, not thrown out")
    func commaDecimalIsAccepted() throws {
        // Plenty of labels, and plenty of keyboards, produce "12,5".
        var draft = valid()
        draft.protein = "12,5"

        let item = try #require(draft.validated)
        #expect(abs(item.facts.protein - 12.5) < 0.001)
    }

    @Test("a blank brand stays nil rather than becoming an empty string")
    func blankBrandIsNil() throws {
        let item = try #require(valid().validated)
        #expect(item.brand == nil)
    }

    @Test("surrounding whitespace is trimmed off the name")
    func nameIsTrimmed() throws {
        var draft = valid()
        draft.name = "  Adobo  "

        #expect(try #require(draft.validated).name == "Adobo")
    }

    @Test("a saved food reopens as an editable draft that round-trips")
    func reopensSavedFoodForEditing() throws {
        // Arrange — what the Foods tab hands the edit sheet.
        let saved = FoodItem(
            id: .stored(UUID()),
            source: .userCustom,
            externalID: nil,
            name: "Adobo",
            brand: "Lola's",
            serving: Serving(amount: 220, unit: "g"),
            facts: NutritionFacts(calories: 310, protein: 24, carbs: 8, fat: 19)
        )

        // Act
        let draft = CustomFoodDraft(food: saved)

        // Assert — whole numbers keep their decimal point off, so a form the
        // user only opened to read doesn't look pre-edited.
        #expect(draft.name == "Adobo")
        #expect(draft.brand == "Lola's")
        #expect(draft.servingAmount == "220")
        #expect(draft.servingUnit == "g")
        #expect(draft.calories == "310")
        #expect(draft.protein == "24")

        let revalidated = try #require(draft.validated)
        #expect(revalidated.name == saved.name)
        #expect(revalidated.serving == saved.serving)
        #expect(revalidated.facts == saved.facts)
    }

    @Test("a food with no brand reopens with an empty brand field, not the word nil")
    func reopensWithoutBrand() {
        let saved = FoodItem(
            id: .stored(UUID()),
            source: .userCustom,
            externalID: nil,
            name: "Rice",
            brand: nil,
            serving: Serving(amount: 150.5, unit: "g"),
            facts: NutritionFacts(calories: 195.5, protein: 4, carbs: 43, fat: 0)
        )

        let draft = CustomFoodDraft(food: saved)

        #expect(draft.brand.isEmpty)
        // Fractional figures keep their decimal — rounding here would edit the
        // user's food behind their back just for opening the screen.
        #expect(draft.servingAmount == "150.5")
        #expect(draft.calories == "195.5")
    }

    @Test("a blank serving means one serving, not one gram")
    func blankServingIsOneServing() throws {
        // The unit field defaults to "g", so falling back to 1 quoted a home
        // recipe at 310 kcal *per gram* — and the quantity step then opens in
        // grams and offers 3,100 kcal as its starting portion. The form says
        // only calories are required, so this path has to stay honest.
        var draft = CustomFoodDraft()
        draft.name = "Lola's adobo"
        draft.calories = "310"

        let food = try #require(draft.validated)
        #expect(food.serving.amount == 1)
        #expect(food.serving.unit == "serving")
        #expect(food.serving.isMass == false)

        // And the portion step opens on one serving, not ten grams.
        let portion = PortionStepper(food: food, usualServings: nil)
        #expect(portion.displayValue == "1")
        #expect(portion.facts.calories == 310)
    }

    @Test("an entered serving is used as typed")
    func enteredServingIsHonoured() throws {
        var draft = CustomFoodDraft()
        draft.name = "Lola's adobo"
        draft.calories = "310"
        draft.servingAmount = "220"

        let food = try #require(draft.validated)
        #expect(food.serving.amount == 220)
        #expect(food.serving.unit == "g")
        #expect(food.serving.isMass)
    }

    @Test("an amount with no unit is a serving, not a bare number")
    func amountWithoutUnitFallsBackToServings() throws {
        var draft = CustomFoodDraft(servingUnit: "")
        draft.name = "Adobo"
        draft.calories = "310"
        draft.servingAmount = "2"

        let food = try #require(draft.validated)
        #expect(food.serving.amount == 2)
        #expect(food.serving.unit == "serving")
    }
}
