import Foundation
import Testing
import Food4ThoughtCore
@testable import Food4Thought

private let foodsUserID = UUID()

private func customFood(
    _ name: String,
    id: UUID = UUID(),
    kcal: Double = 300,
    serving: Serving = Serving(amount: 100, unit: "g")
) -> FoodItem {
    FoodItem(
        id: .stored(id),
        source: .userCustom,
        externalID: nil,
        name: name,
        brand: nil,
        serving: serving,
        facts: NutritionFacts(calories: kcal, protein: 10, carbs: 20, fat: 5)
    )
}

@Suite("Foods view model")
@MainActor
struct FoodsViewModelTests {

    @Test("both shelves load, and they are not the same list")
    func loadsBothShelves() async {
        // A starred USDA hit is a favourite nobody created; a home recipe is a
        // custom food nobody starred. Collapsing them would hide half of each.
        let mine = customFood("Adobo")
        let starred = FoodSuggestion(
            item: FoodItem(
                id: .stored(UUID()),
                source: .usdaFDC,
                externalID: "171077",
                name: "Banana, raw",
                brand: nil,
                serving: .per100g,
                facts: NutritionFacts(calories: 89, protein: 1, carbs: 23, fat: 0)
            ),
            origin: .favorite
        )

        let foods = FakeFoodRepository(favorites: [starred], customFoods: [mine])
        let viewModel = FoodsViewModel(userID: foodsUserID, foods: foods)

        await viewModel.load()

        #expect(viewModel.customFoods.map(\.name) == ["Adobo"])
        #expect(viewModel.favorites.map(\.item.name) == ["Banana, raw"])
    }

    @Test("each shelf reports its own emptiness")
    func emptinessIsPerShelf() async {
        let foods = FakeFoodRepository(customFoods: [customFood("Adobo")])
        let viewModel = FoodsViewModel(userID: foodsUserID, foods: foods)
        await viewModel.load()

        viewModel.shelf = .myFoods
        #expect(viewModel.isEmpty == false)

        viewModel.shelf = .favorites
        #expect(viewModel.isEmpty)
        #expect(viewModel.emptyMessage.contains("Star a food"))
    }

    // MARK: - Editing

    @Test("an edit keeps the row it is editing rather than creating a second food")
    func editPreservesStoredIdentity() async throws {
        // A new id here would leave every logged entry pointing at the old row
        // and the library showing two of everything.
        let id = UUID()
        let original = customFood("Adobo", id: id, kcal: 300)
        let foods = FakeFoodRepository(customFoods: [original])
        let viewModel = FoodsViewModel(userID: foodsUserID, foods: foods)
        await viewModel.load()

        var draft = CustomFoodDraft(food: original)
        draft.calories = "310"
        draft.name = "Chicken adobo"

        await viewModel.save(draft, to: original)

        let updated = try #require(await foods.updatedFoods.first)
        #expect(updated.storedID == id)
        #expect(updated.name == "Chicken adobo")
        #expect(updated.facts.calories == 310)
        #expect(updated.source == .userCustom)
        // The sheet closes only once the write has landed.
        #expect(viewModel.editing == nil)
    }

    @Test("an invalid draft is not written")
    func invalidDraftIsRefused() async {
        let original = customFood("Adobo")
        let foods = FakeFoodRepository(customFoods: [original])
        let viewModel = FoodsViewModel(userID: foodsUserID, foods: foods)

        var draft = CustomFoodDraft(food: original)
        draft.name = "   "

        await viewModel.save(draft, to: original)

        #expect(await foods.updatedFoods.isEmpty)
    }

    // MARK: - Deleting

    @Test("deleting an unused food removes it")
    func deleteRemovesUnusedFood() async {
        let id = UUID()
        let food = customFood("Adobo", id: id)
        let foods = FakeFoodRepository(customFoods: [food])
        let viewModel = FoodsViewModel(userID: foodsUserID, foods: foods)
        await viewModel.load()

        await viewModel.delete(food)

        #expect(await foods.deletedFoodIDs == [id])
        #expect(viewModel.customFoods.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("a food still used by logged meals is refused, and explained rather than errored")
    func deleteBlockedByHistoryIsExplained() async throws {
        // food_log_entries.food_item_id is ON DELETE RESTRICT. That is the
        // database protecting days that already happened, not a failure — so it
        // gets its own explanation and an offer to edit instead.
        let food = customFood("Adobo")
        let foods = FakeFoodRepository(
            customFoods: [food],
            deleteFoodFailure: FoodRepositoryError.foodInUse
        )
        let viewModel = FoodsViewModel(userID: foodsUserID, foods: foods)
        await viewModel.load()

        await viewModel.delete(food)

        let blocked = try #require(viewModel.blockedDeletion)
        #expect(blocked.name == "Adobo")
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.customFoods.count == 1)
    }

    @Test("a genuine delete failure is reported as an error")
    func deleteFailureIsReported() async {
        let food = customFood("Adobo")
        let foods = FakeFoodRepository(
            customFoods: [food],
            deleteFoodFailure: FoodRepositoryError.network
        )
        let viewModel = FoodsViewModel(userID: foodsUserID, foods: foods)
        await viewModel.load()

        await viewModel.delete(food)

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.blockedDeletion == nil)
    }

    // MARK: - Favourites

    @Test("unstarring drops the food from the favourites shelf")
    func unfavoriteRemovesFromShelf() async {
        let id = UUID()
        let starred = FoodSuggestion(item: customFood("Adobo", id: id), origin: .favorite)
        let foods = FakeFoodRepository(favorites: [starred])
        let viewModel = FoodsViewModel(userID: foodsUserID, foods: foods)
        await viewModel.load()

        #expect(viewModel.favorites.count == 1)

        await viewModel.unfavorite(starred.item)

        #expect(viewModel.favorites.isEmpty)
        #expect(await foods.storedFavorites.contains(id) == false)
    }
}
