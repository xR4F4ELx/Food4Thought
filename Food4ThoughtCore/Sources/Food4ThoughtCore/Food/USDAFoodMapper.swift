import Foundation

/// Turns a FoodData Central search payload into foods the app can log.
///
/// The one rule worth remembering: **FDC quotes every nutrient per 100 g**,
/// including on branded rows that also carry a label serving. So a branded
/// 240 g yogurt has to be scaled up from the per-100 g figures; taking them at
/// face value against the 240 g serving under-reports the entry by well over
/// half.
public enum USDAFoodMapper {

    /// USDA nutrient numbers. Stable across dataset types, unlike `nutrientId`.
    private enum Nutrient {
        static let energyKcal = "208"
        static let energyKJ = "268"
        /// Atwater-specific energy, present on newer Foundation rows.
        static let energyGeneralFactors = "957"
        static let energySpecificFactors = "958"
        static let protein = "203"
        static let fat = "204"
        static let carbs = "205"
    }

    private static let kilojoulesPerKilocalorie = 4.184

    public static func items(from response: USDASearchResponse) -> [FoodItem] {
        response.foods.compactMap(item(from:))
    }

    public static func item(from food: USDAFood) -> FoodItem? {
        let name = food.description.trimmingCharacters(in: .whitespacesAndNewlines)

        // food_items requires a non-blank name, and a row with no energy figure
        // would log as 0 kcal — silently under-counting the day, which is worse
        // than not offering the food at all.
        guard !name.isEmpty, let caloriesPer100g = energyPer100g(in: food.foodNutrients) else {
            return nil
        }

        let serving = serving(for: food)
        let scale = serving.amount / 100

        let facts = NutritionFacts(
            calories: caloriesPer100g,
            protein: value(of: Nutrient.protein, in: food.foodNutrients) ?? 0,
            carbs: value(of: Nutrient.carbs, in: food.foodNutrients) ?? 0,
            fat: value(of: Nutrient.fat, in: food.foodNutrients) ?? 0
        ).scaled(by: scale)

        return FoodItem(
            id: .external(String(food.fdcId)),
            source: .usdaFDC,
            externalID: String(food.fdcId),
            name: name,
            brand: brand(for: food),
            serving: serving,
            facts: facts
        )
    }

    // MARK: - Helpers

    /// Only a gram serving is used. A volume ("250 ml") would need a density to
    /// convert, and guessing one per food is exactly the kind of invented
    /// precision the product is meant to avoid — 100 g is honest instead.
    private static func serving(for food: USDAFood) -> Serving {
        guard let size = food.servingSize, size > 0,
              let unit = food.servingSizeUnit?.lowercased(),
              unit == "g" || unit == "grm" else {
            return .per100g
        }
        return Serving(amount: size, unit: "g")
    }

    private static func brand(for food: USDAFood) -> String? {
        let brand = (food.brandName ?? food.brandOwner)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return brand?.isEmpty == false ? brand : nil
    }

    /// Prefers a kcal figure, converts a kJ one, and falls back to the Atwater
    /// variants that newer Foundation rows use instead of 208.
    private static func energyPer100g(in nutrients: [USDANutrient]) -> Double? {
        if let kcal = value(of: Nutrient.energyKcal, in: nutrients) {
            return kcal
        }
        if let atwater = value(of: Nutrient.energySpecificFactors, in: nutrients)
            ?? value(of: Nutrient.energyGeneralFactors, in: nutrients) {
            return atwater
        }
        if let kilojoules = value(of: Nutrient.energyKJ, in: nutrients) {
            return kilojoules / kilojoulesPerKilocalorie
        }
        return nil
    }

    private static func value(of number: String, in nutrients: [USDANutrient]) -> Double? {
        nutrients.first { $0.nutrientNumber == number }?.value
    }
}
