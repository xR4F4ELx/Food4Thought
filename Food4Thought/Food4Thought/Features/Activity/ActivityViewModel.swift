import Foundation
import Observation
import Food4ThoughtCore

/// State for Activity — handoff 3a, and 10b's credit-near-cap variant.
///
/// The screen the balance affordance has been pointing at. Its job is to make
/// the debt actionable: say what is owed, show what has been burned against it
/// today, and let a workout be recorded.
@Observable
@MainActor
final class ActivityViewModel {

    // MARK: - State

    private(set) var entries: [ActivityEntry] = []
    private(set) var balance: BalanceSummary?
    private(set) var weightKg: Double?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var deletingEntryID: UUID?
    private(set) var errorMessage: String?

    // MARK: - Dependencies

    private let userID: UUID
    private let activity: ActivityRepository
    private let today: TodayReading
    private let now: @Sendable () -> Date

    init(
        userID: UUID,
        activity: ActivityRepository = SupabaseActivityRepository(),
        today: TodayReading = SupabaseTodayRepository(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.userID = userID
        self.activity = activity
        self.today = today
        self.now = now
    }

    // MARK: - Loading

    func load() async {
        isLoading = entries.isEmpty && balance == nil
        defer { isLoading = false }

        do {
            // The balance comes through the same snapshot Home reads rather
            // than a query of its own. Two screens showing the same figure from
            // two code paths is two chances for them to disagree.
            async let snapshot = today.snapshot(userID: userID)
            async let logged = activity.entries(userID: userID, on: now())
            async let weight = activity.latestWeightKg(userID: userID)

            let (day, workouts, bodyWeight) = try await (snapshot, logged, weight)

            entries = workouts
            weightKg = bodyWeight
            balance = BalanceSummary(
                kcal: day.balanceKcal,
                todayOverageKcal: day.todayOverageKcal,
                averageDailyOverageKcal: day.averageDailyOverageKcal
            )
            errorMessage = nil
        } catch {
            errorMessage = message(for: error)
        }
    }

    // MARK: - Derived

    /// What today's workouts have contributed, before the cap.
    ///
    /// Deliberately the raw sum rather than the balance movement: past the
    /// credit cap the two diverge, and 10b's example is exactly that — a run
    /// logged 560 while the balance shows 320. Saying "560 burned" is true;
    /// implying it all landed would not be.
    var burnedTodayKcal: Int {
        Int(entries.reduce(0) { $0 + $1.activeKcal }.rounded())
    }

    var hasLoggedToday: Bool { !entries.isEmpty }

    /// True when the burn estimate is running on a default body weight, so the
    /// screen can say so rather than passing it off as personal.
    var isUsingFallbackWeight: Bool { weightKg == nil }

    /// A worked example for the debt banner: how long one walk would take to
    /// clear the focus figure. Nil when nothing is owed.
    var walkMinutesToClearFocus: Int? {
        guard let balance, balance.state == .debt, balance.focusToClearKcal > 0 else { return nil }

        let minutes = ExerciseEstimator.minutes(
            toBurn: Double(balance.focusToClearKcal),
            with: .walking,
            weightKg: weightKg
        )
        return Int(minutes.rounded())
    }

    // MARK: - Writing

    /// Records a workout and rebuilds the balance behind it.
    func log(_ draft: ActivityDraft) async -> Bool {
        guard draft.activeKcal > 0 else { return false }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await activity.log(draft, userID: userID)
            await load()
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func delete(_ entry: ActivityEntry) async {
        deletingEntryID = entry.id
        defer { deletingEntryID = nil }

        do {
            try await activity.delete(id: entry.id, startedAt: entry.startedAt, userID: userID)
            await load()
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
