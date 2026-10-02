import SwiftUI

struct DeleteAccountView: View {
    @EnvironmentObject private var accountService: SupabaseAccountService
    @EnvironmentObject private var session: AppSessionStore

    @State private var showingConfirmation = false
    @State private var deleting = false
    @State private var errorMessage: String?
    @State private var showingManualAppleRevocation = false

    var body: some View {
        Form {
            Section {
                Label("Delete ATHLTH account", systemImage: "trash.fill")
                    .font(.headline)
                    .foregroundStyle(.red)

                Text("This permanently deletes your ATHLTH account and cloud data associated with it. This action cannot be undone.")
                    .font(.subheadline)

                Text("Health data stored in Apple Health is managed by Apple Health and is not deleted by ATHLTH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("If you have an active App Store subscription, deleting your ATHLTH account does not automatically cancel that subscription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if session.signInMethod == .apple {
                Section("Sign in with Apple") {
                    Label("Apple access is revoked with account deletion", systemImage: "apple.logo")
                        .font(.subheadline.weight(.semibold))

                    Text("ATHLTH will automatically revoke its Sign in with Apple authorization when your account is deleted. If Apple revocation cannot be completed, ATHLTH will show the manual fallback steps before returning you to sign-in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    showingConfirmation = true
                } label: {
                    HStack {
                        Text("Delete account")
                        Spacer()
                        if deleting {
                            ProgressView()
                        }
                    }
                }
                .disabled(deleting)
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Permanently delete your ATHLTH account?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete account permanently", role: .destructive) {
                Task {
                    await deleteAccount()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your ATHLTH cloud account and associated ATHLTH data will be deleted. This cannot be undone.")
        }
        .alert(
            "ATHLTH account deleted",
            isPresented: $showingManualAppleRevocation
        ) {
            Button("Continue") {
                session.clearAfterAccountDeletion()
            }
        } message: {
            Text("Your ATHLTH account has been deleted, but Apple authorization could not be revoked automatically. On your iPhone, open Settings → [your name] → Sign in with Apple → ATHLTH, then choose Delete.")
        }
    }

    @MainActor
    private func deleteAccount() async {
        guard !deleting else { return }

        deleting = true
        errorMessage = nil
        defer { deleting = false }

        do {
            let result = try await accountService.deleteAccount()

            if result.appleManualRevocationRequired,
               session.signInMethod == .apple {
                showingManualAppleRevocation = true
            } else {
                session.clearAfterAccountDeletion()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
