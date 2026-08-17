import Foundation
import Food4ThoughtCore

/// One row of `food_log_entries`, with the food's name resolved.
///
/// The nutrients are the entry's own snapshot, not the food's current figures —
/// which is the point of snapshotting them. Correcting a catalogue row must not
/// retroactively change what a past day added up to.
struct LoggedEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let foodName: String
    let mealKey: String
    let loggedAt: Date
    let quantity: Double
    let facts: NutritionFacts
}

/// The targets in force right now — the open `goal_sets` row.
struct DailyTargets: Equatable, Sendable {
    let dailyCalorieTarget: Int
    let macros: MacroTargets
}

/// Everything Home needs, fetched together.
///
/// One value rather than five separate loads because the screen is meaningless
/// in pieces: rings drawn against a target that hasn't arrived yet would show a
/// full day's headroom for a moment and then jump.
struct TodaySnapshot: Equatable, Sendable {
    let targets: DailyTargets
    let schedule: MealSchedule
    let entries: [LoggedEntry]

    /// Signed, straight from `balance_days.closing_balance_kcal`. Never
    /// recomputed on the client: the credit cap is path-dependent and
    /// `recompute_balance` is its only correct author.
    let balanceKcal: Int

    /// What today's *food* put on the debt, before any exercise. This is the
    /// raw overage, so it can exceed the balance once a workout has cleared
    /// part of it — the two only read as consistent when shown together.
    let todayOverageKcal: Int

    /// What today's exercise has taken off, for the same reason.
    let todayBurnedKcal: Int

    /// The user's typical over-day, from their own recent history. Nil when
    /// they have none on record — the focus figure refuses to invent one.
    let averageDailyOverageKcal: Int?
}

protocol TodayReading: Sendable {
    func snapshot(userID: UUID) async throws -> TodaySnapshot
}

enum TodayRepositoryError: LocalizedError, Equatable {
    case notSignedIn
    case network
    case noActiveGoal
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            "You're signed out. Sign in and try again."
        case .network:
            "No connection. This is the last data we loaded."
        case .noActiveGoal:
            "No targets are set yet. Finish onboarding from Settings."
        case .unexpected(let reason):
            reason
        }
    }
}
