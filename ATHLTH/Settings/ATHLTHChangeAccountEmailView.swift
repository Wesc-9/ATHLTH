import SwiftUI

struct ATHLTHChangeAccountEmailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountService: SupabaseAccountService
    @EnvironmentObject private var session: AppSessionStore
    @State private var email = ""
    @State private var sending = false
    @State private var requested = false
    @State private var errorText: String?

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
    private var candidate: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool {
        let parts = candidate.split(separator: "@", omittingEmptySubsequences: false)
        return candidate.count <= 254 && parts.count == 2 && !parts[0].isEmpty &&
            parts[1].contains(".") && !candidate.contains(where: { $0.isWhitespace }) &&
            candidate.caseInsensitiveCompare(accountService.currentEmail ?? "") != .orderedSame
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(tr("Change email", "Endre e-post"))
                        .font(.system(size: 30, design: .serif))
                    Text(tr("Your sign-in address is changed only after the Auth confirmation process is complete.", "Innloggingsadressen endres først når bekreftelsesprosessen er fullført."))
                        .font(.subheadline).foregroundStyle(ATHLTHTheme.mutedText)
                    PremiumSettingsCard {
                        PremiumSettingsRow(icon: "envelope", title: tr("Current email", "Nåværende e-post"),
                                           subtitle: accountService.currentEmail) { EmptyView() }
                        SettingsDivider()
                        TextField(tr("New email address", "Ny e-postadresse"), text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(16)
                            .disabled(sending || requested)
                    }
                    if requested {
                        Label(tr("Request sent. Follow the confirmation instructions in your email.", "Forespørsel sendt. Følg bekreftelsesinstruksjonene i e-posten din."), systemImage: "envelope.badge.shield.half.filled")
                            .font(.subheadline)
                        Button(tr("Refresh account email", "Oppdater kontoadresse")) {
                            Task {
                                do { try await accountService.refreshAccountEmail() }
                                catch { errorText = error.localizedDescription }
                            }
                        }
                        if accountService.currentEmail?.caseInsensitiveCompare(candidate) == .orderedSame {
                            Label(tr("Email updated", "E-post oppdatert"), systemImage: "checkmark.circle")
                        }
                    } else {
                        Button {
                            Task { await request() }
                        } label: {
                            HStack {
                                Spacer()
                                if sending { ProgressView() }
                                Text(tr("Send confirmation", "Send bekreftelse")).fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accentDeep)
                        .disabled(!valid || sending || session.signInMethod != .email)
                    }
                    if let errorText {
                        Text(errorText).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(18).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .background(ATHLTHTheme.canvasTop.ignoresSafeArea())
            .navigationTitle(tr("Email", "E-post"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Ferdig")) { dismiss() }.disabled(sending)
                }
            }
            .interactiveDismissDisabled(sending)
        }
    }

    @MainActor private func request() async {
        guard valid, !sending, session.signedIn, session.signInMethod == .email else { return }
        sending = true; errorText = nil
        defer { sending = false }
        do {
            try await accountService.requestEmailChange(candidate)
            requested = true
        } catch { errorText = error.localizedDescription }
    }
}
