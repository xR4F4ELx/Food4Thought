import Foundation
import Supabase

protocol ProfileRepository: Sendable {
    /// Drives routing: a signed-in user without this set goes to onboarding.
    func hasCompletedOnboarding(userID: UUID) async throws -> Bool
}

struct SupabaseProfileRepository: ProfileRepository {
    private struct OnboardingStatusRow: Decodable {
        let onboardingCompletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case onboardingCompletedAt = "onboarding_completed_at"
        }
    }

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
    }

    func hasCompletedOnboarding(userID: UUID) async throws -> Bool {
        let rows: [OnboardingStatusRow] = try await client
            .from("profiles")
            .select("onboarding_completed_at")
            .eq("id", value: userID)
            .limit(1)
            .execute()
            .value

        // The signup trigger creates the row, but treat a missing row as
        // "not onboarded" rather than an error — routing must still work.
        return rows.first?.onboardingCompletedAt != nil
    }
}
