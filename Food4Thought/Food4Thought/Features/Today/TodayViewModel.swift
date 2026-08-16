import Foundation
import Observation
import Food4ThoughtCore

/// One row of the meal list: a slot, and whatever has been logged to it today.
struct MealSlotGroup: Identifiable, Equatable, Sendable {
    let key: String
    let label: String
    let entries: [LoggedEntry]

    /// True for a group that has no slot behind it any more — entries logged
    /// under a meal key the user has since removed from their schedule.
    let isOrphaned: Bool

    /// A one-day meal, which goes on its own at midnight.
    let isImpromptu: Bool

    var id: String { key }

    var isLogged: Bool { !entries.isEmpty }

    var totalKcal: Int {
        Int(entries.reduce(0) { $0 + $1.facts.calories }.rounded())
    }

    /// The subtitle in 1d.
    ///
    /// Separated by a middot rather than a comma because USDA names carry their
    /// own commas — "McDONALD'S, BIG BREAKFAST" comma-joined to a second food
    /// reads as three items, not two.
    var summary: String {
        entries.map(\.foodName).joined(separator: " · ")
    }
}

/// State for Home / Today — handoff 1d, 1e, 10a, and the 7a first run.
///
/// It owns no arithmetic of its own: the figures come from `DayProgress`,
/// `PaceStatus` and `BalanceSummary` in Core, and the balance integer comes
/// from the database. This class only decides what to ask for and when.
@Observable
@MainActor
final class TodayViewModel {

    /// Where entries whose slot no longer exists are collected, so a schedule
    /// change never makes logged calories disappear from a screen that is still
    /// counting them in the ring.
    static let orphanedSlotKey = "__other__"

    // MARK: - State

    private(set) var snapshot: TodaySnapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Set while a delete is in flight, so the row can't be tapped twice.
    private(set) var deletingEntryID: UUID?

    /// Set while a schedule change is being written.
    private(set) var isSavingSchedule = false

    // MARK: - Dependencies

    private let userID: UUID
    private let today: TodayReading
    private let foods: FoodRepository
    private let profiles: ProfileRepository
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        userID: UUID,
        today: TodayReading = SupabaseTodayRepository(),
        foods: FoodRepository = SupabaseFoodRepository(),
        profiles: ProfileRepository = SupabaseProfileRepository(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.userID = userID
        self.today = today
        self.foods = foods
        self.profiles = profiles
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Loading

    func load() async {
        isLoading = snapshot == nil
        defer { isLoading = false }

        do {
            snapshot = try await today.snapshot(userID: userID)
            errorMessage = nil
        } catch {
            // The last snapshot is kept on screen rather than blanked: stale
            // rings with a note beat an empty dashboard that looks like a
            // deleted account.
            errorMessage = message(for: error)
        }
    }

    // MARK: - Derived figures

    var progress: DayProgress? {
        guard let snapshot else { return nil }
        return DayProgress(
            target: snapshot.targets.dailyCalorieTarget,
            macroTargets: snapshot.targets.macros,
            consumed: snapshot.entries.reduce(NutritionFacts.zero) { $0 + $1.facts }
        )
    }

    var pace: PaceStatus? {
        guard let snapshot, let progress else { return nil }
        return PaceStatus(
            consumedKcal: Double(progress.consumedKcal),
            target: snapshot.targets.dailyCalorieTarget,
            schedule: snapshot.schedule,
            time: currentTimeOfDay()
        )
    }

    var balance: BalanceSummary? {
        guard let snapshot else { return nil }
        return BalanceSummary(
            kcal: snapshot.balanceKcal,
            todayOverageKcal: snapshot.todayOverageKcal,
            averageDailyOverageKcal: snapshot.averageDailyOverageKcal
        )
    }

    /// True on a day nothing has been logged to yet — 7a's rings-at-rest.
    var isFirstRunOfDay: Bool {
        snapshot.map { $0.entries.isEmpty } ?? false
    }

    /// One group per slot, in schedule order, plus a trailing group for any
    /// entries whose meal key no longer matches a slot.
    var slotGroups: [MealSlotGroup] {
        guard let snapshot else { return [] }

        let byKey = Dictionary(grouping: snapshot.entries, by: \.mealKey)
        let knownKeys = Set(snapshot.schedule.slots.map(\.key))

        let groups = snapshot.schedule.slots.map { slot in
            MealSlotGroup(
                key: slot.key,
                label: slot.label,
                entries: byKey[slot.key] ?? [],
                isOrphaned: false,
                isImpromptu: slot.expiresOn != nil
            )
        }

        let orphaned = snapshot.entries.filter { !knownKeys.contains($0.mealKey) }
        guard !orphaned.isEmpty else { return groups }

        return groups + [
            MealSlotGroup(
                key: Self.orphanedSlotKey,
                label: "Other",
                entries: orphaned,
                isOrphaned: true,
                isImpromptu: false
            )
        ]
    }

    // MARK: - Correcting a mistake

    /// Removes one entry and rebuilds the rollup behind it.
    ///
    /// The rebuild is the whole point: `balance_days` is stored rather than
    /// derived, so an entry taken back without one leaves the balance still
    /// carrying calories the user has just said they never ate.
    func delete(_ entry: LoggedEntry) async {
        deletingEntryID = entry.id
        defer { deletingEntryID = nil }

        do {
            try await foods.deleteEntry(id: entry.id, loggedAt: entry.loggedAt, userID: userID)
            await load()
        } catch {
            errorMessage = message(for: error)
        }
    }

    // MARK: - Editing the schedule

    /// Can a meal be removed, or is this the last one standing.
    var canRemoveMeal: Bool {
        snapshot?.schedule.canRemoveSlot ?? false
    }

    /// Adds a meal to the schedule.
    ///
    /// `lastsBeyondToday: false` gives it an expiry of today, which is the
    /// impromptu case — a birthday cake, a work lunch. It behaves exactly like
    /// any other meal until midnight and then stops appearing, rather than
    /// leaving a permanent empty row on Home.
    func addMeal(label: String, typicalTime: TimeOfDay, lastsBeyondToday: Bool) async {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let schedule = snapshot?.schedule else { return }

        await write(
            schedule.addingSlot(
                label: trimmed,
                typicalTime: typicalTime,
                expiresOn: lastsBeyondToday ? nil : ISODay.string(from: now(), in: calendar)
            )
        )
    }

    /// Removes a meal.
    ///
    /// Entries already logged to it keep their `meal_key` — history is never
    /// rewritten — so they reappear under "Other" rather than vanishing from a
    /// day whose rings still count them.
    func removeMeal(key: String) async {
        guard let schedule = snapshot?.schedule, schedule.canRemoveSlot else { return }
        await write(schedule.removingSlot(key: key))
    }

    private func write(_ schedule: MealSchedule) async {
        isSavingSchedule = true
        errorMessage = nil
        defer { isSavingSchedule = false }

        do {
            try await profiles.updateMealSchedule(schedule, userID: userID)
            await load()
        } catch {
            errorMessage = message(for: error)
        }
    }

    // MARK: - Helpers

    private func currentTimeOfDay() -> TimeOfDay {
        let parts = calendar.dateComponents([.hour, .minute], from: now())
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    private func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
