import Foundation
import Food4ThoughtCore

/// The `food_items` columns the logging flow reads, and the translation to and
/// from the Core type.
///
/// Kept apart from `FoodItem` so the domain type never grows Codable keys tied
/// to one table's column names — the same food arrives from USDA too, shaped
/// completely differently.
struct FoodItemRow: Codable, Sendable {
    let id: UUID
    let source: String
    let externalID: String?
    let name: String
    let brand: String?
    let servingSize: Double?
    let servingUnit: String?
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case externalID = "external_id"
        case name
        case brand
        case servingSize = "serving_size"
        case servingUnit = "serving_unit"
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }

    var foodItem: FoodItem {
        FoodItem(
            id: .stored(id),
            source: FoodSource(rawValue: source) ?? .userCustom,
            externalID: externalID,
            name: name,
            brand: brand,
            // Both columns are nullable; a row without a serving is quoted per
            // 100 g, which is what USDA's figures mean anyway.
            serving: servingSize.map { Serving(amount: $0, unit: servingUnit ?? "g") } ?? .per100g,
            facts: NutritionFacts(calories: calories, protein: proteinG, carbs: carbsG, fat: fatG)
        )
    }
}

/// The insert shape. `created_by` is set for custom foods only — USDA rows are
/// a shared cache, and stamping an owner on one would make it look private.
struct NewFoodItemRow: Encodable, Sendable {
    let source: String
    let externalID: String?
    let createdBy: UUID?
    let name: String
    let brand: String?
    let servingSize: Double
    let servingUnit: String
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    enum CodingKeys: String, CodingKey {
        case source
        case externalID = "external_id"
        case createdBy = "created_by"
        case name
        case brand
        case servingSize = "serving_size"
        case servingUnit = "serving_unit"
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }

    init(item: FoodItem, userID: UUID) {
        source = item.source.rawValue
        externalID = item.externalID
        createdBy = item.source == .userCustom ? userID : nil
        name = item.name
        brand = item.brand
        servingSize = max(item.serving.amount, 0.01)
        servingUnit = item.serving.unit
        calories = item.facts.calories
        proteinG = item.facts.protein
        carbsG = item.facts.carbs
        fatG = item.facts.fat
    }
}

/// The `food_log_entries` insert shape.
struct NewFoodLogEntryRow: Encodable, Sendable {
    let userID: UUID
    let foodItemID: UUID
    let loggedAt: Date
    let mealKey: String
    let quantity: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case foodItemID = "food_item_id"
        case loggedAt = "logged_at"
        case mealKey = "meal_key"
        case quantity
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }

    init(draft: FoodLogDraft, userID: UUID) {
        self.userID = userID
        foodItemID = draft.foodItemID
        loggedAt = draft.loggedAt
        mealKey = draft.mealKey
        quantity = draft.quantity
        calories = draft.facts.calories
        proteinG = draft.facts.protein
        carbsG = draft.facts.carbs
        fatG = draft.facts.fat
    }
}
