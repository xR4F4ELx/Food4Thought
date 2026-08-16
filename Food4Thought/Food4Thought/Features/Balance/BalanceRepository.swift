import Foundation
import Supabase

/// Rebuilds the stored daily balance rollup.
///
/// Its own protocol because two unrelated callers invalidate the same rows:
/// logging a food changes a day's intake, and moving the stored timezone moves
/// every day boundary the rollup was built on. Neither needs to know how the
/// rollup is maintained, only that it has to be rebuilt.
protocol BalanceRecomputing: Sendable {
    /// Rebuilds forward from `day`, or from the user's earliest data when nil,
    /// and returns the balance as it now stands in kcal.
    ///
    /// Idempotent — a retry after a dropped connection is safe.
    @discardableResult
    func recompute(from day: Date?) async throws -> Int
}

struct SupabaseBalanceRepository: BalanceRecomputing {
    /// Mirrors the argument name of public.recompute_balance.
    private struct RecomputeParams: Encodable {
        let fromDay: String?

        enum CodingKeys: String, CodingKey {
            case fromDay = "p_from_day"
        }
    }

    private let client: SupabaseClient
    private let calendar: Calendar

    init(client: SupabaseClient = SupabaseClientProvider.shared, calendar: Calendar = .current) {
        self.client = client
        self.calendar = calendar
    }

    @discardableResult
    func recompute(from day: Date?) async throws -> Int {
        let params = RecomputeParams(fromDay: day.map { ISODay.string(from: $0, in: calendar) })

        return try await client
            .rpc("recompute_balance", params: params)
            .execute()
            .value
    }
}
