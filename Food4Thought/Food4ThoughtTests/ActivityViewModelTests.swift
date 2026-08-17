import Foundation
import Testing
import Food4ThoughtCore
@testable import Food4Thought

private let activityUserID = UUID()

private actor FakeActivityRepository: ActivityRepository {
    private(set) var logged: [ActivityDraft] = []
    private(set) var deleted: [UUID] = []
    private(set) var recomputedFrom: [Date] = []

    var storedEntries: [ActivityEntry]
    var weight: Double?
    private var logFailure: (any Error)?

    init(
        entries: [ActivityEntry] = [],
        weight: Double? = 70,
        logFailure: (any Error)? = nil
    ) {
        self.storedEntries = entries
        self.weight = weight
        self.logFailure = logFailure
    }

    func entries(userID: UUID, on date: Date) async throws -> [ActivityEntry] { storedEntries }
    func latestWeightKg(userID: UUID) async throws -> Double? { weight }

    func log(_ draft: ActivityDraft, userID: UUID) async throws {
        if let logFailure { throw logFailure }
        logged.append(draft)
        recomputedFrom.append(draft.startedAt)
        storedEntries.append(
            ActivityEntry(
                id: UUID(),
                startedAt: draft.startedAt,
                endedAt: draft.endedAt,
                activeKcal: draft.activeKcal,
                rawType: draft.type.rawValue,
                isManual: true
            )
        )
    }

    func delete(id: UUID, startedAt: Date, userID: UUID) async throws {
        deleted.append(id)
        recomputedFrom.append(startedAt)
        storedEntries = storedEntries.filter { $0.id != id }
    }
}

private actor StubTodayRepository: TodayReading {
    private let result: TodaySnapshot

    init(balance: Int, todayOverage: Int = 0, todayBurned: Int = 0, averageOverage: Int? = nil) {
        result = TodaySnapshot(
            targets: DailyTargets(
                dailyCalorieTarget: 2000,
                macros: MacroTargets(proteinGrams: 120, carbsGrams: 250, fatGrams: 60)
            ),
            schedule: MealSchedule.Preset.threeMeals.schedule,
            entries: [],
            balanceKcal: balance,
            todayOverageKcal: todayOverage,
            todayBurnedKcal: todayBurned,
            averageDailyOverageKcal: averageOverage
        )
    }

    func snapshot(userID: UUID) async throws -> TodaySnapshot { result }
}

private func workout(_ type: ExerciseType, kcal: Double, id: UUID = UUID()) -> ActivityEntry {
    ActivityEntry(
        id: id,
        startedAt: .now,
        endedAt: Date.now.addingTimeInterval(1800),
        activeKcal: kcal,
        rawType: type.rawValue,
        isManual: true
    )
}

@MainActor
private func makeViewModel(
    activity: FakeActivityRepository = FakeActivityRepository(),
    balance: Int = 0
) -> ActivityViewModel {
    ActivityViewModel(
        userID: activityUserID,
        activity: activity,
        today: StubTodayRepository(balance: balance)
    )
}

@Suite("Activity view model")
@MainActor
struct ActivityViewModelTests {

    // MARK: - Loading

    @Test("the balance comes from the same snapshot Home reads")
    func balanceMatchesHome() async throws {
        // Two screens showing the same figure from two code paths is two
        // chances for them to disagree.
        let viewModel = makeViewModel(balance: -480)
        await viewModel.load()

        let balance = try #require(viewModel.balance)
        #expect(balance.state == .debt)
        #expect(balance.owedKcal == 480)
    }

    @Test("today's burn is the raw sum, not the balance movement")
    func burnedTodayIsTheRawSum() async {
        // 10b's case: a run logs 560 while the balance shows 320, because the
        // cap dropped the rest. "560 burned" is true; implying it all landed
        // would not be.
        let activity = FakeActivityRepository(entries: [
            workout(.running, kcal: 400),
            workout(.walking, kcal: 160)
        ])
        let viewModel = makeViewModel(activity: activity, balance: 320)
        await viewModel.load()

        #expect(viewModel.burnedTodayKcal == 560)
        #expect(viewModel.balance?.creditKcal == 320)
    }

    @Test("a missing body weight is flagged so the estimate isn't passed off as personal")
    func fallbackWeightIsFlagged() async {
        let withWeight = makeViewModel(activity: FakeActivityRepository(weight: 82))
        await withWeight.load()
        #expect(withWeight.isUsingFallbackWeight == false)
        #expect(withWeight.weightKg == 82)

        let without = makeViewModel(activity: FakeActivityRepository(weight: nil))
        await without.load()
        #expect(without.isUsingFallbackWeight)
    }

    // MARK: - The worked example

    @Test("the walk estimate is derived from the focus figure and the user's weight")
    func walkMinutesForFocus() async throws {
        let activity = FakeActivityRepository(weight: 70)
        let viewModel = ActivityViewModel(
            userID: activityUserID,
            activity: activity,
            today: StubTodayRepository(balance: -175)
        )
        await viewModel.load()

        // 175 kcal at (3.5 − 1) METs × 70 kg is exactly an hour.
        let minutes = try #require(viewModel.walkMinutesToClearFocus)
        #expect(minutes == 60)
    }

    @Test("there is no walk to suggest when nothing is owed")
    func noWalkWhenSquareOrInCredit() async {
        let square = makeViewModel(balance: 0)
        await square.load()
        #expect(square.walkMinutesToClearFocus == nil)

        let credit = makeViewModel(balance: 320)
        await credit.load()
        #expect(credit.walkMinutesToClearFocus == nil)
    }

    // MARK: - Writing

    @Test("logging a workout writes it and rebuilds the balance from its day")
    func logWritesAndRecomputes() async throws {
        // activity_entries feeds recompute_balance, but balance_days is stored
        // rather than derived — a workout that skipped the rebuild would sit in
        // the table without ever reaching the balance it exists to move.
        let activity = FakeActivityRepository()
        let viewModel = makeViewModel(activity: activity, balance: -480)
        await viewModel.load()

        let started = Date.now.addingTimeInterval(-3600)
        let draft = ActivityDraft(type: .walking, startedAt: started, minutes: 30, activeKcal: 88)

        #expect(await viewModel.log(draft))

        let written = try #require(await activity.logged.first)
        #expect(written.type == .walking)
        #expect(written.activeKcal == 88)
        #expect(await activity.recomputedFrom == [started])
    }

    @Test("a workout worth nothing is refused")
    func zeroBurnIsRefused() async {
        // A zero entry moves no balance and only adds a row to explain away.
        let activity = FakeActivityRepository()
        let viewModel = makeViewModel(activity: activity)
        await viewModel.load()

        let draft = ActivityDraft(type: .yoga, startedAt: .now, minutes: 0, activeKcal: 0)

        #expect(await viewModel.log(draft) == false)
        #expect(await activity.logged.isEmpty)
    }

    @Test("a failed log is reported and keeps the sheet up")
    func failedLogIsReported() async {
        let activity = FakeActivityRepository(logFailure: ActivityRepositoryError.network)
        let viewModel = makeViewModel(activity: activity)
        await viewModel.load()

        let draft = ActivityDraft(type: .running, startedAt: .now, minutes: 30, activeKcal: 300)

        #expect(await viewModel.log(draft) == false)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.isSaving == false)
    }

    @Test("deleting a workout removes it and rebuilds from its day")
    func deleteRemovesAndRecomputes() async {
        let id = UUID()
        let entry = workout(.running, kcal: 400, id: id)
        let activity = FakeActivityRepository(entries: [entry])
        let viewModel = makeViewModel(activity: activity, balance: 320)
        await viewModel.load()

        await viewModel.delete(entry)

        #expect(await activity.deleted == [id])
        #expect(await activity.recomputedFrom == [entry.startedAt])
        #expect(viewModel.hasLoggedToday == false)
        #expect(viewModel.deletingEntryID == nil)
    }

    // MARK: - Unknown workout types

    @Test("a workout type this app has never heard of is still displayable")
    func unknownTypeStillRenders() {
        // activity_type is free text so a HealthKit sync can write its own
        // taxonomy. Reading one back must not produce a blank row.
        let entry = ActivityEntry(
            id: UUID(),
            startedAt: .now,
            endedAt: nil,
            activeKcal: 210,
            rawType: "HKWorkoutActivityTypeSurfing",
            isManual: false
        )

        #expect(entry.type == nil)
        #expect(entry.label == "HKWorkoutActivityTypeSurfing")
        #expect(entry.symbolName.isEmpty == false)
    }

    @Test("a workout with no type at all still has a label")
    func missingTypeStillRenders() {
        let entry = ActivityEntry(
            id: UUID(), startedAt: .now, endedAt: nil,
            activeKcal: 100, rawType: nil, isManual: true
        )

        #expect(entry.label == "Activity")
    }
}
