/// The four figures every screen in the app is built from.
///
/// Always describes *one serving* of whatever holds it — scaling to a logged
/// quantity is `scaled(by:)`, and is the caller's job. Keeping the unit
/// implicit in "one serving" rather than in grams is what lets a bowl, a scoop
/// and 100 g of rice share a type.
public struct NutritionFacts: Equatable, Sendable {
    public let calories: Double
    public let protein: Double
    public let carbs: Double
    public let fat: Double

    public static let zero = NutritionFacts(calories: 0, protein: 0, carbs: 0, fat: 0)

    /// Negatives are clamped at construction. `food_items` and
    /// `food_log_entries` both carry `>= 0` check constraints on these columns,
    /// so a negative is a value that can never be stored — better to refuse it
    /// here than to fail at the insert.
    public init(calories: Double, protein: Double, carbs: Double, fat: Double) {
        self.calories = max(0, calories)
        self.protein = max(0, protein)
        self.carbs = max(0, carbs)
        self.fat = max(0, fat)
    }

    public func scaled(by factor: Double) -> NutritionFacts {
        NutritionFacts(
            calories: calories * factor,
            protein: protein * factor,
            carbs: carbs * factor,
            fat: fat * factor
        )
    }

    public static func + (lhs: NutritionFacts, rhs: NutritionFacts) -> NutritionFacts {
        NutritionFacts(
            calories: lhs.calories + rhs.calories,
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat
        )
    }
}
