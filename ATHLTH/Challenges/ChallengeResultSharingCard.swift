import SwiftUI

/// Explicit post-workout sharing. The switch is off by default and no
/// challenge invitations, routes or participant identities are exposed.
struct ChallengeResultSharingCard: View {
    @EnvironmentObject private var social: SocialStore

    let challenge: ATHLTHChallenge
    let attempt: ChallengeAttempt

    @State private var wantsToPublish = false
    @State private var audience: ProfileVisibility = .privateOnly
    @State private var isPublishing = false
    @State private var hasPublished = false
    @State private var errorMessage: String?

    var body: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 13) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Share completed workout",
                        norwegian: "Del fullført økt"
                    ),
                    systemImage: "checkmark.shield.fill"
                )
                .font(.headline)
                .foregroundStyle(ATHLTHTheme.primaryText)

                Text(ATHLTHLocalization.choose(
                    english: "This is never posted automatically. Decide whether your completed workout should appear in the activity log.",
                    norwegian: "Dette publiseres aldri automatisk. Du bestemmer selv om sammendraget skal vises i aktivitetsloggen."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)

                Toggle(
                    ATHLTHLocalization.choose(
                        english: "Publish workout summary",
                        norwegian: "Publiser øktsammendrag"
                    ),
                    isOn: $wantsToPublish
                )
                .tint(ATHLTHTheme.accentDeep)
                .disabled(isPublishing || hasPublished)

                if wantsToPublish && !hasPublished {
                    Picker(
                        ATHLTHLocalization.choose(
                            english: "Audience", norwegian: "Hvem kan se"
                        ),
                        selection: $audience
                    ) {
                        Text(ATHLTHLocalization.choose(
                            english: "Private", norwegian: "Privat"
                        )).tag(ProfileVisibility.privateOnly)
                        Text(ATHLTHLocalization.choose(
                            english: "Friends", norwegian: "Venner"
                        )).tag(ProfileVisibility.friends)
                        Text(ATHLTHLocalization.choose(
                            english: "Public", norwegian: "Offentlig"
                        )).tag(ProfileVisibility.publicProfile)
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(challenge.title)
                            .font(.subheadline.weight(.semibold))
                        Text(attempt.detail)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.64),
                                in: RoundedRectangle(cornerRadius: 13))

                    Text(audience == .privateOnly
                        ? ATHLTHLocalization.choose(
                            english: "Only you can see this entry.",
                            norwegian: "Kun du kan se innlegget."
                        )
                        : audience == .friends
                            ? ATHLTHLocalization.choose(
                                english: "Shared with your ATHLTH friends.",
                                norwegian: "Deles med vennene dine i ATHLTH."
                            )
                            : ATHLTHLocalization.choose(
                                english: "Everyone who can view public activity can see this entry.",
                                norwegian: "Alle som kan se offentlig aktivitet, kan se innlegget."
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)

                    Button {
                        Task {
                            isPublishing = true
                            defer { isPublishing = false }
                            let succeeded = await social.publishCompletedChallengeResult(
                                challenge,
                                attempt: attempt,
                                visibility: audience
                            )
                            if succeeded {
                                hasPublished = true
                                wantsToPublish = false
                                errorMessage = nil
                            } else {
                                errorMessage = social.errorMessage ??
                                    ATHLTHLocalization.choose(
                                        english: "Could not publish your result.",
                                        norwegian: "Kunne ikke publisere resultatet."
                                    )
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isPublishing { ProgressView().controlSize(.small) }
                            Text(ATHLTHLocalization.choose(
                                english: "Publish workout", norwegian: "Publiser økt"
                            ))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                    .disabled(isPublishing)
                }

                if hasPublished {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Published with your chosen audience.",
                            norwegian: "Publisert med valgt synlighet."
                        ),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
