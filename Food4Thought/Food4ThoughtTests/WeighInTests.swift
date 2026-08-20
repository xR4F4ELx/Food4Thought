import Foundation
import Testing
import Food4ThoughtCore
@testable import Food4Thought

private let weighInUserID = UUID()

/// 9:00 on a fixed morning, so "today" never depends on when the suite runs.
private func morning() -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 8
    components.day = 19
    components.hour = 9
    return Calendar.current.date(from: components)!
}

private func daysBefore(_ days: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: -days, to: morning())!
}

@Suite("Weigh-in")
@MainActor
struct WeighInTests {

    @Test("the sheet opens on the last recorded weight, since weight barely moves")
    func prefillsWithTheLastWeight() async {
        // Most weigh-ins are an edit of one digit. Starting from blank makes
        // every one of them a typed number.
        let weights = FakeWeightRepository(
            stored: [WeighIn(id: UUID(), recordedAt: daysBefore(1), weightKg: 74.2)]
        )
        let viewModel = WeighInViewModel(userID: weighInUserID, weights: weights, now: morning)

        await viewModel.load()

        #expect(viewModel.draft.amount == "74.2")
        #expect(viewModel.lastWeighIn?.weightKg == 74.2)
    }

    @Test("a first weigh-in opens empty rather than inventing a number")
    func firstWeighInStartsBlank() async {
        let viewModel = WeighInViewModel(
            userID: weighInUserID,
            weights: FakeWeightRepository(),
            now: morning
        )

        await viewModel.load()

        #expect(viewModel.draft.amount.isEmpty)
        #expect(viewModel.canSave == false)
    }

    @Test("saving records the weight in kilograms, whatever the field was showing")
    func savesInKilograms() async throws {
        let weights = FakeWeightRepository()
        let viewModel = WeighInViewModel(userID: weighInUserID, weights: weights, now: morning)
        viewModel.draft = WeighInDraft(amount: "163", units: .imperial)

        #expect(await viewModel.save())

        let logged = try #require(await weights.logged.first)
        #expect(abs(logged.weightKg - 73.94) < 0.01)
        #expect(logged.recordedAt == morning())
    }

    @Test("a failed save keeps the sheet up and says why")
    func failedSaveIsReported() async {
        let weights = FakeWeightRepository(failure: WeightRepositoryError.network)
        let viewModel = WeighInViewModel(userID: weighInUserID, weights: weights, now: morning)
        viewModel.draft = WeighInDraft(amount: "74.2", units: .metric)

        #expect(await viewModel.save() == false)
        #expect(viewModel.errorMessage == WeightRepositoryError.network.errorDescription)
        // Still holding what was typed, so the retry is one tap.
        #expect(viewModel.draft.amount == "74.2")
    }

    @Test("an implausible entry cannot be saved")
    func implausibleEntryIsRefused() async {
        let weights = FakeWeightRepository()
        let viewModel = WeighInViewModel(userID: weighInUserID, weights: weights, now: morning)
        viewModel.draft = WeighInDraft(amount: "7.4", units: .metric)

        #expect(viewModel.canSave == false)
        #expect(await viewModel.save() == false)
        #expect(await weights.logged.isEmpty)
    }

    // MARK: - Trends

    @Test("trends reports movement across the window, not since yesterday")
    func changeIsMeasuredAcrossTheWindow() async {
        // Day to day is mostly water. "+0.4 kg since yesterday" on a screen
        // called Trends invites exactly the wrong reading.
        let weights = FakeWeightRepository(stored: [
            WeighIn(id: UUID(), recordedAt: daysBefore(14), weightKg: 76.0),
            WeighIn(id: UUID(), recordedAt: daysBefore(7), weightKg: 75.4),
            WeighIn(id: UUID(), recordedAt: daysBefore(0), weightKg: 74.5)
        ])
        let viewModel = makeTrendsViewModel(weights)

        await viewModel.load()

        #expect(viewModel.latestWeightText == "74.5")
        #expect(viewModel.changeText == "−1.5 kg over 14 days")
    }

    @Test("a single weigh-in reports no change, because it has nothing to compare")
    func singleWeighInHasNoChange() async {
        let weights = FakeWeightRepository(
            stored: [WeighIn(id: UUID(), recordedAt: morning(), weightKg: 74.5)]
        )
        let viewModel = makeTrendsViewModel(weights)

        await viewModel.load()

        #expect(viewModel.latestWeightText == "74.5")
        #expect(viewModel.changeText == nil)
        // One reading, one point — the axes still stand around it.
        #expect(viewModel.actualPoints.count == 1)
    }

    @Test("two weigh-ins on the same morning plot as one day, latest first")
    func sameDayWeighInsCollapseToOnePoint() async throws {
        // Plotted as two points they drew a vertical bar — two real readings
        // with no elapsed time between them. The later one wins because
        // re-weighing is the only way to correct a mistyped number.
        let weights = FakeWeightRepository(stored: [
            WeighIn(id: UUID(), recordedAt: daysBefore(6), weightKg: 57.0),
            WeighIn(id: UUID(), recordedAt: daysBefore(6).addingTimeInterval(3600), weightKg: 57.5)
        ])
        let viewModel = makeTrendsViewModel(weights)

        await viewModel.load()

        #expect(viewModel.actualPoints.count == 1)
        #expect(viewModel.actualPoints.first?.kilograms == 57.5)
        // Both readings still show in the list underneath.
        #expect(viewModel.weighIns.count == 2)
    }

    @Test("the headline change matches the line drawn beside it")
    func changeMatchesTheChart() async {
        // Read off the raw rows, the header claimed 1.0 kg while the chart fell
        // 0.5 — the earlier reading of a doubled-up day counted for one and not
        // the other.
        let weights = FakeWeightRepository(stored: [
            WeighIn(id: UUID(), recordedAt: daysBefore(7), weightKg: 57.5),
            WeighIn(id: UUID(), recordedAt: daysBefore(7).addingTimeInterval(1800), weightKg: 57.0),
            WeighIn(id: UUID(), recordedAt: daysBefore(0), weightKg: 56.5)
        ])
        let viewModel = makeTrendsViewModel(weights)

        await viewModel.load()

        let plotted = viewModel.actualPoints
        #expect(plotted.count == 2)
        #expect(plotted.first?.kilograms == 57.0)
        #expect(viewModel.changeText == "−0.5 kg over 7 days")
    }

    @Test("the chart stands even with nothing in it")
    func emptyChartStillHasAxes() async {
        // Hidden until the data earned it, the feature was invisible on
        // exactly the days someone is deciding whether to bother.
        let viewModel = makeTrendsViewModel(FakeWeightRepository())

        await viewModel.load()

        #expect(viewModel.hasWeighIns == false)
        #expect(viewModel.actualPoints.isEmpty)
        // A week wide, so the first weigh-in lands somewhere sensible.
        #expect(viewModel.chartXDomain.lowerBound < viewModel.chartXDomain.upperBound)
        #expect(viewModel.chartYDomain.lowerBound < viewModel.chartYDomain.upperBound)
    }

    @Test("a single weigh-in gets an axis with width, not a squashed one")
    func singlePointGetsAWindow() async {
        let weights = FakeWeightRepository(
            stored: [WeighIn(id: UUID(), recordedAt: morning(), weightKg: 74.5)]
        )
        let viewModel = makeTrendsViewModel(weights)

        await viewModel.load()

        #expect(viewModel.actualPoints.count == 1)

        let days = Calendar.current.dateComponents(
            [.day],
            from: viewModel.chartXDomain.lowerBound,
            to: viewModel.chartXDomain.upperBound
        ).day ?? 0
        #expect(days >= 7)

        // And a spread, so one reading is not drawn as a cliff.
        let spread = viewModel.chartYDomain.upperBound - viewModel.chartYDomain.lowerBound
        #expect(spread >= 1.0)
    }

    // MARK: - The plan line

    @Test("the plan line runs from the first weigh-in under it to today")
    func planLineSpansTheWindow() async throws {
        // 500 under TDEE is about half a kilo a week, so two weeks of plan is
        // about a kilo below where it started.
        let weights = FakeWeightRepository(stored: [
            WeighIn(id: UUID(), recordedAt: daysBefore(14), weightKg: 76.0),
            WeighIn(id: UUID(), recordedAt: daysBefore(0), weightKg: 74.5)
        ])
        let viewModel = makeTrendsViewModel(weights, goal: losingGoal(startedDaysAgo: 14))

        await viewModel.load()

        #expect(viewModel.hasWeighIns)
        #expect(viewModel.actualPoints.count == 2)

        let plan = viewModel.planPoints
        #expect(plan.count == 2)
        #expect(plan.first?.kilograms == 76.0)
        #expect(abs((plan.last?.kilograms ?? 0) - 75.09) < 0.05)
    }

    @Test("the plan is anchored inside its own goal set, not before it")
    func planAnchorsAtTheCurrentGoalSet() async throws {
        // The weigh-in from before the plan changed was scored against
        // different targets. Anchoring there would draw a line the user never
        // agreed to across days they were following another one.
        let weights = FakeWeightRepository(stored: [
            WeighIn(id: UUID(), recordedAt: daysBefore(30), weightKg: 80.0),
            WeighIn(id: UUID(), recordedAt: daysBefore(7), weightKg: 76.0),
            WeighIn(id: UUID(), recordedAt: daysBefore(0), weightKg: 75.6)
        ])
        let viewModel = makeTrendsViewModel(weights, goal: losingGoal(startedDaysAgo: 10))

        await viewModel.load()

        #expect(viewModel.planPoints.first?.kilograms == 76.0)
    }

    @Test("a weight tracking the plan reads as on track, water and all")
    func onTrackIsReportedPlainly() async {
        let weights = FakeWeightRepository(stored: [
            WeighIn(id: UUID(), recordedAt: daysBefore(14), weightKg: 76.0),
            WeighIn(id: UUID(), recordedAt: daysBefore(0), weightKg: 75.0)
        ])
        let viewModel = makeTrendsViewModel(weights, goal: losingGoal(startedDaysAgo: 14))

        await viewModel.load()

        #expect(viewModel.standing == .onTrack)
        #expect(viewModel.standingText?.hasPrefix("On track") == true)
    }

    @Test("losing faster than the plan is ahead, not behind")
    func fasterLossIsAhead() async throws {
        let weights = FakeWeightRepository(stored: [
            WeighIn(id: UUID(), recordedAt: daysBefore(14), weightKg: 76.0),
            WeighIn(id: UUID(), recordedAt: daysBefore(0), weightKg: 73.0)
        ])
        let viewModel = makeTrendsViewModel(weights, goal: losingGoal(startedDaysAgo: 14))

        await viewModel.load()

        let standing = try #require(viewModel.standing)
        guard case .ahead = standing else {
            Issue.record("Expected to be ahead, got \(standing)")
            return
        }
        #expect(viewModel.standingText?.contains("ahead") == true)
    }

    @Test("without a plan there is no line and no verdict, just the weights")
    func noGoalSetMeansNoComparison() async {
        let weights = FakeWeightRepository(stored: [
            WeighIn(id: UUID(), recordedAt: daysBefore(7), weightKg: 76.0),
            WeighIn(id: UUID(), recordedAt: daysBefore(0), weightKg: 75.4)
        ])
        let viewModel = makeTrendsViewModel(weights, goal: nil)

        await viewModel.load()

        #expect(viewModel.hasWeighIns)
        #expect(viewModel.planPoints.isEmpty)
        #expect(viewModel.standing == nil)
        #expect(viewModel.standingText == nil)
    }
}

// MARK: - Trends helpers

private func losingGoal(startedDaysAgo days: Int) -> GoalSetSummary {
    GoalSetSummary(
        dailyCalorieTarget: 2_000,
        totalDailyEnergyExpenditure: 2_500,
        goal: .loseWeight,
        effectiveFrom: daysBefore(days)
    )
}

private actor StubGoalProfileRepository: ProfileRepository {
    private let goal: GoalSetSummary?

    init(goal: GoalSetSummary?) { self.goal = goal }

    func hasCompletedOnboarding(userID: UUID) async throws -> Bool { true }
    func activeGoalSet(userID: UUID) async throws -> GoalSetSummary? { goal }
    func currentDetails(userID: UUID) async throws -> ProfileDetails? { nil }
    func completeOnboarding(_ submission: OnboardingSubmission) async throws {}
    func syncTimeZone(_ identifier: String, userID: UUID) async throws -> TimeZoneSyncResult { .unchanged }
    func mealSchedule(userID: UUID) async throws -> MealSchedule { MealSchedule.Preset.threeMeals.schedule }
    func updateMealSchedule(_ schedule: MealSchedule, userID: UUID) async throws {}
    #if DEBUG
    func resetOnboarding(userID: UUID) async throws {}
    #endif
}

@MainActor
private func makeTrendsViewModel(
    _ weights: FakeWeightRepository,
    goal: GoalSetSummary? = losingGoal(startedDaysAgo: 30),
    macros: FakeMacroHistoryRepository = FakeMacroHistoryRepository()
) -> TrendsViewModel {
    TrendsViewModel(
        userID: weighInUserID,
        weights: weights,
        profiles: StubGoalProfileRepository(goal: goal),
        macros: macros,
        now: morning
    )
}
