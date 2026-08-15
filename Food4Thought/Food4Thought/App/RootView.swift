import SwiftUI

/// Single place that decides what the user sees, driven by `AppState.phase`.
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.phase {
            case .loading:
                ProgressView("Loading…")

            case .signedOut:
                SignInView()

            case .onboarding:
                OnboardingFlowView()

            case .ready(let user):
                MainPlaceholderView(user: user)
            }
        }
        .task {
            await appState.bootstrap()
        }
    }
}

// MARK: - Temporary destinations


private struct MainPlaceholderView: View {
    let user: AuthenticatedUser
    @Environment(AppState.self) private var appState
    @State private var resetError: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Signed in")
                .font(.title2.bold())
            if let email = user.email {
                Text(email).foregroundStyle(.secondary)
            }
            Button("Sign Out") {
                Task { await appState.signOut() }
            }

            #if DEBUG
            Divider().padding(.vertical, 8)

            Button("Reset Onboarding", role: .destructive) {
                Task {
                    do {
                        resetError = nil
                        try await appState.resetOnboarding()
                    } catch {
                        resetError = error.localizedDescription
                    }
                }
            }
            Text("Debug only — re-runs the questionnaire. Goal history is kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let resetError {
                Text(resetError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            #endif
        }
        .padding()
    }
}
