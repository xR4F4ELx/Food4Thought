import Foundation
import Food4ThoughtCore
import Supabase

struct SupabaseFoodRepository: FoodRepository {
    /// A log entry joined to the food it points at. PostgREST embeds the
    /// related row under the table name.
    private struct LogEntryWithFood: Decodable {
        let id: UUID
        let loggedAt: Date
        let quantity: Double
        let calories: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let foodItems: FoodItemRow

        enum CodingKeys: String, CodingKey {
            case id
            case loggedAt = "logged_at"
            case quantity
            case calories
            case proteinG = "protein_g"
            case carbsG = "carbs_g"
            case fatG = "fat_g"
            case foodItems = "food_items"
        }
    }

    private struct FavoriteRow: Decodable {
        let foodItemID: UUID
        let foodItems: FoodItemRow

        enum CodingKeys: String, CodingKey {
            case foodItemID = "food_item_id"
            case foodItems = "food_items"
        }
    }

    private struct FavoriteIDRow: Decodable {
        let foodItemID: UUID

        enum CodingKeys: String, CodingKey {
            case foodItemID = "food_item_id"
        }
    }

    private struct NewFavoriteRow: Encodable {
        let userID: UUID
        let foodItemID: UUID

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case foodItemID = "food_item_id"
        }
    }

    /// Enough to cover a normal day's picks without turning the sheet into a
    /// scroll. Recents beyond this are reachable by search.
    private static let recentsLimit = 25
    private static let searchLimit = 20

    /// The reusable per-user row every quick add points at. One kcal per
    /// serving, so `quantity` is the calorie count and the entry's own
    /// snapshot still reconciles against the item it references.
    private static let quickAddName = "Quick add"

    private let client: SupabaseClient
    private let balances: BalanceRecomputing
    private let calendar: Calendar

    init(
        client: SupabaseClient = SupabaseClientProvider.shared,
        balances: BalanceRecomputing = SupabaseBalanceRepository(),
        calendar: Calendar = .current
    ) {
        self.client = client
        self.balances = balances
        self.calendar = calendar
    }

    // MARK: - Fast paths

    func recents(userID: UUID, withinDays days: Int) async throws -> [FoodSuggestion] {
        let since = calendar.date(byAdding: .day, value: -days, to: .now) ?? .now

        let rows: [LogEntryWithFood] = try await run {
            try await client
                .from("food_log_entries")
                .select("id, logged_at, quantity, calories, protein_g, carbs_g, fat_g, food_items(*)")
                .eq("user_id", value: userID)
                .gte("logged_at", value: since.ISO8601Format())
                .order("logged_at", ascending: false)
                .limit(200)
                .execute()
                .value
        }

        return collapsedToSuggestions(rows)
    }

    func favorites(userID: UUID) async throws -> [FoodSuggestion] {
        let rows: [FavoriteRow] = try await run {
            try await client
                .from("food_favorites")
                .select("food_item_id, food_items(*)")
                .eq("user_id", value: userID)
                .order("created_at", ascending: false)
                .execute()
                .value
        }

        return rows.map { FoodSuggestion(item: $0.foodItems.foodItem, origin: .favorite) }
    }

    func searchCatalogue(matching query: String, userID: UUID) async throws -> [FoodSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // PostgREST reads a comma as a separator inside or(), so a query
        // containing one would be parsed as two filters.
        let pattern = "%\(trimmed.replacingOccurrences(of: ",", with: " "))%"

        let rows: [FoodItemRow] = try await run {
            try await client
                .from("food_items")
                .select()
                .or("name.ilike.\(pattern),brand.ilike.\(pattern)")
                .limit(Self.searchLimit)
                .execute()
                .value
        }

        return rows.map { FoodSuggestion(item: $0.foodItem, origin: .catalogue) }
    }

    // MARK: - Writing

    func cacheIfNeeded(_ item: FoodItem, userID: UUID) async throws -> UUID {
        if let stored = item.storedID { return stored }

        // Someone else may have cached the same USDA food since the search ran,
        // and the unique index on (source, external_id) would reject a second
        // insert. Upserting on that index makes the race a no-op.
        let inserted: [FoodItemRow] = try await run {
            try await client
                .from("food_items")
                .upsert(
                    NewFoodItemRow(item: item, userID: userID),
                    onConflict: "source,external_id"
                )
                .select()
                .execute()
                .value
        }

        guard let id = inserted.first?.id else {
            throw FoodRepositoryError.unexpected("The food couldn't be saved to your catalogue.")
        }
        return id
    }

    func createCustomFood(_ item: FoodItem, userID: UUID) async throws -> FoodItem {
        let inserted: [FoodItemRow] = try await run {
            try await client
                .from("food_items")
                .insert(NewFoodItemRow(item: item, userID: userID))
                .select()
                .execute()
                .value
        }

        guard let row = inserted.first else {
            throw FoodRepositoryError.unexpected("The food couldn't be saved.")
        }
        return row.foodItem
    }

    func log(_ drafts: [FoodLogDraft], userID: UUID) async throws {
        guard !drafts.isEmpty else { return }

        try await run {
            try await client
                .from("food_log_entries")
                .insert(drafts.map { NewFoodLogEntryRow(draft: $0, userID: userID) })
                .execute()
        }

        // The rollup is stored, not derived, so an entry that isn't followed by
        // a rebuild leaves the balance showing yesterday's answer.
        let earliest = drafts.map(\.loggedAt).min()
        try await run { try await balances.recompute(from: earliest) }
    }

    func deleteEntry(id: UUID, loggedAt: Date, userID: UUID) async throws {
        try await run {
            try await client
                .from("food_log_entries")
                .delete()
                .eq("id", value: id)
                // Redundant against RLS, which already scopes the delete to the
                // caller. Kept because a filter that is only enforced server
                // side is one policy edit away from deleting someone else's row.
                .eq("user_id", value: userID)
                .execute()
        }

        try await run { try await balances.recompute(from: loggedAt) }
    }

    func customFoods(userID: UUID) async throws -> [FoodItem] {
        let rows: [FoodItemRow] = try await run {
            try await client
                .from("food_items")
                .select()
                .eq("created_by", value: userID)
                .eq("source", value: FoodSource.userCustom.rawValue)
                .order("name", ascending: true)
                .execute()
                .value
        }

        // The quick-add row is plumbing, not a food. It exists because
        // `food_log_entries.food_item_id` is not nullable, and listing it would
        // invite someone to edit the 1 kcal serving every quick add scales from.
        return rows
            .filter { $0.name != Self.quickAddName }
            .map(\.foodItem)
    }

    func updateCustomFood(_ item: FoodItem, userID: UUID) async throws -> FoodItem {
        guard let id = item.storedID else {
            throw FoodRepositoryError.unexpected("That food hasn't been saved yet.")
        }

        let updated: [FoodItemRow] = try await run {
            try await client
                .from("food_items")
                .update(NewFoodItemRow(item: item, userID: userID))
                .eq("id", value: id)
                .eq("created_by", value: userID)
                .select()
                .execute()
                .value
        }

        guard let row = updated.first else {
            throw FoodRepositoryError.unexpected("The change couldn't be saved.")
        }
        return row.foodItem
    }

    func deleteCustomFood(id: UUID, userID: UUID) async throws {
        try await run {
            try await client
                .from("food_items")
                .delete()
                .eq("id", value: id)
                .eq("created_by", value: userID)
                .execute()
        }
    }

    func favoriteIDs(userID: UUID) async throws -> Set<UUID> {
        let rows: [FavoriteIDRow] = try await run {
            try await client
                .from("food_favorites")
                .select("food_item_id")
                .eq("user_id", value: userID)
                .execute()
                .value
        }

        return Set(rows.map(\.foodItemID))
    }

    func setFavorite(_ isFavorite: Bool, foodItemID: UUID, userID: UUID) async throws {
        try await run {
            if isFavorite {
                try await client
                    .from("food_favorites")
                    .upsert(NewFavoriteRow(userID: userID, foodItemID: foodItemID))
                    .execute()
            } else {
                try await client
                    .from("food_favorites")
                    .delete()
                    .eq("user_id", value: userID)
                    .eq("food_item_id", value: foodItemID)
                    .execute()
            }
        }
    }

    func quickAddItem(userID: UUID) async throws -> FoodItem {
        let existing: [FoodItemRow] = try await run {
            try await client
                .from("food_items")
                .select()
                .eq("created_by", value: userID)
                .eq("source", value: FoodSource.userCustom.rawValue)
                .eq("name", value: Self.quickAddName)
                .limit(1)
                .execute()
                .value
        }

        if let row = existing.first { return row.foodItem }

        let template = FoodItem(
            id: .external(Self.quickAddName),
            source: .userCustom,
            externalID: nil,
            name: Self.quickAddName,
            brand: nil,
            serving: Serving(amount: 1, unit: "kcal"),
            facts: NutritionFacts(calories: 1, protein: 0, carbs: 0, fat: 0)
        )

        let inserted: [FoodItemRow] = try await run {
            try await client
                .from("food_items")
                .insert(NewFoodItemRow(item: template, userID: userID))
                .select()
                .execute()
                .value
        }

        guard let row = inserted.first else {
            throw FoodRepositoryError.unexpected("Quick add couldn't be set up.")
        }
        return row.foodItem
    }

    // MARK: - Helpers

    /// Collapses many entries for the same food into one suggestion carrying
    /// the quantity that user actually picks — which is what makes the quantity
    /// sheet open on the right number instead of on 1.
    private func collapsedToSuggestions(_ rows: [LogEntryWithFood]) -> [FoodSuggestion] {
        var order: [UUID] = []
        var byFood: [UUID: (item: FoodItem, last: Date, count: Int, quantities: [Double])] = [:]

        for row in rows {
            let id = row.foodItems.id
            if var existing = byFood[id] {
                existing.last = max(existing.last, row.loggedAt)
                existing.count += 1
                existing.quantities.append(row.quantity)
                byFood[id] = existing
            } else {
                order.append(id)
                byFood[id] = (row.foodItems.foodItem, row.loggedAt, 1, [row.quantity])
            }
        }

        return order.prefix(Self.recentsLimit).compactMap { id in
            guard let entry = byFood[id] else { return nil }
            return FoodSuggestion(
                item: entry.item,
                origin: .recent(lastLoggedAt: entry.last, timesLogged: entry.count),
                usualServings: Self.usualQuantity(from: entry.quantities)
            )
        }
    }

    /// The mode, not the mean. Someone who logs 150 g of rice nine times and
    /// 400 g once eats 150 g; averaging invents a portion they have never had.
    private static func usualQuantity(from quantities: [Double]) -> Double? {
        var counts: [Double: Int] = [:]
        for quantity in quantities { counts[quantity, default: 0] += 1 }

        return counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value < rhs.value
        }?.key
    }

    /// One place to turn transport failures into something a sheet can show.
    ///
    /// Discardable because a write's `PostgrestResponse` carries nothing the
    /// caller needs — the throw is the signal.
    @discardableResult
    private func run<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as FoodRepositoryError {
            throw error
        } catch is URLError {
            throw FoodRepositoryError.network
        } catch let error as PostgrestError {
            switch error.code {
            case "28000":
                throw FoodRepositoryError.notSignedIn
            // foreign_key_violation. The only one this client can provoke is
            // deleting a food that logged entries still reference.
            case "23503":
                throw FoodRepositoryError.foodInUse
            default:
                throw FoodRepositoryError.unexpected(error.message)
            }
        } catch {
            throw FoodRepositoryError.unexpected(error.localizedDescription)
        }
    }
}
