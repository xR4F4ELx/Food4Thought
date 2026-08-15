import Foundation

enum OnboardingFailure: LocalizedError, Equatable {
    case notSignedIn
    /// A server-side validation guard fired. These check invariants the UI is
    /// meant to uphold, so reaching one means a client bug rather than a bad
    /// answer — the raw reason is kept for logging, not for display.
    case rejected(reason: String)
    case network
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            "Your session expired. Sign in again to save your plan."
        case .rejected:
            "Something in your answers didn't add up. Go back a step and try again."
        case .network:
            "Couldn't reach the server. Check your connection and try again."
        case .unexpected(let message):
            message
        }
    }
}
