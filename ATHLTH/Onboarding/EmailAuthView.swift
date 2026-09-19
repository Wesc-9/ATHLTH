import SwiftUI

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

enum EmailAuthResult {
    case existingUser
    case newUser
}

struct EmailAuthView: View {
    @Environment(\.dismiss) private var dismiss

    let onAuthenticated: (EmailAuthResult) -> Void

    @State private var mode: EmailAuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var acceptedLegal = false
    @State private var showingReset = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "envelope.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.green)

                        Text(mode == .signIn ? "Welcome back" : "Create your ATHLTH account")
                            .font(.largeTitle.weight(.bold))
                            .multilineTextAlignment(.center)

                        Text(
                            mode == .signIn
                                ? "Sign in with your email and password."
                                : "Use your email to create an ATHLTH account."
                        )
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }

                    Picker("Email account", selection: $mode) {
                        ForEach(EmailAuthMode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    ATHLTHCard {
                        VStack(spacing: 14) {
                            TextField("Email address", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(14)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

                            SecureField("Password", text: $password)
                                .textContentType(mode == .signIn ? .password : .newPassword)
                                .padding(14)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

                            if mode == .createAccount {
                                SecureField("Confirm password", text: $confirmPassword)
                                    .textContentType(.newPassword)
                                    .padding(14)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }

                    if mode == .createAccount {
                        ATHLTHCard {
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
                        Text(mode == .signIn ? "Sign In" : "Create Account")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)

                    if mode == .signIn {
                        Button("Forgot password?") {
                            showingReset = true
                        }
                        .font(.subheadline)
                    }

                    #if DEBUG
                    Text("Authentication is simulated in V0.1 development builds. Passwords are not stored by this screen.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    #endif
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
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
                PasswordResetView(initialEmail: email)
            }
            .onChange(of: mode) {
                errorMessage = nil
                password = ""
                confirmPassword = ""
                acceptedLegal = false
            }
        }
    }

    private func submit() {
        errorMessage = nil

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

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

            onAuthenticated(.newUser)
        } else {
            onAuthenticated(.existingUser)
        }

        dismiss()
    }
}

private struct PasswordResetView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var email: String
    @State private var sent = false

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        Label("Check your email", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)

                        Text("If an ATHLTH account exists for this email address, password-reset instructions will be sent.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        TextField("Email address", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Section {
                        Button("Send reset link") {
                            sent = true
                        }
                        .disabled(!email.contains("@"))
                    }
                }

                #if DEBUG
                Section {
                    Text("Reset email delivery is a V0.1 placeholder until the authentication backend is connected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                #endif
            }
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
}
