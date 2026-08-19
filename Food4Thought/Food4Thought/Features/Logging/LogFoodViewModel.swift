import Foundation
import Observation
import Food4ThoughtCore

/// State for the 2a log sheet and the 2d quantity sheet behind it.
///
/// The product rule this file exists to hold: **the fastest path is the
/// default**. The sheet opens on recents with a slot already inferred, so the
/// common case is tap-food, tap-log. Search, a different slot, and a different
/// quantity are all available and none of them are on the way.
/// One thing logged during this sitting, for the running tally on the sheet.
struct LoggedSessionItem: Identifiable, Equatable, Sendable {
    let id = UUID()
    let name: String
    let calories: Double
}

@Observable
@MainActor
final class LogFoodViewModel {

    enum FastPath: String, CaseIterable, Identifiable {
        case recents
        case favorites
        case myFoods
        case quickAdd

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recents: "Recents"
            case .favorites: "★ Favorites"
            case .myFoods: "My foods"
            case .quickAdd: "Quick add"
            }
        }
    }

    /// Creating and editing a food share one presentation slot. Two `.sheet`
    /// modifiers on a single view is the bug that silently does nothing —
    /// SwiftUI only reliably honours one.
    enum CustomFoodRoute: Identifiable {
        case create
        case edit(FoodItem)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let food): "edit-\(food.id)"
            }
        }
    }

    /// How far back "recents" reaches. A week covers weekly rhythms — the
    /// Tuesday lunch, the gym-day shake — without burying today's picks.
    private static let recentsWindowDays = 7

    // MARK: - State

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }

    private(set) var slots: [MealSlot] = []
    private(set) var selectedSlot: MealSlot?
    private(set) var path: FastPath = .recents
    private(set) var suggestions: [FoodSuggestion] = []

    /// The foods this user made by hand — the "My foods" shelf.
    ///
    /// Held apart from `suggestions` because this shelf is a library as well as
    /// a list to log from: its rows can be edited and deleted, and the others
    /// cannot.
    private(set) var myFoods: [FoodItem] = []

    private(set) var favoriteIDs: Set<UUID> = []
    private(set) var isLoading = false
    private(set) var isSearching = false

    /// True only while a write is in flight, so a failure releases the button
    /// rather than leaving it spinning.
    private(set) var isCommitting = false
    private(set) var errorMessage: String?

    /// Said plainly rather than raised as an error: local results are still
    /// useful when USDA is unreachable or unconfigured.
    private(set) var searchNotice: String?

    /// Non-nil while the 2d quantity sheet is up.
    var pendingPortion: PortionStepper?
    var isQuickAdding = false

    /// Non-nil while the create-or-edit food sheet is up.
    var customFoodRoute: CustomFoodRoute?

    /// Set when a delete was refused because entries still point at the food.
    /// Held apart from `errorMessage` because it is not a failure — it is the
    /// database protecting history, and it deserves its own explanation.
    var blockedDeletion: FoodItem?

    /// What has gone in since the sheet opened.
    ///
    /// A meal is usually more than one thing — a burger and a drink are one
    /// order — so the sheet stays up after a write and collects them. This is
    /// what 2a's per-row **+** implies: a list you add from repeatedly, not one
    /// that closes on first use. Dismissing after the first item would make the
    /// second cost a reopen, a reload, and finding the food again.
    private(set) var loggedItems: [LoggedSessionItem] = []

    var hasLogged: Bool { !loggedItems.isEmpty }

    var loggedKcal: Int {
        Int(loggedItems.reduce(0) { $0 + $1.calories }.rounded())
    }

    // MARK: - Dependencies

    private let userID: UUID

    /// Set when the sheet was opened from a specific meal — a Home meal row
    /// names the slot, and inferring one from the clock would override the
    /// thing the user just pointed at.
    private let initialSlotKey: String?

    private let foods: FoodRepository
    private let profiles: ProfileRepository
    private let usda: USDAFoodSearching
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let searchDebounce: Duration

    private var searchTask: Task<Void, Never>?

    init(
        userID: UUID,
        initialSlotKey: String? = nil,
        foods: FoodRepository = SupabaseFoodRepository(),
        profiles: ProfileRepository = SupabaseProfileRepository(),
        usda: USDAFoodSearching = USDAFoodClient(),
        calendar: Calendar = .current,
        searchDebounce: Duration = .milliseconds(300),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.userID = userID
        self.initialSlotKey = initialSlotKey
        self.foods = foods
        self.profiles = profiles
        self.usda = usda
        self.calendar = calendar
        self.searchDebounce = searchDebounce
        self.now = now
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let schedule = try await profiles.mealSchedule(userID: userID)
            slots = schedule.slots
            // A named slot wins over the clock. An unrecognised key falls back
            // to inference rather than to nothing — a schedule the user edited
            // between opening Home and tapping must not strand the sheet
            // without a slot to log to.
            selectedSlot = initialSlotKey.flatMap { key in schedule.slots.first { $0.key == key } }
                ?? schedule.slot(at: currentTimeOfDay())
                ?? schedule.slots.first

            async let favorites = foods.favoriteIDs(userID: userID)
            async let recents = foods.recents(userID: userID, withinDays: Self.recentsWindowDays)

            favoriteIDs = try await favorites
            suggestions = FoodSearchRanking.ranked(try await recents)
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// Changing the slot never reloads a shelf: every fast path is a list of
    /// foods, and which meal they are headed for does not change what is on it.
    func select(slot: MealSlot) {
        selectedSlot = slot
    }

    func select(path newPath: FastPath) async {
        path = newPath
        query = ""
        errorMessage = nil
        searchNotice = nil

        switch newPath {
        case .quickAdd:
            isQuickAdding = true
        case .recents, .favorites, .myFoods:
            await loadPath(newPath)
        }
    }

    private func loadPath(_ path: FastPath) async {
        isLoading = true
        defer { isLoading = false }

        do {
            switch path {
            case .recents:
                suggestions = FoodSearchRanking.ranked(
                    try await foods.recents(userID: userID, withinDays: Self.recentsWindowDays)
                )
            case .favorites:
                suggestions = FoodSearchRanking.ranked(try await foods.favorites(userID: userID))
            case .myFoods:
                suggestions = []
                myFoods = try await foods.customFoods(userID: userID)
            case .quickAdd:
                break
            }
        } catch {
            errorMessage = message(for: error)
        }
    }

    // MARK: - Search

    private func scheduleSearch() {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isSearching = false
            searchNotice = nil
            Task { await loadPath(path) }
            return
        }

        searchTask = Task { [searchDebounce] in
            // Debounced so a five-letter word is one round trip, not five.
            try? await Task.sleep(for: searchDebounce)
            guard !Task.isCancelled else { return }
            await search(trimmed)
        }
    }

    /// Local catalogue and USDA answer in parallel; the ranking collapses the
    /// duplicates they inevitably both return.
    func search(_ term: String) async {
        isSearching = true
        defer { isSearching = false }

        errorMessage = nil
        searchNotice = nil

        var found: [FoodSuggestion] = []

        do {
            found += try await foods.searchCatalogue(matching: term, userID: userID)
        } catch {
            errorMessage = message(for: error)
        }

        do {
            found += try await usda.search(term).map { FoodSuggestion(item: $0, origin: .usda) }
        } catch {
            // A remote miss degrades to local-only rather than emptying the
            // list: the user's own foods are the ones they log most anyway.
            searchNotice = message(for: error)
        }

        guard !Task.isCancelled else { return }
        // Gating on the term drops remote hits that only share a word with it —
        // a USDA search for "kaya toast" answers with Melba toast.
        suggestions = FoodSearchRanking.ranked(found, matching: term)
    }

    // MARK: - Picking and logging

    /// Opens the shared 2d sheet, pre-filled with the serving this user
    /// usually logs.
    func pick(_ suggestion: FoodSuggestion) {
        pendingPortion = PortionStepper(
            food: suggestion.item,
            usualServings: suggestion.usualServings
        )
    }

    func adjustPortion(_ transform: (PortionStepper) -> PortionStepper) {
        pendingPortion = pendingPortion.map(transform)
    }

    func isFavorite(_ item: FoodItem) -> Bool {
        item.storedID.map(favoriteIDs.contains) ?? false
    }

    /// Toggles the star. A USDA hit has to be cached first — a favourite is a
    /// row reference, and there is no row until something creates one.
    func toggleFavorite(_ item: FoodItem) async {
        do {
            let id = try await foods.cacheIfNeeded(item, userID: userID)
            let shouldFavorite = !favoriteIDs.contains(id)
            try await foods.setFavorite(shouldFavorite, foodItemID: id, userID: userID)

            var updated = favoriteIDs
            if shouldFavorite { updated.insert(id) } else { updated.remove(id) }
            favoriteIDs = updated
        } catch {
            errorMessage = message(for: error)
        }
    }

    func confirmPendingPortion() async {
        guard let portion = pendingPortion, let slot = selectedSlot else { return }

        isCommitting = true
        errorMessage = nil
        defer { isCommitting = false }

        do {
            let foodItemID = try await foods.cacheIfNeeded(portion.food, userID: userID)
            try await foods.log(
                [
                    FoodLogDraft(
                        foodItemID: foodItemID,
                        mealKey: slot.key,
                        quantity: portion.servings,
                        facts: portion.facts,
                        loggedAt: now()
                    )
                ],
                userID: userID
            )
            // Only the quantity step closes. The list is left exactly as it
            // was — same query, same results — so a second item off the same
            // search is one tap away rather than a re-typed search.
            loggedItems.append(
                LoggedSessionItem(name: portion.food.name, calories: portion.facts.calories)
            )
            pendingPortion = nil
        } catch {
            errorMessage = message(for: error)
        }
    }

    // MARK: - The user's own foods

    /// Saves a hand-entered food and goes straight to the quantity step.
    ///
    /// Straight through rather than back to a list the user would then have to
    /// find it in: they opened the log sheet in order to log something, and the
    /// serving they just typed is already the right default. Nothing is written
    /// to the day until the quantity step is confirmed, so someone who only
    /// wanted to stock their library can dismiss it and the food still stands.
    func createCustomFood(_ draft: CustomFoodDraft) async {
        guard let item = draft.validated else { return }

        isCommitting = true
        errorMessage = nil
        defer { isCommitting = false }

        do {
            let saved = try await foods.createCustomFood(item, userID: userID)
            customFoodRoute = nil
            // The shelf behind the quantity step has to show it, or dismissing
            // without logging looks like the food was never saved.
            myFoods = try await foods.customFoods(userID: userID)
            pendingPortion = PortionStepper(food: saved, usualServings: 1)
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// Rewrites one of the user's own foods.
    ///
    /// Past entries keep the figures they were logged with — they snapshot
    /// their own nutrients, so fixing a food corrects it going forward without
    /// rewriting days that already happened.
    ///
    /// Returns whether it landed, so the sheet closes on success and stays up
    /// with its contents on failure.
    @discardableResult
    func saveCustomFood(_ draft: CustomFoodDraft, to original: FoodItem) async -> Bool {
        guard let edited = draft.validated, let id = original.storedID else { return false }

        isCommitting = true
        errorMessage = nil
        defer { isCommitting = false }

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
            myFoods = try await foods.customFoods(userID: userID)
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func deleteCustomFood(_ item: FoodItem) async {
        guard let id = item.storedID else { return }

        errorMessage = nil

        do {
            try await foods.deleteCustomFood(id: id, userID: userID)
            myFoods = try await foods.customFoods(userID: userID)
        } catch FoodRepositoryError.foodInUse {
            blockedDeletion = item
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// Calories only, for the meal that would otherwise go unlogged.
    func quickAdd(calories: Double) async {
        guard calories > 0, let slot = selectedSlot else { return }

        isCommitting = true
        errorMessage = nil
        defer { isCommitting = false }

        do {
            let item = try await foods.quickAddItem(userID: userID)
            let id = try await foods.cacheIfNeeded(item, userID: userID)

            // The item is quoted at 1 kcal per serving, so quantity is the
            // calorie count and the entry reconciles against what it points at.
            try await foods.log(
                [
                    FoodLogDraft(
                        foodItemID: id,
                        mealKey: slot.key,
                        quantity: calories,
                        facts: NutritionFacts(calories: calories, protein: 0, carbs: 0, fat: 0),
                        loggedAt: now()
                    )
                ],
                userID: userID
            )
            loggedItems.append(LoggedSessionItem(name: "Quick add", calories: calories))
            isQuickAdding = false
        } catch {
            errorMessage = message(for: error)
        }
    }

    // MARK: - Helpers

    private func currentTimeOfDay() -> TimeOfDay {
        let parts = calendar.dateComponents([.hour, .minute], from: now())
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    private func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
