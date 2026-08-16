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
                MainTabView(user: user)
            }
        }
        .task {
            await appState.bootstrap()
        }
    }
}
