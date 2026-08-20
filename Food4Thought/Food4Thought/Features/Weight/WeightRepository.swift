import Foundation

/// One weigh-in, as stored in `body_metrics`.
struct WeighIn: Equatable, Sendable, Identifiable {
    let id: UUID
    let recordedAt: Date
    let weightKg: Double
}

enum WeightRepositoryError: LocalizedError, Equatable {
    case notSignedIn
    case network
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "You're signed out. Sign in and try again."
        case .network: "No connection. Your weigh-in hasn't been saved yet."
        case .unexpected(let reason): reason
        }
    }
}

/// Weight history — the one number Trends is built on.
///
/// Separate from `ActivityRepository`, which only ever reads the latest weight
/// to size a calorie burn. This owns the writing, and the history behind it.
protocol WeightRepository: Sendable {
    /// Most recent first.
    func recentWeighIns(userID: UUID, limit: Int) async throws -> [WeighIn]

    /// Today's weigh-in, if there is one. Drives whether Home asks for it —
    /// a prompt that stays up after you have answered it is nagging.
    func todaysWeighIn(userID: UUID) async throws -> WeighIn?

    /// Records a weigh-in at `recordedAt`.
    ///
    /// Always an insert, never an update: two weigh-ins on one day are a real
    /// thing that happens (morning, then after the gym), and collapsing them
    /// would quietly discard the one the user just took the trouble to enter.
    func logWeight(_ weightKg: Double, recordedAt: Date, userID: UUID) async throws
}
