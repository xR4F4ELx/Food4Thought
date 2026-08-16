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
    /// A custom food still referenced by log entries.
    case foodInUse
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            "You're signed out. Sign in and try again."
        case .network:
            "No connection. Your entry hasn't been saved yet."
        case .foodInUse:
            // `food_log_entries.food_item_id` is ON DELETE RESTRICT, and that
            // is the right call: those entries snapshot their own nutrients,
            // so the food is still the label on days that already happened.
            "This food is in meals you've already logged, so it can't be deleted. Edit it instead — past meals keep the figures they were logged with."
        case .unexpected(let reason):
            reason
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

    /// Saves a hand-entered food and returns it with its real row id.
    ///
    /// Separate from `cacheIfNeeded` because a custom food has no
    /// `external_id` to upsert against — it is always a fresh row, and two
    /// foods with the same name are two different foods.
    func createCustomFood(_ item: FoodItem, userID: UUID) async throws -> FoodItem

    /// Inserts entries and rebuilds the balance rollup for the affected day.
    func log(_ drafts: [FoodLogDraft], userID: UUID) async throws

    /// Removes one entry and rebuilds the rollup for the day it fell on.
    ///
    /// The rebuild is not optional. `balance_days` is stored rather than
    /// derived, so a delete that skips it leaves the balance carrying calories
    /// the user has just said they never ate — the same reason `log` rebuilds.
    func deleteEntry(id: UUID, loggedAt: Date, userID: UUID) async throws

    /// Every food this user has created by hand, for the Foods tab.
    func customFoods(userID: UUID) async throws -> [FoodItem]

    /// Rewrites one of the user's own foods.
    ///
    /// Past entries are untouched by design: they snapshot their nutrients at
    /// log time, so fixing a typo in a food's calories corrects it going
    /// forward without rewriting days the user already lived.
    func updateCustomFood(_ item: FoodItem, userID: UUID) async throws -> FoodItem

    /// Deletes one of the user's own foods. Throws `.foodInUse` when log
    /// entries still point at it.
    func deleteCustomFood(id: UUID, userID: UUID) async throws

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
