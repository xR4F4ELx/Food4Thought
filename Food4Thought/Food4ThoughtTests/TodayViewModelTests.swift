import Foundation
import Testing
import Food4ThoughtCore
@testable import Food4Thought

// MARK: - Fakes

private let todayUserID = UUID()

private actor FakeTodayRepository: TodayReading {
    private var result: Result<TodaySnapshot, any Error>
    private(set) var loads = 0

    init(_ snapshot: TodaySnapshot) { result = .success(snapshot) }
    init(failure: any Error) { result = .failure(failure) }

    func replace(with snapshot: TodaySnapshot) { result = .success(snapshot) }
    func setFailure(_ error: any Error) { result = .failure(error) }

    func snapshot(userID: UUID) async throws -> TodaySnapshot {
        loads += 1
        return try result.get()
    }
}

private func entry(
    _ name: String,
    mealKey: String,
    kcal: Double,
    protein: Double = 0,
    at hour: Int = 12
) -> LoggedEntry {
    LoggedEntry(
        id: UUID(),
        foodName: name,
        mealKey: mealKey,
        loggedAt: Calendar.current.date(
            bySettingHour: hour, minute: 0, second: 0, of: .now
        ) ?? .now,
        quantity: 1,
        facts: NutritionFacts(calories: kcal, protein: protein, carbs: 0, fat: 0)
    )
}

private func snapshot(
    entries: [LoggedEntry],
    target: Int = 2000,
    balance: Int = 0,
    todayOverage: Int = 0,
    averageOverage: Int? = nil,
    schedule: MealSchedule = MealSchedule.Preset.threeMeals.schedule
) -> TodaySnapshot {
    TodaySnapshot(
        targets: DailyTargets(
            dailyCalorieTarget: target,
            macros: MacroTargets(proteinGrams: 120, carbsGrams: 250, fatGrams: 60)
        ),
        schedule: schedule,
        entries: entries,
        balanceKcal: balance,
        todayOverageKcal: todayOverage,
        averageDailyOverageKcal: averageOverage
    )
}

@MainActor
private func makeViewModel(
    _ repository: FakeTodayRepository,
    foods: FakeFoodRepository = FakeFoodRepository()
) -> TodayViewModel {
    TodayViewModel(userID: todayUserID, today: repository, foods: foods)
}

// MARK: - Tests

@Suite("Today view model")
@MainActor
struct TodayViewModelTests {

    // MARK: - The meal list

    @Test("slots appear in schedule order, whether or not anything is logged to them")
    func slotsFollowScheduleOrder() async {
        // Arrange — two of four slots have entries.
        let repository = FakeTodayRepository(snapshot(entries: [
            entry("Oats", mealKey: "breakfast", kcal: 380, at: 8),
            entry("Rice bowl", mealKey: "lunch", kcal: 620, at: 13)
        ]))
        let viewModel = makeViewModel(repository)

        // Act
        await viewModel.load()

        // Assert — an empty slot is still a row, because "+ Add" is the point.
        #expect(viewModel.slotGroups.map(\.key) == ["breakfast", "lunch", "snack", "dinner"])
        #expect(viewModel.slotGroups[0].isLogged)
        #expect(viewModel.slotGroups[2].isLogged == false)
        #expect(viewModel.slotGroups[2].totalKcal == 0)
    }

    @Test("a slot collects every entry logged to it, and totals them")
    func slotCollectsItsEntries() async {
        let repository = FakeTodayRepository(snapshot(entries: [
            entry("Oats", mealKey: "breakfast", kcal: 220, at: 8),
            entry("Banana", mealKey: "breakfast", kcal: 105, at: 8),
            entry("Coffee", mealKey: "breakfast", kcal: 55, at: 9)
        ]))
        let viewModel = makeViewModel(repository)

        await viewModel.load()

        let breakfast = viewModel.slotGroups[0]
        #expect(breakfast.entries.count == 3)
        #expect(breakfast.totalKcal == 380)
        // Middot, not comma: a USDA name carries commas of its own, and
        // comma-joining two of them reads as four foods.
        #expect(breakfast.summary == "Oats · Banana · Coffee")
    }

    @Test("entries logged to a slot the user has since removed are still shown")
    func orphanedEntriesSurviveAScheduleChange() async throws {
        // Someone on three meals who switches to OMAD still ate this morning,
        // and those calories are already counted in the ring. Dropping the row
        // would leave a screen whose meal list doesn't add up to its own total.
        let repository = FakeTodayRepository(snapshot(
            entries: [
                entry("Oats", mealKey: "breakfast", kcal: 380, at: 8),
                entry("Curry", mealKey: "meal", kcal: 700, at: 18)
            ],
            schedule: MealSchedule.Preset.oneMealADay.schedule
        ))
        let viewModel = makeViewModel(repository)

        await viewModel.load()

        #expect(viewModel.slotGroups.map(\.key) == ["meal", TodayViewModel.orphanedSlotKey])

        let other = try #require(viewModel.slotGroups.last)
        #expect(other.label == "Other")
        #expect(other.isOrphaned)
        #expect(other.totalKcal == 380)
    }

    // MARK: - Figures

    @Test("progress sums every entry, including orphaned ones")
    func progressSumsEverything() async throws {
        let repository = FakeTodayRepository(snapshot(
            entries: [
                entry("Oats", mealKey: "breakfast", kcal: 380, protein: 12, at: 8),
                entry("Curry", mealKey: "gone", kcal: 700, protein: 30, at: 18)
            ],
            target: 2000
        ))
        let viewModel = makeViewModel(repository)

        await viewModel.load()

        let progress = try #require(viewModel.progress)
        #expect(progress.consumedKcal == 1080)
        #expect(progress.remainingKcal == 920)
        #expect(progress.grams(of: .protein) == 42)
    }

    @Test("the balance comes from the rollup and is never recomputed on the client")
    func balanceIsPassedThrough() async throws {
        // The cap is path-dependent, so recompute_balance is its only correct
        // author. This view model may only read it.
        let repository = FakeTodayRepository(snapshot(
            entries: [entry("Pasta", mealKey: "dinner", kcal: 900, at: 19)],
            balance: -755,
            todayOverage: 275,
            averageOverage: 240
        ))
        let viewModel = makeViewModel(repository)

        await viewModel.load()

        let balance = try #require(viewModel.balance)
        #expect(balance.state == .debt)
        #expect(balance.owedKcal == 755)
        #expect(balance.focusToClearKcal == 480)
        #expect(balance.ringLabel == "Debt +275")
    }

    @Test("a day with nothing logged is the first-run state")
    func firstRunOfDay() async {
        let empty = FakeTodayRepository(snapshot(entries: []))
        let viewModel = makeViewModel(empty)
        await viewModel.load()
        #expect(viewModel.isFirstRunOfDay)

        let logged = FakeTodayRepository(snapshot(entries: [
            entry("Oats", mealKey: "breakfast", kcal: 380, at: 8)
        ]))
        let second = makeViewModel(logged)
        await second.load()
        #expect(second.isFirstRunOfDay == false)
    }

    // MARK: - Failure

    @Test("a failed reload keeps the figures already on screen")
    func failedReloadKeepsLastSnapshot() async {
        // Blanking the rings on a dropped connection makes a working account
        // look like a deleted one.
        let repository = FakeTodayRepository(snapshot(entries: [
            entry("Oats", mealKey: "breakfast", kcal: 380, at: 8)
        ]))
        let viewModel = makeViewModel(repository)
        await viewModel.load()

        await repository.setFailure(TodayRepositoryError.network)
        await viewModel.load()

        #expect(viewModel.snapshot != nil)
        #expect(viewModel.progress?.consumedKcal == 380)
        #expect(viewModel.errorMessage != nil)
    }

    // MARK: - Deleting

    @Test("deleting an entry removes it and refreshes the figures behind it")
    func deleteRemovesTheEntry() async {
        let removed = entry("Ice cream", mealKey: "dinner", kcal: 300, at: 21)
        let repository = FakeTodayRepository(snapshot(entries: [
            entry("Pasta", mealKey: "dinner", kcal: 640, at: 19),
            removed
        ]))
        let foods = FakeFoodRepository()
        let viewModel = makeViewModel(repository, foods: foods)
        await viewModel.load()

        // The repository answers with the day as it stands after the delete —
        // which is what the rollup rebuild on the server produces.
        await repository.replace(with: snapshot(entries: [
            entry("Pasta", mealKey: "dinner", kcal: 640, at: 19)
        ]))

        await viewModel.delete(removed)

        #expect(await foods.deletedEntryIDs == [removed.id])
        #expect(viewModel.progress?.consumedKcal == 640)
        #expect(viewModel.deletingEntryID == nil)
    }

    @Test("a failed delete surfaces the reason and leaves the entry alone")
    func failedDeleteIsReported() async {
        let doomed = entry("Ice cream", mealKey: "dinner", kcal: 300, at: 21)
        let repository = FakeTodayRepository(snapshot(entries: [doomed]))
        let foods = FakeFoodRepository(deleteFailure: FoodRepositoryError.network)
        let viewModel = makeViewModel(repository, foods: foods)
        await viewModel.load()

        await viewModel.delete(doomed)

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.slotGroups.contains { $0.entries.contains(doomed) })
        // Released rather than left spinning, so the row can be tried again.
        #expect(viewModel.deletingEntryID == nil)
    }
}
