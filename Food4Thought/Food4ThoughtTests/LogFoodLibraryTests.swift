import Foundation
import Testing
import Food4ThoughtCore
@testable import Food4Thought

/// The "My foods" shelf inside the log sheet — the user's own library.
///
/// It used to be its own tab. The shelf replaced it because everything the tab
/// did (create, correct, remove) is something you want while you are already
/// looking at a list of foods to log, and a tab of its own cost a permanent
/// slot in the bar for a screen opened once a month.

private let libraryUserID = UUID()

private func libraryFood(
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

private actor LibraryProfileRepository: ProfileRepository {
    func hasCompletedOnboarding(userID: UUID) async throws -> Bool { true }
    func currentDetails(userID: UUID) async throws -> ProfileDetails? { nil }
    func activeGoalSet(userID: UUID) async throws -> GoalSetSummary? { nil }
    func completeOnboarding(_ submission: OnboardingSubmission) async throws {}
    func syncTimeZone(_ identifier: String, userID: UUID) async throws -> TimeZoneSyncResult { .unchanged }
    func mealSchedule(userID: UUID) async throws -> MealSchedule { MealSchedule.Preset.threeMeals.schedule }
    func updateMealSchedule(_ schedule: MealSchedule, userID: UUID) async throws {}
    #if DEBUG
    func resetOnboarding(userID: UUID) async throws {}
    #endif
}

private struct SilentUSDAClient: USDAFoodSearching {
    var isConfigured = true
    func search(_ query: String) async throws -> [FoodItem] { [] }
}

@MainActor
private func makeLibraryViewModel(_ foods: FakeFoodRepository) async -> LogFoodViewModel {
    let viewModel = LogFoodViewModel(
        userID: libraryUserID,
        foods: foods,
        profiles: LibraryProfileRepository(),
        usda: SilentUSDAClient(),
        searchDebounce: .zero
    )
    await viewModel.load()
    await viewModel.select(path: .myFoods)
    return viewModel
}

@Suite("My foods shelf")
@MainActor
struct LogFoodLibraryTests {

    @Test("the shelf shows the foods this user made, not what they logged")
    func shelfListsCustomFoods() async {
        // Recents and favourites answer "what do you eat"; this shelf answers
        // "what have you written down", which is a different set — a recipe
        // entered on Sunday has never been logged.
        let foods = FakeFoodRepository(
            recents: [FoodSuggestion(item: libraryFood("Banana"), origin: .catalogue)],
            customFoods: [libraryFood("Adobo")]
        )
        let viewModel = await makeLibraryViewModel(foods)

        #expect(viewModel.path == .myFoods)
        #expect(viewModel.myFoods.map(\.name) == ["Adobo"])
        #expect(viewModel.suggestions.isEmpty)
    }

    // MARK: - Creating

    @Test("a food created from the shelf lands in it, saved, before anything is logged")
    func createStocksTheShelf() async throws {
        let foods = FakeFoodRepository()
        let viewModel = await makeLibraryViewModel(foods)

        await viewModel.createCustomFood(
            CustomFoodDraft(name: "Adobo", servingAmount: "220", servingUnit: "g", calories: "310")
        )

        let created = try #require(await foods.createdFoods.first)
        #expect(created.name == "Adobo")
        #expect(created.source == .userCustom)
        #expect(created.facts.calories == 310)
        // The shelf behind the quantity step shows it, so dismissing without
        // logging does not read as the save having failed.
        #expect(viewModel.myFoods.map(\.name) == ["Adobo"])
        // The library grew; the day did not. Nothing is written to today until
        // the quantity step is confirmed.
        #expect(await foods.logged.isEmpty)
    }

    @Test("an invalid draft is never saved")
    func invalidDraftIsNotCreated() async {
        let foods = FakeFoodRepository()
        let viewModel = await makeLibraryViewModel(foods)

        await viewModel.createCustomFood(CustomFoodDraft(name: "Adobo", calories: "not a number"))

        #expect(await foods.createdFoods.isEmpty)
        #expect(viewModel.pendingPortion == nil)
    }

    // MARK: - Editing

    @Test("an edit keeps the row it is editing rather than creating a second food")
    func editPreservesStoredIdentity() async throws {
        // A new id here would leave every logged entry pointing at the old row
        // and the shelf showing two of everything.
        let id = UUID()
        let original = libraryFood("Adobo", id: id, kcal: 300)
        let foods = FakeFoodRepository(customFoods: [original])
        let viewModel = await makeLibraryViewModel(foods)

        var draft = CustomFoodDraft(food: original)
        draft.name = "Chicken adobo"
        draft.calories = "310"

        let saved = await viewModel.saveCustomFood(draft, to: original)

        let updated = try #require(await foods.updatedFoods.first)
        #expect(updated.storedID == id)
        #expect(updated.name == "Chicken adobo")
        #expect(updated.facts.calories == 310)
        #expect(updated.source == .userCustom)
        // The sheet closes only once the write has landed.
        #expect(saved)
        #expect(viewModel.myFoods.map(\.name) == ["Chicken adobo"])
    }

    @Test("a failed save keeps the sheet up rather than losing what was typed")
    func failedSaveDoesNotCloseTheSheet() async {
        let original = libraryFood("Adobo")
        let foods = FakeFoodRepository(
            customFoods: [original],
            updateFailure: FoodRepositoryError.network
        )
        let viewModel = await makeLibraryViewModel(foods)

        var draft = CustomFoodDraft(food: original)
        draft.calories = "310"

        #expect(await viewModel.saveCustomFood(draft, to: original) == false)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("an invalid edit is not written")
    func invalidEditIsRefused() async {
        let original = libraryFood("Adobo")
        let foods = FakeFoodRepository(customFoods: [original])
        let viewModel = await makeLibraryViewModel(foods)

        var draft = CustomFoodDraft(food: original)
        draft.name = "   "

        await viewModel.saveCustomFood(draft, to: original)

        #expect(await foods.updatedFoods.isEmpty)
    }

    // MARK: - Deleting

    @Test("deleting an unused food removes it from the shelf")
    func deleteRemovesUnusedFood() async {
        let id = UUID()
        let food = libraryFood("Adobo", id: id)
        let foods = FakeFoodRepository(customFoods: [food])
        let viewModel = await makeLibraryViewModel(foods)

        await viewModel.deleteCustomFood(food)

        #expect(await foods.deletedFoodIDs == [id])
        #expect(viewModel.myFoods.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("a food still used by logged meals is refused, and explained rather than errored")
    func deleteBlockedByHistoryIsExplained() async throws {
        // food_log_entries.food_item_id is ON DELETE RESTRICT. That is the
        // database protecting days that already happened, not a failure — so it
        // gets its own explanation and an offer to edit instead.
        let food = libraryFood("Adobo")
        let foods = FakeFoodRepository(
            customFoods: [food],
            deleteFoodFailure: FoodRepositoryError.foodInUse
        )
        let viewModel = await makeLibraryViewModel(foods)

        await viewModel.deleteCustomFood(food)

        let blocked = try #require(viewModel.blockedDeletion)
        #expect(blocked.name == "Adobo")
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.myFoods.count == 1)
    }

    @Test("a genuine delete failure is reported as an error")
    func deleteFailureIsReported() async {
        let food = libraryFood("Adobo")
        let foods = FakeFoodRepository(
            customFoods: [food],
            deleteFoodFailure: FoodRepositoryError.network
        )
        let viewModel = await makeLibraryViewModel(foods)

        await viewModel.deleteCustomFood(food)

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.blockedDeletion == nil)
    }

    // MARK: - Logging from the shelf

    @Test("a food on the shelf is still one tap from being logged")
    func shelfFoodLogsLikeAnyOther() async throws {
        // The shelf is inside the log sheet, so it has to log as well as
        // curate — otherwise finding a recipe here means going back to search.
        let food = libraryFood("Adobo", kcal: 300)
        let foods = FakeFoodRepository(customFoods: [food])
        let viewModel = await makeLibraryViewModel(foods)

        viewModel.pick(FoodSuggestion(item: food, origin: .catalogue))
        await viewModel.confirmPendingPortion()

        let draft = try #require(await foods.logged.first?.first)
        #expect(draft.mealKey == viewModel.selectedSlot?.key)
        #expect(draft.facts.calories == 300)
        #expect(viewModel.loggedItems.map(\.name) == ["Adobo"])
    }
}
