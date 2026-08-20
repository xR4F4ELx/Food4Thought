import Foundation
import Food4ThoughtCore
import Supabase

struct SupabaseWeightRepository: WeightRepository {

    private struct WeighInRow: Decodable {
        let id: UUID
        let recordedAt: Date
        let weightKg: Double

        enum CodingKeys: String, CodingKey {
            case id
            case recordedAt = "recorded_at"
            case weightKg = "weight_kg"
        }
    }

    /// `height_cm` is deliberately absent. The column is nullable and only
    /// onboarding has a height to record; a weigh-in that re-sent the last
    /// known height would turn a stale value into a fresh-looking measurement.
    private struct NewWeighInRow: Encodable {
        let userID: UUID
        let recordedAt: Date
        let weightKg: Double
        let source: String

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case recordedAt = "recorded_at"
            case weightKg = "weight_kg"
            case source
        }
    }

    private let client: SupabaseClient
    private let calendar: Calendar

    init(client: SupabaseClient = SupabaseClientProvider.shared, calendar: Calendar = .current) {
        self.client = client
        self.calendar = calendar
    }

    func recentWeighIns(userID: UUID, limit: Int) async throws -> [WeighIn] {
        let rows: [WeighInRow] = try await run {
            try await client
                .from("body_metrics")
                .select("id, recorded_at, weight_kg")
                .eq("user_id", value: userID)
                .order("recorded_at", ascending: false)
                .limit(limit)
                .execute()
                .value
        }

        return rows.map { WeighIn(id: $0.id, recordedAt: $0.recordedAt, weightKg: $0.weightKg) }
    }

    func todaysWeighIn(userID: UUID) async throws -> WeighIn? {
        let start = calendar.startOfDay(for: .now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }

        // Bounded in the device's day, matching how Home decides what "today"
        // is everywhere else on that screen.
        let rows: [WeighInRow] = try await run {
            try await client
                .from("body_metrics")
                .select("id, recorded_at, weight_kg")
                .eq("user_id", value: userID)
                .gte("recorded_at", value: start.ISO8601Format())
                .lt("recorded_at", value: end.ISO8601Format())
                .order("recorded_at", ascending: false)
                .limit(1)
                .execute()
                .value
        }

        return rows.first.map { WeighIn(id: $0.id, recordedAt: $0.recordedAt, weightKg: $0.weightKg) }
    }

    func logWeight(_ weightKg: Double, recordedAt: Date, userID: UUID) async throws {
        _ = try await run {
            try await client
                .from("body_metrics")
                .insert(
                    NewWeighInRow(
                        userID: userID,
                        recordedAt: recordedAt,
                        weightKg: weightKg,
                        source: "manual"
                    )
                )
                .execute()
        }
    }

    private func run<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch is URLError {
            throw WeightRepositoryError.network
        } catch let error as PostgrestError {
            throw error.code == "28000"
                ? WeightRepositoryError.notSignedIn
                : WeightRepositoryError.unexpected(error.message)
        } catch {
            throw WeightRepositoryError.unexpected(error.localizedDescription)
        }
    }
}
