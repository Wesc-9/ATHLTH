import SwiftUI

/// A deliberately small, self-owned navigation boundary for challenges.
///
/// Opening a Challenge used to toggle @State in the very large friend-profile
/// and social-feed view hierarchies. On iOS 27.3 beta (ATHLTH 2.2.7 / 135)
/// this path produced a main-thread Swift generic-metadata stack overflow.
/// Keeping the presentation state and its sheet outside those hierarchies
/// prevents the full profile/feed tree from being rebuilt just to open a
/// competition. The existing server-authoritative competition flow is reused.
struct ATHLTHFriendChallengeLauncher: View {
    enum Style {
        case profileAction
        case feedAction
    }

    let friend: SocialProfileCard
    let isAllowed: Bool
    let style: Style
    var onUnavailable: (() -> Void)? = nil

    @State private var showingCompetition = false

    var body: some View {
        Button {
            guard isAllowed else {
                onUnavailable?()
                return
            }
            showingCompetition = true
        } label: {
            switch style {
            case .profileAction:
                profileLabel
            case .feedAction:
                feedLabel
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("athlth-friend-challenge-launch")
        .sheet(isPresented: $showingCompetition) {
            // This is a cold navigation boundary: avoid nesting the generic
            // competition editor type in the friend-profile view graph.
            AnyView(ATHLTHCompetitionEntryView(
                preselectedFriend: friend
            ))
        }
    }

    private var profileLabel: some View {
        VStack(spacing: 5) {
            Image(systemName: "trophy")
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(height: 25)

            Text(ATHLTHLocalization.choose(
                english: "Challenge",
                norwegian: "Utfordre"
            ))
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(ATHLTHTheme.mutedText)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Challenge", norwegian: "Utfordre"
        ))
    }

    private var feedLabel: some View {
        Image(systemName: "trophy.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.orange)
            .frame(width: 34, height: 34)
            .background(
                Color.orange.opacity(0.10),
                in: Circle()
            )
            .accessibilityLabel(
                ATHLTHLocalization.choose(
                    english: "Challenge ", norwegian: "Utfordre "
                ) + friend.resolvedName
            )
    }
}
