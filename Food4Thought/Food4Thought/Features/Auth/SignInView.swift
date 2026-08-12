import SwiftUI

struct SignInView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = SignInViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $viewModel.password)
                        .textContentType(viewModel.mode.passwordContentType)
                }

                if let message = viewModel.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                Section {
                    Button {
                        Task { await viewModel.submit(appState: appState) }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text(viewModel.mode.actionTitle)
                        }
                    }
                    .disabled(!viewModel.canSubmit)

                    Button(viewModel.mode.toggleTitle) {
                        viewModel.toggleMode()
                    }
                    .font(.footnote)
                }
            }
            .navigationTitle(viewModel.mode.actionTitle)
        }
    }
}

@Observable
@MainActor
final class SignInViewModel {

    enum Mode {
        case signIn
        case signUp

        var actionTitle: String {
            switch self {
            case .signIn: "Sign In"
            case .signUp: "Create Account"
            }
        }

        var toggleTitle: String {
            switch self {
            case .signIn: "No account yet? Create one"
            case .signUp: "Already have an account? Sign in"
            }
        }

        var passwordContentType: UITextContentType {
            switch self {
            case .signIn: .password
            case .signUp: .newPassword
            }
        }
    }

    var email = ""
    var password = ""
    private(set) var mode: Mode = .signIn
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let authService: AuthService

    init(authService: AuthService = SupabaseAuthService()) {
        self.authService = authService
    }

    var canSubmit: Bool {
        !isSubmitting
            && email.contains("@")
            && password.count >= SupabaseAuthService.minimumPasswordLength
    }

    func toggleMode() {
        mode = mode == .signIn ? .signUp : .signIn
        errorMessage = nil
    }

    func submit(appState: AppState) async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let user = switch mode {
            case .signIn: try await authService.signIn(email: email, password: password)
            case .signUp: try await authService.signUp(email: email, password: password)
            }
            await appState.signedIn(user)
        } catch {
            errorMessage = (error as? AuthFailure)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
