import Foundation
import Testing
import Food4ThoughtCore
@testable import Food4Thought

// MARK: - Fakes

private struct StubAuthService: AuthService {
    let user: AuthenticatedUser?

    func currentUser() async -> AuthenticatedUser? { user }
    func signIn(email: String, password: String) async throws -> AuthenticatedUser { user! }
    func signUp(email: String, password: String) async throws -> AuthenticatedUser { user! }
    func signOut() async throws {}
}

/// Stands in for the profiles row, so a test can say what the server already
/// holds and then assert on what the client wrote over it.
private actor FakeProfileRepository: ProfileRepository {
    private(set) var storedTimeZone: String
    private(set) var syncCallCount = 0
    private let onboarded: Bool
    private let syncFailure: (any Error)?

    init(
        storedTimeZone: String = "UTC",
        onboarded: Bool = true,
        syncFailure: (any Error)? = nil
    ) {
        self.storedTimeZone = storedTimeZone
        self.onboarded = onboarded
        self.syncFailure = syncFailure
    }

    func hasCompletedOnboarding(userID: UUID) async throws -> Bool { onboarded }

    func completeOnboarding(_ submission: OnboardingSubmission) async throws {}

    func syncTimeZone(_ identifier: String, userID: UUID) async throws -> TimeZoneSyncResult {
        syncCallCount += 1
        if let syncFailure { throw syncFailure }
        guard storedTimeZone != identifier else { return .unchanged }
        storedTimeZone = identifier
        return .updated
    }

    func mealSchedule(userID: UUID) async throws -> MealSchedule {
        MealSchedule.Preset.threeMeals.schedule
    }

    func updateMealSchedule(_ schedule: MealSchedule, userID: UUID) async throws {}

    #if DEBUG
    func resetOnboarding(userID: UUID) async throws {}
    #endif
}

private actor SpyBalanceRepository: BalanceRecomputing {
    private(set) var recomputeCallCount = 0

    @discardableResult
    func recompute(from day: Date?) async throws -> Int {
        recomputeCallCount += 1
        return 0
    }
}

private let user = AuthenticatedUser(id: UUID(), email: "test@example.com")

@MainActor
private func makeAppState(
    profiles: FakeProfileRepository,
    balances: SpyBalanceRepository = SpyBalanceRepository(),
    deviceZone: String = "Europe/Lisbon",
    signedIn: Bool = true
) -> AppState {
    AppState(
        authService: StubAuthService(user: signedIn ? user : nil),
        profileRepository: profiles,
        balanceRepository: balances,
        currentTimeZone: { TimeZone(identifier: deviceZone)! }
    )
}

// MARK: - Tests

@MainActor
@Suite("AppState timezone sync")
struct AppStateTimeZoneTests {

    @Test("launching writes the device timezone over the UTC default")
    func bootstrapWritesDeviceZone() async {
        let profiles = FakeProfileRepository(storedTimeZone: "UTC")
        let appState = makeAppState(profiles: profiles, deviceZone: "Europe/Lisbon")

        await appState.bootstrap()

        #expect(await profiles.storedTimeZone == "Europe/Lisbon")
    }

    @Test("moving the timezone rebuilds the balance rollup, since every day boundary shifts")
    func changedZoneRebuildsRollup() async {
        let balances = SpyBalanceRepository()
        let appState = makeAppState(
            profiles: FakeProfileRepository(storedTimeZone: "UTC"),
            balances: balances,
            deviceZone: "America/New_York"
        )

        await appState.bootstrap()

        #expect(await balances.recomputeCallCount == 1)
    }

    @Test("an unchanged timezone does not rebuild the rollup")
    func unchangedZoneSkipsRollup() async {
        let balances = SpyBalanceRepository()
        let appState = makeAppState(
            profiles: FakeProfileRepository(storedTimeZone: "Europe/Lisbon"),
            balances: balances,
            deviceZone: "Europe/Lisbon"
        )

        await appState.bootstrap()

        #expect(await balances.recomputeCallCount == 0)
    }

    @Test("finishing onboarding writes the timezone, which the RPC does not carry")
    func completingOnboardingWritesZone() async {
        let profiles = FakeProfileRepository(storedTimeZone: "UTC", onboarded: false)
        let appState = makeAppState(profiles: profiles, deviceZone: "Asia/Tokyo")
        await appState.bootstrap()

        let inputs = GoalInputs(
            birthDate: Date(timeIntervalSince1970: 0),
            sex: .female,
            heightCm: 170,
            weightKg: 65,
            activityLevel: .lightlyActive,
            goal: .maintain
        )

        try? await appState.completeOnboarding(
            OnboardingSubmission(
                inputs: inputs,
                plan: TDEECalculator.plan(for: inputs),
                mealSchedule: MealSchedule.Preset.threeMeals.schedule
            )
        )

        #expect(await profiles.storedTimeZone == "Asia/Tokyo")
        #expect(appState.phase == .ready(user))
    }

    @Test("a failed timezone write records the reason and leaves the user signed in")
    func syncFailureIsRecordedNotSwallowed() async {
        let profiles = FakeProfileRepository(syncFailure: URLError(.notConnectedToInternet))
        let appState = makeAppState(profiles: profiles)

        await appState.bootstrap()

        #expect(appState.timeZoneSyncError != nil)
        #expect(appState.phase == .ready(user))
    }

    @Test("signing out clears the recorded sync failure")
    func signOutClearsSyncError() async {
        let profiles = FakeProfileRepository(syncFailure: URLError(.timedOut))
        let appState = makeAppState(profiles: profiles)
        await appState.bootstrap()

        await appState.signOut()

        #expect(appState.timeZoneSyncError == nil)
    }
}
