import SwiftUI
import UIKit

// MARK: - Community V2
//
// The Community home surface is intentionally rebuilt from scratch.
// Existing Club/Event/Challenge stores and detail flows remain the data layer.
// Only the existing Weekly Challenge and Friends vs Friends cards are reused.

struct ATHLTHCommunityV2View: View {
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var officialChallenges: OfficialWeeklyChallengeStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var groups: CommunityGroupStore

    @State private var refreshError: String?

    private var activeChallenges: [ATHLTHChallenge] {
        challenges.visibleChallenges
            .filter {
                $0.status == .active ||
                $0.status == .upcoming ||
                $0.status == .invited
            }
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

    private var visibleEvents:
        [CommunityEventItem] {
        Array(
            community.upcomingEvents
                .prefix(3)
        )
    }

    private var visibleClubs:
        [CommunityGroupRecord] {
        Array(
            groups.joinedGroups
                .prefix(5)
        )
    }

    private var visibleChallenges:
        [ATHLTHChallenge] {
        Array(
            activeChallenges
                .prefix(3)
        )
    }

    var body: some View {
        let immersive =
            UIDevice.current.userInterfaceIdiom == .pad ||
            UIScreen.main.bounds.width >= 390

        NavigationStack {
            ATHLTHPinnedHeroLayout(
                accent:
                    Color.indigo
                        .opacity(0.30),
                softTransition: true,
                immersiveTransition:
                    immersive,
                scrollFadeTransition: true
            ) {
                ZStack(
                    alignment: .topTrailing
                ) {
                    ATHLTHTabHero(
                        imageName:
                            "CommunityHero",
                        title:
                            "Community",
                        subtitle:
                            "Better together. Find your people, show up, and keep moving.",
                        height:
                            immersive
                                ? 232
                                : 190,
                        alignment: .center,
                        focalOffsetX: 0,
                        focalOffsetY:
                            immersive
                                ? 6
                                : 12,
                        titleFontSize:
                            immersive
                                ? 31
                                : 30,
                        copyWidthFraction:
                            immersive
                                ? 0.72
                                : 0.84,
                        immersiveCopy:
                            immersive
                    )

                    if session
                        .currentRole
                        .canAccessControlCenter {
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
                                    weight:
                                        .semibold
                                )
                            )
                            .foregroundStyle(
                                .white
                            )
                            .frame(
                                width: 38,
                                height: 38
                            )
                            .background(
                                Color.black
                                    .opacity(0.24),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(
                                        Color.white
                                            .opacity(0.30),
                                        lineWidth:
                                            0.8
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "Manage weekly challenges"
                        )
                        .padding(
                            .top,
                            immersive
                                ? 58
                                : 52
                        )
                        .padding(
                            .trailing,
                            16
                        )
                    }
                }
            } content: {
                LazyVStack(
                    spacing: 16
                ) {
                    CommunityV2SnapshotCard(
                        clubCount:
                            groups
                                .joinedGroups
                                .count,
                        eventCount:
                            community
                                .upcomingEvents
                                .count,
                        challengeCount:
                            activeChallenges
                                .count
                    )

                    if let weekly =
                        officialChallenges
                            .activeChallenge ??
                        officialChallenges
                            .upcomingChallenges
                            .first {
                        OfficialWeeklyChallengeCard(
                            challenge: weekly,
                            profiles:
                                social
                                    .visibleProfiles +
                                social.friends
                        )
                    }

                    CommunityFriendsVsFriendsCard(
                        currentUserID:
                            session
                                .profile
                                .userID,
                        currentDisplayName:
                            session
                                .profile
                                .displayName,
                        currentAvatarURL:
                            session
                                .profile
                                .avatarURL,
                        friends:
                            social.friends,
                        feed:
                            social.feed,
                        ownWorkouts:
                            health.workouts
                    )

                    CommunityV2GatewaySection(
                        clubCount:
                            groups
                                .joinedGroups
                                .count,
                        eventCount:
                            community
                                .upcomingEvents
                                .count,
                        challengeCount:
                            activeChallenges
                                .count
                    )

                    CommunityV2ClubsSection(
                        clubs:
                            visibleClubs,
                        groups: groups
                    )

                    CommunityV2EventsSection(
                        events:
                            visibleEvents
                    )

                    CommunityV2ChallengesSection(
                        challenges:
                            visibleChallenges
                    )

                    CommunityV2Footer()
                }
                .padding(
                    .horizontal,
                    16
                )
                .padding(
                    .top,
                    8
                )
                .padding(
                    .bottom,
                    28
                )
                .frame(
                    maxWidth: 900
                )
                .frame(
                    maxWidth: .infinity
                )
            }
            .toolbar(
                .hidden,
                for: .navigationBar
            )
            .refreshable {
                await refreshCommunity(
                    force: true
                )
            }
            .task {
                await refreshCommunity()
            }
            .alert(
                "Community",
                isPresented:
                    Binding(
                        get: {
                            refreshError != nil
                        },
                        set: {
                            shown in

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
                Text(
                    refreshError ?? ""
                )
            }
        }
    }

    private struct CommunityV2SnapshotCard:
        View
    {
        let clubCount: Int
        let eventCount: Int
        let challengeCount: Int

        var body: some View {
            ATHLTHCard {
                HStack(spacing: 8) {
                    snapshotMetric(
                        value: clubCount,
                        label: "Clubs",
                        icon: "person.3.fill"
                    )

                    Divider()
                        .frame(height: 34)

                    snapshotMetric(
                        value: eventCount,
                        label: "Events",
                        icon:
                            "calendar.badge.clock"
                    )

                    Divider()
                        .frame(height: 34)

                    snapshotMetric(
                        value:
                            challengeCount,
                        label:
                            "Challenges",
                        icon:
                            "trophy.fill"
                    )
                }
            }
        }

        private func snapshotMetric(
            value: Int,
            label: String,
            icon: String
        ) -> some View {
            HStack(spacing: 8) {
                Image(
                    systemName: icon
                )
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )

                VStack(
                    alignment: .leading,
                    spacing: 1
                ) {
                    Text("\(value)")
                        .font(
                            .headline
                                .weight(.bold)
                        )
                        .monospacedDigit()

                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(
                            .secondary
                        )
                }

                Spacer(
                    minLength: 0
                )
            }
            .frame(
                maxWidth: .infinity
            )
        }
    }

    @MainActor
    private func refreshCommunity(
        force: Bool = false
    ) async {
        let performanceID =
            ATHLTHPerformance.begin(
                "CommunityV2Refresh"
            )

        defer {
            ATHLTHPerformance.end(
                "CommunityV2Refresh",
                id: performanceID
            )
        }

        async let eventRefresh: Void =
            community.refresh(
                force: force
            )

        async let socialRefresh: Void =
            force
                ? social.refresh(
                    challengeStore:
                        challenges
                )
                : social
                    .refreshIfStale(
                        challengeStore:
                            challenges
                    )

        async let groupRefresh: Void =
            groups.refresh(
                force: force
            )

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
                workouts:
                    health.workouts
            )

        challenges.refreshStatuses()

        refreshError =
            community.errorMessage ??
            groups.errorMessage ??
            officialChallenges
                .errorMessage
    }
}

// MARK: - Hero

private struct CommunityV2Hero: View {
    let clubCount: Int
    let eventCount: Int
    let challengeCount: Int
    let canManageWeekly: Bool

    var body: some View {
        ZStack(
            alignment: .bottomLeading
        ) {
            Image("CommunityHero")
                .resizable()
                .scaledToFill()
                .frame(
                    maxWidth: .infinity
                )
                .frame(height: 286)
                .clipped()

            LinearGradient(
                colors: [
                    Color.black
                        .opacity(0.08),
                    Color.black
                        .opacity(0.22),
                    Color.black
                        .opacity(0.76)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(
                alignment: .leading,
                spacing: 14
            ) {
                HStack {
                    Text("COMMUNITY")
                        .font(
                            .system(
                                size: 10,
                                weight: .bold
                            )
                        )
                        .tracking(1.5)
                        .foregroundStyle(
                            .white
                                .opacity(
                                    0.92
                                )
                        )
                        .padding(
                            .horizontal,
                            10
                        )
                        .frame(height: 28)
                        .background(
                            .ultraThinMaterial,
                            in: Capsule()
                        )

                    Spacer()

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
                                    weight:
                                        .semibold
                                )
                            )
                            .foregroundStyle(
                                .white
                            )
                            .frame(
                                width: 38,
                                height: 38
                            )
                            .background(
                                Color.black
                                    .opacity(
                                        0.25
                                    ),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(
                                        Color.white
                                            .opacity(
                                                0.30
                                            ),
                                        lineWidth:
                                            0.8
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "Manage weekly challenges"
                        )
                    }
                }

                Spacer()

                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {
                    Text(
                        "Better together."
                    )
                    .font(
                        .system(
                            size: 32,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        .white
                    )

                    Text(
                        "Find your people, show up, and keep moving."
                    )
                    .font(
                        .subheadline
                            .weight(
                                .medium
                            )
                    )
                    .foregroundStyle(
                        .white
                            .opacity(
                                0.82
                            )
                    )
                    .lineLimit(2)
                }

                HStack(spacing: 8) {
                    CommunityV2HeroMetric(
                        value:
                            clubCount,
                        label:
                            "Clubs"
                    )

                    CommunityV2HeroMetric(
                        value:
                            eventCount,
                        label:
                            "Events"
                    )

                    CommunityV2HeroMetric(
                        value:
                            challengeCount,
                        label:
                            "Challenges"
                    )
                }
            }
            .padding(
                .horizontal,
                18
            )
            .padding(
                .top,
                54
            )
            .padding(
                .bottom,
                16
            )
        }
        .frame(height: 286)
        .clipShape(
            UnevenRoundedRectangle(
                bottomLeadingRadius:
                    28,
                bottomTrailingRadius:
                    28
            )
        )
        .shadow(
            color:
                Color.black
                    .opacity(0.10),
            radius: 18,
            y: 8
        )
    }
}

private struct CommunityV2HeroMetric:
    View {
    let value: Int
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(
                "\(value)"
            )
            .font(
                .caption.weight(
                    .bold
                )
            )

            Text(label)
                .font(.caption2)
        }
        .foregroundStyle(
            .white
                .opacity(0.92)
        )
        .padding(
            .horizontal,
            10
        )
        .frame(height: 30)
        .background(
            Color.black
                .opacity(0.22),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    Color.white
                        .opacity(0.16),
                    lineWidth: 0.8
                )
        }
    }
}

// MARK: - Gateways

private struct CommunityV2GatewaySection:
    View {
    let clubCount: Int
    let eventCount: Int
    let challengeCount: Int

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            CommunityV2SectionHeader(
                title:
                    "Your community",
                subtitle:
                    "Everything social, without the clutter."
            )

            NavigationLink {
                CommunityGroupsView()
            } label: {
                CommunityV2GatewayCard(
                    title: "Clubs",
                    subtitle:
                        clubCount == 0
                        ? "Find a club or start your own."
                        : "\(clubCount) club\(clubCount == 1 ? "" : "s") joined",
                    icon:
                        "person.3.fill",
                    detail:
                        "Chat, club updates, events and challenges.",
                    emphasis: true
                )
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                NavigationLink {
                    CommunityEventsView()
                } label: {
                    CommunityV2GatewayCard(
                        title:
                            "Events",
                        subtitle:
                            eventCount == 0
                            ? "Nothing scheduled"
                            : "\(eventCount) upcoming",
                        icon:
                            "calendar.badge.clock",
                        detail:
                            "Meet up and train.",
                        emphasis:
                            false
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ChallengeHubView()
                } label: {
                    CommunityV2GatewayCard(
                        title:
                            "Challenges",
                        subtitle:
                            challengeCount == 0
                            ? "Find your next goal"
                            : "\(challengeCount) active",
                        icon:
                            "trophy.fill",
                        detail:
                            "Compete or collaborate.",
                        emphasis:
                            false
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CommunityV2GatewayCard:
    View {
    let title: String
    let subtitle: String
    let icon: String
    let detail: String
    let emphasis: Bool

    var body: some View {
        HStack(
            alignment: .center,
            spacing: 13
        ) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size:
                        emphasis
                        ? 21
                        : 18,
                    weight:
                        .semibold
                )
            )
            .foregroundStyle(
                emphasis
                    ? .white
                    : ATHLTHTheme
                        .accentDeep
            )
            .frame(
                width:
                    emphasis
                    ? 48
                    : 42,
                height:
                    emphasis
                    ? 48
                    : 42
            )
            .background(
                emphasis
                    ? Color.white
                        .opacity(0.15)
                    : ATHLTHTheme
                        .accentSoft,
                in:
                    RoundedRectangle(
                        cornerRadius:
                            emphasis
                            ? 15
                            : 13,
                        style:
                            .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(
                        emphasis
                            ? .headline
                            : .subheadline
                                .weight(
                                    .bold
                                )
                    )
                    .foregroundStyle(
                        emphasis
                            ? .white
                            : ATHLTHTheme
                                .primaryText
                    )

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(
                        emphasis
                            ? .white
                                .opacity(
                                    0.76
                                )
                            : ATHLTHTheme
                                .mutedText
                    )
                    .lineLimit(1)

                if emphasis {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(
                            .white
                                .opacity(
                                    0.62
                                )
                        )
                        .lineLimit(1)
                }
            }

            Spacer(
                minLength: 4
            )

            Image(
                systemName:
                    "chevron.right"
            )
            .font(
                .caption.bold()
            )
            .foregroundStyle(
                emphasis
                    ? .white
                        .opacity(0.70)
                    : ATHLTHTheme
                        .mutedText
            )
        }
        .padding(
            emphasis
                ? 16
                : 13
        )
        .frame(
            maxWidth:
                .infinity,
            minHeight:
                emphasis
                ? 86
                : 76,
            alignment:
                .leading
        )
        .background {
            if emphasis {
                LinearGradient(
                    colors: [
                        Color.indigo
                            .opacity(
                                0.96
                            ),
                        Color.purple
                            .opacity(
                                0.82
                            )
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                )
            } else {
                Color.white
                    .opacity(0.92)
            }
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius:
                    emphasis
                    ? 22
                    : 19,
                style:
                    .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius:
                    emphasis
                    ? 22
                    : 19,
                style:
                    .continuous
            )
            .stroke(
                emphasis
                    ? Color.white
                        .opacity(0.16)
                    : Color.black
                        .opacity(0.05),
                lineWidth: 0.8
            )
        }
    }
}

// MARK: - Clubs

private struct CommunityV2ClubsSection:
    View {
    let clubs: [CommunityGroupRecord]
    let groups: CommunityGroupStore

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            CommunityV2SectionHeader(
                title:
                    "My clubs",
                subtitle:
                    clubs.isEmpty
                    ? "Your place for the people you train with."
                    : "Jump back into your active circles."
            ) {
                NavigationLink {
                    CommunityGroupsView()
                } label: {
                    Text(
                        clubs.isEmpty
                            ? "Discover"
                            : "See all"
                    )
                }
            }

            if clubs.isEmpty {
                NavigationLink {
                    CommunityGroupsView()
                } label: {
                    CommunityV2EmptyClubCard()
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(
                    .horizontal
                ) {
                    LazyHStack(
                        spacing: 11
                    ) {
                        ForEach(clubs) {
                            club in

                            NavigationLink {
                                CommunityGroupDetailView(
                                    group:
                                        club
                                )
                            } label: {
                                CommunityV2ClubCard(
                                    club:
                                        club,
                                    memberCount:
                                        groups
                                            .members(
                                                in:
                                                    club.id
                                            )
                                            .count
                                )
                            }
                            .buttonStyle(
                                .plain
                            )
                        }

                        NavigationLink {
                            CommunityGroupsView()
                        } label: {
                            CommunityV2MoreCard(
                                title:
                                    "All clubs",
                                icon:
                                    "arrow.right"
                            )
                        }
                        .buttonStyle(
                            .plain
                        )
                    }
                }
                .scrollIndicators(
                    .hidden
                )
            }
        }
    }
}

private struct CommunityV2ClubCard:
    View {
    let club: CommunityGroupRecord
    let memberCount: Int

    var body: some View {
        ZStack(
            alignment:
                .bottomLeading
        ) {
            CommunityV2ClubArtwork(
                club: club
            )

            LinearGradient(
                colors: [
                    .clear,
                    Color.black
                        .opacity(
                            0.78
                        )
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                if !club
                    .locationName
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .isEmpty {
                    Label(
                        club.locationName,
                        systemImage:
                            "location.fill"
                    )
                    .font(
                        .system(
                            size: 9,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        .white
                            .opacity(
                                0.78
                            )
                    )
                    .lineLimit(1)
                }

                Text(club.name)
                    .font(
                        .headline
                    )
                    .foregroundStyle(
                        .white
                    )
                    .lineLimit(2)

                Text(
                    ATHLTHLocalization.counted(
                    memberCount,
                    englishSingular: "member",
                    englishPlural: "members",
                    norwegianSingular: "medlem",
                    norwegianPlural: "medlemmer"
                )
                )
                .font(.caption2)
                .foregroundStyle(
                    .white
                        .opacity(0.72)
                )
            }
            .padding(13)
        }
        .frame(
            width: 220,
            height: 154
        )
        .clipShape(
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
                Color.white
                    .opacity(0.26),
                lineWidth: 0.8
            )
        }
    }
}

private struct CommunityV2ClubArtwork:
    View {
    let club: CommunityGroupRecord

    var body: some View {
        Group {
            if let value =
                club.imageURL,
               let url =
                URL(string: value) {
                AsyncImage(
                    url: url
                ) {
                    phase in

                    switch phase {
                    case .success(
                        let image
                    ):
                        image
                            .resizable()
                            .scaledToFill()

                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(
            width: 220,
            height: 154
        )
        .clipped()
    }

    private var fallback:
        some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.indigo
                        .opacity(
                            0.80
                        ),
                    Color.purple
                        .opacity(
                            0.62
                        )
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            )

            Image(
                systemName:
                    "person.3.fill"
            )
            .font(
                .system(
                    size: 42
                )
            )
            .foregroundStyle(
                .white
                    .opacity(0.26)
            )
        }
    }
}

private struct CommunityV2EmptyClubCard:
    View {
    var body: some View {
        HStack(spacing: 14) {
            Image(
                systemName:
                    "person.3.fill"
            )
            .font(.title2)
            .foregroundStyle(
                ATHLTHTheme
                    .accentDeep
            )
            .frame(
                width: 52,
                height: 52
            )
            .background(
                ATHLTHTheme
                    .accentSoft,
                in:
                    RoundedRectangle(
                        cornerRadius:
                            16,
                        style:
                            .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(
                    "Find your club"
                )
                .font(
                    .headline
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )

                Text(
                    "Join people who train, race or move like you do."
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
            }

            Spacer()

            Image(
                systemName:
                    "arrow.right"
            )
            .foregroundStyle(
                ATHLTHTheme
                    .accentDeep
            )
        }
        .padding(15)
        .background(
            Color.white
                .opacity(0.92),
            in:
                RoundedRectangle(
                    cornerRadius: 21,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 21,
                style: .continuous
            )
            .stroke(
                Color.black
                    .opacity(0.05),
                lineWidth: 0.8
            )
        }
    }
}

// MARK: - Events

private struct CommunityV2EventsSection:
    View {
    let events: [CommunityEventItem]

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            CommunityV2SectionHeader(
                title:
                    "Coming up",
                subtitle:
                    events.isEmpty
                    ? "No plans yet. Make the next one happen."
                    : "Events worth showing up for."
            ) {
                NavigationLink {
                    CommunityEventsView()
                } label: {
                    Text("See all")
                }
            }

            if events.isEmpty {
                NavigationLink {
                    CommunityEventsView()
                } label: {
                    CommunityV2EmptyEventCard()
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 9) {
                    ForEach(events) {
                        item in

                        NavigationLink {
                            CommunityEventDetailView(
                                eventID:
                                    item.id
                            )
                        } label: {
                            CommunityV2EventCard(
                                item: item
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct CommunityV2EventCard:
    View {
    let item: CommunityEventItem

    var body: some View {
        HStack(spacing: 13) {
            VStack(spacing: 1) {
                Text(
                    item.event
                        .startsAt
                        .formatted(
                            .dateTime
                                .month(
                                    .abbreviated
                                )
                        )
                        .uppercased()
                )
                .font(
                    .system(
                        size: 9,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )

                Text(
                    item.event
                        .startsAt
                        .formatted(
                            .dateTime
                                .day()
                        )
                )
                .font(
                    .system(
                        size: 24,
                        weight: .bold,
                        design:
                            .rounded
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
            }
            .frame(
                width: 52,
                height: 58
            )
            .background(
                ATHLTHTheme
                    .accentSoft,
                in:
                    RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                HStack(spacing: 6) {
                    Image(
                        systemName:
                            item.event
                                .activityType
                                .systemImage
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .vitality
                    )

                    Text(
                        item.event.title
                    )
                    .font(
                        .subheadline
                            .weight(
                                .bold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)
                }

                Text(
                    eventMeta
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(1)

                Label(
                    ATHLTHLocalization.format(
                    english: "%d going",
                    norwegian: "%d skal",
                    item.participantCount
                ),
                    systemImage:
                        "person.2.fill"
                )
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
            }

            Spacer()

            Image(
                systemName:
                    "chevron.right"
            )
            .font(.caption.bold())
            .foregroundStyle(
                ATHLTHTheme
                    .mutedText
            )
        }
        .padding(13)
        .background(
            Color.white
                .opacity(0.92),
            in:
                RoundedRectangle(
                    cornerRadius: 19,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
            .stroke(
                Color.black
                    .opacity(0.045),
                lineWidth: 0.8
            )
        }
    }

    private var eventMeta:
        String {
        let time =
            item.event
                .startsAt
                .formatted(
                    date: .omitted,
                    time: .shortened
                )

        let place =
            item.event
                .meetingName
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        if place.isEmpty {
            return time
        }

        return "\(time) · \(place)"
    }
}

private struct CommunityV2EmptyEventCard:
    View {
    var body: some View {
        HStack(spacing: 13) {
            Image(
                systemName:
                    "calendar.badge.plus"
            )
            .font(.title2)
            .foregroundStyle(
                ATHLTHTheme
                    .vitality
            )
            .frame(
                width: 50,
                height: 50
            )
            .background(
                ATHLTHTheme
                    .vitalitySoft,
                in:
                    RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    "Create the next meetup"
                )
                .font(
                    .subheadline
                        .weight(
                            .bold
                        )
                )

                Text(
                    "Run, lift, hike or train together."
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
            }

            Spacer()

            Image(
                systemName:
                    "arrow.right"
            )
            .foregroundStyle(
                ATHLTHTheme
                    .accentDeep
            )
        }
        .padding(14)
        .background(
            Color.white
                .opacity(0.92),
            in:
                RoundedRectangle(
                    cornerRadius: 19,
                    style: .continuous
                )
        )
    }
}

// MARK: - Challenges

private struct CommunityV2ChallengesSection:
    View {
    let challenges: [ATHLTHChallenge]

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            CommunityV2SectionHeader(
                title:
                    "Your challenges",
                subtitle:
                    challenges.isEmpty
                    ? "Pick a target and make it social."
                    : "The ones currently asking something from you."
            ) {
                NavigationLink {
                    ChallengeHubView()
                } label: {
                    Text("See all")
                }
            }

            if challenges.isEmpty {
                NavigationLink {
                    ChallengeHubView()
                } label: {
                    CommunityV2EmptyChallengeCard()
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 9) {
                    ForEach(challenges) {
                        challenge in

                        NavigationLink {
                            ChallengeDetailView(
                                challengeID:
                                    challenge.id
                            )
                        } label: {
                            CommunityV2ChallengeCard(
                                challenge:
                                    challenge
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct CommunityV2ChallengeCard:
    View {
    let challenge: ATHLTHChallenge

    var body: some View {
        HStack(spacing: 13) {
            Image(
                systemName:
                    challenge
                        .sport
                        .systemImage
            )
            .font(
                .system(
                    size: 19,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                challengeTint
            )
            .frame(
                width: 48,
                height: 48
            )
            .background(
                challengeTint
                    .opacity(0.10),
                in:
                    RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                HStack(spacing: 7) {
                    Text(
                        challenge.title
                    )
                    .font(
                        .subheadline
                            .weight(
                                .bold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)

                    Text(
                        statusLabel
                    )
                    .font(
                        .system(
                            size: 8,
                            weight: .bold
                        )
                    )
                    .tracking(0.7)
                    .foregroundStyle(
                        challengeTint
                    )
                    .padding(
                        .horizontal,
                        6
                    )
                    .frame(height: 19)
                    .background(
                        challengeTint
                            .opacity(0.09),
                        in: Capsule()
                    )
                }

                Text(
                    challengeSummary
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(1)

                HStack(spacing: 5) {
                    Image(
                        systemName:
                            "person.2.fill"
                    )

                    Text(
                        ATHLTHLocalization.format(
                            english: "%d participating",
                            norwegian: "%d deltar",
                            acceptedCount
                        )
                    )
                }
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
            }

            Spacer()

            Image(
                systemName:
                    "chevron.right"
            )
            .font(.caption.bold())
            .foregroundStyle(
                ATHLTHTheme
                    .mutedText
            )
        }
        .padding(13)
        .background(
            Color.white
                .opacity(0.92),
            in:
                RoundedRectangle(
                    cornerRadius: 19,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
            .stroke(
                Color.black
                    .opacity(0.045),
                lineWidth: 0.8
            )
        }
    }

    private var acceptedCount:
        Int {
        challenge.participants
            .filter {
                $0.state == .creator ||
                $0.state == .accepted
            }
            .count
    }

    private var statusLabel:
        String {
        switch challenge.status {
        case .active:
            return "LIVE"
        case .upcoming:
            return "UPCOMING"
        case .invited:
            return "INVITED"
        case .completed:
            return "DONE"
        case .cancelled:
            return "CANCELLED"
        case .draft:
            return "DRAFT"
        }
    }

    private var challengeSummary:
        String {
        if let route =
            challenge.rules.route {
            return String(
                format:
                    "%.1f km route · %@",
                route.distanceKilometers,
                challenge.rules
                    .scoring
                    .title
            )
        }

        if let distance =
            challenge.rules
                .targetDistanceMeters {
            return String(
                format:
                    "%.1f km · %@",
                distance / 1_000,
                challenge.rules
                    .scoring
                    .title
            )
        }

        if let duration =
            challenge.rules
                .targetDurationSeconds {
            let minutes =
                Int(
                    duration / 60
                )

            return
                "\(minutes) min · \(challenge.rules.scoring.title)"
        }

        return
            "\(challenge.sport.title) · \(challenge.rules.scoring.title)"
    }

    private var challengeTint:
        Color {
        switch challenge.sport {
        case .running:
            return
                ATHLTHTheme
                    .vitality
        case .strength:
            return .indigo
        case .heartRate:
            return .red
        }
    }
}

private struct CommunityV2EmptyChallengeCard:
    View {
    var body: some View {
        HStack(spacing: 13) {
            Image(
                systemName:
                    "trophy.fill"
            )
            .font(.title2)
            .foregroundStyle(
                .orange
            )
            .frame(
                width: 50,
                height: 50
            )
            .background(
                Color.orange
                    .opacity(0.09),
                in:
                    RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    "Give yourself something to chase"
                )
                .font(
                    .subheadline
                        .weight(
                            .bold
                        )
                )

                Text(
                    "Create or join a challenge."
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
            }

            Spacer()

            Image(
                systemName:
                    "arrow.right"
            )
            .foregroundStyle(
                ATHLTHTheme
                    .accentDeep
            )
        }
        .padding(14)
        .background(
            Color.white
                .opacity(0.92),
            in:
                RoundedRectangle(
                    cornerRadius: 19,
                    style: .continuous
                )
        )
    }
}

// MARK: - Shared V2 building blocks

private struct CommunityV2SectionHeader<
    Action: View
>: View {
    let title: String
    let subtitle: String
    let action: Action

    init(
        title: String,
        subtitle: String,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.subtitle = subtitle
        self.action = action()
    }

    var body: some View {
        HStack(
            alignment:
                .firstTextBaseline
        ) {
            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(
                        .title3
                            .weight(
                                .bold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
            }

            Spacer()

            action
                .font(
                    .caption
                        .weight(
                            .semibold
                        )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )
        }
    }
}

private extension CommunityV2SectionHeader
where Action == EmptyView {
    init(
        title: String,
        subtitle: String
    ) {
        self.init(
            title: title,
            subtitle: subtitle
        ) {
            EmptyView()
        }
    }
}

private struct CommunityV2MoreCard:
    View {
    let title: String
    let icon: String

    var body: some View {
        VStack(
            spacing: 10
        ) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 21,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme
                    .accentDeep
            )
            .frame(
                width: 46,
                height: 46
            )
            .background(
                ATHLTHTheme
                    .accentSoft,
                in: Circle()
            )

            Text(title)
                .font(
                    .caption
                        .weight(
                            .semibold
                        )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
        }
        .frame(
            width: 120,
            height: 154
        )
        .background(
            Color.white
                .opacity(0.82),
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
                Color.black
                    .opacity(0.045),
                lineWidth: 0.8
            )
        }
    }
}

private struct CommunityV2Footer:
    View {
    var body: some View {
        VStack(spacing: 7) {
            Image(
                systemName:
                    "person.3.sequence.fill"
            )
            .font(.title3)
            .foregroundStyle(
                ATHLTHTheme
                    .accentDeep
            )

            Text(
                "Community should make training feel closer — not busier."
            )
            .font(
                .caption
                    .weight(
                        .semibold
                    )
            )
            .foregroundStyle(
                ATHLTHTheme
                    .primaryText
            )
            .multilineTextAlignment(
                .center
            )

            Text(
                "Clubs, events and challenges stay connected to the people and workouts that matter."
            )
            .font(.caption2)
            .foregroundStyle(
                ATHLTHTheme
                    .mutedText
            )
            .multilineTextAlignment(
                .center
            )
        }
        .frame(
            maxWidth: .infinity
        )
        .padding(
            .vertical,
            20
        )
    }
}
