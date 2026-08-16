import Foundation
import Food4ThoughtCore

/// One entry on its way into `food_log_entries`.
///
/// Nutrients are carried rather than looked up at insert time because the
/// column set is snapshotted: correcting a cached `food_items` row later must
/// never silently rewrite what the user already logged.
struct FoodLogDraft: Equatable, Sendable {
    let foodItemID: UUID
    let mealKey: String
    let quantity: Double
    let facts: NutritionFacts
    let loggedAt: Date

    init(
        foodItemID: UUID,
        mealKey: String,
        quantity: Double,
        facts: NutritionFacts,
        loggedAt: Date = .now
    ) {
        self.foodItemID = foodItemID
        self.mealKey = mealKey
        self.quantity = quantity
        self.facts = facts
        self.loggedAt = loggedAt
    }
}

enum FoodRepositoryError: LocalizedError, Equatable {
    case notSignedIn
    case network
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "You're signed out. Sign in and try again."
        case .network: "No connection. Your entry hasn't been saved yet."
        case .unexpected(let reason): reason
        }
    }
}

protocol FoodRepository: Sendable {
    /// Everything logged in the last `days`, collapsed to one row per food with
    /// the quantity that user usually picks. The default fast path.
    func recents(userID: UUID, withinDays days: Int) async throws -> [FoodSuggestion]

    func favorites(userID: UUID) async throws -> [FoodSuggestion]

    /// Trigram search over the cached catalogue — `food_items` carries the
    /// index for it, so a repeat lookup never has to reach USDA.
    func searchCatalogue(matching query: String, userID: UUID) async throws -> [FoodSuggestion]

    /// Yesterday's entries for one slot, ready to re-log unchanged.
    func entriesForCopy(
        userID: UUID,
        mealKey: String,
        daysAgo: Int
    ) async throws -> [CopyableEntry]

    /// Gives a USDA hit a `food_items` row so an entry can point at it, or
    /// returns the id of the row that already caches it.
    func cacheIfNeeded(_ item: FoodItem, userID: UUID) async throws -> UUID

    /// Inserts entries and rebuilds the balance rollup for the affected day.
    func log(_ drafts: [FoodLogDraft], userID: UUID) async throws

    func favoriteIDs(userID: UUID) async throws -> Set<UUID>

    func setFavorite(_ isFavorite: Bool, foodItemID: UUID, userID: UUID) async throws

    /// The user's single "Quick add" row, created on first use. Quick add still
    /// has to point at a food item — `food_log_entries.food_item_id` is not
    /// nullable — so one reusable row stands in for all of them rather than
    /// littering the catalogue with one throwaway food per entry.
    func quickAddItem(userID: UUID) async throws -> FoodItem
}

/// A past entry offered back for one-tap re-logging.
struct CopyableEntry: Equatable, Sendable, Identifiable {
    let id: UUID
    let item: FoodItem
    let quantity: Double
    let facts: NutritionFacts
}
