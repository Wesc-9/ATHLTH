import SwiftUI

/// Recipient search is by @username, never a contact list or a broadcast.
/// The existing backend enforces blocks, message-request limits and privacy.
struct ATHLTHDirectShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var messaging: MessagingStore

    let draft: MessageShareDraft

    @State private var username = ""
    @State private var recipient: SocialProfileCard?
    @State private var note = ""
    @State private var sending = false
    @State private var sent = false
    @State private var errorMessage: String?

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var cleanUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    private var searchResults: [SocialProfileCard] {
        guard cleanUsername.count >= 2 else { return [] }
        var ids = Set<UUID>()
        return (social.mutualFollows + social.discoverResults).filter { person in
            person.usernameLabel.localizedCaseInsensitiveContains(cleanUsername)
                && ids.insert(person.userID).inserted
                && social.relationshipState(with: person.userID) != .blocked
                && social.relationshipState(with: person.userID) != .selfUser
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: draft.kind.systemImage)
                            .font(.title2)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 54, height: 54)
                            .background(ATHLTHPlanDesign.selectedSurface,
                                        in: RoundedRectangle(cornerRadius: 17))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(draft.title)
                                .font(.headline)
                                .foregroundStyle(ATHLTHTheme.primaryText)
                            Text(draft.subtitle ?? draft.kind.title)
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 23))

                    if sent {
                        Label(tr("Sent to the recipient's inbox", "Sendt til mottakerens innboks"),
                              systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        Text(tr("Find recipient", "Finn mottaker"))
                            .font(.headline)

                        HStack(spacing: 10) {
                            Image(systemName: "at")
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            TextField(tr("Search @username", "Søk etter @brukernavn"),
                                      text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            if !username.isEmpty {
                                Button {
                                    username = ""
                                    recipient = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(13)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))

                        if cleanUsername.count >= 2 {
                            VStack(spacing: 0) {
                                ForEach(searchResults) { person in
                                    Button {
                                        recipient = person
                                    } label: {
                                        HStack(spacing: 12) {
                                            SocialAvatar(profile: person, size: 45)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(person.resolvedName)
                                                    .font(.subheadline.weight(.semibold))
                                                Text(person.usernameLabel)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: recipient?.userID == person.userID
                                                ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                        }
                                        .padding(12)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                if searchResults.isEmpty {
                                    Text(tr("No discoverable user with this username.",
                                            "Ingen søkbar bruker med dette brukernavnet."))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(18)
                                }
                            }
                            .background(.white, in: RoundedRectangle(cornerRadius: 18))
                        }

                        if recipient != nil {
                            TextField(tr("Optional personal message", "Valgfri personlig melding"),
                                      text: $note, axis: .vertical)
                                .lineLimit(2...4)
                                .padding(14)
                                .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        }

                        Label(tr(
                            "One recipient only. Someone you don't follow receives a message request, which they can accept or decline.",
                            "Kun én mottaker. En person du ikke følger, får en meldingsforespørsel som kan godtas eller avslås."
                        ), systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(18)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("Share", "Del"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if sent {
                        dismiss()
                    } else {
                        Task { await send() }
                    }
                } label: {
                    if sending {
                        ProgressView().tint(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    } else {
                        Label(sent ? tr("Done", "Ferdig") :
                              tr("Send to inbox", "Send til innboks"),
                              systemImage: sent ? "checkmark" : "paperplane.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
                .disabled(!sent && (recipient == nil || sending))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
            .onChange(of: cleanUsername) { _, _ in
                // Changing the query invalidates the earlier selection.
                // Never send to a stale username result.
                recipient = nil
            }
            .task(id: cleanUsername) {
                guard cleanUsername.count >= 2, !sent else {
                    social.clearSearch()
                    return
                }
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled else { return }
                await social.search(cleanUsername)
            }
        }
    }

    private func send() async {
        guard let recipient, !sent, !sending,
              recipient.usernameLabel.localizedCaseInsensitiveContains(cleanUsername),
              social.relationshipState(with: recipient.userID) != .blocked else {
            return
        }
        sending = true
        errorMessage = nil
        defer { sending = false }
        do {
            let conversationID = try await messaging.openConversation(
                with: recipient.userID
            )
            if await messaging.send(
                to: recipient.userID, conversationID: conversationID,
                body: note, attachment: draft
            ) {
                sent = true
            } else {
                errorMessage = messaging.errorMessage ??
                    tr("Could not send the item.", "Kunne ikke sende innholdet.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
