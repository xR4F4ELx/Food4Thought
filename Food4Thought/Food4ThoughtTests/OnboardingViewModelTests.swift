import Foundation
import Testing
import Food4ThoughtCore
@testable import Food4Thought

// MARK: - Fakes

private struct StubAuthService: AuthService {
    let user = AuthenticatedUser(id: UUID(), email: "test@example.com")

    func currentUser() async -> AuthenticatedUser? { user }
    func signIn(email: String, password: String) async throws -> AuthenticatedUser { user }
    func signUp(email: String, password: String) async throws -> AuthenticatedUser { user }
    func signOut() async throws {}
}

/// An actor so it can satisfy the Sendable protocol while still recording calls.
private actor SpyProfileRepository: ProfileRepository {
    var submissions: [OnboardingSubmission] = []
    private var failure: (any Error)?

    init(failing failure: (any Error)? = nil) {
        self.failure = failure
    }

    func hasCompletedOnboarding(userID: UUID) async throws -> Bool { false }
    func currentDetails(userID: UUID) async throws -> ProfileDetails? { nil }
    func activeGoalSet(userID: UUID) async throws -> GoalSetSummary? { nil }

    func completeOnboarding(_ submission: OnboardingSubmission) async throws {
        if let failure { throw failure }
        submissions.append(submission)
    }

    /// Covered on its own in AppStateTimeZoneTests; inert here so a sync can
    /// never be what makes an onboarding assertion pass or fail.
    func syncTimeZone(_ identifier: String, userID: UUID) async throws -> TimeZoneSyncResult {
        .unchanged
    }

    func mealSchedule(userID: UUID) async throws -> MealSchedule {
        MealSchedule.Preset.threeMeals.schedule
    }

    func updateMealSchedule(_ schedule: MealSchedule, userID: UUID) async throws {}

    #if DEBUG
    func resetOnboarding(userID: UUID) async throws {}
    #endif
}

// MARK: - Fixtures

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func birthDate(yearsAgo: Int) -> Date {
    utcCalendar.date(byAdding: .year, value: -yearsAgo, to: .now)!
}

@MainActor
private func makeViewModel(
    repository: SpyProfileRepository = SpyProfileRepository()
) async -> (OnboardingViewModel, AppState) {
    let appState = AppState(authService: StubAuthService(), profileRepository: repository)
    await appState.bootstrap()
    return (OnboardingViewModel(appState: appState, calendar: utcCalendar), appState)
}

/// A draft that answers everything up to, but not including, the pace step.
private func draftThroughDirection(
    sex: BiologicalSex = .male,
    heightCm: Double = 180,
    weightKg: Double = 80,
    age: Int = 25,
    activityLevel: ActivityLevel = .moderatelyActive,
    direction: GoalDirection = .lose
) -> OnboardingDraft {
    var draft = OnboardingDraft()
    draft.birthDate = birthDate(yearsAgo: age)
    draft.sex = sex
    draft.heightCm = heightCm
    draft.weightKg = weightKg
    draft.activityLevel = activityLevel
    draft.direction = direction
    return draft
}

/// Walks the flow the way the UI does. Setting `step` directly is impossible
/// by design, and driving it this way exercises the skip rules on the way in.
@MainActor
private func advance(_ viewModel: OnboardingViewModel, times: Int) {
    for _ in 0..<times { viewModel.advance() }
}

// MARK: - Tests

@Suite("Onboarding routing")
@MainActor
struct OnboardingRoutingTests {
    @Test("a signed-in user without a completed profile lands on onboarding")
    func startsOnOnboarding() async {
        let (_, appState) = await makeViewModel()
        guard case .onboarding = appState.phase else {
            Issue.record("expected .onboarding, got \(appState.phase)")
            return
        }
    }
}

@Suite("Onboarding step advancement")
@MainActor
struct OnboardingStepTests {
    @Test("cannot advance past the first screen until both answers are given")
    func aboutYouGating() async {
        let (viewModel, _) = await makeViewModel()

        #expect(!viewModel.canAdvance)

        viewModel.draft.birthDate = birthDate(yearsAgo: 25)
        #expect(!viewModel.canAdvance, "birth date alone is not enough")

        viewModel.draft.sex = .male
        #expect(viewModel.canAdvance)
    }

    @Test("advancing does nothing while the current screen is unanswered")
    func advanceIsIgnoredWhenIncomplete() async {
        let (viewModel, _) = await makeViewModel()
        viewModel.advance()
        #expect(viewModel.step == .aboutYou)
    }

    @Test("maintain skips the pace screen entirely")
    func maintainSkipsPace() async {
        let (viewModel, _) = await makeViewModel()
        viewModel.draft = draftThroughDirection(direction: .maintain)
        advance(viewModel, times: 3)
        #expect(viewModel.step == .goalDirection)

        viewModel.advance()

        #expect(viewModel.step == .mealRhythm)
    }

    @Test("a directional goal with distinguishable paces asks the question")
    func directionalGoalOffersPace() async {
        let (viewModel, _) = await makeViewModel()
        // 25yo male, 80kg, 180cm, moderately active: no calorie floor binds, so
        // steady and aggressive are ~0.13 kg/week apart.
        viewModel.draft = draftThroughDirection(direction: .lose)
        advance(viewModel, times: 3)

        viewModel.advance()

        #expect(viewModel.step == .pace)
    }

    @Test("the pace screen skips itself when the floors make both paces identical")
    func indistinguishablePacesSkipTheQuestion() async {
        let (viewModel, _) = await makeViewModel()
        // 25yo female, 50kg, 155cm, sedentary: an aggressive cut clamps to the
        // 1200 kcal floor, leaving the two paces within 0.01 kg/week.
        viewModel.draft = draftThroughDirection(
            sex: .female, heightCm: 155, weightKg: 50,
            activityLevel: .sedentary, direction: .lose
        )
        advance(viewModel, times: 3)

        #expect(viewModel.pacesAreIndistinguishable)
        viewModel.advance()
        #expect(viewModel.step == .mealRhythm)
    }

    @Test("back navigation skips the same screens forward navigation did")
    func backNavigationIsSymmetric() async {
        let (viewModel, _) = await makeViewModel()
        viewModel.draft = draftThroughDirection(direction: .maintain)
        advance(viewModel, times: 4)
        #expect(viewModel.step == .mealRhythm)

        viewModel.goBack()

        // Never lands on .pace, which was never asked.
        #expect(viewModel.step == .goalDirection)
    }

    @Test("selecting an answer commits it and advances in one step")
    func selectCommitsAndAdvances() async {
        let (viewModel, _) = await makeViewModel()
        viewModel.draft = draftThroughDirection()
        advance(viewModel, times: 2)

        viewModel.select { $0.activityLevel = .veryActive }

        #expect(viewModel.draft.activityLevel == .veryActive)
        #expect(viewModel.step == .goalDirection)
    }
}

@Suite("Onboarding submission")
@MainActor
struct OnboardingSubmissionTests {
    @Test("a successful save persists the plan and moves the app to ready")
    func submitAdvancesPhase() async {
        let repository = SpyProfileRepository()
        let (viewModel, appState) = await makeViewModel(repository: repository)
        viewModel.draft = draftThroughDirection()

        await viewModel.submit()

        let submissions = await repository.submissions
        #expect(submissions.count == 1)
        #expect(submissions.first?.plan.dailyCalorieTarget == viewModel.plan?.dailyCalorieTarget)
        #expect(viewModel.errorMessage == nil)

        guard case .ready = appState.phase else {
            Issue.record("expected .ready, got \(appState.phase)")
            return
        }
    }

    @Test("the meal schedule is normalised before it is sent")
    func submitNormalisesMealSchedule() async {
        let repository = SpyProfileRepository()
        let (viewModel, _) = await makeViewModel(repository: repository)
        viewModel.draft = draftThroughDirection()

        await viewModel.submit()

        // complete_onboarding rejects shares that do not sum to 1.0.
        let shares = await repository.submissions.first?.mealSchedule.slots
            .reduce(0) { $0 + $1.expectedShare } ?? 0
        #expect(abs(shares - 1.0) < 0.001)
    }

    @Test("a failed save keeps the user on onboarding and surfaces the reason")
    func submitFailureDoesNotAdvance() async {
        let repository = SpyProfileRepository(failing: OnboardingFailure.network)
        let (viewModel, appState) = await makeViewModel(repository: repository)
        viewModel.draft = draftThroughDirection()

        await viewModel.submit()

        #expect(viewModel.errorMessage == OnboardingFailure.network.errorDescription)

        guard case .onboarding = appState.phase else {
            Issue.record("a failed save must not route to the dashboard")
            return
        }
    }

    @Test("an incomplete draft cannot be submitted")
    func submitRequiresACompleteDraft() async {
        let repository = SpyProfileRepository()
        let (viewModel, _) = await makeViewModel(repository: repository)
        await viewModel.submit()

        let submissions = await repository.submissions
        #expect(submissions.isEmpty)
    }
}
