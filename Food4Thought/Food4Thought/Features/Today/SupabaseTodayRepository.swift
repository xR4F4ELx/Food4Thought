import Foundation
import Food4ThoughtCore
import Supabase

struct SupabaseTodayRepository: TodayReading {

    private struct GoalSetRow: Decodable {
        let dailyCalorieTarget: Int
        let proteinGTarget: Double
        let carbsGTarget: Double
        let fatGTarget: Double

        enum CodingKeys: String, CodingKey {
            case dailyCalorieTarget = "daily_calorie_target"
            case proteinGTarget = "protein_g_target"
            case carbsGTarget = "carbs_g_target"
            case fatGTarget = "fat_g_target"
        }
    }

    private struct EntryRow: Decodable {
        let id: UUID
        let mealKey: String
        let loggedAt: Date
        let quantity: Double
        let calories: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let foodItems: NamedFood

        struct NamedFood: Decodable {
            let name: String
        }

        enum CodingKeys: String, CodingKey {
            case id
            case mealKey = "meal_key"
            case loggedAt = "logged_at"
            case quantity
            case calories
            case proteinG = "protein_g"
            case carbsG = "carbs_g"
            case fatG = "fat_g"
            case foodItems = "food_items"
        }
    }

    private struct BalanceDayRow: Decodable {
        let day: String
        let closingBalanceKcal: Int
        let overageKcal: Int

        enum CodingKeys: String, CodingKey {
            case day
            case closingBalanceKcal = "closing_balance_kcal"
            case overageKcal = "overage_kcal"
        }
    }

    /// How far back the "typical over-day" average reaches. Two weeks is long
    /// enough to survive a quiet week and short enough that a habit the user has
    /// since changed stops counting against them.
    private static let overageWindowDays = 14

    private let client: SupabaseClient
    private let profiles: ProfileRepository
    private let calendar: Calendar

    init(
        client: SupabaseClient = SupabaseClientProvider.shared,
        profiles: ProfileRepository = SupabaseProfileRepository(),
        calendar: Calendar = .current
    ) {
        self.client = client
        self.profiles = profiles
        self.calendar = calendar
    }

    func snapshot(userID: UUID) async throws -> TodaySnapshot {
        let startOfDay = calendar.startOfDay(for: .now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let windowStart = calendar.date(
            byAdding: .day, value: -Self.overageWindowDays, to: startOfDay
        ) ?? startOfDay

        // Issued together: the screen is meaningless in pieces, so there is
        // nothing to show until all four have answered anyway.
        async let goals = activeGoal(userID: userID)
        async let schedule = profiles.mealSchedule(userID: userID)
        async let entries = todayEntries(userID: userID, from: startOfDay, to: endOfDay)
        async let balances = balanceDays(userID: userID, from: windowStart)

        let (targets, mealSchedule, logged, days) = try await (goals, schedule, entries, balances)

        let today = ISODay.string(from: startOfDay, in: calendar)
        let todayRow = days.first { $0.day == today }

        return TodaySnapshot(
            targets: targets,
            schedule: mealSchedule,
            entries: logged,
            // A day with no rollup row yet carries the balance forward from the
            // last day that has one — the rollup only writes days the user had
            // data for, so a quiet day is a gap, not a reset to zero.
            balanceKcal: todayRow?.closingBalanceKcal ?? days.last?.closingBalanceKcal ?? 0,
            todayOverageKcal: todayRow?.overageKcal ?? 0,
            averageDailyOverageKcal: Self.averageOverage(in: days, excluding: today)
        )
    }

    // MARK: - Queries

    private func activeGoal(userID: UUID) async throws -> DailyTargets {
        let rows: [GoalSetRow] = try await run {
            try await client
                .from("goal_sets")
                .select("daily_calorie_target, protein_g_target, carbs_g_target, fat_g_target")
                .eq("user_id", value: userID)
                .is("effective_to", value: nil)
                .limit(1)
                .execute()
                .value
        }

        guard let row = rows.first else {
            throw TodayRepositoryError.noActiveGoal
        }

        return DailyTargets(
            dailyCalorieTarget: row.dailyCalorieTarget,
            macros: MacroTargets(
                proteinGrams: row.proteinGTarget,
                carbsGrams: row.carbsGTarget,
                fatGrams: row.fatGTarget
            )
        )
    }

    private func todayEntries(
        userID: UUID,
        from start: Date,
        to end: Date
    ) async throws -> [LoggedEntry] {
        let rows: [EntryRow] = try await run {
            try await client
                .from("food_log_entries")
                .select("id, meal_key, logged_at, quantity, calories, protein_g, carbs_g, fat_g, food_items(name)")
                .eq("user_id", value: userID)
                .gte("logged_at", value: start.ISO8601Format())
                .lt("logged_at", value: end.ISO8601Format())
                .order("logged_at", ascending: true)
                .execute()
                .value
        }

        return rows.map {
            LoggedEntry(
                id: $0.id,
                foodName: $0.foodItems.name,
                mealKey: $0.mealKey,
                loggedAt: $0.loggedAt,
                quantity: $0.quantity,
                facts: NutritionFacts(
                    calories: $0.calories,
                    protein: $0.proteinG,
                    carbs: $0.carbsG,
                    fat: $0.fatG
                )
            )
        }
    }

    private func balanceDays(userID: UUID, from start: Date) async throws -> [BalanceDayRow] {
        try await run {
            try await client
                .from("balance_days")
                .select("day, closing_balance_kcal, overage_kcal")
                .eq("user_id", value: userID)
                .gte("day", value: ISODay.string(from: start, in: calendar))
                .order("day", ascending: true)
                .execute()
                .value
        }
    }

    // MARK: - Helpers

    /// The user's typical over-day, averaged over the days they actually went
    /// over. Days on target are excluded rather than averaged in as zeroes: the
    /// figure answers "when you go over, by how much", and diluting it with
    /// good days would shrink the focus target every time someone did well.
    ///
    /// Today is excluded because it is still in progress — a day that is 80
    /// kcal over at lunchtime would drag the average down and make the focus
    /// figure move for reasons that have nothing to do with history.
    private static func averageOverage(in days: [BalanceDayRow], excluding today: String) -> Int? {
        let overDays = days.filter { $0.day != today && $0.overageKcal > 0 }
        guard !overDays.isEmpty else { return nil }

        let total = overDays.reduce(0) { $0 + $1.overageKcal }
        return total / overDays.count
    }

    private func run<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as TodayRepositoryError {
            throw error
        } catch is URLError {
            throw TodayRepositoryError.network
        } catch let error as PostgrestError {
            throw error.code == "28000"
                ? TodayRepositoryError.notSignedIn
                : TodayRepositoryError.unexpected(error.message)
        } catch {
            throw TodayRepositoryError.unexpected(error.localizedDescription)
        }
    }
}
