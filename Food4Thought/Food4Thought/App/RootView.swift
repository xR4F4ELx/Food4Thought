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
                // Placeholder until the questionnaire lands.
                OnboardingPlaceholderView()

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

private struct OnboardingPlaceholderView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            Text("Onboarding")
                .font(.title2.bold())
            Text("The goals questionnaire lands here next.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Sign Out") {
                Task { await appState.signOut() }
            }
        }
        .padding()
    }
}

private struct MainPlaceholderView: View {
    let user: AuthenticatedUser
    @Environment(AppState.self) private var appState

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
        }
        .padding()
    }
}
