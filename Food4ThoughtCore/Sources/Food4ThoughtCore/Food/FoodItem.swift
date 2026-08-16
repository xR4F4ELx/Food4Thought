import Foundation

/// Mirrors the `source` check constraint on `food_items`.
public enum FoodSource: String, Codable, Sendable {
    case usdaFDC = "usda_fdc"
    case userCustom = "user_custom"
}

/// The portion a food's nutrients are quoted against — "100 g", "1 bowl".
public struct Serving: Equatable, Sendable {
    public let amount: Double
    public let unit: String

    /// Only a gram serving can be stepped by weight; everything else steps in
    /// servings, because there is no honest conversion from a bowl to a number.
    public var isMass: Bool { unit.lowercased() == "g" }

    public init(amount: Double, unit: String) {
        self.amount = max(0, amount)
        self.unit = unit
    }

    /// The default when a source gives no usable serving. USDA quotes nutrients
    /// per 100 g, so this is the portion its figures already describe.
    public static let per100g = Serving(amount: 100, unit: "g")
}

/// A food the user can log, whether it lives in `food_items` yet or not.
public struct FoodItem: Identifiable, Equatable, Sendable {
    /// A search result can be a row we already hold or a USDA hit nobody has
    /// cached. Making that a type rather than an optional UUID means the code
    /// that logs an entry cannot forget to resolve one into the other — a
    /// `food_log_entries.food_item_id` has to point at a real row.
    public enum Identity: Hashable, Sendable {
        case stored(UUID)
        case external(String)
    }

    public let id: Identity
    public let source: FoodSource
    public let externalID: String?
    public let name: String
    public let brand: String?
    public let serving: Serving

    /// Nutrients for exactly one `serving`.
    public let facts: NutritionFacts

    public init(
        id: Identity,
        source: FoodSource,
        externalID: String?,
        name: String,
        brand: String?,
        serving: Serving,
        facts: NutritionFacts
    ) {
        self.id = id
        self.source = source
        self.externalID = externalID
        self.name = name
        self.brand = brand
        self.serving = serving
        self.facts = facts
    }

    public var storedID: UUID? {
        if case .stored(let uuid) = id { return uuid }
        return nil
    }

    /// "1 bowl · 320 g" style subtitle for a search row.
    public var servingDescription: String {
        let amount = PortionFormatter.string(from: serving.amount)
        return "\(amount) \(serving.unit)"
    }
}
