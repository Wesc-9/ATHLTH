import SwiftUI

/// One home for requests from Community's existing backends.
/// It intentionally routes into the authoritative workflows rather than
/// introducing a second invite/accept implementation.
struct ATHLTHCommunityActionCenterView: View {
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var groups: CommunityGroupStore
    @EnvironmentObject private var session: AppSessionStore

    private var messages: Int {
        messaging.unreadCount + messaging.messageRequestCount
    }

    private var socialRequests: Int {
        social.incomingRequests.count + social.workoutInvites.filter {
            $0.participant.state == .invited
        }.count
    }

    private var challengeInvites: Int {
        challenges.incomingInvitations(for: session.profile.userID).count
    }

    private var clubInvites: Int {
        groups.ownInvites.count
    }

    private var total: Int {
        messages + socialRequests + challengeInvites + clubInvites
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ATHLTHPlanSurface {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("ATHLTH · COMMUNITY")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(ATHLTHPlanDesign.accent)
                        Text(ATHLTHLocalization.choose(
                            english: "Your inbox",
                            norwegian: "Din innboks"
                        ))
                        .font(.system(size: 28, design: .serif))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        Text(ATHLTHLocalization.choose(
                            english: "Messages, training invitations and club requests in one place.",
                            norwegian: "Meldinger, treningsinvitasjoner og klubbforespørsler på ett sted."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }

                if total == 0 {
                    ATHLTHPlanSurface {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Nothing needs your attention right now",
                                norwegian: "Ingenting trenger oppfølging akkurat nå"
                            ),
                            systemImage: "checkmark.circle"
                        )
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }

                NavigationLink {
                    MessageInboxDestinationView()
                } label: {
                    actionRow(
                        title: ATHLTHLocalization.choose(
                            english: "Messages", norwegian: "Meldinger"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Conversations, requests and Arena invitations",
                            norwegian: "Samtaler, meldingsforespørsler og Arena-invitasjoner"
                        ),
                        icon: "bubble.left.and.bubble.right",
                        count: messages
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SocialHubView(initialTab: .requests)
                } label: {
                    actionRow(
                        title: ATHLTHLocalization.choose(
                            english: "Social requests", norwegian: "Sosiale forespørsler"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Follow and training invitations",
                            norwegian: "Følgeforespørsler og treningsinvitasjoner"
                        ),
                        icon: "person.crop.circle.badge.plus",
                        count: socialRequests
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ChallengeHubView()
                } label: {
                    actionRow(
                        title: ATHLTHLocalization.choose(
                            english: "Challenges", norwegian: "Utfordringer"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Invitations to participate",
                            norwegian: "Invitasjoner til å delta"
                        ),
                        icon: "trophy",
                        count: challengeInvites
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    CommunityGroupsView()
                } label: {
                    actionRow(
                        title: ATHLTHLocalization.choose(
                            english: "Clubs", norwegian: "Klubber"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Membership and club invitations",
                            norwegian: "Medlemskap og klubbinvitasjoner"
                        ),
                        icon: "person.3",
                        count: clubInvites
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Inbox", norwegian: "Innboks"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func actionRow(
        title: String,
        subtitle: String,
        icon: String,
        count: Int
    ) -> some View {
        ATHLTHPlanSurface {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(ATHLTHPlanDesign.accent)
                    .frame(width: 44, height: 44)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                Spacer(minLength: 4)
                if count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .padding(.horizontal, 9)
                        .frame(minHeight: 26)
                        .background(ATHLTHPlanDesign.selectedSurface, in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            .frame(minHeight: 50)
        }
        .accessibilityElement(children: .combine)
    }
}
