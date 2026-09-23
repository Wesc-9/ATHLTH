import SwiftUI

struct PasswordUpdateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountService: SupabaseAccountService

    let onUpdated: (BackendUserBootstrap) -> Void

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Spacer().frame(height: 24)

                    Image(systemName: "key.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(OnboardingTheme.green)

                    VStack(spacing: 8) {
                        Text("Set a new password")
                            .font(.largeTitle.weight(.bold))
                            .multilineTextAlignment(.center)

                        Text("Choose a new password for your ATHLTH account.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    OnboardingCard {
                        VStack(spacing: 14) {
                            SecureField("New password", text: $password)
                                .textContentType(.newPassword)
                                .padding(14)
                                .background(.white.opacity(0.90), in: RoundedRectangle(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(OnboardingTheme.border, lineWidth: 1)
                                }

                            SecureField("Confirm new password", text: $confirmPassword)
                                .textContentType(.newPassword)
                                .padding(14)
                                .background(.white.opacity(0.90), in: RoundedRectangle(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(OnboardingTheme.border, lineWidth: 1)
                                }

                            Text("Use at least 12 characters with uppercase, lowercase and a number.")
                                .font(.caption2)
                                .foregroundStyle(OnboardingTheme.faintText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        updatePassword()
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Update Password")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(isSubmitting)
                    .opacity(isSubmitting ? 0.65 : 1)
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(OnboardingBackground().ignoresSafeArea())
            .navigationTitle("Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        accountService.cancelPasswordRecovery()
                        dismiss()
                    }
                }
            }
        }
    }

    private func passwordValidationMessage(_ value: String) -> String? {
        guard value.count >= 12 else {
            return "Password must contain at least 12 characters."
        }

        guard value.contains(where: \.isLowercase),
              value.contains(where: \.isUppercase),
              value.contains(where: \.isNumber)
        else {
            return "Password must include uppercase, lowercase and a number."
        }

        return nil
    }

    private func updatePassword() {
        errorMessage = nil

        if let validationMessage = passwordValidationMessage(password) {
            errorMessage = validationMessage
            return
        }

        guard password == confirmPassword else {
            errorMessage = "The passwords do not match."
            return
        }

        Task {
            isSubmitting = true
            defer { isSubmitting = false }

            do {
                let bootstrap = try await accountService.updateRecoveredPassword(password)
                onUpdated(bootstrap)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
