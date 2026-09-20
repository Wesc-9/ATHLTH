import SwiftUI

struct DeleteAccountView: View {
    @EnvironmentObject private var accountService: SupabaseAccountService
    @EnvironmentObject private var session: AppSessionStore

    @State private var showingConfirmation = false
    @State private var deletionInProgress = false
    @State private var errorMessage: String?

    private let subscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.minus")
                        .font(.system(size: 34))
                        .foregroundStyle(.red)

                    Text("Delete your ATHLTH account")
                        .font(.title3.weight(.bold))

                    Text("This permanently removes your ATHLTH account and cloud profile. This action cannot be undone.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("What will be deleted") {
                Label("Your ATHLTH profile and username", systemImage: "person")
                Label("Account preferences and personalization", systemImage: "slider.horizontal.3")
                Label("ATHLTH+ entitlement data linked to this account", systemImage: "sparkles")
                Label("ATHLTH cloud records linked to your account", systemImage: "icloud.slash")
            }

            Section("What is not deleted") {
                Label("Health data stored in Apple Health", systemImage: "heart.fill")
                Label("Your App Store subscription", systemImage: "creditcard")

                Text("Apple Health data is managed separately in the Health app. Deleting your ATHLTH account does not automatically cancel an App Store subscription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link(destination: subscriptionsURL) {
                    Label("Manage App Store subscription", systemImage: "arrow.up.right.square")
                }
            }

            Section {
                Button(role: .destructive) {
                    showingConfirmation = true
                } label: {
                    HStack {
                        Text("Delete my account")
                        Spacer()
                        if deletionInProgress {
                            ProgressView()
                        }
                    }
                }
                .disabled(deletionInProgress)

                Text("You will be returned to the ATHLTH sign-in screen after deletion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete account permanently?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task {
                    await deleteAccount()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your ATHLTH account and associated ATHLTH cloud data will be permanently deleted.")
        }
        .alert(
            "Account could not be deleted",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { presented in
                    if !presented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func deleteAccount() async {
        guard !deletionInProgress else { return }

        deletionInProgress = true
        errorMessage = nil

        do {
            try await accountService.deleteAccount()
            session.clearAfterAccountDeletion()
        } catch {
            errorMessage = error.localizedDescription
        }

        deletionInProgress = false
    }
}
