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
}
