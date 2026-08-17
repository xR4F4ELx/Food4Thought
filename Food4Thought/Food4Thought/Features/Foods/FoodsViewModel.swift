import Foundation
import Observation
import Food4ThoughtCore

/// State for the Foods tab — the user's own library.
///
/// Two lists rather than one: foods the user created, and foods they starred.
/// They overlap but are not the same set — a starred USDA hit is a favourite
/// nobody created, and a home recipe logged once is a custom food nobody
/// starred — so collapsing them would hide half of each.
@Observable
@MainActor
final class FoodsViewModel {

    enum Shelf: String, CaseIterable, Identifiable {
        case myFoods
        case favorites

        var id: String { rawValue }

        var title: String {
            switch self {
            case .myFoods: "My foods"
            case .favorites: "Favourites"
            }
        }
    }

    // MARK: - State

    var shelf: Shelf = .myFoods

    private(set) var customFoods: [FoodItem] = []
    private(set) var favorites: [FoodSuggestion] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    /// Set when a delete was refused because entries still point at the food.
    /// Held apart from `errorMessage` because it is not a failure — it is the
    /// database protecting history, and it deserves its own explanation.
    var blockedDeletion: FoodItem?

    // MARK: - Dependencies

    private let userID: UUID
    private let foods: FoodRepository

    init(userID: UUID, foods: FoodRepository = SupabaseFoodRepository()) {
        self.userID = userID
        self.foods = foods
    }

    // MARK: - Loading

    func load() async {
        isLoading = customFoods.isEmpty && favorites.isEmpty
        defer { isLoading = false }

        do {
            async let mine = foods.customFoods(userID: userID)
            async let starred = foods.favorites(userID: userID)

            customFoods = try await mine
            favorites = try await starred
            errorMessage = nil
        } catch {
            errorMessage = message(for: error)
        }
    }

    var isEmpty: Bool {
        switch shelf {
        case .myFoods: customFoods.isEmpty
        case .favorites: favorites.isEmpty
        }
    }

    var emptyMessage: String {
        switch shelf {
        case .myFoods:
            "Nothing here yet. Anything you cook or buy that isn't in the food database can live here — tap + to add one, or create one while logging."
        case .favorites:
            "No favourites yet. Star a food while logging it and it shows up here."
        }
    }

    // MARK: - Creating

    /// Adds a food to the library without logging it.
    ///
    /// The counterpart to creating one mid-log, which goes straight to the
    /// quantity step because that user is holding the food. Someone stocking
    /// their library on a Sunday evening is not, and making them fake a log
    /// entry to record a recipe would put a meal on their day that never
    /// happened.
    ///
    /// Returns whether it landed, so the sheet closes on success and stays up
    /// with its contents on failure.
    func create(_ draft: CustomFoodDraft) async -> Bool {
        guard let item = draft.validated else { return false }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            _ = try await foods.createCustomFood(item, userID: userID)
            shelf = .myFoods
            await load()
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    // MARK: - Editing

    /// Saves an edit. Past entries keep the figures they were logged with —
    /// they snapshot their own nutrients, so fixing a food corrects it going
    /// forward without rewriting days that already happened.
    @discardableResult
    func save(_ draft: CustomFoodDraft, to original: FoodItem) async -> Bool {
        guard let edited = draft.validated, let id = original.storedID else { return false }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let updated = FoodItem(
            id: .stored(id),
            source: original.source,
            externalID: original.externalID,
            name: edited.name,
            brand: edited.brand,
            serving: edited.serving,
            facts: edited.facts
        )

        do {
            _ = try await foods.updateCustomFood(updated, userID: userID)
            await load()
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func delete(_ item: FoodItem) async {
        guard let id = item.storedID else { return }

        errorMessage = nil

        do {
            try await foods.deleteCustomFood(id: id, userID: userID)
            await load()
        } catch FoodRepositoryError.foodInUse {
            blockedDeletion = item
        } catch {
            errorMessage = message(for: error)
        }
    }

    func unfavorite(_ item: FoodItem) async {
        guard let id = item.storedID else { return }

        errorMessage = nil

        do {
            try await foods.setFavorite(false, foodItemID: id, userID: userID)
            await load()
        } catch {
            errorMessage = message(for: error)
        }
    }

    // MARK: - Helpers

    private func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
