import SwiftUI

/// A proposal is only a message until the creator approves it.
struct ChallengeProposalCard: View {
    let proposal: ChallengeChangeProposal
    let response: ChallengeChangeProposalResponse?
    let currentUserID: UUID?
    let sending: Bool
    let onApprove: () -> Void
    let onReject: () -> Void

    private var isCreator: Bool {
        currentUserID == proposal.original.creatorID
    }
    private var changes: [ChallengeChangeDiff.Row] {
        ChallengeChangeDiff.rows(proposal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                ATHLTHLocalization.choose(
                    english: "CHALLENGE · CHANGE REQUEST",
                    norwegian: "UTFORDRING · ENDRINGSFORSLAG"
                ),
                systemImage: "square.and.pencil"
            )
            .font(.system(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(ATHLTHTheme.accentDeep)

            Text(proposal.proposed.title)
                .font(.headline)
                .foregroundStyle(ATHLTHTheme.primaryText)

            Text(ATHLTHLocalization.choose(
                english: "Proposed changes are marked in red. Nothing takes effect until approved.",
                norwegian: "Endringer er merket med rødt. Ingenting trer i kraft før forslaget godkjennes."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)

            ForEach(changes) { change in
                VStack(alignment: .leading, spacing: 4) {
                    Text(change.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Was: ", norwegian: "Før: "
                        ) + change.oldValue
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Text(change.newValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.red.opacity(0.045),
                            in: RoundedRectangle(cornerRadius: 12))
            }

            if let response {
                Label(
                    response.accepted
                        ? ATHLTHLocalization.choose(
                            english: "Approved", norwegian: "Godkjent"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Rejected", norwegian: "Avslått"
                        ),
                    systemImage: response.accepted
                        ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(.subheadline.weight(.bold))
                .foregroundStyle(response.accepted
                    ? ATHLTHTheme.accentDeep : .red)
            } else if isCreator {
                HStack(spacing: 8) {
                    Button(action: onReject) {
                        Text(ATHLTHLocalization.choose(
                            english: "Reject", norwegian: "Avslå"
                        ))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button(action: onApprove) {
                        HStack(spacing: 5) {
                            if sending { ProgressView().controlSize(.mini) }
                            Text(ATHLTHLocalization.choose(
                                english: "Approve", norwegian: "Godkjenn"
                            ))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                }
                .disabled(sending)
            } else {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Waiting for creator approval",
                        norwegian: "Venter på oppretterens godkjenning"
                    ),
                    systemImage: "clock"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
        }
        .padding(15)
        .frame(maxWidth: 330, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Color.white.opacity(0.97),
                        ATHLTHTheme.surfaceStone.opacity(0.84)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ATHLTHTheme.accent.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: ATHLTHTheme.accentDeep.opacity(0.06),
                radius: 12, x: 0, y: 5)
    }
}

struct ChallengeProposalResponseCard: View {
    let response: ChallengeChangeProposalResponse
    var body: some View {
        Label(
            response.accepted
                ? ATHLTHLocalization.choose(
                    english: "Challenge changes approved",
                    norwegian: "Endringene i utfordringen er godkjent"
                )
                : ATHLTHLocalization.choose(
                    english: "Challenge changes rejected",
                    norwegian: "Endringene i utfordringen er avslått"
                ),
            systemImage: response.accepted
                ? "checkmark.circle.fill" : "xmark.circle.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(response.accepted ? ATHLTHTheme.accentDeep : .red)
        .padding(13)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 16))
    }
}
