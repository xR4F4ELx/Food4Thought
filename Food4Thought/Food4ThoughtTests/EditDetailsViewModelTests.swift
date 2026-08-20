import Foundation
import Testing
import Food4ThoughtCore
@testable import Food4Thought

private let detailsUserID = UUID()

private func birthday() -> Date {
    var components = DateComponents()
    components.year = 1994
    components.month = 3
    components.day = 2
    return Calendar.current.date(from: components)!
}

private func today() -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 8
    components.day = 19
    components.hour = 9
    return Calendar.current.date(from: components)!
}

private func storedDetails(
    goal: GoalType = .loseWeight,
    activity: ActivityLevel = .lightlyActive
) -> ProfileDetails {
    ProfileDetails(
        displayName: "Rafael",
        birthDate: birthday(),
        sex: .male,
        heightCm: 178,
        activityLevel: activity,
        goal: goal,
        mealSchedule: MealSchedule.Preset.noBreakfast.schedule
    )
}

private actor SpyProfileEditingRepository: ProfileRepository {
    var details: ProfileDetails?
    private(set) var submissions: [OnboardingSubmission] = []
    private var saveFailure: (any Error)?

    init(details: ProfileDetails? = storedDetails(), saveFailure: (any Error)? = nil) {
        self.details = details
        self.saveFailure = saveFailure
    }

    func hasCompletedOnboarding(userID: UUID) async throws -> Bool { true }
    func currentDetails(userID: UUID) async throws -> ProfileDetails? { details }
    func activeGoalSet(userID: UUID) async throws -> GoalSetSummary? { nil }

    func completeOnboarding(_ submission: OnboardingSubmission) async throws {
        if let saveFailure { throw saveFailure }
        submissions.append(submission)
    }

    func syncTimeZone(_ identifier: String, userID: UUID) async throws -> TimeZoneSyncResult { .unchanged }
    func mealSchedule(userID: UUID) async throws -> MealSchedule { MealSchedule.Preset.threeMeals.schedule }
    func updateMealSchedule(_ schedule: MealSchedule, userID: UUID) async throws {}
    #if DEBUG
    func resetOnboarding(userID: UUID) async throws {}
    #endif
}

@MainActor
private func makeViewModel(
    profiles: SpyProfileEditingRepository = SpyProfileEditingRepository(),
    weights: FakeWeightRepository = FakeWeightRepository(
        stored: [WeighIn(id: UUID(), recordedAt: today(), weightKg: 82.4)]
    )
) -> EditDetailsViewModel {
    EditDetailsViewModel(
        userID: detailsUserID,
        profiles: profiles,
        weights: weights,
        now: today
    )
}

@Suite("Edit details")
@MainActor
struct EditDetailsViewModelTests {

    @Test("opens on the answers already stored, not on blanks")
    func loadsStoredAnswers() async {
        let viewModel = makeViewModel()

        await viewModel.load()

        #expect(viewModel.heightText == "178.0")
        #expect(viewModel.weightText == "82.4")
        #expect(viewModel.sex == .male)
        #expect(viewModel.activityLevel == .lightlyActive)
        // The stored goal is reopened in the terms it was chosen in.
        #expect(viewModel.direction == .lose)
        #expect(viewModel.pace == .steady)
    }

    @Test("the plan updates as the answers change, before anything is saved")
    func planFollowsTheEdits() async {
        // Editing a number whose only consequence appears tomorrow on another
        // screen is editing blind.
        let viewModel = makeViewModel()
        await viewModel.load()
        let before = viewModel.plan?.dailyCalorieTarget

        viewModel.direction = .gain
        viewModel.pace = .aggressive

        #expect(before != nil)
        #expect(viewModel.plan?.dailyCalorieTarget != before)
    }

    @Test("saving submits the recomputed plan and the weight as entered")
    func saveSubmitsTheEditedPlan() async throws {
        let profiles = SpyProfileEditingRepository()
        let viewModel = makeViewModel(profiles: profiles)
        await viewModel.load()

        viewModel.weightText = "80.0"
        viewModel.activityLevel = .veryActive

        #expect(await viewModel.save())

        let submission = try #require(await profiles.submissions.first)
        #expect(abs(submission.inputs.weightKg - 80) < 0.001)
        #expect(submission.inputs.activityLevel == .veryActive)
        // The stored plan has to be the one the screen showed, or the user
        // agrees to one set of targets and gets another.
        #expect(submission.plan.dailyCalorieTarget == viewModel.plan?.dailyCalorieTarget)
    }

    @Test("the meal schedule is carried through untouched")
    func saveKeepsTheStoredMealSchedule() async throws {
        // Meal times are edited on Home. Re-sending a default here would
        // silently revert a schedule changed there.
        let profiles = SpyProfileEditingRepository()
        let viewModel = makeViewModel(profiles: profiles)
        await viewModel.load()

        _ = await viewModel.save()

        let submission = try #require(await profiles.submissions.first)
        #expect(submission.mealSchedule.slots.count == MealSchedule.Preset.noBreakfast.schedule.slots.count)
        #expect(submission.displayName == "Rafael")
    }

    @Test("switching units converts the figures rather than reinterpreting them")
    func switchingUnitsConverts() async {
        // Left alone, 178 cm would be read as 178 inches — a 4.5 metre human
        // with a plausible-looking calorie target.
        let viewModel = makeViewModel()
        await viewModel.load()

        viewModel.setUsesMetric(false)

        #expect(viewModel.heightText == "70.1")
        #expect(viewModel.weightText == "181.7")

        viewModel.setUsesMetric(true)

        #expect(viewModel.heightText == "178.1")
    }

    @Test("an implausible weight blocks the save")
    func implausibleWeightIsRefused() async {
        let profiles = SpyProfileEditingRepository()
        let viewModel = makeViewModel(profiles: profiles)
        await viewModel.load()

        viewModel.weightText = "8.24"

        #expect(viewModel.canSave == false)
        #expect(await viewModel.save() == false)
        #expect(await profiles.submissions.isEmpty)
    }

    @Test("a failed save keeps the edits on screen and says why")
    func failedSaveKeepsEdits() async {
        let profiles = SpyProfileEditingRepository(saveFailure: OnboardingFailure.network)
        let viewModel = makeViewModel(profiles: profiles)
        await viewModel.load()
        viewModel.weightText = "80.0"

        #expect(await viewModel.save() == false)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.weightText == "80.0")
    }

    @Test("a profile with nothing stored says so instead of offering empty fields")
    func missingDetailsAreExplained() async {
        let viewModel = makeViewModel(profiles: SpyProfileEditingRepository(details: nil))

        await viewModel.load()

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.canSave == false)
    }
}
