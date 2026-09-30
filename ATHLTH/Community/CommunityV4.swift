import Foundation
import SwiftUI

// Community V4 is intentionally a social overview rather than another
// scrolling content feed. Weekly Challenge and Friends vs Friends are the two
// retained Community concepts. Everything else is rebuilt around the current
// Follow / Following, messaging, live-training, Clubs and Events models.
struct ATHLTHCommunityV4View: View {
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var officialChallenges: OfficialWeeklyChallengeStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var groups: CommunityGroupStore
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore

    @State private var refreshError: String?

    private var mutuals: [SocialProfileCard] {
        social.mutualFollows
    }

    private var circleFeed: [SocialFeedItem] {
        social.feed
            .filter {
                $0.actor.userID != session.profile.userID
            }
            .sorted {
                $0.activity.createdAt >
                $1.activity.createdAt
            }
    }

    private var activeChallenges: [ATHLTHChallenge] {
        challenges
            .trainingChallenges(
                for: session.profile.userID
            )
            .sorted {
                $0.rules.startsAt <
                $1.rules.startsAt
            }
    }

    private var challengeInvites: [ATHLTHChallenge] {
        challenges.incomingInvitations(
            for: session.profile.userID
        )
    }

    private var onlineFollowing: [SocialProfileCard] {
        social.following.filter {
            realtime.isOnline($0.userID)
        }
    }

    private var visibleCircleLiveSessions:
        [ATHLTHLiveWorkoutSession] {
        realtime.visibleLiveSessions.filter { live in
            live.ownerID != session.profile.userID &&
            (
                social.followingIDs.contains(
                    live.ownerID
                ) ||
                social.followerIDs.contains(
                    live.ownerID
                )
            )
        }
    }

    private var upcomingGroupEvents:
        [CommunityGroupEventRecord] {
        groups.calendarEvents.filter {
            $0.status != "cancelled" &&
            $0.startsAt >= Date()
        }
    }

    private var socialEventCount: Int {
        community.upcomingEvents.count +
        upcomingGroupEvents.count
    }

    private var attentionCount: Int {
        messaging.unreadCount +
        messaging.messageRequestCount +
        social.incomingRequests.count +
        social.workoutInvites.count +
        challengeInvites.count +
        groups.ownInvites.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 22
                ) {
                    CommunityV4Header(
                        unreadMessages:
                            messaging.unreadCount,
                        attentionCount:
                            attentionCount,
                        canManageWeekly:
                            session.currentRole
                                .canAccessControlCenter
                    )

                    CommunityV4SocialSnapshot(
                        followers:
                            social.followerCount,
                        following:
                            social.followingCount,
                        mutuals:
                            mutuals.count,
                        online:
                            onlineFollowing.count,
                        live:
                            visibleCircleLiveSessions.count
                    )

                    peopleNowSection

                    if attentionCount > 0 {
                        CommunityV4AttentionCard(
                            unreadMessages:
                                messaging.unreadCount,
                            messageRequests:
                                messaging.messageRequestCount,
                            followRequests:
                                social.incomingRequests.count,
                            workoutInvites:
                                social.workoutInvites.count,
                            challengeInvites:
                                challengeInvites.count,
                            clubInvites:
                                groups.ownInvites.count
                        )
                    }

                    weeklyChallengeSection
                    friendsVsFriendsSection
                    recentCircleSection

                    CommunityV4SocialWorld(
                        clubCount:
                            groups.joinedGroups.count,
                        eventCount:
                            socialEventCount,
                        challengeCount:
                            activeChallenges.count +
                            (
                                officialChallenges
                                    .activeChallenge == nil
                                    ? 0
                                    : 1
                            ),
                        nextEvent:
                            community
                                .upcomingEvents
                                .first,
                        latestClubActivity:
                            groups
                                .communityActivity
                                .first,
                        latestClubName:
                            groups
                                .communityActivity
                                .first
                                .flatMap {
                                    groups.group(
                                        for:
                                            $0.groupID
                                    )?
                                    .name
                                }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 34)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(
                ATHLTHPremiumCanvas(
                    accent:
                        Color.indigo
                            .opacity(0.12)
                )
            )
            .toolbar(.hidden, for: .navigationBar)
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
                        set: { shown in
                            if !shown {
                                refreshError = nil
                            }
                        }
                    )
            ) {
                Button("OK", role: .cancel) {
                    refreshError = nil
                }
            } message: {
                Text(refreshError ?? "")
            }
        }
    }

    private var peopleNowSection: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            CommunityV4SectionHeader(
                eyebrow: "YOUR PEOPLE",
                title: "People now",
                subtitle:
                    "Following, online status and live training in one place.",
                destinationTitle: "Find people",
                destination: {
                    AnyView(
                        SocialHubView(
                            initialTab: .discover
                        )
                    )
                }
            )

            if social.following.isEmpty {
                NavigationLink {
                    SocialHubView(
                        initialTab: .discover
                    )
                } label: {
                    CommunityV4EmptyPeopleCard()
                }
                .buttonStyle(.plain)
            } else {
                CommunityV4PeopleStrip(
                    people:
                        sortedPeopleNow,
                    liveSessions:
                        visibleCircleLiveSessions
                )

                if !visibleCircleLiveSessions.isEmpty {
                    VStack(spacing: 9) {
                        ForEach(
                            visibleCircleLiveSessions
                                .prefix(2)
                        ) { live in
                            NavigationLink {
                                ATHLTHLiveWorkoutMapView(
                                    session: live
                                )
                            } label: {
                                CommunityV4LiveWorkoutRow(
                                    session: live,
                                    profile:
                                        profile(
                                            for:
                                                live.ownerID
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var sortedPeopleNow:
        [SocialProfileCard] {
        social.following.sorted { left, right in
            let leftLive =
                visibleCircleLiveSessions
                    .contains {
                        $0.ownerID ==
                            left.userID
                    }
            let rightLive =
                visibleCircleLiveSessions
                    .contains {
                        $0.ownerID ==
                            right.userID
                    }

            if leftLive != rightLive {
                return leftLive
            }

            let leftOnline =
                realtime.isOnline(
                    left.userID
                )
            let rightOnline =
                realtime.isOnline(
                    right.userID
                )

            if leftOnline != rightOnline {
                return leftOnline
            }

            return left.resolvedName
                .localizedCaseInsensitiveCompare(
                    right.resolvedName
                ) == .orderedAscending
        }
    }

    private var weeklyChallengeSection:
        some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            CommunityV4SectionHeader(
                eyebrow: "THIS WEEK",
                title: "Weekly Challenge",
                subtitle:
                    "One shared target for the whole ATHLTH community.",
                destinationTitle: "Challenges",
                destination: {
                    AnyView(
                        ChallengeHubView()
                    )
                }
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
                        social.visibleProfiles
                )
            } else {
                NavigationLink {
                    ChallengeHubView()
                } label: {
                    CommunityV4EmptyWeeklyCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var friendsVsFriendsSection:
        some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            CommunityV4SectionHeader(
                eyebrow: "HEAD TO HEAD",
                title: "Friends vs Friends",
                subtitle:
                    "Mutual follows compared by running distance over the last seven days.",
                destinationTitle: "Following",
                destination: {
                    AnyView(
                        SocialHubView(
                            initialTab: .friends
                        )
                    )
                }
            )

            CommunityFriendsVsFriendsCard(
                currentUserID:
                    session.profile.userID,
                currentDisplayName:
                    session.profile.displayName,
                currentAvatarURL:
                    session.profile.avatarURL,
                friends: mutuals,
                feed: social.feed,
                ownWorkouts: health.workouts
            )
        }
    }

    private var recentCircleSection:
        some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            CommunityV4SectionHeader(
                eyebrow: "FROM YOUR CIRCLE",
                title: "Recent activity",
                subtitle:
                    "The latest shared training from athletes you follow.",
                destinationTitle: "See all",
                destination: {
                    AnyView(
                        SocialHubView(
                            initialTab: .feed
                        )
                    )
                }
            )

            if circleFeed.isEmpty {
                CommunityV4EmptyActivityCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        Array(
                            circleFeed
                                .prefix(4)
                        )
                    ) { item in
                        NavigationLink {
                            FriendProfileView(
                                userID:
                                    item.actor
                                        .userID
                            )
                        } label: {
                            CommunityV4ActivityRow(
                                item: item,
                                isOnline:
                                    realtime
                                        .isOnline(
                                            item.actor
                                                .userID
                                        )
                            )
                        }
                        .buttonStyle(.plain)

                        if item.id !=
                            circleFeed
                                .prefix(4)
                                .last?
                                .id {
                            Divider()
                                .padding(
                                    .leading,
                                    64
                                )
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(
                    Color.white.opacity(0.86),
                    in:
                        RoundedRectangle(
                            cornerRadius: 24,
                            style: .continuous
                        )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 24,
                        style: .continuous
                    )
                    .stroke(
                        Color.white.opacity(0.94),
                        lineWidth: 0.8
                    )
                }
            }
        }
    }

    private func profile(
        for userID: UUID
    ) -> SocialProfileCard? {
        social.visibleProfiles.first {
            $0.userID == userID
        } ??
        social.following.first {
            $0.userID == userID
        } ??
        social.followers.first {
            $0.userID == userID
        }
    }

    @MainActor
    private func refreshCommunity(
        force: Bool = false
    ) async {
        let performanceID =
            ATHLTHPerformance.begin(
                "CommunityV4Refresh"
            )

        defer {
            ATHLTHPerformance.end(
                "CommunityV4Refresh",
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
                : social.refreshIfStale(
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
        async let messageRefresh: Void =
            messaging.refresh()
        async let onlineRefresh: Void =
            realtime.refreshOnlineUsers()
        async let liveRefresh: Void =
            realtime
                .refreshVisibleLiveSessions()

        _ = await (
            eventRefresh,
            socialRefresh,
            groupRefresh,
            weeklyRefresh,
            messageRefresh,
            onlineRefresh,
            liveRefresh
        )

        await groups.refreshCalendarContent()

        await officialChallenges
            .syncCompletionState(
                workouts: health.workouts
            )

        challenges.refreshStatuses()

        refreshError =
            social.errorMessage ??
            messaging.errorMessage ??
            community.errorMessage ??
            groups.errorMessage ??
            officialChallenges.errorMessage ??
            realtime.errorMessage
    }
}

// MARK: - Header

private struct CommunityV4Header: View {
    let unreadMessages: Int
    let attentionCount: Int
    let canManageWeekly: Bool

    var body: some View {
        HStack(
            alignment: .top,
            spacing: 14
        ) {
            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text("COMMUNITY")
                    .font(
                        .caption2.weight(
                            .bold
                        )
                    )
                    .tracking(1.9)
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                            .opacity(0.54)
                    )

                Text("Your social world.")
                    .font(
                        .system(
                            size: 32,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                Text(
                    "People, training, messages, clubs, events and competition — without turning Community into an endless feed."
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

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                NavigationLink {
                    SocialHubView(
                        initialTab: .discover
                    )
                } label: {
                    headerButton(
                        icon:
                            "person.badge.plus"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Find people"
                )

                NavigationLink {
                    MessageInboxDestinationView()
                } label: {
                    ZStack(
                        alignment: .topTrailing
                    ) {
                        headerButton(
                            icon:
                                unreadMessages > 0
                                ? "bubble.left.and.bubble.right.fill"
                                : "bubble.left.and.bubble.right"
                        )

                        if unreadMessages > 0 {
                            badge(
                                unreadMessages
                            )
                            .offset(
                                x: 4,
                                y: -4
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    unreadMessages > 0
                        ? "Messages, \(unreadMessages) unread"
                        : "Messages"
                )

                if canManageWeekly {
                    NavigationLink {
                        OfficialWeeklyChallengeAdminListView()
                    } label: {
                        headerButton(
                            icon:
                                "slider.horizontal.3"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "Manage weekly challenges"
                    )
                }
            }
        }
    }

    private func headerButton(
        icon: String
    ) -> some View {
        Image(systemName: icon)
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
                width: 40,
                height: 40
            )
            .background(
                Color.white.opacity(0.90),
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(
                        Color.black
                            .opacity(0.055),
                        lineWidth: 0.8
                    )
            }
    }

    private func badge(
        _ value: Int
    ) -> some View {
        Text(
            value > 99
                ? "99+"
                : "\(value)"
        )
        .font(
            .system(
                size: 8,
                weight: .bold
            )
        )
        .foregroundStyle(.white)
        .frame(
            minWidth: 15,
            minHeight: 15
        )
        .padding(
            .horizontal,
            value > 9 ? 2 : 0
        )
        .background(
            Color.red,
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    Color.white,
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Social snapshot

private struct CommunityV4SocialSnapshot: View {
    let followers: Int
    let following: Int
    let mutuals: Int
    let online: Int
    let live: Int

    private var summary: String {
        if live > 0 {
            return live == 1
                ? "Someone in your circle is training live right now."
                : "\(live) people in your circle are training live right now."
        }

        if online > 0 {
            return online == 1
                ? "1 person you follow is online."
                : "\(online) people you follow are online."
        }

        if following > 0 {
            return "Your circle is quiet right now. Recent activity is waiting below."
        }

        return "Follow athletes to build your training circle."
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 17
        ) {
            HStack(
                alignment: .center,
                spacing: 12
            ) {
                ZStack {
                    Circle()
                        .fill(
                            Color.white
                                .opacity(0.14)
                        )

                    Image(
                        systemName:
                            live > 0
                                ? "dot.radiowaves.left.and.right"
                                : "person.2.fill"
                    )
                    .font(
                        .system(
                            size: 19,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.white)
                }
                .frame(
                    width: 46,
                    height: 46
                )

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text("SOCIAL SNAPSHOT")
                        .font(
                            .caption2.weight(
                                .bold
                            )
                        )
                        .tracking(1.4)
                        .foregroundStyle(
                            Color.white
                                .opacity(0.58)
                        )

                    Text(summary)
                        .font(
                            .subheadline
                                .weight(
                                    .semibold
                                )
                        )
                        .foregroundStyle(.white)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }

                Spacer()
            }

            HStack(spacing: 8) {
                NavigationLink {
                    ProfileFollowListView(
                        mode: .followers
                    )
                } label: {
                    metric(
                        followers,
                        "Followers"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ProfileFollowListView(
                        mode: .following
                    )
                } label: {
                    metric(
                        following,
                        "Following"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SocialHubView(
                        initialTab: .friends
                    )
                } label: {
                    metric(
                        mutuals,
                        "Mutual"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SocialHubView(
                        initialTab: .friends
                    )
                } label: {
                    metric(
                        online,
                        "Online"
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color(
                        red: 0.08,
                        green: 0.10,
                        blue: 0.16
                    ),
                    ATHLTHTheme
                        .accentDeep
                        .opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.10),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                ATHLTHTheme
                    .accentDeep
                    .opacity(0.13),
            radius: 18,
            y: 8
        )
    }

    private func metric(
        _ value: Int,
        _ label: String
    ) -> some View {
        VStack(spacing: 2) {
            Text(value.formatted())
                .font(
                    .headline.weight(
                        .bold
                    )
                )
                .monospacedDigit()
                .foregroundStyle(.white)

            Text(label)
                .font(.caption2)
                .foregroundStyle(
                    Color.white
                        .opacity(0.58)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            Color.white.opacity(0.09),
            in:
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
        )
    }
}

// MARK: - People now

private struct CommunityV4PeopleStrip: View {
    @EnvironmentObject private var realtime:
        ATHLTHRealtimeSocialStore

    let people: [SocialProfileCard]
    let liveSessions:
        [ATHLTHLiveWorkoutSession]

    var body: some View {
        ScrollView(
            .horizontal,
            showsIndicators: false
        ) {
            HStack(spacing: 14) {
                ForEach(
                    people.prefix(10)
                ) { person in
                    NavigationLink {
                        FriendProfileView(
                            userID:
                                person.userID
                        )
                    } label: {
                        VStack(spacing: 7) {
                            ZStack(
                                alignment:
                                    .bottomTrailing
                            ) {
                                CommunityV4Avatar(
                                    profile:
                                        person,
                                    size: 58,
                                    isOnline:
                                        realtime
                                            .isOnline(
                                                person
                                                    .userID
                                            )
                                )

                                if liveSessions
                                    .contains(
                                        where: {
                                            $0.ownerID ==
                                                person
                                                    .userID
                                        }
                                    ) {
                                    Image(
                                        systemName:
                                            "figure.run"
                                    )
                                    .font(
                                        .system(
                                            size: 9,
                                            weight:
                                                .bold
                                        )
                                    )
                                    .foregroundStyle(
                                        .white
                                    )
                                    .frame(
                                        width: 22,
                                        height: 22
                                    )
                                    .background(
                                        ATHLTHTheme
                                            .vitality,
                                        in: Circle()
                                    )
                                    .overlay {
                                        Circle()
                                            .stroke(
                                                .white,
                                                lineWidth:
                                                    2
                                            )
                                    }
                                }
                            }

                            Text(
                                firstName(
                                    person
                                        .resolvedName
                                )
                            )
                            .font(
                                .caption.weight(
                                    .semibold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .lineLimit(1)
                            .frame(width: 70)

                            Text(
                                liveSessions
                                    .contains(
                                        where: {
                                            $0.ownerID ==
                                                person
                                                    .userID
                                        }
                                    )
                                    ? "Training"
                                    : realtime
                                        .isOnline(
                                            person
                                                .userID
                                        )
                                        ? "Online"
                                        : "Following"
                            )
                            .font(.caption2)
                            .foregroundStyle(
                                liveSessions
                                    .contains(
                                        where: {
                                            $0.ownerID ==
                                                person
                                                    .userID
                                        }
                                    )
                                    ? ATHLTHTheme
                                        .vitality
                                    : ATHLTHTheme
                                        .mutedText
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func firstName(
        _ value: String
    ) -> String {
        value.split(separator: " ")
            .first
            .map(String.init) ??
        value
    }
}

private struct CommunityV4LiveWorkoutRow: View {
    let session: ATHLTHLiveWorkoutSession
    let profile: SocialProfileCard?

    var body: some View {
        HStack(spacing: 12) {
            if let profile {
                CommunityV4Avatar(
                    profile: profile,
                    size: 42,
                    isOnline: true
                )
            } else {
                Image(
                    systemName: "figure.run"
                )
                .font(
                    .system(
                        size: 17,
                        weight: .semibold
                    )
                )
                .foregroundStyle(.white)
                .frame(
                    width: 42,
                    height: 42
                )
                .background(
                    ATHLTHTheme.vitality,
                    in: Circle()
                )
            }

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                HStack(spacing: 6) {
                    Text(
                        profile?
                            .resolvedName ??
                        "ATHLTH athlete"
                    )
                    .font(
                        .subheadline
                            .weight(.bold)
                    )

                    Text("LIVE")
                        .font(
                            .system(
                                size: 8,
                                weight: .bold
                            )
                        )
                        .tracking(1.0)
                        .foregroundStyle(
                            ATHLTHTheme
                                .vitality
                        )
                }

                Text(session.title)
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 5) {
                Text("Watch")
                Image(
                    systemName:
                        "chevron.right"
                )
            }
            .font(
                .caption.weight(
                    .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme
                    .accentDeep
            )
        }
        .padding(13)
        .background(
            Color.white.opacity(0.84),
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
                ATHLTHTheme.vitality
                    .opacity(0.12),
                lineWidth: 0.8
            )
        }
    }
}

private struct CommunityV4EmptyPeopleCard: View {
    var body: some View {
        HStack(spacing: 13) {
            Image(
                systemName:
                    "person.2.badge.plus"
            )
            .font(.title2)
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )
            .frame(
                width: 48,
                height: 48
            )
            .background(
                ATHLTHTheme.accentSoft,
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
                Text("Build your circle")
                    .font(.headline)
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                Text(
                    "Follow athletes to see training, compete and connect."
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()

            Image(
                systemName:
                    "chevron.right"
            )
            .font(.caption.bold())
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )
        }
        .padding(16)
        .background(
            Color.white.opacity(0.88),
            in:
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
        )
    }
}

// MARK: - Attention

private struct CommunityV4AttentionCard: View {
    let unreadMessages: Int
    let messageRequests: Int
    let followRequests: Int
    let workoutInvites: Int
    let challengeInvites: Int
    let clubInvites: Int

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text("NEEDS ATTENTION")
                        .font(
                            .caption2.weight(
                                .bold
                            )
                        )
                        .tracking(1.6)
                        .foregroundStyle(
                            Color.orange
                        )

                    Text("Social inbox")
                        .font(
                            .title3.weight(
                                .bold
                            )
                        )
                }

                Spacer()

                Text(
                    total.formatted()
                )
                .font(
                    .headline.weight(
                        .bold
                    )
                )
                .foregroundStyle(
                    Color.orange
                )
                .frame(
                    minWidth: 34,
                    minHeight: 34
                )
                .background(
                    Color.orange
                        .opacity(0.10),
                    in: Circle()
                )
            }

            if unreadMessages > 0 ||
                messageRequests > 0 {
                NavigationLink {
                    MessageInboxDestinationView()
                } label: {
                    attentionRow(
                        title: "Messages",
                        detail:
                            messageDetail,
                        icon:
                            "bubble.left.and.bubble.right.fill",
                        count:
                            unreadMessages +
                            messageRequests
                    )
                }
                .buttonStyle(.plain)
            }

            if followRequests > 0 ||
                workoutInvites > 0 {
                NavigationLink {
                    SocialHubView(
                        initialTab: .requests
                    )
                } label: {
                    attentionRow(
                        title: "Social requests",
                        detail:
                            socialRequestDetail,
                        icon:
                            "person.crop.circle.badge.plus",
                        count:
                            followRequests +
                            workoutInvites
                    )
                }
                .buttonStyle(.plain)
            }

            if challengeInvites > 0 {
                NavigationLink {
                    ChallengeHubView()
                } label: {
                    attentionRow(
                        title:
                            "Challenge invites",
                        detail:
                            "Respond to people who challenged you.",
                        icon:
                            "trophy.fill",
                        count:
                            challengeInvites
                    )
                }
                .buttonStyle(.plain)
            }

            if clubInvites > 0 {
                NavigationLink {
                    CommunityGroupsView()
                } label: {
                    attentionRow(
                        title: "Club invites",
                        detail:
                            "New invitations to join a Club.",
                        icon:
                            "person.3.fill",
                        count:
                            clubInvites
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(17)
        .background(
            LinearGradient(
                colors: [
                    Color.orange
                        .opacity(0.055),
                    Color.white
                        .opacity(0.93)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 25,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 25,
                style: .continuous
            )
            .stroke(
                Color.orange
                    .opacity(0.12),
                lineWidth: 0.8
            )
        }
    }

    private var total: Int {
        unreadMessages +
        messageRequests +
        followRequests +
        workoutInvites +
        challengeInvites +
        clubInvites
    }

    private var messageDetail: String {
        var parts: [String] = []

        if unreadMessages > 0 {
            parts.append(
                "\(unreadMessages) unread"
            )
        }

        if messageRequests > 0 {
            parts.append(
                "\(messageRequests) request\(messageRequests == 1 ? "" : "s")"
            )
        }

        return parts.joined(
            separator: " · "
        )
    }

    private var socialRequestDetail:
        String {
        var parts: [String] = []

        if followRequests > 0 {
            parts.append(
                "\(followRequests) follow request\(followRequests == 1 ? "" : "s")"
            )
        }

        if workoutInvites > 0 {
            parts.append(
                "\(workoutInvites) workout invite\(workoutInvites == 1 ? "" : "s")"
            )
        }

        return parts.joined(
            separator: " · "
        )
    }

    private func attentionRow(
        title: String,
        detail: String,
        icon: String,
        count: Int
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 16,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(
                    width: 38,
                    height: 38
                )
                .background(
                    ATHLTHTheme.accentSoft,
                    in:
                        RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(title)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(1)
            }

            Spacer()

            Text(count.formatted())
                .font(
                    .caption.weight(
                        .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )

            Image(
                systemName:
                    "chevron.right"
            )
            .font(.caption2.bold())
            .foregroundStyle(.tertiary)
        }
        .padding(11)
        .background(
            Color.white.opacity(0.72),
            in:
                RoundedRectangle(
                    cornerRadius: 17,
                    style: .continuous
                )
        )
    }
}

// MARK: - Recent activity

private struct CommunityV4ActivityRow: View {
    let item: SocialFeedItem
    let isOnline: Bool

    var body: some View {
        HStack(
            alignment: .center,
            spacing: 12
        ) {
            CommunityV4Avatar(
                profile: item.actor,
                size: 44,
                isOnline: isOnline
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    item.actor.resolvedName
                )
                .font(
                    .subheadline.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .lineLimit(1)

                Text(item.activity.title)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(1)

                if let subtitle =
                    item.activity.subtitle,
                   !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                                .opacity(0.82)
                        )
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(
                alignment: .trailing,
                spacing: 4
            ) {
                Text(
                    item.activity
                        .createdAt,
                    style: .relative
                )
                .font(.caption2)
                .foregroundStyle(
                    .tertiary
                )

                if !item.reactions.isEmpty {
                    Label(
                        "\(item.reactions.count)",
                        systemImage:
                            "hand.thumbsup.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                }
            }
        }
        .padding(.vertical, 12)
    }
}

private struct CommunityV4EmptyActivityCard: View {
    var body: some View {
        HStack(spacing: 13) {
            Image(
                systemName:
                    "waveform.path.ecg"
            )
            .font(.title2)
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )
            .frame(
                width: 48,
                height: 48
            )
            .background(
                ATHLTHTheme.accentSoft,
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
                Text("Nothing shared yet")
                    .font(.headline)

                Text(
                    "Shared workouts from people you follow will appear here."
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()
        }
        .padding(16)
        .background(
            Color.white.opacity(0.86),
            in:
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
        )
    }
}

// MARK: - Social world

private struct CommunityV4SocialWorld: View {
    let clubCount: Int
    let eventCount: Int
    let challengeCount: Int
    let nextEvent: CommunityEventItem?
    let latestClubActivity:
        CommunityGroupActivityRecord?
    let latestClubName: String?

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            CommunityV4SectionHeader(
                eyebrow: "YOUR SOCIAL WORLD",
                title: "Everything connected",
                subtitle:
                    "Clubs, events and challenges stay available without crowding the main overview.",
                destinationTitle: nil,
                destination: nil
            )

            HStack(spacing: 9) {
                NavigationLink {
                    CommunityGroupsView()
                } label: {
                    tile(
                        title: "Clubs",
                        value: clubCount,
                        icon:
                            "person.3.fill",
                        tint: .indigo
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    CommunityEventsView()
                } label: {
                    tile(
                        title: "Events",
                        value: eventCount,
                        icon:
                            "calendar.badge.clock",
                        tint: .purple
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ChallengeHubView()
                } label: {
                    tile(
                        title:
                            "Challenges",
                        value:
                            challengeCount,
                        icon:
                            "trophy.fill",
                        tint: .orange
                    )
                }
                .buttonStyle(.plain)
            }

            if let nextEvent {
                NavigationLink {
                    CommunityEventDetailView(
                        eventID:
                            nextEvent.id
                    )
                } label: {
                    HStack(spacing: 12) {
                        VStack(spacing: 1) {
                            Text(
                                nextEvent
                                    .event
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
                                    size: 8,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                .purple
                            )

                            Text(
                                nextEvent
                                    .event
                                    .startsAt
                                    .formatted(
                                        .dateTime
                                            .day()
                                    )
                            )
                            .font(
                                .title3
                                    .weight(
                                        .bold
                                    )
                            )
                        }
                        .frame(
                            width: 42,
                            height: 48
                        )
                        .background(
                            Color.purple
                                .opacity(0.08),
                            in:
                                RoundedRectangle(
                                    cornerRadius:
                                        12,
                                    style:
                                        .continuous
                                )
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text("NEXT EVENT")
                                .font(
                                    .system(
                                        size: 8,
                                        weight:
                                            .bold
                                    )
                                )
                                .tracking(1.2)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )

                            Text(
                                nextEvent
                                    .event
                                    .title
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .lineLimit(1)

                            Text(
                                nextEvent
                                    .event
                                    .startsAt
                                    .formatted(
                                        date:
                                            .omitted,
                                        time:
                                            .shortened
                                    ) +
                                " · " +
                                nextEvent
                                    .event
                                    .meetingName
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
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
                    .padding(13)
                    .background(
                        Color.white.opacity(
                            0.84
                        ),
                        in:
                            RoundedRectangle(
                                cornerRadius: 19,
                                style:
                                    .continuous
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            if let latestClubActivity {
                NavigationLink {
                    CommunityGroupsView()
                } label: {
                    HStack(spacing: 12) {
                        Image(
                            systemName:
                                "person.3.fill"
                        )
                        .font(
                            .system(
                                size: 16,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            .indigo
                        )
                        .frame(
                            width: 42,
                            height: 42
                        )
                        .background(
                            Color.indigo
                                .opacity(0.08),
                            in:
                                RoundedRectangle(
                                    cornerRadius:
                                        13,
                                    style:
                                        .continuous
                                )
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text(
                                (
                                    latestClubName ??
                                    "Club activity"
                                )
                                .uppercased()
                            )
                            .font(
                                .system(
                                    size: 8,
                                    weight: .bold
                                )
                            )
                            .tracking(1.1)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )

                            Text(
                                latestClubActivity
                                    .headline
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .lineLimit(1)

                            Text(
                                latestClubActivity
                                    .createdAt,
                                style: .relative
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
                            .tertiary
                        )
                    }
                    .padding(13)
                    .background(
                        Color.white.opacity(
                            0.84
                        ),
                        in:
                            RoundedRectangle(
                                cornerRadius: 19,
                                style:
                                    .continuous
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tile(
        title: String,
        value: Int,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 16,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(tint)

                Spacer()

                Image(
                    systemName:
                        "arrow.up.right"
                )
                .font(.caption2.bold())
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
            }

            Text(value.formatted())
                .font(
                    .title3.weight(
                        .bold
                    )
                )
                .monospacedDigit()
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )

            Text(title)
                .font(
                    .caption.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(13)
        .frame(
            maxWidth: .infinity,
            minHeight: 108,
            alignment: .leading
        )
        .background(
            Color.white.opacity(0.88),
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
                tint.opacity(0.09),
                lineWidth: 0.8
            )
        }
    }
}

// MARK: - Shared presentation

private struct CommunityV4SectionHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let destinationTitle: String?
    let destination: (() -> AnyView)?

    var body: some View {
        HStack(
            alignment: .bottom,
            spacing: 12
        ) {
            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(eyebrow)
                    .font(
                        .caption2.weight(
                            .bold
                        )
                    )
                    .tracking(1.5)
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                            .opacity(0.55)
                    )

                Text(title)
                    .font(
                        .title3.weight(
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
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }

            Spacer(minLength: 6)

            if let destinationTitle,
               let destination {
                NavigationLink {
                    destination()
                } label: {
                    HStack(spacing: 4) {
                        Text(
                            destinationTitle
                        )
                        Image(
                            systemName:
                                "chevron.right"
                        )
                    }
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CommunityV4Avatar: View {
    let profile: SocialProfileCard
    let size: CGFloat
    let isOnline: Bool

    var body: some View {
        Group {
            if let raw =
                    profile.avatarURL,
               let url = URL(
                    string: raw
               ) {
                AsyncImage(
                    url: url
                ) { phase in
                    switch phase {
                    case .success(
                        let image
                    ):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(
            width: size,
            height: size
        )
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(
                    isOnline
                        ? ATHLTHTheme
                            .vitality
                        : Color.black
                            .opacity(0.06),
                    lineWidth:
                        isOnline
                            ? 2.2
                            : 1
                )
        }
    }

    private var placeholder:
        some View {
        Circle()
            .fill(
                ATHLTHTheme
                    .accentSoft
            )
            .overlay {
                Text(initials)
                    .font(
                        .system(
                            size:
                                size * 0.28,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
            }
    }

    private var initials: String {
        let parts =
            profile.resolvedName
                .split(separator: " ")
        let values =
            parts.prefix(2)
                .compactMap {
                    $0.first
                }
        let result =
            String(values)

        return result.isEmpty
            ? "A"
            : result.uppercased()
    }
}

private struct CommunityV4EmptyWeeklyCard: View {
    var body: some View {
        HStack(spacing: 14) {
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
                spacing: 4
            ) {
                Text(
                    "No weekly challenge yet"
                )
                .font(.headline)
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )

                Text(
                    "Open Challenges to see what is available."
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
                    "chevron.right"
            )
            .font(.caption.bold())
            .foregroundStyle(
                .tertiary
            )
        }
        .padding(16)
        .background(
            Color.white.opacity(0.88),
            in:
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
        )
    }
}
