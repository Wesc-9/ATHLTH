import SwiftUI

// MARK: - Community V3
//
// Community V3 deliberately starts from a blank visual hierarchy.
// The existing social/challenge/event/group stores remain the source of truth,
// while the tab itself becomes a lightweight people-and-competition hub.
//
// V2 is intentionally left in the repository as a reversible fallback.

struct ATHLTHCommunityV3View: View {
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var officialChallenges: OfficialWeeklyChallengeStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var groups: CommunityGroupStore

    @State private var refreshError: String?

    private var activeChallenges: [ATHLTHChallenge] {
        challenges.trainingChallenges(
            for: session.profile.userID
        )
        .sorted {
            if $0.status == .active &&
                $1.status != .active {
                return true
            }

            if $1.status == .active &&
                $0.status != .active {
                return false
            }

            return $0.rules.startsAt <
                $1.rules.startsAt
        }
    }

    private var challengeRequests:
        [ATHLTHChallenge] {
        challenges.incomingInvitations(
            for: session.profile.userID
        )
    }

    private var pulseSummary: String {
        if !social.friends.isEmpty && !activeChallenges.isEmpty {
            return "Your circle is moving. Keep the week competitive."
        }

        if !social.friends.isEmpty {
            return "Your people are here. Give the week something to rally around."
        }

        if !groups.joinedGroups.isEmpty {
            return "Your clubs are ready. Build your training circle from here."
        }

        return "Find your people, train together, and make progress visible."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 22) {
                    CommunityV3Header(
                        canManageWeekly:
                            session.currentRole
                                .canAccessControlCenter
                    )

                    CommunityV3PulseCard(
                        friendCount: social.friends.count,
                        clubCount: groups.joinedGroups.count,
                        eventCount: community.upcomingEvents.count,
                        challengeCount: activeChallenges.count,
                        summary: pulseSummary
                    )

                    weeklyChallengeSection

                    if !challengeRequests.isEmpty {
                        challengeRequestsSection
                    }

                    friendsVsFriendsSection

                    CommunityV3ExploreDock(
                        clubCount: groups.joinedGroups.count,
                        eventCount: community.upcomingEvents.count,
                        challengeCount: activeChallenges.count
                    )

                    CommunityV3Footer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 34)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color.white,
                        ATHLTHTheme.cardWarm.opacity(0.28),
                        ATHLTHTheme.canvasBottom.opacity(0.52)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await refreshCommunity(force: true)
            }
            .task {
                await refreshCommunity()
            }
            .alert(
                "Community",
                isPresented:
                    Binding(
                        get: { refreshError != nil },
                        set: { shown in
                            if !shown {
                                refreshError = nil
                            }
                        }
                    )
            ) {
                Button("OK") {
                    refreshError = nil
                }
            } message: {
                Text(refreshError ?? "")
            }
        }
    }

    @ViewBuilder
    private var weeklyChallengeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CommunityV3SectionTitle(
                eyebrow: "THIS WEEK",
                title: "One challenge. Everyone in.",
                subtitle:
                    "A shared target gives the community something concrete to chase."
            )

            if let weeklyChallenge =
                officialChallenges.activeChallenge ??
                officialChallenges.upcomingChallenges.first {
                OfficialWeeklyChallengeCard(
                    challenge: weeklyChallenge,
                    profiles:
                        social.visibleProfiles +
                        social.friends
                )
            } else {
                NavigationLink {
                    ChallengeHubView()
                } label: {
                    CommunityV3EmptyWeeklyCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var challengeRequestsSection:
        some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            CommunityV3SectionTitle(
                eyebrow: "REQUESTS",
                title:
                    challengeRequests.count == 1
                        ? "Someone challenged you."
                        : "\(challengeRequests.count) challenges waiting.",
                subtitle:
                    "Accept or decline here. The same request also appears in Inbox."
            )

            VStack(spacing: 10) {
                ForEach(
                    challengeRequests.prefix(3)
                ) { challenge in
                    CommunityChallengeRequestCard(
                        challenge: challenge,
                        creator:
                            profile(
                                for:
                                    challenge.creatorID
                            ),
                        onAccept: {
                            respondToChallenge(
                                challenge,
                                accept: true
                            )
                        },
                        onDecline: {
                            respondToChallenge(
                                challenge,
                                accept: false
                            )
                        }
                    )
                }
            }

            if challengeRequests.count > 3 {
                NavigationLink {
                    ChallengeHubView()
                } label: {
                    Label(
                        "View all challenge requests",
                        systemImage:
                            "arrow.up.right"
                    )
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func profile(
        for userID: UUID
    ) -> SocialProfileCard? {
        social.visibleProfiles.first {
            $0.userID == userID
        } ??
        social.friends.first {
            $0.userID == userID
        } ??
        social.following.first {
            $0.userID == userID
        }
    }

    private func respondToChallenge(
        _ challenge: ATHLTHChallenge,
        accept: Bool
    ) {
        guard let participant =
                challenges
                    .invitationParticipant(
                        in: challenge,
                        userID:
                            session.profile.userID
                    )
        else {
            return
        }

        challenges.setParticipantState(
            challengeID: challenge.id,
            participantID: participant.id,
            state:
                accept
                    ? .accepted
                    : .declined
        )

        guard let updated =
                challenges.challenge(
                    id: challenge.id
                )
        else {
            return
        }

        Task {
            _ = await social.syncChallenge(
                updated
            )
        }
    }

    private var friendsVsFriendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CommunityV3SectionTitle(
                eyebrow: "HEAD TO HEAD",
                title: "Friends vs Friends",
                subtitle:
                    "A quick read on who is putting in the work right now."
            )

            CommunityFriendsVsFriendsCard(
                currentUserID: session.profile.userID,
                currentDisplayName:
                    session.profile.displayName,
                currentAvatarURL:
                    session.profile.avatarURL,
                friends: social.friends,
                feed: social.feed,
                ownWorkouts: health.workouts
            )
        }
    }

    @MainActor
    private func refreshCommunity(
        force: Bool = false
    ) async {
        let performanceID =
            ATHLTHPerformance.begin(
                "CommunityV3Refresh"
            )

        defer {
            ATHLTHPerformance.end(
                "CommunityV3Refresh",
                id: performanceID
            )
        }

        async let eventRefresh: Void =
            community.refresh(force: force)

        async let socialRefresh: Void =
            force
                ? social.refresh(
                    challengeStore: challenges
                )
                : social.refreshIfStale(
                    challengeStore: challenges
                )

        async let groupRefresh: Void =
            groups.refresh(force: force)

        async let weeklyRefresh: Void =
            officialChallenges.refresh(
                force: force
            )

        _ = await (
            eventRefresh,
            socialRefresh,
            groupRefresh,
            weeklyRefresh
        )

        await officialChallenges
            .syncCompletionState(
                workouts: health.workouts
            )

        challenges.refreshStatuses()

        refreshError =
            community.errorMessage ??
            groups.errorMessage ??
            officialChallenges.errorMessage
    }
}

private struct CommunityChallengeRequestCard:
    View {
    let challenge: ATHLTHChallenge
    let creator: SocialProfileCard?
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 13) {
            NavigationLink {
                ChallengeDetailView(
                    challengeID: challenge.id
                )
            } label: {
                HStack(spacing: 12) {
                    if let creator {
                        SocialAvatar(
                            profile: creator,
                            size: 48
                        )
                    } else {
                        Image(
                            systemName:
                                challenge.sport
                                    .systemImage
                        )
                        .font(
                            .system(
                                size: 19,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                        .frame(
                            width: 48,
                            height: 48
                        )
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: Circle()
                        )
                    }

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(
                            creator?.resolvedName
                                .map {
                                    "\($0) challenged you"
                                } ??
                            "Challenge invitation"
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .lineLimit(1)

                        Text(challenge.title)
                            .font(
                                .headline
                            )
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )
                            .lineLimit(1)

                        Text(detailText)
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(
                        systemName:
                            "chevron.right"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(
                        .tertiary
                    )
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 9) {
                Button(
                    "Decline",
                    action: onDecline
                )
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button(
                    "Accept",
                    action: onAccept
                )
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme.accentDeep
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(15)
        .background(
            Color.white.opacity(0.84),
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.045),
                lineWidth: 0.8
            )
        }
    }

    private var detailText: String {
        var parts = [
            challenge.sport.title,
            challenge.rules.scoring.title
        ]

        if challenge.rules.startsAt > Date() {
            parts.append(
                challenge.rules.startsAt
                    .formatted(
                        date: .abbreviated,
                        time: .omitted
                    )
            )
        } else {
            parts.append("Open now")
        }

        return parts.joined(
            separator: " · "
        )
    }
}

// MARK: - Header

private struct CommunityV3Header: View {
    let canManageWeekly: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("COMMUNITY")
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                            .opacity(0.58)
                    )

                Text("Train together.")
                    .font(
                        .system(
                            size: 31,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(
                    "Less feed. More people, competition and reasons to show up."
                )
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }

            Spacer(minLength: 12)

            if canManageWeekly {
                NavigationLink {
                    OfficialWeeklyChallengeAdminListView()
                } label: {
                    Image(
                        systemName:
                            "slider.horizontal.3"
                    )
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .frame(
                        width: 42,
                        height: 42
                    )
                    .background(
                        Color.white.opacity(0.88),
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                Color.black.opacity(0.06),
                                lineWidth: 0.8
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Manage weekly challenges"
                )
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Pulse

private struct CommunityV3PulseCard: View {
    let friendCount: Int
    let clubCount: Int
    let eventCount: Int
    let challengeCount: Int
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            Color.white.opacity(0.16)
                        )

                    Image(
                        systemName:
                            "person.2.wave.2.fill"
                    )
                    .font(
                        .system(
                            size: 20,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text("YOUR CIRCLE")
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(
                            .white.opacity(0.64)
                        )

                    Text(summary)
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                        .foregroundStyle(.white)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                CommunityV3PulseMetric(
                    value: friendCount,
                    label: "Friends"
                )

                CommunityV3PulseMetric(
                    value: clubCount,
                    label: "Clubs"
                )

                CommunityV3PulseMetric(
                    value: eventCount,
                    label: "Events"
                )

                CommunityV3PulseMetric(
                    value: challengeCount,
                    label: "Live"
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.accentDeep,
                    Color.indigo.opacity(0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 26,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.14),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                ATHLTHTheme.accentDeep
                    .opacity(0.14),
            radius: 18,
            x: 0,
            y: 8
        )
    }
}

private struct CommunityV3PulseMetric: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value.formatted())
                .font(
                    .headline
                        .weight(.bold)
                )
                .monospacedDigit()
                .foregroundStyle(.white)

            Text(label)
                .font(.caption2)
                .foregroundStyle(
                    .white.opacity(0.62)
                )
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            Color.white.opacity(0.10),
            in:
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
        )
    }
}

// MARK: - Explore

private struct CommunityV3ExploreDock: View {
    let clubCount: Int
    let eventCount: Int
    let challengeCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CommunityV3SectionTitle(
                eyebrow: "GO DEEPER",
                title: "More ways to train together",
                subtitle:
                    "The full community tools stay one tap away without taking over the front page."
            )

            HStack(spacing: 10) {
                NavigationLink {
                    CommunityGroupsView()
                } label: {
                    CommunityV3DockItem(
                        title: "Clubs",
                        value: clubCount,
                        icon: "person.3.fill"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    CommunityEventsView()
                } label: {
                    CommunityV3DockItem(
                        title: "Events",
                        value: eventCount,
                        icon:
                            "calendar.badge.clock"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ChallengeHubView()
                } label: {
                    CommunityV3DockItem(
                        title: "Challenges",
                        value: challengeCount,
                        icon: "trophy.fill"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CommunityV3DockItem: View {
    let title: String
    let value: Int
    let icon: String

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 11
        ) {
            HStack {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 17,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )

                Spacer(minLength: 0)

                Image(
                    systemName:
                        "arrow.up.right"
                )
                .font(.caption.bold())
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                        .opacity(0.72)
                )
            }

            Text(value.formatted())
                .font(
                    .title3
                        .weight(.bold)
                )
                .monospacedDigit()
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

            Text(title)
                .font(
                    .caption
                        .weight(.semibold)
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)
        }
        .padding(14)
        .frame(
            maxWidth: .infinity,
            minHeight: 112,
            alignment: .leading
        )
        .background(
            Color.white.opacity(0.90),
            in:
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.05),
                lineWidth: 0.8
            )
        }
    }
}

// MARK: - Supporting cards

private struct CommunityV3EmptyWeeklyCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "trophy.fill")
                .font(
                    .system(
                        size: 21,
                        weight: .semibold
                    )
                )
                .foregroundStyle(.orange)
                .frame(
                    width: 48,
                    height: 48
                )
                .background(
                    Color.orange.opacity(0.10),
                    in:
                        RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("No weekly challenge yet")
                    .font(.headline)
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(
                    "Open Challenges and pick the next target."
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            Color.white.opacity(0.92),
            in:
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.05),
                lineWidth: 0.8
            )
        }
    }
}

private struct CommunityV3SectionTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.caption2.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                        .opacity(0.56)
                )

            Text(title)
                .font(
                    .title3
                        .weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
        }
    }
}

private struct CommunityV3Footer: View {
    var body: some View {
        HStack(spacing: 9) {
            Image(
                systemName:
                    "figure.run.circle.fill"
            )
            .font(.system(size: 17))
            .foregroundStyle(
                ATHLTHTheme.accentDeep
                    .opacity(0.72)
            )

            Text(
                "Community should help you train more — not give you another feed to scroll."
            )
            .font(.caption)
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }
}
