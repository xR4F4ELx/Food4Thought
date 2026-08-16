import Foundation
import Observation

/// Owns the session and the one routing decision the whole app depends on.
@Observable
@MainActor
final class AppState {

    enum Phase: Equatable {
        case loading
        case signedOut
        case onboarding(AuthenticatedUser)
        case ready(AuthenticatedUser)
    }

    private(set) var phase: Phase = .loading

    /// Last failure from the timezone reconciliation, which runs alongside
    /// routing rather than gating it. Surfaced rather than swallowed: a stale
    /// zone shows up as a wrong balance, so it needs somewhere to be seen.
    private(set) var timeZoneSyncError: String?

    private let authService: AuthService
    private let profileRepository: ProfileRepository
    private let balanceRepository: BalanceRecomputing
    private let currentTimeZone: @Sendable () -> TimeZone

    init(
        authService: AuthService = SupabaseAuthService(),
        profileRepository: ProfileRepository = SupabaseProfileRepository(),
        balanceRepository: BalanceRecomputing = SupabaseBalanceRepository(),
        currentTimeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.authService = authService
        self.profileRepository = profileRepository
        self.balanceRepository = balanceRepository
        self.currentTimeZone = currentTimeZone
    }

    /// Restores a persisted session on launch. Safe to call once per app start.
    func bootstrap() async {
        guard let user = await authService.currentUser() else {
            phase = .signedOut
            return
        }
        phase = await resolvedPhase(for: user)
        await syncTimeZone(for: user)
    }

    func signedIn(_ user: AuthenticatedUser) async {
        phase = await resolvedPhase(for: user)
        await syncTimeZone(for: user)
    }

    /// Persists first, advances second. Taking the submission rather than
    /// exposing a bare phase flip means no caller can land on the dashboard
    /// without a stored goal set behind it.
    func completeOnboarding(_ submission: OnboardingSubmission) async throws {
        guard case .onboarding(let user) = phase else { return }
        try await profileRepository.completeOnboarding(submission)
        phase = .ready(user)

        // complete_onboarding does not take a timezone, so this is where a new
        // account first moves off the UTC default — before any food has been
        // logged, which is the only moment the rebuild is free.
        await syncTimeZone(for: user)
    }

    #if DEBUG
    /// Sends a completed user back through the questionnaire. Only flips the
    /// phase once the flag is actually cleared, so a failed write can't leave
    /// the UI claiming a reset that didn't happen.
    func resetOnboarding() async throws {
        guard case .ready(let user) = phase else { return }
        try await profileRepository.resetOnboarding(userID: user.id)
        phase = .onboarding(user)
    }
    #endif

    func signOut() async {
        // Clear local state regardless: a failed network sign-out must not
        // strand the user in a session they asked to leave.
        try? await authService.signOut()
        phase = .signedOut
        timeZoneSyncError = nil
    }

    // MARK: - Routing

    private func resolvedPhase(for user: AuthenticatedUser) async -> Phase {
        do {
            let completed = try await profileRepository.hasCompletedOnboarding(userID: user.id)
            return completed ? .ready(user) : .onboarding(user)
        } catch {
            // Onboarding is idempotent, so it is the safe fallback when the
            // status can't be read — better than showing an empty dashboard.
            return .onboarding(user)
        }
    }

    // MARK: - Timezone

    /// Reconciles `profiles.time_zone` with the device.
    ///
    /// Runs after the phase is set, never before: the app must not be held at a
    /// spinner over a value only the balance rollup reads. A moved zone recuts
    /// every day boundary, so the rollup is rebuilt from the beginning — the
    /// only correct starting point when the days themselves have shifted.
    private func syncTimeZone(for user: AuthenticatedUser) async {
        do {
            let result = try await profileRepository.syncTimeZone(
                currentTimeZone().identifier,
                userID: user.id
            )

            if result == .updated {
                try await balanceRepository.recompute(from: nil)
            }
            timeZoneSyncError = nil
        } catch {
            // Retried on the next launch, so a failure here is recoverable and
            // must not block a user who is otherwise signed in and ready.
            timeZoneSyncError = error.localizedDescription
        }
    }
}
