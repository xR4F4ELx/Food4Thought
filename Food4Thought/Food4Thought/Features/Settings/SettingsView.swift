import SwiftUI

/// Settings — handoff 6b. The grouped sections are stubbed until the screens
/// behind them exist; what's here is the account row that already works.
struct SettingsView: View {
    let user: AuthenticatedUser

    @Environment(AppState.self) private var appState
    @State private var resetError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if let email = user.email {
                        LabeledContent("Signed in as", value: email)
                    }
                    Button("Sign out") {
                        Task { await appState.signOut() }
                    }
                }

                if let syncError = appState.timeZoneSyncError {
                    Section("Sync") {
                        Text("Couldn't reach the server to update your time zone: \(syncError)")
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.inkSecondary)
                        Text("Your day boundaries may be off until this succeeds. It retries on the next launch.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.inkSecondary)
                    }
                }

                #if DEBUG
                Section {
                    Button("Reset onboarding", role: .destructive) {
                        Task {
                            do {
                                resetError = nil
                                try await appState.resetOnboarding()
                            } catch {
                                resetError = error.localizedDescription
                            }
                        }
                    }
                    if let resetError {
                        Text(resetError)
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.over)
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Re-runs the questionnaire. Goal history is kept.")
                }
                #endif

                Section {
                    Text("Targets are estimates from your height, weight, age and activity. They are not medical advice — talk to a clinician before making big changes.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
