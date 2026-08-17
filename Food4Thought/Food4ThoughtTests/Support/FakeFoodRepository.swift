import Foundation
import Food4ThoughtCore
@testable import Food4Thought

/// Shared by the logging, Today and Foods suites — one fake so a protocol
/// change surfaces in one place rather than three.
actor FakeFoodRepository: FoodRepository {
    var recentSuggestions: [FoodSuggestion] = []
    var favoriteSuggestions: [FoodSuggestion] = []
    var catalogueResults: [FoodSuggestion] = []
    var copyables: [CopyableEntry] = []
    var storedFavorites: Set<UUID> = []
    private(set) var logged: [[FoodLogDraft]] = []
    private(set) var cachedItems: [FoodItem] = []
    private(set) var quickAddRequests = 0
    private(set) var deletedEntryIDs: [UUID] = []
    private(set) var deletedFoodIDs: [UUID] = []
    private(set) var updatedFoods: [FoodItem] = []
    private(set) var createdFoods: [FoodItem] = []
    var storedCustomFoods: [FoodItem] = []
    private var logFailure: (any Error)?
    private var updateFailure: (any Error)?
    private var deleteFailure: (any Error)?
    private var deleteFoodFailure: (any Error)?

    /// The id handed back for a USDA hit that had to be cached first.
    let newlyCachedID = UUID()

    init(
        recents: [FoodSuggestion] = [],
        favorites: [FoodSuggestion] = [],
        catalogue: [FoodSuggestion] = [],
        copyables: [CopyableEntry] = [],
        customFoods: [FoodItem] = [],
        logFailure: (any Error)? = nil,
        updateFailure: (any Error)? = nil,
        deleteFailure: (any Error)? = nil,
        deleteFoodFailure: (any Error)? = nil
    ) {
        self.recentSuggestions = recents
        self.favoriteSuggestions = favorites
        self.catalogueResults = catalogue
        self.copyables = copyables
        self.storedCustomFoods = customFoods
        self.logFailure = logFailure
        self.updateFailure = updateFailure
        self.deleteFailure = deleteFailure
        self.deleteFoodFailure = deleteFoodFailure
    }

    func recents(userID: UUID, withinDays days: Int) async throws -> [FoodSuggestion] { recentSuggestions }
    func favorites(userID: UUID) async throws -> [FoodSuggestion] { favoriteSuggestions }
    func searchCatalogue(matching query: String, userID: UUID) async throws -> [FoodSuggestion] { catalogueResults }
    func entriesForCopy(userID: UUID, mealKey: String, daysAgo: Int) async throws -> [CopyableEntry] { copyables }

    func cacheIfNeeded(_ item: FoodItem, userID: UUID) async throws -> UUID {
        cachedItems.append(item)
        return item.storedID ?? newlyCachedID
    }

    func createCustomFood(_ item: FoodItem, userID: UUID) async throws -> FoodItem {
        cachedItems.append(item)
        createdFoods.append(item)

        let saved = FoodItem(
            id: .stored(newlyCachedID),
            source: item.source,
            externalID: item.externalID,
            name: item.name,
            brand: item.brand,
            serving: item.serving,
            facts: item.facts
        )
        // Lands in the library too, so a reload after creating sees it — the
        // Foods tab reads this list back and would otherwise look unchanged.
        storedCustomFoods.append(saved)
        return saved
    }

    func log(_ drafts: [FoodLogDraft], userID: UUID) async throws {
        if let logFailure { throw logFailure }
        logged.append(drafts)
    }

    func deleteEntry(id: UUID, loggedAt: Date, userID: UUID) async throws {
        if let deleteFailure { throw deleteFailure }
        deletedEntryIDs.append(id)
    }

    func customFoods(userID: UUID) async throws -> [FoodItem] { storedCustomFoods }

    func updateCustomFood(_ item: FoodItem, userID: UUID) async throws -> FoodItem {
        if let updateFailure { throw updateFailure }
        updatedFoods.append(item)
        storedCustomFoods = storedCustomFoods.map { $0.id == item.id ? item : $0 }
        return item
    }

    func deleteCustomFood(id: UUID, userID: UUID) async throws {
        if let deleteFoodFailure { throw deleteFoodFailure }
        deletedFoodIDs.append(id)
        storedCustomFoods = storedCustomFoods.filter { $0.storedID != id }
    }

    func favoriteIDs(userID: UUID) async throws -> Set<UUID> { storedFavorites }

    func setFavorite(_ isFavorite: Bool, foodItemID: UUID, userID: UUID) async throws {
        if isFavorite {
            storedFavorites.insert(foodItemID)
        } else {
            storedFavorites.remove(foodItemID)
            // The shelf reads back through `favorites`, so unstarring has to
            // move that list too — otherwise a test can pass against a set
            // nothing on screen is built from.
            favoriteSuggestions = favoriteSuggestions.filter { $0.item.storedID != foodItemID }
        }
    }

    func quickAddItem(userID: UUID) async throws -> FoodItem {
        quickAddRequests += 1
        return FoodItem(
            id: .stored(newlyCachedID),
            source: .userCustom,
            externalID: nil,
            name: "Quick add",
            brand: nil,
            serving: Serving(amount: 1, unit: "kcal"),
            facts: NutritionFacts(calories: 1, protein: 0, carbs: 0, fat: 0)
        )
    }
}
