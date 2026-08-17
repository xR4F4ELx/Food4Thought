import Foundation
import Food4ThoughtCore
import Supabase

struct SupabaseActivityRepository: ActivityRepository {

    private struct EntryRow: Decodable {
        let id: UUID
        let source: String
        let activityType: String?
        let startedAt: Date
        let endedAt: Date?
        let activeEnergyKcal: Double

        enum CodingKeys: String, CodingKey {
            case id
            case source
            case activityType = "activity_type"
            case startedAt = "started_at"
            case endedAt = "ended_at"
            case activeEnergyKcal = "active_energy_kcal"
        }
    }

    /// The insert shape. `external_id` is left off entirely: it is HealthKit's
    /// own identifier, and the partial unique index it feeds only covers rows
    /// that have one.
    private struct NewEntryRow: Encodable {
        let userID: UUID
        let source: String
        let activityType: String
        let startedAt: Date
        let endedAt: Date
        let activeEnergyKcal: Double

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case source
            case activityType = "activity_type"
            case startedAt = "started_at"
            case endedAt = "ended_at"
            case activeEnergyKcal = "active_energy_kcal"
        }
    }

    private struct WeightRow: Decodable {
        let weightKg: Double

        enum CodingKeys: String, CodingKey {
            case weightKg = "weight_kg"
        }
    }

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

    func entries(userID: UUID, on date: Date) async throws -> [ActivityEntry] {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start

        let rows: [EntryRow] = try await run {
            try await client
                .from("activity_entries")
                .select("id, source, activity_type, started_at, ended_at, active_energy_kcal")
                .eq("user_id", value: userID)
                .gte("started_at", value: start.ISO8601Format())
                .lt("started_at", value: end.ISO8601Format())
                .order("started_at", ascending: false)
                .execute()
                .value
        }

        return rows.map {
            ActivityEntry(
                id: $0.id,
                startedAt: $0.startedAt,
                endedAt: $0.endedAt,
                activeKcal: $0.activeEnergyKcal,
                rawType: $0.activityType,
                isManual: $0.source == "manual"
            )
        }
    }

    func latestWeightKg(userID: UUID) async throws -> Double? {
        let rows: [WeightRow] = try await run {
            try await client
                .from("body_metrics")
                .select("weight_kg")
                .eq("user_id", value: userID)
                .order("recorded_at", ascending: false)
                .limit(1)
                .execute()
                .value
        }

        return rows.first?.weightKg
    }

    func log(_ draft: ActivityDraft, userID: UUID) async throws {
        try await run {
            try await client
                .from("activity_entries")
                .insert(
                    NewEntryRow(
                        userID: userID,
                        source: "manual",
                        activityType: draft.type.rawValue,
                        startedAt: draft.startedAt,
                        endedAt: draft.endedAt,
                        activeEnergyKcal: draft.activeKcal
                    )
                )
                .execute()
        }

        // The rollup is stored, not derived, so a workout that skipped this
        // would sit in the table without ever reaching the balance it exists
        // to move. Same contract as logging food.
        try await run { try await balances.recompute(from: draft.startedAt) }
    }

    func delete(id: UUID, startedAt: Date, userID: UUID) async throws {
        try await run {
            try await client
                .from("activity_entries")
                .delete()
                .eq("id", value: id)
                // Redundant against RLS, which already scopes this to the
                // caller — kept so the filter does not live only server side.
                .eq("user_id", value: userID)
                .execute()
        }

        try await run { try await balances.recompute(from: startedAt) }
    }

    @discardableResult
    private func run<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch is URLError {
            throw ActivityRepositoryError.network
        } catch let error as PostgrestError {
            throw error.code == "28000"
                ? ActivityRepositoryError.notSignedIn
                : ActivityRepositoryError.unexpected(error.message)
        } catch {
            throw ActivityRepositoryError.unexpected(error.localizedDescription)
        }
    }
}
