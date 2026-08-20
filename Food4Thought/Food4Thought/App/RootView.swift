import SwiftUI

/// Single place that decides what the user sees, driven by `AppState.phase`.
struct RootView: View {
    @Environment(AppState.self) private var appState

    /// Read here rather than in Settings so the choice covers every screen,
    /// including the sheets that present over them — a preference applied
    /// further down would leave the log sheet in the system's scheme.
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .system

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
        .preferredColorScheme(appearance.colorScheme)
        .task {
            await appState.bootstrap()
        }
    }
}
