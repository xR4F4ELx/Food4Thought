import Foundation
import Food4ThoughtCore
import Supabase

/// One logged day, totalled.
struct DailyMacros: Identifiable, Equatable, Sendable {
    let day: Date
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double

    var id: Date { day }

    var split: MacroSplit? {
        MacroSplit(proteinGrams: proteinGrams, carbsGrams: carbsGrams, fatGrams: fatGrams)
    }
}

/// Macro totals per day, for the Trends chart.
///
/// Days with nothing logged are absent rather than zeroed: a gap in the chart
/// is an honest "no record", where a zero-height bar claims a day of eating
/// nothing.
protocol MacroHistoryRepository: Sendable {
    func dailyMacros(userID: UUID, since: Date) async throws -> [DailyMacros]
}

struct SupabaseMacroHistoryRepository: MacroHistoryRepository {

    private struct EntryRow: Decodable {
        let loggedAt: Date
        let proteinG: Double
        let carbsG: Double
        let fatG: Double

        enum CodingKeys: String, CodingKey {
            case loggedAt = "logged_at"
            case proteinG = "protein_g"
            case carbsG = "carbs_g"
            case fatG = "fat_g"
        }
    }

    private let client: SupabaseClient
    private let calendar: Calendar

    init(client: SupabaseClient = SupabaseClientProvider.shared, calendar: Calendar = .current) {
        self.client = client
        self.calendar = calendar
    }

    /// Summed on the client rather than in SQL.
    ///
    /// The grouping is by *the user's* day, and the device knows which day a
    /// timestamp falls in without a round trip through the profile's stored
    /// timezone. A fortnight of entries is a few hundred rows at most.
    func dailyMacros(userID: UUID, since: Date) async throws -> [DailyMacros] {
        let rows: [EntryRow] = try await run {
            try await client
                .from("food_log_entries")
                .select("logged_at, protein_g, carbs_g, fat_g")
                .eq("user_id", value: userID)
                .gte("logged_at", value: calendar.startOfDay(for: since).ISO8601Format())
                .order("logged_at", ascending: true)
                .execute()
                .value
        }

        let byDay = Dictionary(grouping: rows) { calendar.startOfDay(for: $0.loggedAt) }

        return byDay
            .map { day, entries in
                DailyMacros(
                    day: day,
                    proteinGrams: entries.reduce(0) { $0 + $1.proteinG },
                    carbsGrams: entries.reduce(0) { $0 + $1.carbsG },
                    fatGrams: entries.reduce(0) { $0 + $1.fatG }
                )
            }
            .sorted { $0.day < $1.day }
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
