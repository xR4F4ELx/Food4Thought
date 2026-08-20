import Foundation
import Testing
import Food4ThoughtCore
@testable import Food4Thought

private let macroUserID = UUID()

/// A fixed morning, so "the last two weeks" never depends on the clock.
private func macroMorning() -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 8
    components.day = 20
    components.hour = 9
    return Calendar.current.date(from: components)!
}

private func macroDay(_ daysAgo: Int, protein: Double, carbs: Double, fat: Double) -> DailyMacros {
    let day = Calendar.current.startOfDay(
        for: Calendar.current.date(byAdding: .day, value: -daysAgo, to: macroMorning())!
    )
    return DailyMacros(day: day, proteinGrams: protein, carbsGrams: carbs, fatGrams: fat)
}

private actor QuietProfileRepository: ProfileRepository {
    func hasCompletedOnboarding(userID: UUID) async throws -> Bool { true }
    func activeGoalSet(userID: UUID) async throws -> GoalSetSummary? { nil }
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
private func makeViewModel(_ days: [DailyMacros]) -> TrendsViewModel {
    TrendsViewModel(
        userID: macroUserID,
        weights: FakeWeightRepository(),
        profiles: QuietProfileRepository(),
        macros: FakeMacroHistoryRepository(days: days),
        now: macroMorning
    )
}

@Suite("Macro trends")
@MainActor
struct MacroTrendTests {

    @Test("share mode gives each day three segments adding up to a full bar")
    func shareModeFillsTheBar() async {
        let viewModel = makeViewModel([
            macroDay(1, protein: 130, carbs: 210, fat: 62),
            macroDay(0, protein: 96, carbs: 240, fat: 70)
        ])

        await viewModel.load()

        #expect(viewModel.macroReading == .share)
        #expect(viewModel.macroBars.count == 6)

        // Every day fills to 100, which is what makes the bars comparable.
        for day in Set(viewModel.macroBars.map(\.day)) {
            let total = viewModel.macroBars.filter { $0.day == day }.reduce(0) { $0 + $1.value }
            #expect(abs(total - 100) < 0.001)
        }
    }

    @Test("grams mode plots what was eaten, not what share of it")
    func gramsModePlotsGrams() async throws {
        let viewModel = makeViewModel([macroDay(0, protein: 130, carbs: 210, fat: 62)])
        await viewModel.load()

        viewModel.macroReading = .grams

        let protein = try #require(viewModel.macroBars.first { $0.macro == .protein })
        #expect(protein.value == 130)
    }

    @Test("an unlogged day is a gap, not a bar of zero")
    func unloggedDaysAreOmitted() async {
        // A zero-height bar claims a day of eating nothing. Absence says the
        // day was not recorded, which is the true statement.
        let viewModel = makeViewModel([
            macroDay(2, protein: 120, carbs: 200, fat: 60),
            macroDay(1, protein: 0, carbs: 0, fat: 0),
            macroDay(0, protein: 110, carbs: 190, fat: 55)
        ])

        await viewModel.load()

        #expect(Set(viewModel.macroBars.map(\.day)).count == 2)
    }

    @Test("the window's split weights days by what was eaten in them")
    func averageSplitIsWeighted() async throws {
        // A 900 kcal Tuesday should not count as much as a full Wednesday when
        // one figure has to stand for the fortnight.
        let viewModel = makeViewModel([
            macroDay(1, protein: 10, carbs: 10, fat: 1),
            macroDay(0, protein: 200, carbs: 100, fat: 40)
        ])

        await viewModel.load()

        let split = try #require(viewModel.averageSplit)
        let percentages = split.roundedPercentages
        #expect(percentages.protein + percentages.carbs + percentages.fat == 100)
        // Protein-heavy overall, because the big day was protein-heavy.
        #expect(percentages.protein > percentages.carbs)
    }

    @Test("the split is described by calories, and says so")
    func averageSplitTextNamesItsUnits() async throws {
        // By weight the same day reads completely differently, and someone
        // checking the numbers against their food packets deserves to know
        // which one this is.
        let viewModel = makeViewModel([macroDay(0, protein: 100, carbs: 100, fat: 100)])

        await viewModel.load()

        let text = try #require(viewModel.averageSplitText)
        #expect(text.contains("by calories"))
        #expect(text.contains("One logged day"))
    }

    @Test("nothing logged leaves the card with something to say and no chart")
    func emptyHistoryIsHandled() async {
        let viewModel = makeViewModel([])

        await viewModel.load()

        #expect(viewModel.hasMacroHistory == false)
        #expect(viewModel.averageSplitText == nil)
    }
}
