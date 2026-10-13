import SwiftUI

/// Club invitations join the existing message / challenge / Arena inbox.
/// We reuse the authoritative Club invite RPC and membership state instead
/// of introducing another invitation table or an unrelated notification feed.
struct ATHLTHCommunityClubInboxSection: View {
    @EnvironmentObject private var groups: CommunityGroupStore

    @State private var busyGroupID: UUID?
    @State private var errorMessage: String?

    private var invitations: [CommunityGroupInviteRecord] {
        groups.ownInvites
            .filter { $0.status == "pending" }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        if !invitations.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(ATHLTHPlanDesign.accent)
                    Text(ATHLTHLocalization.choose(
                        english: "CLUB INVITATIONS", norwegian: "KLUBBINVITASJONER"
                    ))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    Spacer(minLength: 2)
                    Text(invitations.count.formatted())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                }

                ForEach(invitations, id: \.groupID) { invite in
                    ATHLTHPlanSurface {
                        HStack(spacing: 10) {
                            Image(systemName: "person.3.sequence.fill")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(ATHLTHPlanDesign.accent)
                                .frame(width: 43, height: 43)
                                .background(ATHLTHPlanDesign.selectedSurface, in: Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(groups.group(for: invite.groupID)?.name ??
                                     ATHLTHLocalization.choose(
                                        english: "Club invitation",
                                        norwegian: "Invitasjon til klubb"
                                     ))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                    .lineLimit(2)
                                Text(ATHLTHLocalization.choose(
                                    english: "You've been invited to join.",
                                    norwegian: "Du er invitert til å bli medlem."
                                ))
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                            Spacer(minLength: 0)
                        }

                        HStack(spacing: 9) {
                            Button {
                                respond(to: invite, accept: false)
                            } label: {
                                Text(ATHLTHLocalization.choose(
                                    english: "Decline", norwegian: "Avslå"
                                ))
                                .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .tint(ATHLTHPlanDesign.ink)

                            Button {
                                respond(to: invite, accept: true)
                            } label: {
                                if busyGroupID == invite.groupID {
                                    ProgressView().tint(.white)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                } else {
                                    Text(ATHLTHLocalization.choose(
                                        english: "Accept", norwegian: "Godta"
                                    ))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ATHLTHPlanDesign.ink)
                        }
                        .disabled(busyGroupID != nil)
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func respond(to invite: CommunityGroupInviteRecord, accept: Bool) {
        guard busyGroupID == nil else { return }
        busyGroupID = invite.groupID
        errorMessage = nil

        Task {
            let success = await groups.respondToInvite(
                groupID: invite.groupID,
                accept: accept
            )
            busyGroupID = nil
            if !success {
                errorMessage = ATHLTHLocalization.choose(
                    english: "The Club invitation couldn't be updated. Try again.",
                    norwegian: "Kunne ikke svare på klubb-invitasjonen. Prøv igjen."
                )
            }
        }
    }
}
