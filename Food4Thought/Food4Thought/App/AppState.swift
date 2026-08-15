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

    private let authService: AuthService
    private let profileRepository: ProfileRepository

    init(
        authService: AuthService = SupabaseAuthService(),
        profileRepository: ProfileRepository = SupabaseProfileRepository()
    ) {
        self.authService = authService
        self.profileRepository = profileRepository
    }

    /// Restores a persisted session on launch. Safe to call once per app start.
    func bootstrap() async {
        guard let user = await authService.currentUser() else {
            phase = .signedOut
            return
        }
        phase = await resolvedPhase(for: user)
    }

    func signedIn(_ user: AuthenticatedUser) async {
        phase = await resolvedPhase(for: user)
    }

    /// Persists first, advances second. Taking the submission rather than
    /// exposing a bare phase flip means no caller can land on the dashboard
    /// without a stored goal set behind it.
    func completeOnboarding(_ submission: OnboardingSubmission) async throws {
        guard case .onboarding(let user) = phase else { return }
        try await profileRepository.completeOnboarding(submission)
        phase = .ready(user)
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
}
