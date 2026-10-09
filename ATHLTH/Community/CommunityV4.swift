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
    @State private var showingPeopleSearch = false
    @State private var peopleSearchText = ""
    @State private var searchingPeople = false
    @FocusState private var peopleSearchFocused: Bool

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

    private var joinedUpcomingEvents:
        [CommunityEventItem] {
        func belongsToCurrentUser(
            _ item: CommunityEventItem
        ) -> Bool {
            item.event.creatorID ==
                session.profile.userID ||
            item.participantRows.contains {
                $0.userID ==
                    session.profile.userID &&
                (
                    $0.attendanceStatus == .going ||
                    $0.attendanceStatus == .maybe
                )
            }
        }

        let live =
            community.upcomingEvents
                .filter {
                    $0.event.status ==
                        "live" &&
                    belongsToCurrentUser($0)
                }

        let recentlyCompleted =
            community
                .recentlyCompletedEvents
                .filter(
                    belongsToCurrentUser
                )

        let upcoming =
            community.upcomingEvents
                .filter {
                    $0.event.status !=
                        "live" &&
                    belongsToCurrentUser($0)
                }

        return live +
            recentlyCompleted +
            upcoming
    }

    private var joinedUpcomingChallenges:
        [ATHLTHChallenge] {
        activeChallenges.filter {
            $0.status == .active ||
            $0.status == .upcoming
        }
    }

    private var discoveryGroups:
        [CommunityGroupRecord] {
        let joined = groups.groups.filter {
            groups.joinedGroupIDs.contains($0.id)
        }
        let publicUnjoined = publicDiscoveryGroups

        return Array(
            (joined + publicUnjoined)
                .reduce(
                    into: [CommunityGroupRecord]()
                ) { result, group in
                    if !result.contains(
                        where: { $0.id == group.id }
                    ) {
                        result.append(group)
                    }
                }
                .prefix(5)
        )
    }

    private var publicDiscoveryGroups:
        [CommunityGroupRecord] {
        groups.groups.filter {
            $0.visibility == "public" &&
            !groups.joinedGroupIDs.contains($0.id) &&
            groups.pendingInvite(for: $0.id) == nil
        }
    }

    private var publicDiscoveryEvents:
        [CommunityEventItem] {
        community.upcomingEvents.filter { item in
            guard item.event.visibility ==
                    ProfileVisibility
                        .publicProfile
                        .rawValue
            else {
                return false
            }

            return item.event.creatorID !=
                    session.profile.userID &&
                !item.participantRows.contains {
                    $0.userID ==
                        session.profile.userID
                }
        }
    }

    private var publicDiscoveryChallenges:
        [ATHLTHChallenge] {
        challenges.visibleChallenges.filter { challenge in
            guard challenge.visibility ==
                    .publicProfile,
                  challenge.status == .active ||
                    challenge.status == .upcoming
            else {
                return false
            }

            return !challenge.participants.contains {
                $0.userID ==
                    session.profile.userID
            }
        }
    }


    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    if showingPeopleSearch {
                        communityPeopleSearch
                    }

                    CommunityReferenceHeader(
                        canManageWeekly:
                            session.currentRole
                                .canAccessControlCenter
                    )

                    if let refreshError {
                        communityRefreshNotice(
                            message: refreshError
                        )
                        .transition(
                            .opacity.combined(
                                with:
                                    .move(
                                        edge: .top
                                    )
                            )
                        )
                    }

                    referenceWeeklyChallengeSection
                    referenceFriendsVsFriendsSection

                    CommunityReferenceQuickActions()

                    referenceRecentActivitySection
                    referenceUpcomingSection
                    referenceDiscoverySection
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 30)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top < -55
            } action: { _, pulledDown in
                if pulledDown && !showingPeopleSearch {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingPeopleSearch = true
                    }
                }
            }
            .task(id: peopleSearchText) {
                let query = peopleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard query.count >= 2 else {
                    searchingPeople = false
                    social.clearSearch()
                    return
                }
                searchingPeople = true
                do {
                    try await Task.sleep(for: .milliseconds(300))
                } catch { return }
                await social.search(query)
                guard !Task.isCancelled else { return }
                searchingPeople = false
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .background(
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHTheme.champagneSoft
                            .opacity(0.16)
                )
            )
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await refreshCommunity(force: true)
            }
            .task {
                await refreshCommunity()
            }
        }
    }

    private var communityPeopleSearch: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                TextField(
                    ATHLTHLocalization.choose(
                        english: "Search people or @username",
                        norwegian: "Søk etter personer eller @brukernavn"
                    ),
                    text: $peopleSearchText
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($peopleSearchFocused)
                if searchingPeople {
                    ProgressView().controlSize(.small)
                }
                Button {
                    peopleSearchFocused = false
                    peopleSearchText = ""
                    social.clearSearch()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingPeopleSearch = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Close search", norwegian: "Lukk søk"
                ))
            }
            .padding(13)
            .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 17))

            if peopleSearchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                if !searchingPeople, let error = social.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                } else if !searchingPeople && social.discoverResults.isEmpty {
                    Text(ATHLTHLocalization.choose(
                        english: "No matching users.", norwegian: "Ingen brukere funnet."
                    ))
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                if !searchingPeople {
                    ForEach(social.discoverResults) { profile in
                        NavigationLink {
                            FriendProfileView(userID: profile.userID)
                        } label: {
                            HStack(spacing: 12) {
                                SocialAvatar(profile: profile, size: 40)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(profile.resolvedName).font(.subheadline.weight(.semibold))
                                    if let username = profile.username, !username.isEmpty {
                                        Text("@\(username)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .padding(12)
                            .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 17))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func communityRefreshNotice(
        message: String
    ) -> some View {
        HStack(
            alignment: .center,
            spacing: 10
        ) {
            Image(
                systemName:
                    "arrow.clockwise.circle.fill"
            )
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
                width: 34,
                height: 34
            )
            .background(
                ATHLTHTheme
                    .accentSoft
                    .opacity(0.82),
                in:
                    RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
            )

            Text(message)
                .font(
                    .system(
                        size: 11.5,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

            Spacer(
                minLength: 6
            )

            Button {
                Task {
                    await refreshCommunity(
                        force: true
                    )
                }
            } label: {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Retry",
                        norwegian: "Prøv igjen"
                    )
                )
                .font(
                    .system(
                        size: 11.5,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .padding(
                    .horizontal,
                    10
                )
                .frame(height: 32)
                .background(
                    Color.white.opacity(0.82),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
        }
        .padding(11)
        .background(
            ATHLTHTheme
                .accentSoft
                .opacity(0.42),
            in:
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .accentDeep
                    .opacity(0.08),
                lineWidth: 0.7
            )
        }
    }

    @ViewBuilder
    private var referenceWeeklyChallengeSection: some View {
        if let weekly =
            officialChallenges.activeChallenge ??
            officialChallenges.upcomingChallenges.first {
            NavigationLink {
                OfficialWeeklyChallengeDetailView(
                    challengeID: weekly.id
                )
            } label: {
                CommunityReferenceWeeklyChallengeCard(
                    challenge: weekly,
                    profiles: social.visibleProfiles
                )
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                ChallengeHubView()
            } label: {
                CommunityV4EmptyWeeklyCard()
            }
            .buttonStyle(.plain)
        }
    }

    private var referenceFriendsVsFriendsSection: some View {
        NavigationLink {
            CommunityFriendsVsFriendsDetailView(
                currentUserID: session.profile.userID,
                currentDisplayName: session.profile.displayName,
                currentAvatarURL: session.profile.avatarURL,
                friends: mutuals
            )
        } label: {
            CommunityReferenceFriendsCard(
                currentUserID: session.profile.userID,
                currentDisplayName: session.profile.displayName,
                currentAvatarURL: session.profile.avatarURL,
                friends: mutuals,
                feed: social.feed,
                ownWorkouts: health.workouts
            )
        }
        .buttonStyle(.plain)
    }

    private var referenceRecentActivitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommunityReferenceSectionTitle(
                title:
                    ATHLTHLocalization.choose(
                        english: "Recent activity",
                        norwegian: "Siste aktivitet"
                    ),
                destinationTitle:
                    ATHLTHLocalization.choose(
                        english: "See all",
                        norwegian: "Se alle"
                    ),
                destination: {
                    AnyView(
                        SocialHubView(initialTab: .feed)
                    )
                }
            )

            if circleFeed.isEmpty {
                CommunityReferenceEmptyActivityCard()
            } else {
                VStack(spacing: 8) {
                    ForEach(
                        Array(circleFeed.prefix(3))
                    ) { item in
                        NavigationLink {
                            socialDestination(for: item)
                        } label: {
                            CommunityReferenceActivityRow(
                                item: item,
                                isOnline:
                                    realtime.isOnline(
                                        item.actor.userID
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var referenceDiscoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CommunityReferenceSectionTitle(
                title: "Discovery",
                destinationTitle:
                    ATHLTHLocalization.choose(
                        english: "Explore",
                        norwegian: "Utforsk"
                    ),
                destination: {
                    AnyView(
                        CommunityDiscoveryView()
                    )
                }
            )

            discoveryGroupStrip
            discoveryEventChallengeStrip
        }
    }

    private var discoveryGroupStrip: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(
                ATHLTHLocalization.choose(
                    english: "Clubs",
                    norwegian: "Grupper"
                )
            )
            .font(.subheadline.weight(.bold))
            .foregroundStyle(ATHLTHTheme.primaryText)

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {
                // At most five Clubs: eager layout keeps the scroll strip
                // stable when a Club header image is refreshed.
                HStack(alignment: .top, spacing: 14) {
                    ForEach(discoveryGroups) { group in
                        NavigationLink {
                            CommunityGroupDetailView(
                                group: group
                            )
                        } label: {
                            CommunityDiscoveryClubCard(
                                group: group,
                                memberCount:
                                    groups.members(
                                        in: group.id
                                    ).count,
                                isJoined:
                                    groups
                                        .joinedGroupIDs
                                        .contains(
                                            group.id
                                        )
                            )
                            .frame(width: 252)
                        }
                        .buttonStyle(.plain)
                    }

                    if discoveryGroups.isEmpty {
                        CommunityDiscoveryVisualEmptyCard(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Discover Clubs",
                                    norwegian: "Oppdag Clubs"
                                ),
                            detail:
                                ATHLTHLocalization.choose(
                                    english: "Public Clubs will appear here.",
                                    norwegian: "Offentlige Clubs vises her."
                                ),
                            assetName:
                                "CommunityHero",
                            icon:
                                "person.3.fill"
                        )
                        .frame(width: 252)
                    }
                }
            }
        }
    }

    private var discoveryEventChallengeStrip: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(
                ATHLTHLocalization.choose(
                    english: "Events & challenges",
                    norwegian: "Events & challenges"
                )
            )
            .font(.subheadline.weight(.bold))
            .foregroundStyle(ATHLTHTheme.primaryText)

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {
                LazyHStack(spacing: 9) {
                    ForEach(
                        Array(
                            publicDiscoveryChallenges
                                .prefix(3)
                        )
                    ) { challenge in
                        NavigationLink {
                            ChallengeDetailView(
                                challengeID: challenge.id
                            )
                        } label: {
                            CommunityDiscoveryChallengeCard(
                                challenge: challenge,
                                creator:
                                    social.visibleProfiles
                                        .first {
                                            $0.userID ==
                                            challenge
                                                .creatorID
                                        }
                            )
                            .frame(width: 252)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(
                        Array(
                            publicDiscoveryEvents
                                .prefix(2)
                        )
                    ) { event in
                        NavigationLink {
                            CommunityEventDetailView(
                                eventID: event.id
                            )
                        } label: {
                            CommunityDiscoveryEventCard(
                                item: event
                            )
                            .frame(width: 252)
                        }
                        .buttonStyle(.plain)
                    }

                    if publicDiscoveryChallenges.isEmpty &&
                        publicDiscoveryEvents.isEmpty {
                        CommunityDiscoveryVisualEmptyCard(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Discover what's next",
                                    norwegian: "Oppdag det som skjer"
                                ),
                            detail:
                                ATHLTHLocalization.choose(
                                    english: "Public events and challenges will appear here.",
                                    norwegian: "Offentlige events og challenges vises her."
                                ),
                            assetName:
                                "GoalAdventureThumbnail",
                            icon:
                                "sparkles"
                        )
                        .frame(width: 252)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var referenceUpcomingSection: some View {
        if !joinedUpcomingEvents.isEmpty ||
            !joinedUpcomingChallenges.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                CommunityReferenceSectionTitle(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Upcoming",
                            norwegian: "Kommende"
                        ),
                    destinationTitle:
                        ATHLTHLocalization.choose(
                            english: "See all",
                            norwegian: "Se alle"
                        ),
                    destination: {
                        AnyView(
                            CommunityEventsView()
                        )
                    }
                )

                ScrollView(
                    .horizontal,
                    showsIndicators: false
                ) {
                    LazyHStack(spacing: 9) {
                        ForEach(
                            joinedUpcomingEvents
                                .prefix(3)
                        ) { event in
                            NavigationLink {
                                CommunityEventDetailView(
                                    eventID: event.id
                                )
                            } label: {
                                CommunityReferenceUpcomingEventCard(
                                    item: event
                                )
                                .frame(width: 252)
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(
                            joinedUpcomingChallenges
                                .prefix(3)
                        ) { challenge in
                            NavigationLink {
                                ChallengeDetailView(
                                    challengeID:
                                        challenge.id
                                )
                            } label: {
                                CommunityDiscoveryNowRow(
                                    eyebrow:
                                        ATHLTHLocalization.choose(
                                            english: "JOINED CHALLENGE",
                                            norwegian: "PÅMELDT CHALLENGE"
                                        ),
                                    title: challenge.title,
                                    detail: challenge.sport.title,
                                    icon:
                                        challenge.sport.systemImage,
                                    tint: .orange
                                )
                                .frame(width: 260)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
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
                        ProfileFollowListView(mode: .following)
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
                    "Workouts, events, challenges and milestones from people you follow.",
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
                VStack(spacing: 10) {
                    ForEach(
                        Array(
                            circleFeed
                                .prefix(5)
                        )
                    ) { item in
                        NavigationLink {
                            socialDestination(
                                for: item
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
                    }
                }
            }
        }
    }

    private func socialDestination(
        for item: SocialFeedItem
    ) -> AnyView {
        let metadata =
            item.activity.metadata ?? [:]

        if item.activity.kind == "event",
           let rawID = metadata["event_id"],
           let eventID = UUID(uuidString: rawID) {
            return AnyView(
                CommunityEventDetailView(
                    eventID: eventID
                )
            )
        }

        if item.activity.kind == "challenge",
           let rawID = metadata["challenge_id"],
           let challengeID = UUID(uuidString: rawID) {
            return AnyView(
                ChallengeDetailView(
                    challengeID:
                        challengeID
                )
            )
        }

        return AnyView(
            FriendProfileView(
                userID:
                    item.actor.userID
            )
        )
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

    private var hasUsableCommunityContent:
        Bool {
        officialChallenges.activeChallenge != nil ||
        !officialChallenges
            .upcomingChallenges
            .isEmpty ||
        !social.feed.isEmpty ||
        !social.following.isEmpty ||
        !social.followers.isEmpty ||
        !groups.joinedGroups.isEmpty ||
        !community.upcomingEvents.isEmpty
    }

    private func friendlyCommunityRefreshMessage(
        for rawError: String
    ) -> String {
        let normalized =
            rawError.lowercased()

        if normalized.contains(
            "timed out"
        ) ||
        normalized.contains(
            "timeout"
        ) ||
        normalized.contains(
            "tidsavbrudd"
        ) ||
        normalized.contains(
            "request timed"
        ) {
            return ATHLTHLocalization.choose(
                english:
                    "The connection took too long. Showing the latest available content.",
                norwegian:
                    "Tilkoblingen tok for lang tid. Viser sist tilgjengelige innhold."
            )
        }

        return ATHLTHLocalization.choose(
            english:
                "Some community data couldn't be updated. Showing the latest available content.",
            norwegian:
                "Noe innhold kunne ikke oppdateres. Viser sist tilgjengelige innhold."
        )
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
            messaging.refresh(force: force)
        async let onlineRefresh: Void =
            realtime.refreshOnlineUsers(
                force: force
            )
        async let liveRefresh: Void =
            realtime
                .refreshVisibleLiveSessions(
                    force: force
                )

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

        let rawRefreshError =
            social.errorMessage ??
            messaging.errorMessage ??
            community.errorMessage ??
            groups.errorMessage ??
            officialChallenges.errorMessage ??
            realtime.errorMessage

        if let rawRefreshError {
            // Background refreshes must never interrupt a Community page that
            // already has useful cached content. Pull-to-refresh can surface a
            // compact inline notice, but raw networking/system errors never
            // reach the user.
            if force ||
                !hasUsableCommunityContent {
                withAnimation(
                    .easeInOut(
                        duration: 0.18
                    )
                ) {
                    refreshError =
                        friendlyCommunityRefreshMessage(
                            for:
                                rawRefreshError
                        )
                }
            } else {
                refreshError = nil
            }
        } else {
            refreshError = nil
        }
    }
}

// MARK: - Reference Community Front Page

private struct CommunityReferenceHeader: View {
    let canManageWeekly: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Community")
                    .font(
                        .system(
                            size: 35,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Friends, clubs and challenges",
                        norwegian:
                            "Venner, klubber og challenges"
                    )
                )
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                if canManageWeekly {
                    NavigationLink {
                        OfficialWeeklyChallengeAdminListView()
                    } label: {
                        button(
                            icon: "slider.horizontal.3",
                            badge: 0
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 1)
    }

    private func button(
        icon: String,
        badge: Int
    ) -> some View {
        ZStack(alignment: .topTrailing) {
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
                .frame(width: 46, height: 46)
                .background(
                    Color.white.opacity(0.92),
                    in:
                        RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
                    .stroke(
                        Color.black.opacity(0.055),
                        lineWidth: 0.8
                    )
                }

            if badge > 0 {
                Text(
                    badge > 99
                        ? "99+"
                        : "\(badge)"
                )
                .font(
                    .system(
                        size: 9,
                        weight: .bold
                    )
                )
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minHeight: 18)
                .background(
                    Color.red,
                    in: Capsule()
                )
                .offset(x: 5, y: -5)
            }
        }
    }
}

private struct CommunityReferenceWeeklyChallengeCard: View {
    @EnvironmentObject private var store:
        OfficialWeeklyChallengeStore

    let challenge: OfficialWeeklyChallenge
    let profiles: [SocialProfileCard]

    private let premiumGold =
        Color(
            red: 0.82,
            green: 0.67,
            blue: 0.34
        )

    private var participantProfiles:
        [SocialProfileCard] {
        let ids =
            store.participantIDs(
                for: challenge.id
            )

        return ids.compactMap { id in
            profiles.first {
                $0.userID == id
            }
        }
    }

    private var daysRemaining: Int {
        max(
            Calendar.current
                .dateComponents(
                    [.day],
                    from: Date(),
                    to: challenge.endsAt
                )
                .day ?? 0,
            0
        )
    }

    private var targetText: String {
        challenge.kind
            .targetText(
                challenge.targetValue
            )
    }

    var body: some View {
        let appearance = challenge.resolvedAppearance
        let titleColor = Color(athlthHex: appearance.textColorHex)
        let secondaryColor = Color(athlthHex: appearance.secondaryTextColorHex)

        ZStack {
            OfficialWeeklyChallengeArtwork(
                challenge: challenge,
                preserveOriginalColors: appearance.preserveOriginalImageColors
            )

            // Protect text contrast within the photo, without floating text boxes.
            LinearGradient(
                colors: [
                    Color.black.opacity(0.47),
                    Color.black.opacity(0.20),
                    Color.black.opacity(0.02),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .allowsHitTesting(false)

            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.05),
                    Color.black.opacity(0.33)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            if appearance.showImageOverlay {
                Color.black.opacity(appearance.resolvedImageOverlayOpacity)
                    .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 0) {
                if appearance.showBadge {
                    HStack(spacing: 10) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(premiumGold)

                        Rectangle()
                            .fill(premiumGold.opacity(0.85))
                            .frame(width: 1, height: 18)

                        Text(
                            ATHLTHLocalization.choose(
                                english: "WEEKLY CHALLENGE",
                                norwegian: "UKENS CHALLENGE"
                            )
                        )
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.35)
                        .foregroundStyle(Color.white.opacity(0.97))
                    }
                    .shadow(color: Color.black.opacity(0.32), radius: 3, y: 1)
                }

                Spacer(minLength: 16)

                VStack(alignment: .leading, spacing: 6) {
                    Text(challenge.title)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(titleColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .shadow(
                            color: Color.black.opacity(
                                appearance.showTextShadow
                                    ? max(appearance.resolvedShadowOpacity, 0.46)
                                    : 0.24
                            ),
                            radius: appearance.showTextShadow ? 4 : 2,
                            y: 1.5
                        )

                    if appearance.showSubtitle {
                        Text(challenge.subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(secondaryColor)
                            .lineLimit(2)
                            .lineSpacing(1.5)
                            .truncationMode(.tail)
                            .shadow(color: .black.opacity(0.38), radius: 3, y: 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 14)

                HStack(alignment: .center, spacing: 10) {
                    if appearance.showMetadata {
                        Label(
                            ATHLTHLocalization.format(
                                english: "%d days left",
                                norwegian: "%d dager igjen",
                                daysRemaining
                            ),
                            systemImage: "clock.fill"
                        )
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.98))
                        .shadow(color: .black.opacity(0.40), radius: 4, y: 1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(
                            Color(red: 0.34, green: 0.25, blue: 0.08)
                        )
                        .frame(width: 43, height: 43)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle().stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.92),
                                        premiumGold.opacity(0.88),
                                        Color.white.opacity(0.28)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                        }
                        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
                }
            }
            .padding(14)
        }
        .frame(height: 184)
        .frame(maxWidth: .infinity)
        .clipShape(
            RoundedRectangle(cornerRadius: 27, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.76),
                            premiumGold.opacity(0.52),
                            Color.white.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.12), radius: 17, y: 8)
        .shadow(color: premiumGold.opacity(0.08), radius: 24, y: 10)
    }
}

private struct CommunityReferenceFriendsCard: View {
    let currentUserID: UUID
    let currentDisplayName: String
    let currentAvatarURL: URL?
    let friends: [SocialProfileCard]
    let feed: [SocialFeedItem]
    let ownWorkouts: [WorkoutSummary]

    private var threshold: Date {
        Calendar.current.date(
            byAdding: .day,
            value: -7,
            to: Date()
        ) ?? .distantPast
    }

    private var currentWeekWorkouts:
        [WorkoutSummary] {
        ownWorkouts.filter {
            $0.startDate >= threshold
        }
    }

    private var currentActivityPoints: Double {
        activityPoints(
            workouts:
                currentWeekWorkouts.count,
            activeMinutes:
                currentWeekWorkouts
                    .reduce(0) {
                        $0 + $1.duration
                    } / 60
        )
    }

    private var currentWorkoutCount: Int {
        currentWeekWorkouts.count
    }

    private var topFriend: SocialProfileCard? {
        friends.max {
            friendActivityPoints($0) <
                friendActivityPoints($1)
        }
    }

    private var totalPoints: Double {
        let friendValue =
            topFriend.map {
                friendActivityPoints($0)
            } ?? 0

        return currentActivityPoints +
            friendValue
    }

    private var currentShare: Double {
        guard totalPoints > 0 else {
            return 0.5
        }

        return currentActivityPoints /
            totalPoints
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(
                    alignment: .leading,
                    spacing: 1
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Friends vs Friends",
                            norwegian:
                                "Venner mot venner"
                        )
                    )
                    .font(
                        .headline.weight(
                            .bold
                        )
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Weekly activity duel",
                            norwegian:
                                "Ukentlig aktivitetsduell"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()

                HStack(spacing: 4) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "See all",
                            norwegian: "Se alle"
                        )
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
                    ATHLTHTheme.accentDeep
                )
            }

            if let topFriend {
                HStack(
                    alignment: .center,
                    spacing: 8
                ) {
                    participant(
                        name:
                            ATHLTHLocalization.choose(
                                english: "You",
                                norwegian: "Deg"
                            ),
                        avatarURL:
                            currentAvatarURL,
                        fallback:
                            currentDisplayName,
                        points:
                            currentActivityPoints,
                        workouts:
                            currentWorkoutCount,
                        ringTint: .green
                    )

                    Text("VS")
                        .font(
                            .caption2.weight(
                                .heavy
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .frame(
                            width: 34,
                            height: 34
                        )
                        .background(
                            Color.white,
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.black
                                        .opacity(
                                            0.07
                                        ),
                                    lineWidth: 1
                                )
                        }

                    participant(
                        name:
                            firstName(
                                topFriend
                                    .resolvedName
                            ),
                        avatarURL:
                            topFriend
                                .avatarURL
                                .flatMap(URL.init(string:)),
                        fallback:
                            topFriend
                                .resolvedName,
                        points:
                            friendActivityPoints(
                                topFriend
                            ),
                        workouts:
                            friendWorkoutCount(
                                topFriend
                            ),
                        ringTint: .blue
                    )
                }

                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        Capsule()
                            .fill(
                                Color.green
                                    .opacity(
                                        0.78
                                    )
                            )
                            .frame(
                                width:
                                    proxy.size.width *
                                    currentShare
                            )

                        Capsule()
                            .fill(
                                Color.blue
                                    .opacity(
                                        0.72
                                    )
                            )
                    }
                }
                .frame(height: 7)
                .background(
                    Color.black.opacity(0.06),
                    in: Capsule()
                )
                .clipShape(Capsule())
            } else {
                HStack(spacing: 11) {
                    Image(
                        systemName:
                            "person.2.badge.plus"
                    )
                    .font(.title3)
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .frame(
                        width: 42,
                        height: 42
                    )
                    .background(
                        ATHLTHTheme.accentSoft,
                        in:
                            RoundedRectangle(
                                cornerRadius: 13,
                                style:
                                    .continuous
                            )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Follow each other to compete",
                                norwegian:
                                    "Følg hverandre for å konkurrere"
                            )
                        )
                        .font(
                            .subheadline
                                .weight(
                                    .semibold
                                )
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Mutual follows unlock head-to-head matchups.",
                                norwegian:
                                    "Gjensidig følge åpner head-to-head."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }

                    Spacer()
                }
            }
        }
        .padding(13)
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
                Color.black.opacity(0.045),
                lineWidth: 0.8
            )
        }
    }

    private func participant(
        name: String,
        avatarURL: URL?,
        fallback: String,
        points: Double,
        workouts: Int,
        ringTint: Color
    ) -> some View {
        HStack(spacing: 9) {
            CommunityReferenceAvatar(
                url: avatarURL,
                fallback: fallback,
                size: 58
            )
            .overlay {
                Circle()
                    .stroke(
                        ringTint.opacity(
                            0.75
                        ),
                        lineWidth: 3
                    )
            }

            VStack(
                alignment: .leading,
                spacing: 1
            ) {
                Text(name)
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .lineLimit(1)

                Text(
                    ATHLTHLocalization.format(
                        english:
                            "%d pts",
                        norwegian:
                            "%d poeng",
                        Int(
                            points.rounded()
                        )
                    )
                )
                .font(
                    .headline.weight(
                        .bold
                    )
                )
                .monospacedDigit()

                Text(
                    ATHLTHLocalization.format(
                        english:
                            "%d workouts",
                        norwegian:
                            "%d økter",
                        workouts
                    )
                )
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func firstName(
        _ name: String
    ) -> String {
        name.split(separator: " ")
            .first
            .map(String.init) ??
        name
    }

    private func friendActivities(
        _ friend: SocialProfileCard
    ) -> [SocialFeedItem] {
        feed.filter {
            $0.actor.userID ==
                friend.userID &&
            $0.activity.createdAt >=
                threshold &&
            $0.activity.kind ==
                "workout"
        }
    }

    private func friendActivityPoints(
        _ friend: SocialProfileCard
    ) -> Double {
        let activities =
            friendActivities(friend)
        let minutes =
            activities
                .compactMap {
                    durationSeconds(
                        $0.activity
                    )
                }
                .reduce(0, +) / 60

        return activityPoints(
            workouts:
                activities.count,
            activeMinutes:
                minutes
        )
    }

    private func friendWorkoutCount(
        _ friend: SocialProfileCard
    ) -> Int {
        friendActivities(friend).count
    }

    private func activityPoints(
        workouts: Int,
        activeMinutes: Double
    ) -> Double {
        let count =
            max(workouts, 0)
        let cappedMinutes =
            min(
                max(
                    activeMinutes,
                    0
                ),
                Double(count) * 120
            )

        return
            Double(count) * 20 +
            cappedMinutes / 5
    }

    private func durationSeconds(
        _ activity:
            SocialActivityRecord
    ) -> Double? {
        guard let raw =
                activity.metadata?[
                    "duration_seconds"
                ],
              let value =
                Double(raw)
        else {
            return nil
        }

        return max(value, 0)
    }
}

private struct CommunityDiscoveryView: View {
    @EnvironmentObject private var groups:
        CommunityGroupStore
    @EnvironmentObject private var community:
        CommunityEventStore
    @EnvironmentObject private var challenges:
        ChallengeStore
    @EnvironmentObject private var social:
        SocialStore
    @EnvironmentObject private var session:
        AppSessionStore

    private var publicGroups:
        [CommunityGroupRecord] {
        groups.groups
            .filter {
                $0.visibility == "public" &&
                !groups.joinedGroupIDs
                    .contains($0.id) &&
                groups.pendingInvite(
                    for: $0.id
                ) == nil
            }
            .sorted {
                $0.createdAt >
                    $1.createdAt
            }
    }

    private var publicEvents:
        [CommunityEventItem] {
        community.upcomingEvents.filter { item in
            guard item.event.visibility ==
                    ProfileVisibility
                        .publicProfile
                        .rawValue
            else {
                return false
            }

            return item.event.creatorID !=
                    session.profile.userID &&
                !item.participantRows.contains {
                    $0.userID ==
                        session.profile.userID
                }
        }
    }

    private var publicChallenges:
        [ATHLTHChallenge] {
        challenges.visibleChallenges.filter {
            challenge in

            guard challenge.visibility ==
                    .publicProfile,
                  challenge.status == .active ||
                    challenge.status == .upcoming
            else {
                return false
            }

            return !challenge.participants
                .contains {
                    $0.userID ==
                        session.profile.userID
                }
        }
    }

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme
                        .champagneSoft
                        .opacity(0.20)
            )

            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 22
                ) {
                    discoveryHeader

                    discoverySection(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Public clubs",
                                norwegian:
                                    "Offentlige klubber"
                            ),
                        subtitle:
                            ATHLTHLocalization.choose(
                                english:
                                    "Find communities you can join.",
                                norwegian:
                                    "Finn fellesskap du kan bli med i."
                            ),
                        icon: "person.3.fill",
                        tint: .green
                    ) {
                        if publicGroups.isEmpty {
                            CommunityDiscoveryEmptyCard(
                                text:
                                    ATHLTHLocalization.choose(
                                        english:
                                            "No public clubs to discover right now.",
                                        norwegian:
                                            "Ingen offentlige klubber å oppdage akkurat nå."
                                    )
                            )
                        } else {
                            VStack(spacing: 9) {
                                ForEach(
                                    Array(
                                        publicGroups
                                            .prefix(8)
                                    )
                                ) { group in
                                    NavigationLink {
                                        CommunityGroupDetailView(
                                            group: group
                                        )
                                    } label: {
                                        CommunityDiscoveryGroupRow(
                                            group: group
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    discoverySection(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Public events",
                                norwegian:
                                    "Offentlige events"
                            ),
                        subtitle:
                            ATHLTHLocalization.choose(
                                english:
                                    "See upcoming activities open to ATHLTH.",
                                norwegian:
                                    "Se kommende aktiviteter som er åpne for ATHLTH."
                            ),
                        icon: "calendar",
                        tint: .blue
                    ) {
                        if publicEvents.isEmpty {
                            CommunityDiscoveryEmptyCard(
                                text:
                                    ATHLTHLocalization.choose(
                                        english:
                                            "No public events are scheduled yet.",
                                        norwegian:
                                            "Ingen offentlige events er planlagt ennå."
                                    )
                            )
                        } else {
                            VStack(spacing: 9) {
                                ForEach(
                                    Array(
                                        publicEvents
                                            .prefix(8)
                                    )
                                ) { item in
                                    NavigationLink {
                                        CommunityEventDetailView(
                                            eventID:
                                                item.id
                                        )
                                    } label: {
                                        CommunityReferenceUpcomingEventCard(
                                            item: item
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    discoverySection(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Public challenges",
                                norwegian:
                                    "Offentlige challenges"
                            ),
                        subtitle:
                            ATHLTHLocalization.choose(
                                english:
                                    "Explore challenges from the community.",
                                norwegian:
                                    "Utforsk challenges fra fellesskapet."
                            ),
                        icon: "trophy.fill",
                        tint: .orange
                    ) {
                        if publicChallenges.isEmpty {
                            CommunityDiscoveryEmptyCard(
                                text:
                                    ATHLTHLocalization.choose(
                                        english:
                                            "No public challenges to discover right now.",
                                        norwegian:
                                            "Ingen offentlige challenges å oppdage akkurat nå."
                                    )
                            )
                        } else {
                            VStack(spacing: 9) {
                                ForEach(
                                    Array(
                                        publicChallenges
                                            .prefix(8)
                                    )
                                ) { challenge in
                                    NavigationLink {
                                        ChallengeDetailView(
                                            challengeID:
                                                challenge.id
                                        )
                                    } label: {
                                        CommunityDiscoveryChallengeRow(
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
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Discovery")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await refreshDiscovery()
        }
    }

    private var discoveryHeader: some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            HStack {
                Image(systemName: "sparkles")
                    .font(
                        .system(
                            size: 18,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.premiumGold
                    )
                    .frame(
                        width: 42,
                        height: 42
                    )
                    .background(
                        ATHLTHTheme
                            .premiumGoldSoft,
                        in:
                            RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                    )

                Spacer()

                Text(
                    ATHLTHLocalization.choose(
                        english: "PUBLIC",
                        norwegian: "OFFENTLIG"
                    )
                )
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    ATHLTHTheme
                        .accentSoft,
                    in: Capsule()
                )
            }

            Text("Discovery")
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
                ATHLTHLocalization.choose(
                    english:
                        "Find public clubs, events and challenges beyond your current circle.",
                    norwegian:
                        "Finn offentlige klubber, events og challenges utenfor ditt nåværende fellesskap."
                )
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
        .padding(16)
        .background(
            Color.white.opacity(0.88),
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
                ATHLTHTheme
                    .premiumGold
                    .opacity(0.10),
                lineWidth: 0.8
            )
        }
    }

    @ViewBuilder
    private func discoverySection<
        Content: View
    >(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        @ViewBuilder content:
            () -> Content
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(tint)
                    .frame(
                        width: 34,
                        height: 34
                    )
                    .background(
                        tint.opacity(0.10),
                        in:
                            RoundedRectangle(
                                cornerRadius: 10,
                                style:
                                    .continuous
                            )
                    )

                VStack(
                    alignment: .leading,
                    spacing: 1
                ) {
                    Text(title)
                        .font(
                            .headline
                                .weight(.bold)
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
            }

            content()
        }
    }

    @MainActor
    private func refreshDiscovery() async {
        async let groupRefresh: Void =
            groups.refresh(force: true)
        async let eventRefresh: Void =
            community.refresh(force: true)
        async let socialRefresh: Void =
            social.refresh(
                challengeStore:
                    challenges
            )

        _ = await (
            groupRefresh,
            eventRefresh,
            socialRefresh
        )

        challenges.refreshStatuses()
    }
}

private struct CommunityDiscoveryGroupRow:
    View {
    let group: CommunityGroupRecord

    var body: some View {
        HStack(spacing: 11) {
            ATHLTHArtworkImage(
                reference:
                    group.headerImageURL ??
                    group.imageURL,
                fallbackAssetName:
                    "CommunityHero"
            )
            .frame(
                width: 70,
                height: 62
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 13,
                    style: .continuous
                )
            )

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(group.name)
                    .font(
                        .subheadline
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)

                Text(
                    group.locationName.isEmpty
                        ? group.summary
                        : group.locationName
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)

                Label(
                    ATHLTHLocalization.choose(
                        english: "Public club",
                        norwegian:
                            "Offentlig klubb"
                    ),
                    systemImage: "globe"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
            }

            Spacer(minLength: 6)

            Image(
                systemName:
                    "chevron.right"
            )
            .font(.caption.bold())
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )
        }
        .padding(9)
        .background(
            Color.white.opacity(0.88),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.04),
                lineWidth: 0.7
            )
        }
    }
}

private struct CommunityDiscoveryChallengeRow:
    View {
    let challenge: ATHLTHChallenge

    private var participantCount: Int {
        challenge.participants.filter {
            $0.state == .creator ||
            $0.state == .accepted
        }
        .count
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(
                systemName:
                    challenge.sport.systemImage
            )
            .font(
                .system(
                    size: 19,
                    weight: .semibold
                )
            )
            .foregroundStyle(.orange)
            .frame(
                width: 52,
                height: 52
            )
            .background(
                Color.orange.opacity(0.10),
                in:
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(challenge.title)
                    .font(
                        .subheadline
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(
                        challenge.sport.title,
                        systemImage:
                            challenge
                                .sport
                                .systemImage
                    )

                    Label(
                        "\(participantCount)",
                        systemImage:
                            "person.2.fill"
                    )
                }
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

                if let endsAt =
                        challenge.rules.endsAt {
                    Label(
                        endsAt.formatted(
                            date: .abbreviated,
                            time: .omitted
                        ),
                        systemImage: "clock"
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                }
            }

            Spacer(minLength: 6)

            Image(
                systemName:
                    "chevron.right"
            )
            .font(.caption.bold())
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )
        }
        .padding(11)
        .background(
            Color.white.opacity(0.88),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.04),
                lineWidth: 0.7
            )
        }
    }
}

private struct CommunityDiscoveryEmptyCard:
    View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(
                systemName:
                    "sparkles"
            )
            .foregroundStyle(
                ATHLTHTheme.premiumGold
            )

            Text(text)
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

            Spacer()
        }
        .padding(13)
        .background(
            Color.white.opacity(0.82),
            in:
                RoundedRectangle(
                    cornerRadius: 17,
                    style: .continuous
                )
        )
    }
}

private struct CommunityDiscoveryClubCard:
    View {
    let group: CommunityGroupRecord
    let memberCount: Int
    let isJoined: Bool

    private var forest: Color {
        Color(
            red: 0.025,
            green: 0.30,
            blue: 0.21
        )
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            ZStack(
                alignment: .bottomLeading
            ) {
                // Use a fixed-size viewport before loading the artwork.
                // A newly uploaded ultrawide Club header must never change
                // the intrinsic width of the horizontally scrolling cards.
                GeometryReader { viewport in
                    ATHLTHArtworkImage(
                        reference:
                            group.headerImageURL ??
                            group.imageURL,
                        fallbackAssetName:
                            "CommunityHero",
                        maxPixelSize: 420
                    )
                    .athlthBoundedFill()
                    .frame(
                        width: viewport.size.width,
                        height: viewport.size.height
                    )
                    .clipped()
                }
                .frame(width: 252, height: 92)
                .clipped()

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black
                            .opacity(0.34)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                clubAvatar
                    .frame(
                        width: 46,
                        height: 46
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 13,
                            style:
                                .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 13,
                            style:
                                .continuous
                        )
                        .stroke(
                            Color.white,
                            lineWidth: 2
                        )
                    }
                    .shadow(
                        color:
                            Color.black
                                .opacity(0.16),
                        radius: 6,
                        y: 3
                    )
                    .padding(.leading, 11)
                    .offset(y: 18)

                HStack {
                    Spacer()

                    Text(
                        isJoined
                            ? ATHLTHLocalization
                                .choose(
                                    english:
                                        "YOUR CLUB",
                                    norwegian:
                                        "DIN CLUB"
                                )
                            : ATHLTHLocalization
                                .choose(
                                    english:
                                        "PUBLIC",
                                    norwegian:
                                        "OFFENTLIG"
                                )
                    )
                    .font(
                        .system(
                            size: 8,
                            weight: .bold
                        )
                    )
                    .tracking(0.7)
                    .foregroundStyle(
                        .white
                    )
                    .padding(
                        .horizontal,
                        8
                    )
                    .frame(height: 24)
                    .background(
                        forest
                            .opacity(0.88),
                        in: Capsule()
                    )
                    .padding(9)
                }
                .frame(
                    maxHeight:
                        .infinity,
                    alignment: .top
                )
            }
            .frame(width: 252, height: 92)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(group.name)
                    .font(
                        .subheadline
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if !group
                        .locationName
                        .isEmpty {
                        Label(
                            group.locationName,
                            systemImage:
                                "location.fill"
                        )
                    } else {
                        Label(
                            ATHLTHLocalization
                                .choose(
                                    english:
                                        "Club",
                                    norwegian:
                                        "Club"
                                ),
                            systemImage:
                                "person.3.fill"
                        )
                    }

                    if memberCount > 0 {
                        Text("·")

                        Text(
                            ATHLTHLocalization
                                .counted(
                                    memberCount,
                                    englishSingular:
                                        "member",
                                    englishPlural:
                                        "members",
                                    norwegianSingular:
                                        "medlem",
                                    norwegianPlural:
                                        "medlemmer"
                                )
                        )
                    }
                }
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(1)
            }
            .padding(.leading, 68)
            .padding(.trailing, 10)
            .padding(.top, 9)
            .padding(.bottom, 10)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .frame(width: 252, alignment: .leading)
        .background(
            Color.white.opacity(
                0.96
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style:
                        .continuous
                )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                forest.opacity(
                    0.10
                ),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                forest.opacity(
                    0.06
                ),
            radius: 10,
            y: 4
        )
    }

    @ViewBuilder
    private var clubAvatar:
        some View {
        ATHLTHArtworkImage(
            reference:
                group.imageURL ??
                group.headerImageURL,
            fallbackAssetName:
                "CommunityHero",
            maxPixelSize: 220
        )
    }
}

private struct CommunityDiscoveryChallengeCard:
    View {
    let challenge: ATHLTHChallenge
    let creator: SocialProfileCard?

    private var participantCount: Int {
        challenge.participants
            .filter {
                $0.state == .creator ||
                $0.state == .accepted
            }
            .count
    }

    var body: some View {
        discoveryVisualCard(
            eyebrow:
                ATHLTHLocalization
                    .choose(
                        english:
                            "PUBLIC CHALLENGE",
                        norwegian:
                            "OFFENTLIG CHALLENGE"
                    ),
            title: challenge.title,
            detail:
                challenge.sport.title,
            meta:
                ATHLTHLocalization
                    .counted(
                        participantCount,
                        englishSingular:
                            "participant",
                        englishPlural:
                            "participants",
                        norwegianSingular:
                            "deltaker",
                        norwegianPlural:
                            "deltakere"
                    ),
            assetName:
                challengeArtworkAsset,
            icon:
                challenge.sport
                    .systemImage
        )
    }

    private var challengeArtworkAsset:
        String {
        switch challenge.sport {
        case .running:
            return "GoalRunningThumbnail"
        case .walking:
            return "GoalWalkingThumbnail"
        case .strength:
            return "GoalStrengthThumbnail"
        case .heartRate:
            return "GoalRecoveryThumbnail"
        }
    }

    private func discoveryVisualCard(
        eyebrow: String,
        title: String,
        detail: String,
        meta: String,
        assetName: String,
        icon: String
    ) -> some View {
        CommunityDiscoveryPeopleCardShell(
            eyebrow: eyebrow,
            title: title,
            detail: detail,
            meta: meta,
            assetName: assetName,
            icon: icon,
            profile: creator
        )
    }
}

private struct CommunityDiscoveryEventCard:
    View {
    let item: CommunityEventItem

    var body: some View {
        CommunityDiscoveryPeopleCardShell(
            eyebrow:
                ATHLTHLocalization
                    .choose(
                        english:
                            "PUBLIC EVENT",
                        norwegian:
                            "OFFENTLIG EVENT"
                    ),
            title:
                item.event.title,
            detail:
                item.event.startsAt
                    .formatted(
                        date:
                            .abbreviated,
                        time:
                            .shortened
                    ),
            meta:
                item.event
                    .meetingName
                    .isEmpty
                    ? item.event
                        .activityType
                        .title
                    : item.event
                        .meetingName,
            assetName:
                eventArtworkAsset,
            icon:
                item.event
                    .activityType
                    .systemImage,
            profile:
                item.creator
        )
    }

    private var eventArtworkAsset:
        String {
        switch item.event.activityType {
        case .running:
            return "GoalRunningThumbnail"
        case .walking:
            return "GoalWalkingThumbnail"
        case .strength:
            return "GoalStrengthThumbnail"
        case .cycling:
            return "GoalEnduranceThumbnail"
        case .hike:
            return "GoalMountainThumbnail"
        case .groupWorkout:
            return "CommunityHero"
        case .other:
            return "GoalAdventureThumbnail"
        }
    }
}

private struct CommunityDiscoveryPeopleCardShell:
    View {
    let eyebrow: String
    let title: String
    let detail: String
    let meta: String
    let assetName: String
    let icon: String
    let profile: SocialProfileCard?

    private var forest: Color {
        Color(
            red: 0.025,
            green: 0.30,
            blue: 0.21
        )
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            ZStack(
                alignment:
                    .bottomLeading
            ) {
                Image(assetName)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
                    .athlthBoundedFill()
                    .frame(
                        maxWidth:
                            .infinity
                    )
                    .frame(height: 92)
                    .clipped()

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black
                            .opacity(0.42)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                creatorAvatar
                    .frame(
                        width: 43,
                        height: 43
                    )
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(
                                Color.white,
                                lineWidth: 2
                            )
                    }
                    .shadow(
                        color:
                            Color.black
                                .opacity(
                                    0.16
                                ),
                        radius: 6,
                        y: 3
                    )
                    .padding(.leading, 11)
                    .offset(y: 17)

                HStack {
                    Label(
                        eyebrow,
                        systemImage: icon
                    )
                    .font(
                        .system(
                            size: 8,
                            weight: .bold
                        )
                    )
                    .tracking(0.6)
                    .foregroundStyle(
                        .white
                    )
                    .lineLimit(1)
                    .padding(
                        .horizontal,
                        8
                    )
                    .frame(height: 24)
                    .background(
                        forest
                            .opacity(0.88),
                        in: Capsule()
                    )

                    Spacer()
                }
                .padding(9)
                .frame(
                    maxHeight:
                        .infinity,
                    alignment: .top
                )
            }
            .frame(height: 92)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(
                        .subheadline
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(1)

                if !meta.isEmpty {
                    Text(meta)
                        .font(
                            .system(
                                size: 9.5,
                                weight:
                                    .medium
                            )
                        )
                        .foregroundStyle(
                            forest
                        )
                        .lineLimit(1)
                }
            }
            .padding(.leading, 65)
            .padding(.trailing, 10)
            .padding(.top, 8)
            .padding(.bottom, 9)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .background(
            Color.white.opacity(
                0.96
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style:
                        .continuous
                )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                forest.opacity(
                    0.10
                ),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                forest.opacity(
                    0.05
                ),
            radius: 10,
            y: 4
        )
    }

    @ViewBuilder
    private var creatorAvatar:
        some View {
        if let profile {
            CommunityV4Avatar(
                profile: profile,
                size: 43,
                isOnline: false
            )
        } else {
            Circle()
                .fill(
                    Color.white
                        .opacity(0.94)
                )
                .overlay {
                    Image(
                        systemName:
                            "person.fill"
                    )
                    .font(
                        .system(
                            size: 17,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        forest
                    )
                }
        }
    }
}

private struct CommunityDiscoveryVisualEmptyCard:
    View {
    let title: String
    let detail: String
    let assetName: String
    let icon: String

    var body: some View {
        ZStack(
            alignment: .bottomLeading
        ) {
            Image(assetName)
                .resizable()
                .scaledToFill()
                .athlthBoundedFill()
                .frame(height: 130)
                .frame(
                    maxWidth:
                        .infinity
                )
                .clipped()

            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black
                        .opacity(0.58)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Image(
                    systemName: icon
                )
                .font(.caption.bold())

                Text(title)
                    .font(
                        .subheadline
                            .weight(.bold)
                    )

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(
                        .white.opacity(
                            0.86
                        )
                    )
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(12)
        }
        .frame(height: 130)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }
}

private struct CommunityDiscoveryNowRow:
    View {
    let eyebrow: String
    let title: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 16,
                        weight: .semibold
                    )
                )
                .foregroundStyle(tint)
                .frame(
                    width: 39,
                    height: 39
                )
                .background(
                    tint.opacity(0.10),
                    in:
                        RoundedRectangle(
                            cornerRadius: 11,
                            style: .continuous
                        )
                )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(eyebrow)
                    .font(
                        .system(
                            size: 8,
                            weight: .bold
                        )
                    )
                    .tracking(0.8)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )

                Text(title)
                    .font(
                        .subheadline
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)

                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            Image(
                systemName:
                    "chevron.right"
            )
            .font(.caption.bold())
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )
        }
        .padding(
            .horizontal,
            12
        )
        .padding(
            .vertical,
            10
        )
    }
}

private struct CommunityDiscoveryDivider:
    View {
    var body: some View {
        Rectangle()
            .fill(
                ATHLTHTheme.divider
            )
            .frame(height: 0.5)
            .padding(.leading, 62)
            .padding(.trailing, 12)
    }
}

private struct CommunityReferenceQuickActions: View {
    @State private var showingCreateChallenge = false
    @State private var showingCreateEvent = false

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink {
                CommunityGroupsView()
            } label: {
                tile(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Clubs",
                            norwegian: "Klubber"
                        ),
                    detail:
                        ATHLTHLocalization.choose(
                            english: "Explore",
                            norwegian: "Utforsk"
                        ),
                    icon:
                        "person.3.fill",
                    tint: .green
                )
            }
            .buttonStyle(.plain)

            Button {
                showingCreateChallenge = true
            } label: {
                tile(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Challenge",
                            norwegian: "Challenge"
                        ),
                    detail:
                        ATHLTHLocalization.choose(
                            english: "Create",
                            norwegian: "Opprett"
                        ),
                    icon: "trophy.fill",
                    tint: .orange
                )
            }
            .buttonStyle(.plain)

            Button {
                showingCreateEvent = true
            } label: {
                tile(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Event",
                            norwegian: "Event"
                        ),
                    detail:
                        ATHLTHLocalization.choose(
                            english: "Create",
                            norwegian: "Opprett"
                        ),
                    icon: "calendar.badge.plus",
                    tint: .blue
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                TrainTogetherMarketplaceView()
            } label: {
                tile(
                    title: "Train Together",
                    detail:
                        ATHLTHLocalization.choose(
                            english: "Join a workout",
                            norwegian: "Tren sammen"
                        ),
                    icon:
                        "person.2.wave.2.fill",
                    tint:
                        ATHLTHTheme.accentDeep
                )
            }
            .buttonStyle(.plain)
        }
        .sheet(
            isPresented: $showingCreateChallenge
        ) {
            ChallengeCreationView()
        }
        .sheet(
            isPresented: $showingCreateEvent
        ) {
            CommunityEventCreateView()
        }
    }

    private func tile(
        title: String,
        detail: String,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 18,
                        weight: .semibold
                    )
                )
                .foregroundStyle(tint)
                .frame(
                    width: 35,
                    height: 35
                )
                .background(
                    tint.opacity(0.10),
                    in:
                        RoundedRectangle(
                            cornerRadius: 11,
                            style:
                                .continuous
                        )
                )

            Text(title)
                .font(
                    .caption.weight(
                        .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 78
        )
        .background(
            Color.white.opacity(0.90),
            in:
                RoundedRectangle(
                    cornerRadius: 17,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
            .stroke(
                tint.opacity(0.08),
                lineWidth: 0.7
            )
        }
    }
}

private struct CommunityReferenceSectionTitle: View {
    let title: String
    let destinationTitle: String
    let destination: () -> AnyView

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(
                    .title3.weight(
                        .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

            Spacer()

            NavigationLink {
                destination()
            } label: {
                HStack(spacing: 4) {
                    Text(destinationTitle)
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
                    ATHLTHTheme.accentDeep
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CommunityReferenceActivityRow: View {
    let item: SocialFeedItem
    let isOnline: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                HStack(spacing: 7) {
                    CommunityV4Avatar(
                        profile: item.actor,
                        size: 35,
                        isOnline: isOnline
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 1
                    ) {
                        Text(
                            item.actor
                                .resolvedName
                        )
                        .font(
                            .caption.weight(
                                .bold
                            )
                        )
                        .lineLimit(1)

                        Text(
                            item.activity
                                .createdAt,
                            style: .relative
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }
                }

                HStack(spacing: 5) {
                    Image(
                        systemName:
                            activityIcon
                    )
                    .font(
                        .system(
                            size: 11,
                            weight: .bold
                        )
                    )

                    Text(activityTitle)
                        .font(
                            .subheadline
                                .weight(
                                    .bold
                                )
                        )
                        .lineLimit(1)
                }
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                if let metricsText {
                    Text(metricsText)
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(1)
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )

            mediaPreview
                .frame(
                    width: 148,
                    height: 62
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                )
        }
        .padding(8)
        .background(
            Color.white.opacity(0.91),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.04),
                lineWidth: 0.7
            )
        }
    }

    private var workoutKind: String {
        item.activity.metadata?["kind"]?
            .lowercased() ?? ""
    }

    private var activityIcon: String {
        switch item.activity.kind {
        case "event":
            return "calendar"
        case "challenge":
            return "trophy.fill"
        case "personal_record":
            return "medal.fill"
        case "trophy":
            return "rosette"
        case "goal":
            return "target"
        default:
            return workoutKind == "strength"
                ? "dumbbell.fill"
                : "figure.run"
        }
    }

    private var activityTitle: String {
        switch item.activity.kind {
        case "event":
            return ATHLTHLocalization.choose(
                english: "Shared an event",
                norwegian: "Delte et event"
            )
        case "challenge":
            return ATHLTHLocalization.choose(
                english: "Shared a challenge",
                norwegian: "Delte en challenge"
            )
        default:
            if workoutKind == "strength" {
                return ATHLTHLocalization.choose(
                    english: "Strength workout",
                    norwegian: "Styrkeøkt"
                )
            }

            if workoutKind.contains("walk") {
                return ATHLTHLocalization.choose(
                    english: "Walk",
                    norwegian: "Gåtur"
                )
            }

            return ATHLTHLocalization.choose(
                english: "Run",
                norwegian: "Løpetur"
            )
        }
    }

    private var metricsText: String? {
        let metadata =
            item.activity.metadata ?? [:]

        if item.activity.kind == "event" {
            let startsAt =
                metadata["starts_at"]
                    .flatMap {
                        ISO8601DateFormatter()
                            .date(from: $0)
                    }

            let parts = [
                startsAt?.formatted(
                    date: .abbreviated,
                    time: .shortened
                ),
                metadata["meeting_name"]
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

            return parts.isEmpty
                ? item.activity.subtitle
                : parts.joined(
                    separator: " · "
                )
        }

        if item.activity.kind ==
            "challenge" {
            return item.activity.subtitle
        }

        let distanceText: String? = {
            guard let raw =
                metadata[
                    "distance_meters"
                ],
                  let meters =
                    Double(raw),
                  meters > 0
            else {
                return nil
            }

            return String(
                format:
                    "%.1f km",
                meters / 1_000
            )
        }()

        let durationText: String? = {
            guard let raw =
                metadata[
                    "duration_seconds"
                ],
                  let seconds =
                    Double(raw),
                  seconds > 0
            else {
                return nil
            }

            let total =
                Int(seconds.rounded())
            let hours = total / 3600
            let minutes =
                (total % 3600) / 60

            return hours > 0
                ? String(
                    format:
                        "%d:%02d",
                    hours,
                    minutes
                )
                : "\(minutes) min"
        }()

        let parts =
            [distanceText, durationText]
                .compactMap { $0 }

        if !parts.isEmpty {
            return parts.joined(
                separator: " · "
            )
        }

        return item.activity.subtitle
    }

    @ViewBuilder
    private var mediaPreview: some View {
        if item.activity.kind == "event" {
            CommunityEventFeedCoverView(
                metadata:
                    item.activity.metadata ??
                    [:],
                title:
                    item.activity.subtitle ??
                    ATHLTHLocalization.choose(
                        english: "Event",
                        norwegian: "Event"
                    )
            )
        } else if item.activity.kind ==
                    "challenge" {
            let metadata =
                item.activity.metadata ?? [:]
            let sport =
                ATHLTHChallengeSport(
                    rawValue:
                        metadata["sport"] ??
                        ""
                ) ?? .running

            ChallengeCoverArtworkView(
                sport: sport,
                artworkName:
                    metadata["cover_artwork"],
                remoteURL:
                    metadata[
                        "cover_image_url"
                    ]
            )
        } else if workoutKind ==
                    "strength" {
            Image("TrainHero")
                .resizable()
                .scaledToFill()
        } else if item.activity.kind ==
                    "workout" {
            CommunityReferenceRoutePreview()
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        ATHLTHTheme
                            .champagneSoft,
                        ATHLTHTheme
                            .surfaceSage
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(
                    systemName:
                        activityIcon
                )
                .font(.title2)
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )
            }
        }
    }
}

private struct CommunityEventFeedCoverView:
    View {
    let metadata: [String: String]
    let title: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let rawURL =
                        metadata[
                            "cover_image_url"
                        ],
                   let url =
                        URL(string: rawURL) {
                    ATHLTHStorageImage(
                        url: url,
                        maxPixelSize: 900
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
                            fallbackArtwork
                        }
                    }
                } else {
                    fallbackArtwork
                }
            }

            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.38)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Text(title)
                .font(
                    .system(
                        size: 9,
                        weight: .bold
                    )
                )
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(8)
        }
    }

    @ViewBuilder
    private var fallbackArtwork:
        some View {
        Image(
            metadata[
                "cover_artwork"
            ] ??
            "CommunityHero"
        )
        .resizable()
        .scaledToFill()
    }
}

private struct CommunityReferenceRoutePreview: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(
                            red: 0.86,
                            green: 0.92,
                            blue: 0.84
                        ),
                        Color(
                            red: 0.78,
                            green: 0.87,
                            blue: 0.91
                        )
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Path { path in
                    let w =
                        proxy.size.width
                    let h =
                        proxy.size.height

                    path.move(
                        to:
                            CGPoint(
                                x: w * 0.12,
                                y: h * 0.68
                            )
                    )
                    path.addCurve(
                        to:
                            CGPoint(
                                x: w * 0.36,
                                y: h * 0.34
                            ),
                        control1:
                            CGPoint(
                                x: w * 0.18,
                                y: h * 0.42
                            ),
                        control2:
                            CGPoint(
                                x: w * 0.28,
                                y: h * 0.58
                            )
                    )
                    path.addCurve(
                        to:
                            CGPoint(
                                x: w * 0.62,
                                y: h * 0.55
                            ),
                        control1:
                            CGPoint(
                                x: w * 0.45,
                                y: h * 0.16
                            ),
                        control2:
                            CGPoint(
                                x: w * 0.55,
                                y: h * 0.72
                            )
                    )
                    path.addCurve(
                        to:
                            CGPoint(
                                x: w * 0.88,
                                y: h * 0.24
                            ),
                        control1:
                            CGPoint(
                                x: w * 0.72,
                                y: h * 0.42
                            ),
                        control2:
                            CGPoint(
                                x: w * 0.80,
                                y: h * 0.50
                            )
                    )
                }
                .stroke(
                    Color.green
                        .opacity(0.82),
                    style:
                        StrokeStyle(
                            lineWidth: 3,
                            lineCap: .round,
                            lineJoin: .round
                        )
                )

                Circle()
                    .fill(.white)
                    .frame(
                        width: 8,
                        height: 8
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                Color.green,
                                lineWidth: 2
                            )
                    }
                    .position(
                        x:
                            proxy.size.width *
                            0.88,
                        y:
                            proxy.size.height *
                            0.24
                    )
            }
        }
    }
}

private struct CommunityReferenceEmptyActivityCard: View {
    var body: some View {
        HStack(spacing: 11) {
            Image(
                systemName:
                    "figure.run.circle"
            )
            .font(.title3)
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )

            Text(
                ATHLTHLocalization.choose(
                    english:
                        "Activity from people you follow will appear here.",
                    norwegian:
                        "Aktivitet fra personer du følger vises her."
                )
            )
            .font(.caption)
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )

            Spacer()
        }
        .padding(13)
        .background(
            Color.white.opacity(0.86),
            in:
                RoundedRectangle(
                    cornerRadius: 17,
                    style: .continuous
                )
        )
    }
}

private struct CommunityReferenceClubCard: View {
    let group: CommunityGroupRecord
    let memberCount: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            groupArtwork

            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.64)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .bottom) {
                VStack(
                    alignment: .leading,
                    spacing: 1
                ) {
                    Text(group.name)
                        .font(
                            .caption.weight(
                                .bold
                            )
                        )
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(
                        ATHLTHLocalization.format(
                            english:
                                "%d members",
                            norwegian:
                                "%d medlemmer",
                            memberCount
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        .white.opacity(0.86)
                    )
                }

                Spacer()

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(.caption.bold())
                .foregroundStyle(.white)
            }
            .padding(10)
        }
        .frame(
            width: 178,
            height: 82
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private var groupArtwork: some View {
        ATHLTHArtworkImage(
            reference:
                group.headerImageURL ??
                group.imageURL,
            fallbackAssetName:
                "CommunityHero"
        )
        .athlthBoundedFill()
    }
}

private struct CommunityReferenceUpcomingEventCard: View {
    let item: CommunityEventItem

    private var isCompleted: Bool {
        item.event.status ==
            "completed"
    }

    private var statusTint: Color {
        isCompleted
            ? .indigo
            : ATHLTHTheme.accentDeep
    }

    var body: some View {
        HStack(spacing: 9) {
            VStack(spacing: 0) {
                Text(
                    item.event.startsAt
                        .formatted(
                            .dateTime
                                .weekday(
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
                .foregroundStyle(.red)

                Text(
                    item.event.startsAt
                        .formatted(
                            .dateTime.day()
                        )
                )
                .font(
                    .title3.weight(
                        .bold
                    )
                )

                Text(
                    item.event.startsAt
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
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }
            .frame(
                width: 46,
                height: 70
            )
            .background(
                Color.white,
                in:
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
            )

            eventCover
                .athlthBoundedFill()
                .frame(
                    width: 40,
                    height: 40
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(item.event.title)
                    .font(
                        .system(
                            size: 14,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        isCompleted
                            ? ATHLTHTheme.mutedText
                            : ATHLTHTheme.primaryText
                    )
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )

                if isCompleted {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Finished · shown for 24h",
                            norwegian:
                                "Ferdig · vises i 24 t"
                        ),
                        systemImage:
                            "checkmark.circle.fill"
                    )
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        .indigo
                    )
                    .lineLimit(1)
                }

                Label(
                    eventLocationText,
                    systemImage:
                        "location.fill"
                )
                .font(
                    .system(
                        size: 10,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)

                HStack(spacing: 8) {
                    Label(
                        item.event.startsAt
                            .formatted(
                                date: .omitted,
                                time: .shortened
                            ),
                        systemImage: "clock"
                    )

                    Label(
                        "\(item.participantCount)",
                        systemImage:
                            "person.2.fill"
                    )
                }
                .font(
                    .system(
                        size: 9.5,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .layoutPriority(1)

            Image(
                systemName:
                    "chevron.right"
            )
            .font(
                .system(
                    size: 11,
                    weight: .bold
                )
            )
            .foregroundStyle(
                statusTint
            )
            .frame(
                width: 20,
                height: 34
            )
        }
        .padding(9)
        .background(
            (
                isCompleted
                    ? Color.indigo
                        .opacity(0.075)
                    : Color.white
                        .opacity(0.90)
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.04),
                lineWidth: 0.7
            )
        }
    }

    private var eventLocationText:
        String {
        let clean =
            item.event
                .meetingName
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        return clean.isEmpty
            ? item.event
                .activityType
                .title
            : clean
    }

    @ViewBuilder
    private var eventCover:
        some View {
        if let rawURL =
                item.event
                    .coverImageURL,
           let url =
                URL(string: rawURL) {
            ATHLTHStorageImage(
                url: url,
                maxPixelSize: 220
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()

                default:
                    standardCover
                }
            }
        } else {
            standardCover
        }
    }

    private var standardCover:
        some View {
        Image(
            CommunityEventCoverPolicy
                .displayArtworkName(
                    item.event
                        .coverArtworkName ??
                    CommunityEventCoverPolicy
                        .defaultArtwork(
                            for:
                                item.event
                                    .activityType
                        )
                )
        )
        .resizable()
        .scaledToFill()
        .clipped()
    }
}

private struct CommunityReferenceAvatar: View {
    let url: URL?
    let fallback: String
    let size: CGFloat

    var body: some View {
        ATHLTHStorageImage(
            url: url,
            maxPixelSize:
                max(
                    Int(
                        ceil(
                            size * 3
                        )
                    ),
                    160
                )
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Circle()
                    .fill(
                        ATHLTHTheme
                            .surfaceSage
                    )
                    .overlay {
                        Text(initials)
                            .font(
                                .system(
                                    size:
                                        size *
                                        0.30,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accentDeep
                            )
                    }
            }
        }
        .frame(
            width: size,
            height: size
        )
        .clipShape(Circle())
    }

    private var initials: String {
        let parts =
            fallback
                .split(separator: " ")
                .prefix(2)

        let value =
            parts.compactMap {
                $0.first
            }
            .map(String.init)
            .joined()

        return value.isEmpty
            ? "A"
            : value.uppercased()
    }
}

// MARK: - Header

private struct CommunityV4Header: View {
    let unreadMessages: Int
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
                Text("Community")
                    .font(
                        .system(
                            size: 34,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                Text(
                    "Friends, clubs and challenges"
                )
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                NavigationLink {
                    MessageInboxDestinationView()
                } label: {
                    ZStack(
                        alignment: .topTrailing
                    ) {
                        headerButton(
                            icon:
                                unreadMessages > 0
                                ? "envelope.fill"
                                : "envelope"
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
                    ProfileFollowListView(mode: .following)
                } label: {
                    metric(
                        mutuals,
                        "Mutual"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ProfileFollowListView(mode: .following)
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

// MARK: - Quick actions

private struct CommunityV4QuickActions: View {
    let clubCount: Int
    let challengeCount: Int
    let eventCount: Int
    let unreadMessages: Int

    var body: some View {
        HStack(spacing: 9) {
            NavigationLink {
                CommunityGroupsView()
            } label: {
                tile(
                    title: "Clubs",
                    value: clubCount,
                    icon: "person.3.fill",
                    tint: .green
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                ChallengeHubView()
            } label: {
                tile(
                    title: "Challenges",
                    value: challengeCount,
                    icon: "trophy.fill",
                    tint: .orange
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                CommunityEventsView()
            } label: {
                tile(
                    title: "Events",
                    value: eventCount,
                    icon: "calendar",
                    tint: .blue
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                MessageInboxDestinationView()
            } label: {
                tile(
                    title: "Chat",
                    value: unreadMessages,
                    icon: "bubble.left.and.bubble.right.fill",
                    tint: ATHLTHTheme.accentDeep
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func tile(
        title: String,
        value: Int,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 17,
                        weight: .semibold
                    )
                )
                .foregroundStyle(tint)
                .frame(
                    width: 38,
                    height: 38
                )
                .background(
                    tint.opacity(0.10),
                    in:
                        RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                )

            Text(title)
                .font(
                    .caption.weight(
                        .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(
                value > 0
                    ? value.formatted()
                    : "Open"
            )
            .font(.caption2)
            .foregroundStyle(
                ATHLTHTheme
                    .mutedText
            )
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 96
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
                tint.opacity(0.10),
                lineWidth: 0.8
            )
        }
    }
}

// MARK: - Recent activity

private struct CommunityV4ActivityRow: View {
    let item: SocialFeedItem
    let isOnline: Bool

    var body: some View {
        HStack(
            alignment: .top,
            spacing: 12
        ) {
            CommunityV4Avatar(
                profile: item.actor,
                size: 44,
                isOnline: isOnline
            )

            VStack(
                alignment: .leading,
                spacing: 7
            ) {
                HStack(spacing: 7) {
                    Text(
                        item.actor.resolvedName
                    )
                    .font(
                        .subheadline.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)

                    Spacer(minLength: 6)

                    Text(
                        item.activity
                            .createdAt,
                        style: .relative
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        .tertiary
                    )
                }

                HStack(spacing: 6) {
                    Image(
                        systemName:
                            activityIcon
                    )
                    .font(
                        .system(
                            size: 11,
                            weight: .bold
                        )
                    )

                    Text(activityLabel)
                        .font(
                            .caption.weight(
                                .bold
                            )
                        )
                }
                .foregroundStyle(activityTint)

                Text(item.activity.title)
                    .font(
                        .subheadline.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(2)

                if let subtitle =
                    item.activity.subtitle,
                   !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(2)
                }

                if let metadataLine {
                    Text(metadataLine)
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                                .opacity(0.88)
                        )
                        .lineLimit(1)
                }

                if !item.reactions.isEmpty ||
                    !item.comments.isEmpty {
                    HStack(spacing: 12) {
                        if !item.reactions.isEmpty {
                            Label(
                                "\(item.reactions.count)",
                                systemImage:
                                    "hand.thumbsup.fill"
                            )
                        }

                        if !item.comments.isEmpty {
                            Label(
                                "\(item.comments.count)",
                                systemImage:
                                    "bubble.left.fill"
                            )
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                }
            }

            Image(
                systemName:
                    "chevron.right"
            )
            .font(.caption.bold())
            .foregroundStyle(.tertiary)
            .padding(.top, 16)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.96),
                    activityTint.opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
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
                activityTint.opacity(0.09),
                lineWidth: 0.8
            )
        }
    }

    private var activityIcon: String {
        switch item.activity.kind {
        case "event":
            return "calendar.badge.plus"
        case "challenge":
            return "trophy.fill"
        case "personal_record":
            return "medal.fill"
        case "trophy":
            return "rosette"
        case "goal":
            return "target"
        case "status":
            return "text.bubble.fill"
        default:
            let workoutKind =
                item.activity
                    .metadata?["kind"]
            return workoutKind == "strength"
                ? "dumbbell.fill"
                : "figure.run"
        }
    }

    private var activityLabel: String {
        switch item.activity.kind {
        case "event":
            return "EVENT"
        case "challenge":
            return "CHALLENGE"
        case "personal_record":
            return "PERSONAL BEST"
        case "trophy":
            return "ACHIEVEMENT"
        case "goal":
            return "GOAL"
        case "status":
            return "STATUS"
        default:
            return "WORKOUT"
        }
    }

    private var activityTint: Color {
        switch item.activity.kind {
        case "event":
            return .blue
        case "challenge":
            return .orange
        case "personal_record",
             "trophy":
            return .yellow
        case "goal":
            return .green
        case "status":
            return .indigo
        default:
            return ATHLTHTheme.vitality
        }
    }

    private var metadataLine: String? {
        let metadata =
            item.activity.metadata ?? [:]

        if item.activity.kind == "event" {
            let startsAt =
                metadata["starts_at"]
                    .flatMap {
                        ISO8601DateFormatter()
                            .date(from: $0)
                    }
            let dateText =
                startsAt?.formatted(
                    date: .abbreviated,
                    time: .shortened
                )
            let meeting =
                metadata["meeting_name"]

            let line = [
                dateText,
                meeting
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

            return line.isEmpty
                ? nil
                : line
        }

        if item.activity.kind == "challenge" {
            return metadata["sport"]?
                .replacingOccurrences(
                    of: "_",
                    with: " "
                )
                .capitalized
        }

        if item.activity.kind == "workout",
           let rawDistance =
                metadata["distance_meters"],
           let meters = Double(rawDistance),
           meters > 0 {
            return String(
                format:
                    "%.1f km",
                meters / 1_000
            )
        }

        return nil
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
                    "Workouts, events, challenges and milestones from people you follow will appear here."
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
                eyebrow: "MORE FROM COMMUNITY",
                title: "Clubs & upcoming",
                subtitle:
                    "\(clubCount) clubs · \(eventCount) events · \(challengeCount) challenges",
                destinationTitle: nil,
                destination: nil
            )

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
                ATHLTHStorageImage(
                    url: url,
                    maxPixelSize:
                        max(
                            Int(
                                ceil(
                                    size * 3
                                )
                            ),
                            160
                        )
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
