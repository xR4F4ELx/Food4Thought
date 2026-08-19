import Foundation
import Testing
import Food4ThoughtCore
@testable import Food4Thought

// MARK: - Fakes

private let userID = UUID()
private let riceID = UUID()

private func storedItem(
    _ id: UUID = riceID,
    name: String = "Chicken rice bowl",
    servingGrams: Double = 100,
    calories: Double = 200
) -> FoodItem {
    FoodItem(
        id: .stored(id),
        source: .userCustom,
        externalID: nil,
        name: name,
        brand: nil,
        serving: Serving(amount: servingGrams, unit: "g"),
        facts: NutritionFacts(calories: calories, protein: 10, carbs: 30, fat: 5)
    )
}

/// A distinct food each call. The default `storedItem` reuses one id, which is
/// right for the single-food tests and wrong for anything logging two things —
/// two suggestions sharing an identity are one row, not two.
private func distinctItem(name: String, calories: Double) -> FoodItem {
    storedItem(UUID(), name: name, calories: calories)
}

private func usdaItem(_ fdcID: String = "171077") -> FoodItem {
    FoodItem(
        id: .external(fdcID),
        source: .usdaFDC,
        externalID: fdcID,
        name: "Chicken breast, grilled",
        brand: nil,
        serving: .per100g,
        facts: NutritionFacts(calories: 165, protein: 31, carbs: 0, fat: 3.6)
    )
}


private actor StubProfileRepository: ProfileRepository {
    func hasCompletedOnboarding(userID: UUID) async throws -> Bool { true }
    func completeOnboarding(_ submission: OnboardingSubmission) async throws {}
    func syncTimeZone(_ identifier: String, userID: UUID) async throws -> TimeZoneSyncResult { .unchanged }
    func mealSchedule(userID: UUID) async throws -> MealSchedule { MealSchedule.Preset.threeMeals.schedule }
    func updateMealSchedule(_ schedule: MealSchedule, userID: UUID) async throws {}
    #if DEBUG
    func resetOnboarding(userID: UUID) async throws {}
    #endif
}

private struct StubUSDAClient: USDAFoodSearching {
    var isConfigured = true
    var results: [FoodItem] = []
    var failure: (any Error)?

    func search(_ query: String) async throws -> [FoodItem] {
        if let failure { throw failure }
        return results
    }
}

/// 10:11 — the time in the wireframe, past breakfast, before lunch.
private func midMorning() -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 8
    components.day = 16
    components.hour = 10
    components.minute = 11
    return Calendar.current.date(from: components)!
}

@MainActor
private func makeViewModel(
    foods: FakeFoodRepository = FakeFoodRepository(),
    usda: StubUSDAClient = StubUSDAClient()
) -> LogFoodViewModel {
    LogFoodViewModel(
        userID: userID,
        foods: foods,
        profiles: StubProfileRepository(),
        usda: usda,
        searchDebounce: .zero,
        now: { midMorning() }
    )
}

// MARK: - Tests

@MainActor
@Suite("LogFoodViewModel")
struct LogFoodViewModelTests {

    @Test("the sheet opens on recents with the slot already inferred — no taps spent choosing")
    func opensOnRecentsWithInferredSlot() async {
        let recent = FoodSuggestion(
            item: storedItem(),
            origin: .recent(lastLoggedAt: midMorning(), timesLogged: 4),
            usualServings: 3.2
        )
        let viewModel = makeViewModel(foods: FakeFoodRepository(recents: [recent]))

        await viewModel.load()

        #expect(viewModel.path == .recents)
        #expect(viewModel.selectedSlot?.key == "lunch")
        #expect(viewModel.suggestions.count == 1)
    }

    @Test("picking a food opens the quantity step on the serving that user usually logs")
    func pickOpensOnUsualServing() async {
        let recent = FoodSuggestion(
            item: storedItem(servingGrams: 100),
            origin: .recent(lastLoggedAt: midMorning(), timesLogged: 8),
            usualServings: 3.2
        )
        let viewModel = makeViewModel(foods: FakeFoodRepository(recents: [recent]))
        await viewModel.load()

        viewModel.pick(recent)

        #expect(viewModel.pendingPortion?.displayValue == "320")
        #expect(abs((viewModel.pendingPortion?.facts.calories ?? 0) - 640) < 0.001)
    }

    @Test("logging writes the stepped quantity and its own snapshot of the macros")
    func confirmLogsSnapshottedFacts() async {
        let foods = FakeFoodRepository(recents: [])
        let viewModel = makeViewModel(foods: foods)
        await viewModel.load()

        viewModel.pick(FoodSuggestion(item: storedItem(), origin: .catalogue, usualServings: 1))
        viewModel.adjustPortion { $0.incremented() }
        await viewModel.confirmPendingPortion()

        let drafts = await foods.logged.first
        let draft = try! #require(drafts?.first)
        #expect(draft.mealKey == "lunch")
        #expect(abs(draft.quantity - 1.1) < 0.001)
        #expect(abs(draft.facts.calories - 220) < 0.001)
        #expect(viewModel.hasLogged)
    }

    @Test("a USDA hit is cached into food_items before an entry can point at it")
    func usdaHitIsCachedBeforeLogging() async {
        let foods = FakeFoodRepository()
        let viewModel = makeViewModel(foods: foods)
        await viewModel.load()

        viewModel.pick(FoodSuggestion(item: usdaItem(), origin: .usda))
        await viewModel.confirmPendingPortion()

        let cached = await foods.cachedItems
        #expect(cached.first?.externalID == "171077")

        let draft = try! #require(await foods.logged.first?.first)
        #expect(draft.foodItemID == foods.newlyCachedID)
    }

    @Test("search merges local and USDA results and shows the cached copy once")
    func searchDeduplicatesAcrossSources() async {
        let cachedCopy = FoodSuggestion(
            item: FoodItem(
                id: .stored(riceID),
                source: .usdaFDC,
                externalID: "171077",
                name: "Chicken breast, grilled",
                brand: nil,
                serving: .per100g,
                facts: NutritionFacts(calories: 165, protein: 31, carbs: 0, fat: 3.6)
            ),
            origin: .catalogue
        )
        let viewModel = makeViewModel(
            foods: FakeFoodRepository(catalogue: [cachedCopy]),
            usda: StubUSDAClient(results: [usdaItem()])
        )
        await viewModel.load()

        await viewModel.search("chicken")

        #expect(viewModel.suggestions.count == 1)
        #expect(viewModel.suggestions.first?.item.storedID == riceID)
    }

    @Test("a USDA hit that only shares a word with the query is dropped, not shown")
    func remoteFalseMatchIsFilteredOut() async {
        // The real response: USDA answers "kaya toast" with Melba toast. Left
        // in, it logs at 390 kcal/100g and looks entirely reasonable.
        let melbaToast = FoodItem(
            id: .external("6107"),
            source: .usdaFDC,
            externalID: "6107",
            name: "Melba toast",
            brand: nil,
            serving: .per100g,
            facts: NutritionFacts(calories: 390, protein: 12, carbs: 74, fat: 3)
        )
        let viewModel = makeViewModel(usda: StubUSDAClient(results: [melbaToast]))
        await viewModel.load()

        await viewModel.search("kaya toast")

        #expect(viewModel.suggestions.isEmpty)
    }

    @Test("an unreachable USDA degrades to local results with a note, not an error")
    func usdaFailureKeepsLocalResults() async {
        let local = FoodSuggestion(item: storedItem(), origin: .catalogue)
        let viewModel = makeViewModel(
            foods: FakeFoodRepository(catalogue: [local]),
            usda: StubUSDAClient(failure: USDAFoodClient.Failure.network)
        )
        await viewModel.load()

        await viewModel.search("rice")

        #expect(viewModel.suggestions.count == 1)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.searchNotice != nil)
    }

    @Test("quick add logs calories only, against the reusable quick-add item")
    func quickAddLogsCaloriesOnly() async {
        let foods = FakeFoodRepository()
        let viewModel = makeViewModel(foods: foods)
        await viewModel.load()

        await viewModel.quickAdd(calories: 450)

        let draft = try! #require(await foods.logged.first?.first)
        #expect(abs(draft.facts.calories - 450) < 0.001)
        #expect(draft.facts.protein == 0)
        // Quoted at 1 kcal per serving, so quantity is the calorie count and the
        // entry reconciles against the item it points at.
        #expect(abs(draft.quantity - 450) < 0.001)
        #expect(await foods.quickAddRequests == 1)
    }

    @Test("quick add refuses a zero, which the quantity check constraint would reject anyway")
    func quickAddRefusesZero() async {
        let foods = FakeFoodRepository()
        let viewModel = makeViewModel(foods: foods)
        await viewModel.load()

        await viewModel.quickAdd(calories: 0)

        #expect(await foods.logged.isEmpty)
        #expect(viewModel.hasLogged == false)
    }

    @Test("a failed write keeps the sheet up and says why")
    func failedLogKeepsTheSheetUp() async {
        let foods = FakeFoodRepository(logFailure: FoodRepositoryError.network)
        let viewModel = makeViewModel(foods: foods)
        await viewModel.load()

        viewModel.pick(FoodSuggestion(item: storedItem(), origin: .catalogue, usualServings: 1))
        await viewModel.confirmPendingPortion()

        #expect(viewModel.hasLogged == false)
        #expect(viewModel.pendingPortion != nil)
        #expect(viewModel.errorMessage == FoodRepositoryError.network.errorDescription)
        #expect(viewModel.isCommitting == false)
    }

    @Test("starring a USDA hit caches it first — a favourite is a row reference")
    func favouritingCachesFirst() async {
        let foods = FakeFoodRepository()
        let viewModel = makeViewModel(foods: foods)
        await viewModel.load()

        await viewModel.toggleFavorite(usdaItem())

        #expect(await foods.storedFavorites.contains(foods.newlyCachedID))
        #expect(viewModel.favoriteIDs.contains(foods.newlyCachedID))
    }

    @Test("a created food goes straight to the quantity step, already saved")
    func customFoodFlowsIntoLogging() async {
        // The user made this food in order to log it; sending them back to a
        // list to find it again would waste the whole point of the screen.
        let foods = FakeFoodRepository()
        let viewModel = makeViewModel(foods: foods)
        await viewModel.load()
        viewModel.customFoodRoute = .create

        await viewModel.createCustomFood(
            CustomFoodDraft(name: "Mum's adobo", servingAmount: "250", servingUnit: "g", calories: "420")
        )

        #expect(viewModel.customFoodRoute == nil)
        #expect(viewModel.pendingPortion?.food.name == "Mum's adobo")
        // Saved with a real row id, so the entry can point at it.
        #expect(viewModel.pendingPortion?.food.storedID == foods.newlyCachedID)
    }

    @Test("an incomplete custom food is never saved")
    func incompleteCustomFoodIsNotSaved() async {
        let foods = FakeFoodRepository()
        let viewModel = makeViewModel(foods: foods)
        await viewModel.load()

        await viewModel.createCustomFood(CustomFoodDraft(name: "", calories: "420"))

        #expect(await foods.cachedItems.isEmpty)
        #expect(viewModel.pendingPortion == nil)
    }

    @Test("switching the slot only changes where the next food goes, not the shelf")
    func changingSlotKeepsTheShelf() async {
        let mine = storedItem(name: "Mum's adobo")
        let viewModel = makeViewModel(foods: FakeFoodRepository(customFoods: [mine]))
        await viewModel.load()
        await viewModel.select(path: .myFoods)

        let dinner = try! #require(viewModel.slots.first { $0.key == "dinner" })
        viewModel.select(slot: dinner)

        #expect(viewModel.selectedSlot?.key == "dinner")
        #expect(viewModel.path == .myFoods)
        #expect(viewModel.myFoods.map(\.name) == ["Mum's adobo"])
    }

    // MARK: - Logging more than one thing in a sitting

    @Test("logging a food leaves the sheet ready for the next one")
    func loggingKeepsTheSessionOpen() async {
        // A burger and a drink are one order. Dismissing after the first item
        // makes the second cost a whole reopen — sheet, network load, and
        // finding the food again.
        let burger = distinctItem(name: "Burger", calories: 540)
        let drink = distinctItem(name: "Cola", calories: 200)
        let foods = FakeFoodRepository(recents: [
            FoodSuggestion(item: burger, origin: .catalogue),
            FoodSuggestion(item: drink, origin: .catalogue)
        ])
        let viewModel = makeViewModel(foods: foods)
        await viewModel.load()

        viewModel.pick(FoodSuggestion(item: burger, origin: .catalogue))
        await viewModel.confirmPendingPortion()

        // The quantity step is done with, the sitting is not.
        #expect(viewModel.pendingPortion == nil)
        #expect(viewModel.hasLogged)
        #expect(viewModel.loggedItems.map(\.name) == ["Burger"])

        viewModel.pick(FoodSuggestion(item: drink, origin: .catalogue))
        await viewModel.confirmPendingPortion()

        #expect(viewModel.loggedItems.map(\.name) == ["Burger", "Cola"])
        #expect(viewModel.loggedKcal == 740)
        #expect(await foods.logged.count == 2)
    }

    @Test("the list the user was looking at survives a log")
    func loggingDoesNotResetTheList() async {
        // Two items off the same search is the ordinary case. Clearing the
        // query would send them back to recents and make them type it again.
        let item = distinctItem(name: "Chicken rice", calories: 600)
        let foods = FakeFoodRepository(catalogue: [FoodSuggestion(item: item, origin: .catalogue)])
        let viewModel = makeViewModel(foods: foods)
        await viewModel.load()

        await viewModel.search("chicken")
        let resultsBefore = viewModel.suggestions
        #expect(resultsBefore.isEmpty == false)

        viewModel.pick(FoodSuggestion(item: item, origin: .catalogue))
        await viewModel.confirmPendingPortion()

        // The search results are still standing, so the next item off the same
        // query is one tap away rather than a re-typed search.
        #expect(viewModel.suggestions == resultsBefore)
        #expect(viewModel.pendingPortion == nil)
        #expect(viewModel.hasLogged)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("a failed log records nothing and leaves the quantity step up")
    func failedLogRecordsNothing() async {
        let item = distinctItem(name: "Burger", calories: 540)
        let foods = FakeFoodRepository(
            recents: [FoodSuggestion(item: item, origin: .catalogue)],
            logFailure: FoodRepositoryError.network
        )
        let viewModel = makeViewModel(foods: foods)
        await viewModel.load()

        viewModel.pick(FoodSuggestion(item: item, origin: .catalogue))
        await viewModel.confirmPendingPortion()

        #expect(viewModel.loggedItems.isEmpty)
        #expect(viewModel.hasLogged == false)
        // Still up, so the user can retry without finding the food again.
        #expect(viewModel.pendingPortion != nil)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("a quick add joins the sitting like anything else")
    func quickAddJoinsTheSession() async {
        let viewModel = makeViewModel(foods: FakeFoodRepository())
        await viewModel.load()

        await viewModel.quickAdd(calories: 250)

        #expect(viewModel.loggedKcal == 250)
        #expect(viewModel.loggedItems.count == 1)
        // The quick-add sheet closes; the log sheet does not.
        #expect(viewModel.isQuickAdding == false)
    }
}
