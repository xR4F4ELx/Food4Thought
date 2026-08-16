import Foundation

/// The slice of FoodData Central's `/v1/foods/search` payload we read.
///
/// Decodable lives in Core rather than in the networking layer so the mapping
/// is testable against fixtures without a URLSession anywhere near it — the
/// shape of this response is exactly the kind of thing that changes under you.
public struct USDASearchResponse: Decodable, Sendable {
    public let foods: [USDAFood]

    public init(foods: [USDAFood]) {
        self.foods = foods
    }
}

public struct USDAFood: Decodable, Sendable {
    public let fdcId: Int
    public let description: String
    public let dataType: String?
    public let brandOwner: String?
    public let brandName: String?
    public let servingSize: Double?
    public let servingSizeUnit: String?
    public let foodNutrients: [USDANutrient]
}

public struct USDANutrient: Decodable, Sendable {
    /// The stable identifier across dataset types — `nutrientId` is not.
    public let nutrientNumber: String?
    public let unitName: String?
    public let value: Double?
}
