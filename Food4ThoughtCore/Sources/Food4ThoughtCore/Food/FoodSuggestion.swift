import Foundation

/// A food offered in the log sheet, together with why it is being offered.
///
/// The reason is not decoration: it drives the ordering, and it is what the row
/// shows as its subtitle. "★" and "Recent" tell the user why this thing is in
/// front of them, which is what makes a recents-first list feel picked rather
/// than random.
public struct FoodSuggestion: Identifiable, Equatable, Sendable {
    public enum Origin: Equatable, Sendable {
        case favorite
        case recent(lastLoggedAt: Date, timesLogged: Int)
        /// A cached `food_items` row matching the query.
        case catalogue
        /// A fresh FoodData Central hit, not yet cached.
        case usda

        /// Lower sorts first. Favourites are things the user marked on purpose,
        /// so they outrank even today's logs.
        var rank: Int {
            switch self {
            case .favorite: 0
            case .recent: 1
            case .catalogue: 2
            case .usda: 3
            }
        }
    }

    public let item: FoodItem
    public let origin: Origin

    /// The quantity this user usually logs, in servings, when they have logged
    /// it before. Feeds `PortionStepper`'s opening value.
    public let usualServings: Double?

    public var id: FoodItem.Identity { item.id }

    public init(item: FoodItem, origin: Origin, usualServings: Double? = nil) {
        self.item = item
        self.origin = origin
        self.usualServings = usualServings
    }
}
