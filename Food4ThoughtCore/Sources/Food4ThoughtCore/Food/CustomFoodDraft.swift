import Foundation

/// What stops a hand-entered food from being saved.
public enum CustomFoodProblem: Equatable, Sendable {
    case missingName
    case invalidCalories
    case invalidServing

    public var message: String {
        switch self {
        case .missingName: "Give it a name."
        case .invalidCalories: "Enter the calories as a number."
        case .invalidServing: "A serving has to be more than zero."
        }
    }
}

/// The form behind "create a food", held as raw text.
///
/// Text rather than parsed numbers because that is what a `TextField` produces,
/// and because a half-typed "12." has to survive being typed. Validation is a
/// computed property, so the save button reflects the form on every keystroke
/// without anything having to remember to re-run it.
///
/// Only name and calories are required. Everything else defaults, because this
/// screen exists for the food that is not in any database — usually something
/// home-cooked, where the honest answer to "how much protein" is a shrug, and
/// demanding one would just stop the entry from being made at all.
public struct CustomFoodDraft: Equatable, Sendable {
    public var name: String
    public var brand: String
    public var servingAmount: String
    public var servingUnit: String
    public var calories: String
    public var protein: String
    public var carbs: String
    public var fat: String

    public init(
        name: String = "",
        brand: String = "",
        servingAmount: String = "",
        servingUnit: String = "g",
        calories: String = "",
        protein: String = "",
        carbs: String = "",
        fat: String = ""
    ) {
        self.name = name
        self.brand = brand
        self.servingAmount = servingAmount
        self.servingUnit = servingUnit
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    /// Reopens a saved food for editing.
    ///
    /// Figures are formatted the way they were typed rather than as raw
    /// Doubles: "220" is what someone entered and what they expect to see, and
    /// putting "220.0" in the field makes a form they only came to glance at
    /// look like it has already been changed.
    public init(food: FoodItem) {
        self.init(
            name: food.name,
            brand: food.brand ?? "",
            servingAmount: PortionFormatter.string(from: food.serving.amount),
            servingUnit: food.serving.unit,
            calories: PortionFormatter.string(from: food.facts.calories),
            protein: PortionFormatter.string(from: food.facts.protein),
            carbs: PortionFormatter.string(from: food.facts.carbs),
            fat: PortionFormatter.string(from: food.facts.fat)
        )
    }

    /// The first thing wrong with the draft, or nil when it is ready to save.
    public var problem: CustomFoodProblem? {
        guard !trimmed(name).isEmpty else { return .missingName }
        guard let calories = number(calories), calories >= 0 else { return .invalidCalories }
        // A blank serving is fine and defaults; an explicit zero is not, because
        // every scaled quantity would divide by it.
        if !trimmed(servingAmount).isEmpty {
            guard let amount = number(servingAmount), amount > 0 else { return .invalidServing }
        }
        return nil
    }

    public var validated: FoodItem? {
        guard problem == nil else { return nil }

        let brand = trimmed(brand)
        let serving = resolvedServing

        return FoodItem(
            // No row exists yet; the repository swaps this for a real id on save.
            id: .external(UUID().uuidString),
            source: .userCustom,
            externalID: nil,
            name: trimmed(name),
            brand: brand.isEmpty ? nil : brand,
            serving: serving,
            facts: NutritionFacts(
                calories: number(calories) ?? 0,
                protein: number(protein) ?? 0,
                carbs: number(carbs) ?? 0,
                fat: number(fat) ?? 0
            )
        )
    }

    /// The portion the entered figures are quoted against.
    ///
    /// A blank amount means one serving of the thing, not one *gram* of it.
    /// The unit field defaults to "g", so falling back to `1` with that unit
    /// quoted a home recipe at 310 kcal per gram — and the quantity step would
    /// then open in grams and offer 3,100 kcal as a starting portion. The form
    /// says only calories are required, so leaving the serving blank has to
    /// produce something honest rather than something off by a hundredfold.
    private var resolvedServing: Serving {
        let unit = trimmed(servingUnit)

        guard let amount = number(servingAmount) else {
            return Serving(amount: 1, unit: "serving")
        }
        return Serving(amount: amount, unit: unit.isEmpty ? "serving" : unit)
    }

    // MARK: - Helpers

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Accepts a comma decimal. Plenty of labels and plenty of keyboards
    /// produce "12,5", and rejecting it reads as the app being broken.
    private func number(_ value: String) -> Double? {
        let normalised = trimmed(value).replacingOccurrences(of: ",", with: ".")
        guard !normalised.isEmpty else { return nil }
        return Double(normalised)
    }
}
