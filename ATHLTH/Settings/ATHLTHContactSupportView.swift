import Foundation
import Supabase
import SwiftUI

/// A privacy-aware contact form: the authenticated account supplies the
/// sender identity, not any editable sender/from address or mail client.
struct ATHLTHContactSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var accountService: SupabaseAccountService

    @State private var subject = ""
    @State private var message = ""
    @State private var allowEmailReply = false
    @State private var sending = false
    @State private var sent = false
    @State private var errorMessage: String?

    private var cleanSubject: String {
        subject.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var senderName: String {
        let username = session.profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return username.isEmpty
            ? session.profile.displayName
            : "@\(username)"
    }

    private var canSend: Bool {
        !sending && !sent &&
            accountService.currentUserID != nil &&
            (4...120).contains(cleanSubject.count) &&
            (12...5000).contains(cleanMessage.count)
    }

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(accent: ATHLTHTheme.premiumGold.opacity(0.34))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro
                    identityCard
                    formCard
                    if let email = accountService.currentEmail,
                       !email.isEmpty {
                        replyOptions(email: email)
                    }
                    sendButton
                    Text(ATHLTHLocalization.choose(
                        english: "This form sends your message to ATHLTH support. Do not include passwords, health records or other sensitive details.",
                        norwegian: "Meldingen sendes til ATHLTH. Ikke del passord, helsejournaler eller andre sensitive opplysninger."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                }
                .padding(18)
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Contact us", norwegian: "Kontakt oss"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            ATHLTHLocalization.choose(
                english: "Could not send message",
                norwegian: "Kunne ikke sende meldingen"
            ),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Message sent",
                norwegian: "Meldingen er sendt"
            ),
            isPresented: $sent
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Done", norwegian: "Ferdig"
            )) {
                dismiss()
            }
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "Your message was accepted by our email provider. Thank you!",
                norwegian: "Meldingen ble godkjent av e-postleverandøren. Takk for tilbakemeldingen!"
            ))
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ATHLTH / SUPPORT")
                .font(.system(size: 10, weight: .bold))
                .tracking(2.2)
                .foregroundStyle(ATHLTHTheme.premiumGold)

            Text(ATHLTHLocalization.choose(
                english: "How can we help?",
                norwegian: "Hva kan vi hjelpe med?"
            ))
            .font(.system(size: 29, weight: .regular, design: .serif))
            .foregroundStyle(ATHLTHTheme.primaryText)

            Text(ATHLTHLocalization.choose(
                english: "Report an issue, share an idea or ask a question. No email app required.",
                norwegian: "Meld inn en feil, del et forslag eller still et spørsmål – uten å åpne e-postappen."
            ))
            .font(.subheadline)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
    }

    private var identityCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 22))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 46, height: 46)
                .background(ATHLTHTheme.accentSoft, in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(ATHLTHLocalization.choose(
                    english: "Sending as",
                    norwegian: "Sendes fra"
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)

                Text(senderName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 21))
        .overlay {
            RoundedRectangle(cornerRadius: 21)
                .stroke(ATHLTHTheme.border.opacity(0.7), lineWidth: 0.8)
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ATHLTHLocalization.choose(
                english: "Subject", norwegian: "Emne"
            ))
            .font(.subheadline.weight(.semibold))

            TextField(ATHLTHLocalization.choose(
                english: "What is this about?",
                norwegian: "Hva gjelder henvendelsen?"
            ), text: $subject)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.next)
            .padding(13)
            .background(
                ATHLTHTheme.surfaceStone.opacity(0.6),
                in: RoundedRectangle(cornerRadius: 13)
            )
            .onChange(of: subject) { _, new in
                if new.count > 120 { subject = String(new.prefix(120)) }
            }

            Text("\(subject.count)/120")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(ATHLTHTheme.mutedText)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Rectangle()
                .fill(ATHLTHTheme.divider)
                .frame(height: 0.8)

            Text(ATHLTHLocalization.choose(
                english: "Message", norwegian: "Melding"
            ))
            .font(.subheadline.weight(.semibold))

            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text(ATHLTHLocalization.choose(
                        english: "Tell us what happened or what we could improve…",
                        norwegian: "Fortell hva som skjedde, eller hva vi kan forbedre…"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                    .allowsHitTesting(false)
                }

                TextEditor(text: $message)
                    .scrollContentBackground(.hidden)
                    .font(.subheadline)
                    .frame(minHeight: 175)
                    .padding(10)
                    .onChange(of: message) { _, new in
                        if new.count > 5000 { message = String(new.prefix(5000)) }
                    }
            }
            .background(
                ATHLTHTheme.surfaceStone.opacity(0.6),
                in: RoundedRectangle(cornerRadius: 13)
            )
            Text("\(message.count)/5000")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(ATHLTHTheme.mutedText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(ATHLTHTheme.primaryText)
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 23))
        .overlay {
            RoundedRectangle(cornerRadius: 23)
                .stroke(ATHLTHTheme.border.opacity(0.70), lineWidth: 0.8)
        }
    }

    private func replyOptions(email: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(
                ATHLTHLocalization.choose(
                    english: "Allow a reply to my account email",
                    norwegian: "Tillat svar til e-posten på kontoen min"
                ),
                isOn: $allowEmailReply
            )
            .font(.subheadline.weight(.medium))
            .tint(ATHLTHTheme.accentDeep)

            Text(allowEmailReply
                ? ATHLTHLocalization.choose(
                    english: "Your registered email will be shared with ATHLTH support to reply to this request.",
                    norwegian: "Din registrerte e-postadresse deles med ATHLTH for å kunne svare på henvendelsen."
                )
                : ATHLTHLocalization.choose(
                    english: "Off by default. Only your username identifies the sender.",
                    norwegian: "Av som standard. Kun brukernavnet identifiserer avsenderen."
                )
            )
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background(ATHLTHTheme.champagneSoft.opacity(0.52),
                    in: RoundedRectangle(cornerRadius: 18))
    }

    private var sendButton: some View {
        Button {
            Task { await send() }
        } label: {
            HStack(spacing: 10) {
                Spacer()
                if sending {
                    ProgressView().tint(.white)
                } else {
                    Text(ATHLTHLocalization.choose(
                        english: "Send message",
                        norwegian: "Send melding"
                    ))
                    .font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .frame(height: 54)
            .background(
                canSend ? ATHLTHTheme.accentDeep : ATHLTHTheme.mutedText.opacity(0.52),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Submits directly to ATHLTH without opening your email app.",
            norwegian: "Sender direkte til ATHLTH uten å åpne e-postappen."
        ))
    }

    @MainActor
    private func send() async {
        guard canSend else { return }
        sending = true
        errorMessage = nil
        defer { sending = false }

        struct SupportRequest: Encodable {
            let subject: String
            let message: String
            let allow_reply: Bool
        }

        struct SupportReceipt: Decodable {
            let sent: Bool
        }

        do {
            let response: SupportReceipt = try await SupabaseEnvironment.client.functions.invoke(
                "submit-support-message",
                options: FunctionInvokeOptions(
                    body: SupportRequest(
                        subject: cleanSubject,
                        message: cleanMessage,
                        allow_reply: allowEmailReply
                    )
                )
            )
            guard response.sent else {
                throw ContactError.notDelivered
            }
            sent = true
        } catch {
            // Do not clear the draft or claim delivery when the provider,
            // network, or server reports a failure.
            errorMessage = ATHLTHLocalization.choose(
                english: "Your message was not sent. Please try again later. You can also email contact@athlth.com.",
                norwegian: "Meldingen ble ikke sendt. Prøv igjen senere. Du kan også skrive til contact@athlth.com."
            )
        }
    }

    private enum ContactError: Error {
        case notDelivered
    }
}
