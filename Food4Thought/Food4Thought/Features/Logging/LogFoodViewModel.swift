import Foundation
import Observation
import Food4ThoughtCore

/// State for the 2a log sheet and the 2d quantity sheet behind it.
///
/// The product rule this file exists to hold: **the fastest path is the
/// default**. The sheet opens on recents with a slot already inferred, so the
/// common case is tap-food, tap-log. Search, a different slot, and a different
/// quantity are all available and none of them are on the way.
@Observable
@MainActor
final class LogFoodViewModel {

    enum FastPath: String, CaseIterable, Identifiable {
        case recents
        case favorites
        case copyYesterday
        case quickAdd

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recents: "Recents"
            case .favorites: "★ Favorites"
            case .copyYesterday: "Copy yesterday"
            case .quickAdd: "Quick add"
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
    private(set) var copyableEntries: [CopyableEntry] = []
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

    /// Set when an entry has been written, so the sheet can dismiss itself.
    private(set) var didLog = false

    // MARK: - Dependencies

    private let userID: UUID
    private let foods: FoodRepository
    private let profiles: ProfileRepository
    private let usda: USDAFoodSearching
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let searchDebounce: Duration

    private var searchTask: Task<Void, Never>?

    init(
        userID: UUID,
        foods: FoodRepository = SupabaseFoodRepository(),
        profiles: ProfileRepository = SupabaseProfileRepository(),
        usda: USDAFoodSearching = USDAFoodClient(),
        calendar: Calendar = .current,
        searchDebounce: Duration = .milliseconds(300),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.userID = userID
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
            selectedSlot = schedule.slot(at: currentTimeOfDay()) ?? schedule.slots.first

            async let favorites = foods.favoriteIDs(userID: userID)
            async let recents = foods.recents(userID: userID, withinDays: Self.recentsWindowDays)

            favoriteIDs = try await favorites
            suggestions = FoodSearchRanking.ranked(try await recents)
        } catch {
            errorMessage = message(for: error)
        }
    }

    func select(slot: MealSlot) {
        selectedSlot = slot
        // Copy-yesterday is the one path whose contents depend on the slot.
        if path == .copyYesterday {
            Task { await select(path: .copyYesterday) }
        }
    }

    func select(path newPath: FastPath) async {
        path = newPath
        query = ""
        errorMessage = nil
        searchNotice = nil

        switch newPath {
        case .quickAdd:
            isQuickAdding = true
        case .recents, .favorites, .copyYesterday:
            await loadPath(newPath)
        }
    }

    private func loadPath(_ path: FastPath) async {
        isLoading = true
        defer { isLoading = false }

        do {
            switch path {
            case .recents:
                copyableEntries = []
                suggestions = FoodSearchRanking.ranked(
                    try await foods.recents(userID: userID, withinDays: Self.recentsWindowDays)
                )
            case .favorites:
                copyableEntries = []
                suggestions = FoodSearchRanking.ranked(try await foods.favorites(userID: userID))
            case .copyYesterday:
                suggestions = []
                copyableEntries = try await foods.entriesForCopy(
                    userID: userID,
                    mealKey: selectedSlot?.key ?? "",
                    daysAgo: 1
                )
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
        copyableEntries = []

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
        suggestions = FoodSearchRanking.ranked(found)
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
            pendingPortion = nil
            didLog = true
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// Re-logs a whole slot from yesterday in one write.
    func copyYesterday() async {
        guard let slot = selectedSlot, !copyableEntries.isEmpty else { return }

        isCommitting = true
        errorMessage = nil
        defer { isCommitting = false }

        do {
            try await foods.log(
                copyableEntries.map {
                    FoodLogDraft(
                        foodItemID: $0.item.storedID ?? UUID(),
                        mealKey: slot.key,
                        quantity: $0.quantity,
                        facts: $0.facts,
                        loggedAt: now()
                    )
                },
                userID: userID
            )
            didLog = true
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
            isQuickAdding = false
            didLog = true
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
