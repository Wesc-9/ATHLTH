import SwiftUI

struct EmailAuthView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountService: SupabaseAccountService
    @EnvironmentObject private var session: AppSessionStore

    let onAuthenticated: (BackendUserBootstrap) -> Void

    @State private var mode: EmailAuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var acceptedLegal = false
    @State private var showingReset = false
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var confirmationSent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if confirmationSent {
                        confirmationState
                    } else {
                        authForm
                    }
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(OnboardingBackground().ignoresSafeArea())
            .foregroundStyle(.white)
            .preferredColorScheme(.dark)
            .navigationTitle("Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingReset) {
                PasswordResetRequestView(initialEmail: email)
                    .environmentObject(accountService)
            }
            .onChange(of: mode) {
                errorMessage = nil
                password = ""
                confirmPassword = ""
                acceptedLegal = false
                confirmationSent = false
            }
            .onChange(of: session.signedIn) {
                if session.signedIn {
                    dismiss()
                }
            }
            .onChange(of: accountService.passwordRecoveryPending) {
                if accountService.passwordRecoveryPending {
                    showingReset = false
                    dismiss()
                }
            }
        }
    }

    private var authForm: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "envelope.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(OnboardingTheme.green)

                Text(mode == .signIn ? "Welcome back" : "Create your ATHLTH account")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(
                    mode == .signIn
                        ? "Sign in with your email and password."
                        : "Create an account, then verify your email before continuing."
                )
                .foregroundStyle(OnboardingTheme.mutedText)
                .multilineTextAlignment(.center)
            }

            Picker("Email account", selection: $mode) {
                ForEach(EmailAuthMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            OnboardingCard {
                VStack(spacing: 14) {
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(OnboardingTheme.border, lineWidth: 1)
                        }

                    SecureField("Password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(OnboardingTheme.border, lineWidth: 1)
                        }

                    if mode == .createAccount {
                        SecureField("Confirm password", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(OnboardingTheme.border, lineWidth: 1)
                            }
                    }
                }
            }

            if mode == .createAccount {
                OnboardingCard {
                    Toggle(isOn: $acceptedLegal) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("I agree to the Terms and Privacy Policy")
                                .font(.subheadline.weight(.semibold))

                            HStack(spacing: 12) {
                                NavigationLink("Terms") {
                                    LegalDocumentView(kind: .terms)
                                }

                                NavigationLink("Privacy Policy") {
                                    LegalDocumentView(kind: .privacy)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                submit()
            } label: {
                HStack {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(mode == .signIn ? "Sign In" : "Create Account")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .disabled(isSubmitting)
            .opacity(isSubmitting ? 0.65 : 1)

            if mode == .signIn {
                Button("Forgot password?") {
                    showingReset = true
                }
                .font(.subheadline)
                .disabled(isSubmitting)
            }
        }
    }

    private var confirmationState: some View {
        VStack(spacing: 18) {
            Spacer().frame(height: 28)

            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 70))
                .foregroundStyle(OnboardingTheme.green)

            Text("Check your email")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            Text("We sent a confirmation link to \(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()). Open it on this iPhone to verify your address and return to ATHLTH.")
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.mutedText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            OnboardingCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Email verification required", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(OnboardingTheme.green)

                    Text("Your ATHLTH account has been created, but sign-in is not completed until the email address is verified.")
                        .font(.caption)
                        .foregroundStyle(OnboardingTheme.mutedText)
                }
            }

            Button("Back to sign in") {
                mode = .signIn
                confirmationSent = false
                password = ""
                confirmPassword = ""
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
        }
    }

    private func submit() {
        errorMessage = nil

        let cleanEmail = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard cleanEmail.contains("@"), cleanEmail.contains(".") else {
            errorMessage = "Enter a valid email address."
            return
        }

        guard password.count >= 8 else {
            errorMessage = "Password must contain at least 8 characters."
            return
        }

        if mode == .createAccount {
            guard password == confirmPassword else {
                errorMessage = "The passwords do not match."
                return
            }

            guard acceptedLegal else {
                errorMessage = "Please accept the Terms and Privacy Policy."
                return
            }
        }

        Task {
            isSubmitting = true
            defer { isSubmitting = false }

            do {
                switch mode {
                case .signIn:
                    let bootstrap = try await accountService.signIn(
                        email: cleanEmail,
                        password: password
                    )
                    onAuthenticated(bootstrap)
                    dismiss()

                case .createAccount:
                    let outcome = try await accountService.signUp(
                        email: cleanEmail,
                        password: password
                    )

                    switch outcome {
                    case .confirmationRequired:
                        email = cleanEmail
                        confirmationSent = true

                    case .authenticated(let bootstrap):
                        onAuthenticated(bootstrap)
                        dismiss()
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

enum EmailAuthMode: String, CaseIterable, Identifiable {
    case signIn
    case createAccount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signIn: return "Sign In"
        case .createAccount: return "Create Account"
        }
    }
}

private struct PasswordResetRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountService: SupabaseAccountService

    @State private var email: String
    @State private var sent = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        Label("Check your email", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(OnboardingTheme.green)

                        Text("If an ATHLTH account exists for this email address, a password-reset link has been sent. Open the link on this iPhone to return to ATHLTH and choose a new password.")
                            .font(.subheadline)
                            .foregroundStyle(OnboardingTheme.mutedText)
                    }
                } else {
                    Section {
                        TextField("Email address", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    if let errorMessage {
                        Section {
                            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }

                    Section {
                        Button {
                            sendReset()
                        } label: {
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("Send reset link")
                            }
                        }
                        .disabled(isSubmitting || !email.contains("@"))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(OnboardingBackground().ignoresSafeArea())
            .tint(OnboardingTheme.green)
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func sendReset() {
        let cleanEmail = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard cleanEmail.contains("@"), cleanEmail.contains(".") else {
            errorMessage = "Enter a valid email address."
            return
        }

        Task {
            isSubmitting = true
            errorMessage = nil
            defer { isSubmitting = false }

            do {
                try await accountService.sendPasswordReset(email: cleanEmail)
                sent = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
