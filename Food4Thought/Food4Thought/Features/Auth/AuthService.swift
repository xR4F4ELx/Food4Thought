import Foundation
import Supabase

/// The app's view of a signed-in user, deliberately narrower than the SDK's
/// `User` so swapping in Sign in with Apple later touches only this file.
struct AuthenticatedUser: Equatable, Sendable {
    let id: UUID
    let email: String?
}

enum AuthFailure: LocalizedError, Equatable {
    case invalidCredentials
    case emailAlreadyRegistered
    case weakPassword(minimumLength: Int)
    case emailConfirmationRequired
    case network
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "That email and password don't match an account."
        case .emailAlreadyRegistered:
            "An account already exists for that email. Try signing in."
        case .weakPassword(let minimumLength):
            "Password must be at least \(minimumLength) characters."
        case .emailConfirmationRequired:
            "Check your inbox to confirm your email, then sign in."
        case .network:
            "Couldn't reach the server. Check your connection and try again."
        case .unexpected(let message):
            message
        }
    }
}

protocol AuthService: Sendable {
    /// Restored from disk on launch; nil when signed out.
    func currentUser() async -> AuthenticatedUser?
    func signIn(email: String, password: String) async throws -> AuthenticatedUser
    func signUp(email: String, password: String) async throws -> AuthenticatedUser
    func signOut() async throws
}

struct SupabaseAuthService: AuthService {
    static let minimumPasswordLength = 8

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
    }

    func currentUser() async -> AuthenticatedUser? {
        // `session` refreshes an expired token; a throw here means no valid session.
        guard let session = try? await client.auth.session else { return nil }
        return AuthenticatedUser(id: session.user.id, email: session.user.email)
    }

    func signIn(email: String, password: String) async throws -> AuthenticatedUser {
        do {
            let session = try await client.auth.signIn(
                email: normalized(email),
                password: password
            )
            return AuthenticatedUser(id: session.user.id, email: session.user.email)
        } catch {
            throw mapped(error)
        }
    }

    func signUp(email: String, password: String) async throws -> AuthenticatedUser {
        guard password.count >= Self.minimumPasswordLength else {
            throw AuthFailure.weakPassword(minimumLength: Self.minimumPasswordLength)
        }

        do {
            let response = try await client.auth.signUp(
                email: normalized(email),
                password: password
            )
            // With email confirmation enabled (Supabase's default) there is no
            // session yet — the account exists but cannot be used until confirmed.
            guard response.session != nil else {
                throw AuthFailure.emailConfirmationRequired
            }
            return AuthenticatedUser(id: response.user.id, email: response.user.email)
        } catch let failure as AuthFailure {
            throw failure
        } catch {
            throw mapped(error)
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            throw mapped(error)
        }
    }

    // MARK: - Helpers

    private func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Supabase surfaces auth problems as message strings rather than typed
    /// cases, so match on the documented error codes where possible.
    private func mapped(_ error: Error) -> AuthFailure {
        if error is URLError {
            return .network
        }

        let message = error.localizedDescription.lowercased()
        if message.contains("invalid login credentials") {
            return .invalidCredentials
        }
        if message.contains("already registered") || message.contains("already been registered") {
            return .emailAlreadyRegistered
        }
        if message.contains("password should be at least") {
            return .weakPassword(minimumLength: Self.minimumPasswordLength)
        }
        return .unexpected(error.localizedDescription)
    }
}
