import SwiftUI

/// Settings — handoff 6b.
///
/// Two things live here that do not fit anywhere else: the answers behind the
/// targets, and how the app looks. Both are things you change rarely and want
/// to find in one predictable place, which is what Settings is for.
struct SettingsView: View {
    let user: AuthenticatedUser

    @Environment(AppState.self) private var appState
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .system
    @State private var resetError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("Your details") {
                        EditDetailsView(viewModel: EditDetailsViewModel(userID: user.id))
                    }
                } header: {
                    Text("You")
                } footer: {
                    Text("Height, weight, age, activity and goal — the answers your targets are calculated from.")
                }

                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearancePreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("System follows your phone, including its sunset schedule.")
                }

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
