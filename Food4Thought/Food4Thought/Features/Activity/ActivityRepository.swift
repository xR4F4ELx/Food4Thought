import Foundation
import Food4ThoughtCore

/// One row of `activity_entries`.
struct ActivityEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?

    /// Always an estimate, and labelled as one everywhere it is shown.
    let activeKcal: Double

    /// What the column actually holds. Free text, so it may be a value this app
    /// has never heard of — a HealthKit sync would write its own taxonomy.
    let rawType: String?

    let isManual: Bool

    /// Nil when the stored string isn't one of ours, which is why `rawType` is
    /// kept alongside: an unrecognised workout still has to be displayable.
    var type: ExerciseType? { rawType.flatMap(ExerciseType.init(rawValue:)) }

    var label: String { type?.label ?? rawType ?? "Activity" }
    var symbolName: String { type?.symbolName ?? "figure.mixed.cardio" }

    var minutes: Int? {
        guard let endedAt else { return nil }
        return Int((endedAt.timeIntervalSince(startedAt) / 60).rounded())
    }
}

/// A workout on its way into `activity_entries`.
struct ActivityDraft: Equatable, Sendable {
    let type: ExerciseType
    let startedAt: Date
    let minutes: Double
    let activeKcal: Double

    var endedAt: Date { startedAt.addingTimeInterval(minutes * 60) }
}

protocol ActivityRepository: Sendable {
    /// Everything logged on the day `date` falls in, newest first.
    func entries(userID: UUID, on date: Date) async throws -> [ActivityEntry]

    /// The user's most recent recorded weight, for the burn estimate. Nil when
    /// they have none — the estimator falls back and the UI says so.
    func latestWeightKg(userID: UUID) async throws -> Double?

    /// Inserts a workout and rebuilds the balance rollup from its day.
    func log(_ draft: ActivityDraft, userID: UUID) async throws

    /// Removes a workout and rebuilds the rollup from its day.
    func delete(id: UUID, startedAt: Date, userID: UUID) async throws
}

enum ActivityRepositoryError: LocalizedError, Equatable {
    case notSignedIn
    case network
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "You're signed out. Sign in and try again."
        case .network: "No connection. Your workout hasn't been saved yet."
        case .unexpected(let reason): reason
        }
    }
}
