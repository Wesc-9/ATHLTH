import SwiftUI

enum SocialHubTab: String, CaseIterable, Identifiable {
    case feed
    case messages
    case requests
    case discover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: return "Feed"
        case .messages: return "Messages"
        case .requests: return "Requests"
        case .discover: return "Discover"
        }
    }
}

struct ProfileFriendsSection: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore

    var body: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Following")
                        .font(.title3.weight(.bold))
                    Text("See training from athletes you follow.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    ProfileFollowListView(mode: .following)
                } label: {
                    HStack(spacing: 5) {
                        let socialBadgeCount =
                            social.pendingRequestCount +
                            messaging.unreadCount +
                            messaging.messageRequestCount
                        if socialBadgeCount > 0 {
                            Text("\(socialBadgeCount)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(.red, in: Circle())
                        }

                        Text("Social")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(ATHLTHTheme.accent)
                }
            }

            if social.following.isEmpty {
                NavigationLink {
                    SocialHubView(initialTab: .discover)
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "person.2.badge.plus")
                            .font(.title2)
                            .foregroundStyle(ATHLTHTheme.accent)
                            .frame(width: 44, height: 44)
                            .background(ATHLTHTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Find your training crew")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Search athletes and follow public profiles instantly.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(social.following.prefix(6)) { friend in
                            NavigationLink {
                                FriendProfileView(userID: friend.userID)
                            } label: {
                                VStack(spacing: 7) {
                                    ATHLTHOnlineAvatar(
                                        profile: friend,
                                        size: 54
                                    )

                                    Text(friend.resolvedName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .frame(width: 72)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
        .task {
            await realtime.refreshOnlineUsers()
            await realtime.refreshVisibleLiveSessions()
        }
    }
}

struct SocialHubView: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore

    let initialTab: SocialHubTab

    @State private var selectedTab: SocialHubTab
    @State private var searchText = ""
    @State private var showingNewMessage = false
    @State private var acceptedWorkoutInvite:
        SocialWorkoutInviteDisplay?

    private var clubForest: Color {
        Color(red: 0.025, green: 0.30, blue: 0.21)
    }

    private var clubEmerald: Color {
        Color(red: 0.055, green: 0.49, blue: 0.32)
    }

    private var clubMint: Color {
        Color(red: 0.90, green: 0.96, blue: 0.92)
    }

    private var suggestedProfiles:
        [SocialProfileCard] {
        social.visibleProfiles
            .filter {
                profile in

                profile.userID !=
                    social.currentUserID &&
                !social.isFollowing(
                    profile.userID
                )
            }
            .prefix(5)
            .map { $0 }
    }

    init(initialTab: SocialHubTab = .feed) {
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SocialHubTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 6) {
                                Text(tab.title)

                                let messageBadgeCount =
                                    messaging.unreadCount +
                                    messaging.messageRequestCount
                                if tab == .messages, messageBadgeCount > 0 {
                                    Text("\(messageBadgeCount)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(
                                            selectedTab == tab
                                                ? ATHLTHTheme.accent
                                                : Color.white
                                        )
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            selectedTab == tab
                                                ? Color.white
                                                : clubForest,
                                            in: Capsule()
                                        )
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                selectedTab == tab
                                    ? Color.white
                                    : ATHLTHTheme.primaryText
                            )
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(
                                selectedTab == tab
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [
                                                clubForest,
                                                clubEmerald
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    : AnyShapeStyle(
                                        Color.white.opacity(
                                            0.92
                                        )
                                    ),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }

            if let error = social.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }

            Group {
                switch selectedTab {
                case .feed:
                    SocialFeedView()
                case .messages:
                    MessageInboxView {
                        showingNewMessage = true
                    }
                case .requests:
                    requestsContent
                case .discover:
                    discoverContent
                }
            }
        }
        .background(
            ATHLTHPremiumCanvas(
                accent:
                    clubEmerald.opacity(
                        0.14
                    )
            )
        )
        .navigationTitle(
            ATHLTHLocalization.choose(
                english: "Social",
                norwegian: "Sosialt"
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if selectedTab == .messages {
                    Button {
                        showingNewMessage = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 38, height: 38)
                    }
                    .accessibilityLabel("New message")
                }
            }
        }
        .sheet(isPresented: $showingNewMessage) {
            NewMessageView()
        }
        .sheet(item: $acceptedWorkoutInvite) { invite in
            WorkoutInviteLaunchSheet(
                invite: invite
            )
        }
        .task {
            async let socialRefresh: Void =
                social.refresh()
            async let messageRefresh: Void =
                messaging.refresh()
            async let onlineRefresh: Void =
                realtime.refreshOnlineUsers()
            async let liveRefresh: Void =
                realtime.refreshVisibleLiveSessions()

            _ = await (
                socialRefresh,
                messageRefresh,
                onlineRefresh,
                liveRefresh
            )
        }
        .refreshable {
            async let socialRefresh: Void =
                social.refresh()
            async let messageRefresh: Void =
                messaging.refresh()
            async let onlineRefresh: Void =
                realtime.refreshOnlineUsers()
            async let liveRefresh: Void =
                realtime.refreshVisibleLiveSessions()

            _ = await (
                socialRefresh,
                messageRefresh,
                onlineRefresh,
                liveRefresh
            )
        }
    }

    private var requestsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if social.incomingRequests.isEmpty &&
                    social.outgoingRequests.isEmpty &&
                    social.workoutInvites.isEmpty {
                    ContentUnavailableView(
                        "No requests",
                        systemImage: "person.crop.circle.badge.checkmark",
                        description: Text("Follow and workout requests will appear here.")
                    )
                    .padding(.vertical, 50)
                }

                if !social.workoutInvites.isEmpty {
                    sectionTitle("Train Together")

                    ForEach(social.workoutInvites) { invite in
                        VStack(alignment: .leading, spacing: 11) {
                            HStack(spacing: 12) {
                                if let creator = invite.creator {
                                    SocialAvatar(profile: creator, size: 46)
                                } else {
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(clubForest)
                                        .frame(width: 46, height: 46)
                                        .background(
                                            ATHLTHTheme.accent.opacity(0.10),
                                            in: Circle()
                                        )
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(
                                        invite.creator?.resolvedName
                                            ?? "An athlete"
                                    )
                                    .font(.subheadline.weight(.semibold))

                                    Text(invite.session.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text(
                                        invite.session.startedAt.formatted(
                                            date: .abbreviated,
                                            time: .shortened
                                        )
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }

                            HStack(spacing: 8) {
                                if invite.participant.state == .accepted {
                                    Button(
                                        role: .destructive
                                    ) {
                                        Task {
                                            await social
                                                .declineWorkoutInvite(
                                                    invite
                                                )
                                        }
                                    } label: {
                                        Text(
                                            ATHLTHLocalization.choose(
                                                english: "Leave",
                                                norwegian: "Forlat"
                                            )
                                        )
                                    }
                                    .buttonStyle(.bordered)
                                    .frame(maxWidth: .infinity)

                                    Button(
                                        ATHLTHLocalization.choose(
                                            english: "Continue",
                                            norwegian: "Fortsett"
                                        )
                                    ) {
                                        acceptedWorkoutInvite =
                                            invite
                                    }
                                    .buttonStyle(
                                        .borderedProminent
                                    )
                                    .tint(
                                        ATHLTHTheme.accent
                                    )
                                    .frame(
                                        maxWidth: .infinity
                                    )
                                } else {
                                    Button(
                                        ATHLTHLocalization.choose(
                                            english: "Decline",
                                            norwegian: "Avslå"
                                        )
                                    ) {
                                        Task {
                                            await social
                                                .declineWorkoutInvite(
                                                    invite
                                                )
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .frame(maxWidth: .infinity)

                                    Button(
                                        ATHLTHLocalization.choose(
                                            english: "Join",
                                            norwegian: "Godta"
                                        )
                                    ) {
                                        Task {
                                            if await social
                                                .acceptWorkoutInvite(
                                                    invite
                                                ) {
                                                acceptedWorkoutInvite =
                                                    invite
                                            }
                                        }
                                    }
                                    .buttonStyle(
                                        .borderedProminent
                                    )
                                    .tint(
                                        ATHLTHTheme.accent
                                    )
                                    .frame(
                                        maxWidth: .infinity
                                    )
                                }
                            }
                        }
                        .padding(12)
                        .background(
                            Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 17)
                        )
                    }
                }

                if !social.incomingRequests.isEmpty {
                    sectionTitle("Follow Requests")

                    ForEach(social.incomingRequests) { request in
                        SocialProfileRow(profile: request.profile) {
                            HStack(spacing: 7) {
                                Button("Decline") {
                                    Task { await social.decline(request) }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("Accept") {
                                    Task { await social.accept(request) }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .tint(clubForest)
                            }
                        }
                    }
                }

                if !social.outgoingRequests.isEmpty {
                    sectionTitle("Follow Requests Sent")

                    ForEach(social.outgoingRequests) { request in
                        SocialProfileRow(profile: request.profile) {
                            Button("Cancel") {
                                Task { await social.cancel(request) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var discoverContent:
        some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                discoverHero
                discoverSearchField

                if searchText.isEmpty {
                    if !suggestedProfiles
                        .isEmpty {
                        HStack {
                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Suggested for you",
                                    norwegian:
                                        "Forslag til deg"
                                )
                            )
                            .font(
                                .title3
                                    .weight(.bold)
                            )

                            Spacer()
                        }

                        VStack(spacing: 8) {
                            ForEach(
                                suggestedProfiles
                            ) {
                                profile in

                                NavigationLink {
                                    FriendProfileView(
                                        userID:
                                            profile
                                                .userID
                                    )
                                } label: {
                                    SocialProfileRow(
                                        profile:
                                            profile
                                    ) {
                                        relationshipAction(
                                            profile
                                        )
                                    }
                                    .padding(
                                        .horizontal,
                                        12
                                    )
                                    .padding(
                                        .vertical,
                                        4
                                    )
                                    .background(
                                        Color.white
                                            .opacity(
                                                0.94
                                            ),
                                        in:
                                            RoundedRectangle(
                                                cornerRadius:
                                                    18,
                                                style:
                                                    .continuous
                                            )
                                    )
                                    .overlay {
                                        RoundedRectangle(
                                            cornerRadius:
                                                18,
                                            style:
                                                .continuous
                                        )
                                        .stroke(
                                            clubMint,
                                            lineWidth:
                                                0.8
                                        )
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack(spacing: 12) {
                            Image(
                                systemName:
                                    "person.3.fill"
                            )
                            .font(.title3)
                            .foregroundStyle(
                                clubForest
                            )
                            .frame(
                                width: 46,
                                height: 46
                            )
                            .background(
                                clubMint,
                                in:
                                    RoundedRectangle(
                                        cornerRadius:
                                            14,
                                        style:
                                            .continuous
                                    )
                            )

                            VStack(
                                alignment:
                                    .leading,
                                spacing: 3
                            ) {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Connect with the community",
                                        norwegian:
                                            "Koble deg med fellesskapet"
                                    )
                                )
                                .font(
                                    .subheadline
                                        .weight(
                                            .bold
                                        )
                                )

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Find friends, Clubs and challenges around you.",
                                        norwegian:
                                            "Finn venner, Clubs og utfordringer rundt deg."
                                    )
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
                            .font(
                                .caption.bold()
                            )
                            .foregroundStyle(
                                clubForest
                            )
                        }
                        .padding(14)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color.white
                                        .opacity(
                                            0.96
                                        ),
                                    clubMint
                                        .opacity(
                                            0.72
                                        )
                                ],
                                startPoint:
                                    .topLeading,
                                endPoint:
                                    .bottomTrailing
                            ),
                            in:
                                RoundedRectangle(
                                    cornerRadius:
                                        20,
                                    style:
                                        .continuous
                                )
                        )
                    } else {
                        VStack(spacing: 12) {
                            Image(
                                systemName:
                                    "person.2.badge.plus"
                            )
                            .font(
                                .system(
                                    size: 36,
                                    weight:
                                        .medium
                                )
                            )
                            .foregroundStyle(
                                clubForest
                            )
                            .frame(
                                width: 76,
                                height: 76
                            )
                            .background(
                                clubMint,
                                in:
                                    RoundedRectangle(
                                        cornerRadius:
                                            22,
                                        style:
                                            .continuous
                                    )
                            )

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Find ATHLTH users",
                                    norwegian:
                                        "Finn ATHLTH-brukere"
                                )
                            )
                            .font(
                                .title3
                                    .weight(.bold)
                            )

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Search by name or @username.",
                                    norwegian:
                                        "Søk etter navn eller @brukernavn."
                                )
                            )
                            .font(.subheadline)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                        }
                        .frame(
                            maxWidth:
                                .infinity
                        )
                        .padding(
                            .vertical,
                            50
                        )
                    }
                } else if social
                    .discoverResults
                    .isEmpty {
                    HStack(spacing: 12) {
                        Image(
                            systemName:
                                "magnifyingglass"
                        )
                        .foregroundStyle(
                            clubForest
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "No matching ATHLTH users.",
                                norwegian:
                                    "Ingen treff på ATHLTH-brukere."
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )

                        Spacer()
                    }
                    .padding(15)
                    .background(
                        Color.white.opacity(
                            0.94
                        ),
                        in:
                            RoundedRectangle(
                                cornerRadius: 18,
                                style:
                                    .continuous
                            )
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(
                            social
                                .discoverResults
                        ) {
                            profile in

                            NavigationLink {
                                FriendProfileView(
                                    userID:
                                        profile
                                            .userID
                                )
                            } label: {
                                SocialProfileRow(
                                    profile:
                                        profile
                                ) {
                                    relationshipAction(
                                        profile
                                    )
                                }
                                .padding(
                                    .horizontal,
                                    12
                                )
                                .padding(
                                    .vertical,
                                    4
                                )
                                .background(
                                    Color.white
                                        .opacity(
                                            0.94
                                        ),
                                    in:
                                        RoundedRectangle(
                                            cornerRadius:
                                                18,
                                            style:
                                                .continuous
                                        )
                                )
                                .overlay {
                                    RoundedRectangle(
                                        cornerRadius:
                                            18,
                                        style:
                                            .continuous
                                    )
                                    .stroke(
                                        clubMint,
                                        lineWidth:
                                            0.8
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private var discoverHero:
        some View {
        ZStack(
            alignment: .bottomLeading
        ) {
            Image("CommunityHero")
                .resizable()
                .scaledToFill()
                .frame(height: 170)
                .frame(
                    maxWidth: .infinity
                )
                .clipped()

            LinearGradient(
                colors: [
                    Color.clear,
                    clubForest.opacity(0.86)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Find new training friends",
                        norwegian:
                            "Finn nye treningsvenner"
                    )
                )
                .font(
                    .title2.weight(
                        .bold
                    )
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Search by name or @username and discover more of the ATHLTH community.",
                        norwegian:
                            "Søk etter navn eller @brukernavn og oppdag mer av ATHLTH-fellesskapet."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    .white.opacity(0.88)
                )
                .lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(16)
        }
        .frame(height: 170)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .shadow(
            color:
                clubForest.opacity(
                    0.13
                ),
            radius: 15,
            y: 6
        )
    }

    private var discoverSearchField:
        some View {
        HStack(spacing: 10) {
            Image(
                systemName:
                    "magnifyingglass"
            )
            .font(
                .system(
                    size: 15,
                    weight:
                        .semibold
                )
            )
            .foregroundStyle(
                clubForest
            )

            TextField(
                ATHLTHLocalization.choose(
                    english:
                        "Name or @username",
                    norwegian:
                        "Navn eller @brukernavn"
                ),
                text: $searchText
            )
            .textInputAutocapitalization(
                .never
            )
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit {
                Task {
                    await social.search(
                        searchText
                    )
                }
            }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    social.clearSearch()
                } label: {
                    Image(
                        systemName:
                            "xmark.circle.fill"
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 52)
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.96),
                    clubMint
                        .opacity(0.48)
                ],
                startPoint:
                    .leading,
                endPoint:
                    .trailing
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
                clubMint,
                lineWidth: 0.9
            )
        }
        .onChange(
            of: searchText
        ) { _, value in
            if value
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .count >= 2 {
                Task {
                    try? await Task.sleep(
                        for:
                            .milliseconds(
                                300
                            )
                    )

                    guard value ==
                            searchText
                    else {
                        return
                    }

                    await social.search(
                        value
                    )
                }
            } else {
                social.clearSearch()
            }
        }
    }

    @ViewBuilder
    private func relationshipAction(
        _ profile: SocialProfileCard
    ) -> some View {
        if social.isFollowing(profile.userID) {
            Text("Following")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(clubForest)
        } else if social.isFollowedBy(profile.userID) {
            Button(
                profile.isPrivateProfile
                    ? "Request back"
                    : "Follow back"
            ) {
                Task {
                    if profile.isPrivateProfile {
                        await social.sendFollowRequest(to: profile)
                    } else {
                        await social.follow(profile)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(clubForest)
        } else {
            switch social.relationshipState(
                with: profile.userID
            ) {
            case .outgoingPending:
                Text("Requested")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

            case .incomingPending:
                Text("Respond")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)

            case .blocked:
                Text("Blocked")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)

            case .mutualFollow:
                Button("Follow") {
                    Task {
                        await social.follow(profile)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(clubForest)

            case .none:
                Button("Follow") {
                    Task {
                        if profile.isPrivateProfile {
                            await social.sendFollowRequest(
                                to: profile
                            )
                        } else {
                            await social.follow(profile)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(clubForest)

            case .selfUser:
                EmptyView()
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.bold())
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

struct SocialFeedView: View {
    @EnvironmentObject private var social: SocialStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if social.feed.isEmpty {
                    ContentUnavailableView(
                        "Your social feed is quiet",
                        systemImage: "bolt.heart.fill",
                        description: Text("Workouts, trophies, goals and challenges can appear here when athletes you follow choose to share them.")
                    )
                    .padding(.vertical, 50)
                } else {
                    ForEach(social.feed) { item in
                        SocialActivityCard(item: item)
                    }
                }
            }
            .padding()
        }
    }
}

private struct SocialActivityCard: View {
    @EnvironmentObject private var social: SocialStore

    let item: SocialFeedItem

    @State private var commentText = ""
    @State private var showingChallenge = false

    private var canChallenge: Bool {
        item.actor.userID != social.currentUserID &&
            social.isMutualFollow(item.actor.userID)
    }

    private var cleanComment: String {
        commentText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                NavigationLink {
                    FriendProfileView(userID: item.actor.userID)
                } label: {
                    SocialAvatar(profile: item.actor, size: 42)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.actor.resolvedName)
                        .font(.subheadline.weight(.semibold))
                    Text(item.activity.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: activityIcon(item.activity.kind))
                    .foregroundStyle(ATHLTHTheme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.activity.title)
                    .font(.headline)

                if let subtitle = item.activity.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let names = item.activity.metadata?["with_names"],
                   !names.isEmpty {
                    Label(
                        "with \(names)",
                        systemImage: "person.2.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                }

                if let caption = item.activity.metadata?["caption"],
                   !caption.isEmpty {
                    Text(caption)
                        .font(.subheadline)
                        .padding(.top, 2)
                }
            }

            reactionRow

            if !item.comments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(item.comments.suffix(3)) { comment in
                        commentRow(comment)
                    }

                    if item.comments.count > 3 {
                        Text(
                            "\(item.comments.count - 3) more comment" +
                            (item.comments.count - 3 == 1 ? "" : "s")
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(
                    "Add a comment…",
                    text: $commentText,
                    axis: .vertical
                )
                .lineLimit(1...3)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Color(.tertiarySystemGroupedBackground),
                    in: RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
                .onSubmit {
                    submitComment()
                }

                Button {
                    submitComment()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            cleanComment.isEmpty
                                ? Color.secondary.opacity(0.35)
                                : ATHLTHTheme.accentDeep,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(cleanComment.isEmpty)
                .accessibilityLabel("Post comment")

                if canChallenge {
                    Button {
                        showingChallenge = true
                    } label: {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 34, height: 34)
                            .background(
                                Color.orange.opacity(0.10),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "Challenge \(item.actor.resolvedName)"
                    )
                }
            }
        }
        .padding(15)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .sheet(isPresented: $showingChallenge) {
            ChallengeCreationView(
                preselectedFriends: [item.actor]
            )
        }
    }

    private var reactionRow: some View {
        HStack(spacing: 7) {
            ForEach(SocialActivityReaction.allCases) { reaction in
                Button {
                    let mine = item.reactions.first {
                        $0.userID == social.currentUserID
                    }

                    Task {
                        await social.setReaction(
                            activityID: item.id,
                            reaction:
                                mine?.reaction == reaction
                                    ? nil
                                    : reaction
                        )
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(reaction.emoji)

                        let count = item.reactions.filter {
                            $0.reaction == reaction
                        }.count

                        if count > 0 {
                            Text("\(count)")
                                .font(.caption2.bold())
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        item.reactions.contains(where: {
                            $0.userID == social.currentUserID &&
                            $0.reaction == reaction
                        })
                            ? ATHLTHTheme.accent.opacity(0.12)
                            : Color(.tertiarySystemGroupedBackground),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if !item.comments.isEmpty {
                Label(
                    "\(item.comments.count)",
                    systemImage: "bubble.left"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
        }
    }

    @ViewBuilder
    private func commentRow(
        _ comment: SocialActivityCommentRecord
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let profile = social.profile(for: comment.userID) {
                SocialAvatar(
                    profile: profile,
                    size: 28
                )
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 28, height: 28)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: Circle()
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(commentAuthor(comment))
                        .font(.caption.weight(.semibold))

                    Text(comment.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(comment.body)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }

            Spacer(minLength: 0)
        }
        .contextMenu {
            if comment.userID == social.currentUserID ||
                item.actor.userID == social.currentUserID {
                Button(
                    "Delete comment",
                    role: .destructive
                ) {
                    Task {
                        await social.deleteComment(
                            comment.id
                        )
                    }
                }
            }
        }
    }

    private func commentAuthor(
        _ comment: SocialActivityCommentRecord
    ) -> String {
        if comment.userID == social.currentUserID {
            return "You"
        }

        return social.profile(
            for: comment.userID
        )?.resolvedName ?? "ATHLTH athlete"
    }

    private func submitComment() {
        let body = cleanComment
        guard !body.isEmpty else { return }

        commentText = ""

        Task {
            await social.addComment(
                activityID: item.id,
                body: body
            )
        }
    }

    private func activityIcon(_ kind: String) -> String {
        switch kind {
        case "workout": return "figure.run"
        case "trophy": return "trophy.fill"
        case "goal": return "target"
        case "challenge": return "person.2.fill"
        case "personal_record": return "bolt.fill"
        default: return "sparkles"
        }
    }
}

struct FriendProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var messaging: MessagingStore

    let userID: UUID

    @State private var profile: SocialFriendProfile?
    @State private var loading = true
    @State private var showingChallenge = false
    @State private var showingReport = false
    @State private var confirmBlock = false
    @State private var followOverview = SocialFollowOverview.empty
    @State private var followActionInProgress = false
    @State private var followActionError: String?

    var body: some View {
        ATHLTHPinnedHeroLayout(
            accent: ATHLTHTheme.premiumGold.opacity(0.62)
        ) {
            if let profile {
                remoteProfileHero(profile)
            } else {
                Color.clear
                    .frame(height: 236)
            }
        } content: {
            LazyVStack(spacing: 16) {
                if loading && profile == nil {
                    ProgressView("Loading profile…")
                        .padding(.top, 70)
                } else if let profile {
                    actionBar(profile)

                    if profile.card.isPrivateProfile &&
                        !social.isFollowing(userID) {
                        privateProfileNotice
                    }

                    // Keep the same visual order as the owner's profile.
                    // Privacy/RLS still controls which remote data exists.
                    if !profile.trophies.isEmpty {
                        trophyCard(profile.trophies)
                    }

                    if let performance = profile.performance {
                        performanceCard(performance)
                    }

                    if !profile.gear.isEmpty {
                        remoteGearCard(profile.gear)
                    }

                    if !profile.workoutMedia.isEmpty {
                        remoteHighlightsCard(
                            profile.workoutMedia
                        )
                    }

                    let workouts = profile.recentActivities.filter {
                        $0.activity.kind == "workout"
                    }

                    if profile.card.isPublicProfile ||
                        !workouts.isEmpty {
                        workoutHistoryCard(workouts)
                    }

                    if !profile.goals.isEmpty {
                        remoteGoalsCard(profile.goals)
                    }
                } else {
                    ContentUnavailableView(
                        "Profile unavailable",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text(
                            "This profile may be private or unavailable."
                        )
                    )
                    .padding(.top, 70)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 34)
            .padding(.bottom, 120)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep.opacity(0.74)
                        )
                        .frame(width: 32, height: 32)
                        .background(
                            Color.white.opacity(0.46),
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white.opacity(0.58),
                                    lineWidth: 0.8
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            if profile != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(
                            social.isMuted(userID)
                                ? "Unmute activity"
                                : "Mute activity"
                        ) {
                            Task {
                                await social.setMuted(
                                    userID,
                                    muted:
                                        !social.isMuted(
                                            userID
                                        )
                                )
                            }
                        }

                        Button("Report") {
                            showingReport = true
                        }

                        Button("Block User", role: .destructive) {
                            confirmBlock = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 40, height: 40)
                            .background(
                                ATHLTHTheme.cardWarm.opacity(0.82),
                                in: Circle()
                            )
                    }
                }
            }
        }
        .task {
            await load()
        }
        .refreshable {
            await load(force: true)
        }
        .sheet(isPresented: $showingChallenge) {
            if let profile {
                ChallengeCreationView(
                    preselectedFriends: [profile.card]
                )
            }
        }
        .sheet(isPresented: $showingReport) {
            if let profile {
                ReportUserView(profile: profile.card)
            }
        }
        .confirmationDialog(
            "Block this user?",
            isPresented: $confirmBlock,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                Task {
                    if await social.block(userID) {
                        await messaging.refresh()
                        dismiss()
                    }
                }
            }
        }
        .alert(
            "Follow unavailable",
            isPresented: Binding(
                get: { followActionError != nil },
                set: { visible in
                    if !visible {
                        followActionError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                followActionError = nil
            }
        } message: {
            Text(
                followActionError ??
                    "ATHLTH could not update this follow right now."
            )
        }
    }

    private func remoteProfileHero(
        _ profile: SocialFriendProfile
    ) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Image("ProfileHero")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(
                            color:
                                Color.black.opacity(0.04),
                            location: 0
                        ),
                        .init(
                            color:
                                Color.black.opacity(0.10),
                            location: 0.42
                        ),
                        .init(
                            color:
                                Color.black.opacity(0.76),
                            location: 1
                        )
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    Spacer()

                    HStack(
                        alignment: .bottom,
                        spacing: 14
                    ) {
                        SocialAvatar(
                            profile: profile.card,
                            size: 92
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white.opacity(0.96),
                                    lineWidth: 3
                                )
                        }
                        .shadow(
                            color:
                                Color.black.opacity(0.20),
                            radius: 9,
                            y: 4
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {
                            Text(
                                profile.card
                                    .resolvedName
                            )
                            .font(
                                .system(
                                    size: 27,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.70)

                            if !profile.card
                                .usernameLabel
                                .isEmpty {
                                Text(
                                    profile.card
                                        .usernameLabel
                                )
                                .font(
                                    .subheadline
                                        .weight(.medium)
                                )
                                .foregroundStyle(
                                    .white.opacity(0.86)
                                )
                            }

                            if let focus =
                                    profile
                                        .trainingFocus {
                                Text(focus.title)
                                    .font(
                                        .caption
                                            .weight(
                                                .semibold
                                            )
                                    )
                                    .foregroundStyle(
                                        .white.opacity(
                                            0.92
                                        )
                                    )
                            }

                            if let bio =
                                    profile.card.bio?
                                        .trimmingCharacters(
                                            in:
                                                .whitespacesAndNewlines
                                        ),
                               !bio.isEmpty {
                                Text(bio)
                                    .font(.caption)
                                    .foregroundStyle(
                                        .white.opacity(
                                            0.88
                                        )
                                    )
                                    .lineLimit(2)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    remoteProfileStats(
                        profile
                    )
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
                .shadow(
                    color:
                        Color.black.opacity(0.24),
                    radius: 12,
                    y: 5
                )
            }
        }
        .frame(height: 306)
        .clipped()
    }

    private func relationshipPill(
        _ title: String,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.bold))
            .foregroundStyle(ATHLTHTheme.accentDeep)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Color.white.opacity(0.66),
                in: Capsule()
            )
            .lineLimit(1)
    }

    private func remoteProfileStats(
        _ profile: SocialFriendProfile
    ) -> some View {
        HStack(spacing: 6) {
            remoteHeroStat(
                value:
                    followOverview
                        .followerCount
                        .formatted(),
                title:
                    ATHLTHLocalization.choose(
                        english: "Followers",
                        norwegian: "Følgere"
                    ),
                icon: "person.fill"
            )

            remoteHeroStat(
                value:
                    followOverview
                        .followingCount
                        .formatted(),
                title:
                    ATHLTHLocalization.choose(
                        english: "Following",
                        norwegian: "Følger"
                    ),
                icon: "person.2.fill"
            )

            remoteHeroStat(
                value:
                    (profile.performance?
                        .totalWorkoutCount ?? 0)
                        .formatted(),
                title:
                    ATHLTHLocalization.choose(
                        english: "Workouts",
                        norwegian: "Økter"
                    ),
                icon: "figure.run"
            )

            remoteHeroStat(
                value:
                    remoteLifetimeDistance(
                        profile.performance
                    ),
                title:
                    ATHLTHLocalization.choose(
                        english: "Total km",
                        norwegian: "Km totalt"
                    ),
                icon: "chart.bar.fill"
            )
        }
    }

    private func remoteHeroStat(
        value: String,
        title: String,
        icon: String
    ) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 13,
                            weight: .semibold
                        )
                    )
                    .frame(width: 15)

                Text(value)
                    .font(
                        .system(
                            size: 14,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }

            Text(title)
                .font(
                    .system(
                        size: 8.5,
                        weight: .medium
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
            Color.black.opacity(0.43),
            in: RoundedRectangle(
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
                Color.white.opacity(0.14),
                lineWidth: 0.7
            )
        }
    }

    private func remoteLifetimeDistance(
        _ performance:
            SocialPerformanceStats?
    ) -> String {
        guard let meters =
                performance?
                    .totalRunningDistanceMeters,
              meters > 0 else {
            return "0"
        }

        let kilometers =
            meters / 1_000

        if kilometers >= 1_000 {
            return String(
                format: "%.0f",
                kilometers
            )
        }

        return String(
            format: "%.1f",
            kilometers
        )
    }

    @ViewBuilder
    private func followStats(
        _ profile: SocialFriendProfile
    ) -> some View {
        let canBrowseConnections =
            !profile.card.isPrivateProfile ||
            social.isFollowing(userID)

        HStack(spacing: 0) {
            if canBrowseConnections {
                NavigationLink {
                    ProfileConnectionsView(
                        title: "Followers",
                        profiles: followOverview.followers,
                        totalCount: followOverview.followerCount
                    )
                } label: {
                    followStat(
                        value: followOverview.followerCount,
                        title: "Followers",
                        icon: "person.2.fill"
                    )
                }
                .buttonStyle(.plain)
            } else {
                followStat(
                    value: followOverview.followerCount,
                    title: "Followers",
                    icon: "person.2.fill"
                )
            }

            Divider()
                .frame(height: 34)

            if canBrowseConnections {
                NavigationLink {
                    ProfileConnectionsView(
                        title:
                        ATHLTHLocalization.choose(
                            english: "Following",
                            norwegian: "Følger"
                        ),
                        profiles: followOverview.following,
                        totalCount: followOverview.followingCount
                    )
                } label: {
                    followStat(
                        value: followOverview.followingCount,
                        title:
                        ATHLTHLocalization.choose(
                            english: "Following",
                            norwegian: "Følger"
                        ),
                        icon: "person.badge.plus"
                    )
                }
                .buttonStyle(.plain)
            } else {
                followStat(
                    value: followOverview.followingCount,
                    title:
                        ATHLTHLocalization.choose(
                            english: "Following",
                            norwegian: "Følger"
                        ),
                    icon: "person.badge.plus"
                )
            }
        }
        .padding(.vertical, 12)
        .background(
            Color.white.opacity(0.70),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private func followStat(
        value: Int,
        title: String,
        icon: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 18,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep.opacity(0.68)
                )

            VStack(
                alignment: .leading,
                spacing: 1
            ) {
                Text("\(value)")
                    .font(
                        .headline.monospacedDigit()
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(title)
                    .font(
                        .caption.weight(.medium)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .center
        )
        .contentShape(Rectangle())
    }

    private func actionBar(
        _ profile: SocialFriendProfile
    ) -> some View {
        HStack(spacing: 8) {
            mainFollowButton(profile)

            NavigationLink {
                DirectMessageThreadView(
                    friend: profile.card
                )
            } label: {
                profileActionLabel(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Message",
                            norwegian: "Melding"
                        ),
                    icon: "message",
                    tint:
                        ATHLTHTheme.accentDeep,
                    emphasized: false
                )
            }
            .buttonStyle(.plain)

            Button {
                showingChallenge = true
            } label: {
                profileActionLabel(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Challenge",
                            norwegian: "Utfordre"
                        ),
                    icon: "trophy.fill",
                    tint:
                        ATHLTHTheme
                            .premiumGold,
                    emphasized: false
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func profileActionLabel(
        title: String,
        icon: String,
        tint: Color,
        emphasized: Bool
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )

            Text(title)
                .font(
                    .system(
                        size: 11,
                        weight: .semibold
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(
            emphasized
                ? Color.white
                : ATHLTHTheme
                    .primaryText
        )
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(
            emphasized
                ? ATHLTHTheme
                    .accentDeep
                : Color.white
                    .opacity(0.90),
            in: RoundedRectangle(
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
                emphasized
                    ? Color.white
                        .opacity(0.10)
                    : tint.opacity(0.14),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.035),
            radius: 8,
            y: 3
        )
    }

    @ViewBuilder
    private func mainFollowButton(
        _ profile: SocialFriendProfile
    ) -> some View {
        let relationship =
            social.relationshipState(
                with: userID
            )
        let followsYou =
            social.isFollowedBy(userID)

        if social.isFollowing(userID) {
            Button {
                Task {
                    followActionInProgress = true
                    await social.unfollow(userID)

                    if let error = social.errorMessage {
                        followActionError = error
                    } else {
                        followOverview =
                            await social
                                .loadFollowOverview(
                                    for: userID
                                )
                    }

                    followActionInProgress = false
                }
            } label: {
                profileActionLabel(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Following",
                            norwegian: "Følger"
                        ),
                    icon: "person.fill.checkmark",
                    tint: ATHLTHTheme.accentDeep,
                    emphasized: true
                )
            }
            .buttonStyle(.plain)
            .disabled(followActionInProgress)
        } else if relationship == .outgoingPending {
            profileActionLabel(
                title:
                    ATHLTHLocalization.choose(
                        english: "Requested",
                        norwegian: "Forespurt"
                    ),
                icon: "clock.fill",
                tint: ATHLTHTheme.mutedText,
                emphasized: false
            )
        } else if relationship == .blocked {
            profileActionLabel(
                title:
                    ATHLTHLocalization.choose(
                        english: "Blocked",
                        norwegian: "Blokkert"
                    ),
                icon: "nosign",
                tint: .red,
                emphasized: false
            )
        } else if relationship == .selfUser {
            EmptyView()
        } else if profile.card.isPrivateProfile {
            Button {
                Task {
                    followActionInProgress = true
                    await social.sendFollowRequest(
                        to: profile.card
                    )

                    if let error = social.errorMessage {
                        followActionError = error
                    } else {
                        await load(force: true)
                    }

                    followActionInProgress = false
                }
            } label: {
                profileActionLabel(
                    title:
                        followsYou
                            ? ATHLTHLocalization.choose(
                                english: "Follow back",
                                norwegian: "Følg tilbake"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Follow",
                                norwegian: "Følg"
                            ),
                    icon: "person.badge.plus",
                    tint: ATHLTHTheme.accentDeep,
                    emphasized: true
                )
            }
            .buttonStyle(.plain)
            .disabled(followActionInProgress)
        } else {
            Button {
                Task {
                    followActionInProgress = true
                    await social.follow(
                        profile.card
                    )

                    if let error = social.errorMessage {
                        followActionError = error
                    } else {
                        followOverview =
                            await social
                                .loadFollowOverview(
                                    for: userID
                                )
                    }

                    followActionInProgress = false
                }
            } label: {
                profileActionLabel(
                    title:
                        followsYou
                            ? ATHLTHLocalization.choose(
                                english: "Follow back",
                                norwegian: "Følg tilbake"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Follow",
                                norwegian: "Følg"
                            ),
                    icon: "person.badge.plus",
                    tint: ATHLTHTheme.accentDeep,
                    emphasized: true
                )
            }
            .buttonStyle(.plain)
            .disabled(followActionInProgress)
        }
    }

    private var privateProfileNotice: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.title3)
                .foregroundStyle(ATHLTHTheme.accentDeep)

            Text("This profile is private")
                .font(.headline)

            Text(
                "Send a follow request to unlock the profile sections this athlete shares with approved followers."
            )
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(
            Color.white.opacity(0.76),
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
            .stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
    }

    private func remoteGearCard(
        _ items: [ProfileGearItem]
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Gear",
                        norwegian: "Utstyr"
                    ),
                    systemImage:
                        "shoeprints.fill"
                )
                .font(
                    .title3.weight(.bold)
                )

                Spacer()

                Text(
                    "\(items.count)"
                )
                .font(
                    .caption.weight(.semibold)
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            HStack(spacing: 8) {
                ForEach(
                    Array(items.prefix(3))
                ) { item in
                    HStack(spacing: 7) {
                        Image(
                            systemName:
                                item.category
                                    .systemImage
                        )
                        .font(
                            .system(
                                size: 15,
                                weight:
                                    .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .accentDeep
                        )
                        .frame(
                            width: 34,
                            height: 34
                        )
                        .background(
                            ATHLTHTheme
                                .accentSoft,
                            in:
                                RoundedRectangle(
                                    cornerRadius:
                                        10,
                                    style:
                                        .continuous
                                )
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 1
                        ) {
                            Text(item.name)
                                .font(
                                    .system(
                                        size: 9,
                                        weight:
                                            .semibold
                                    )
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(
                                    0.66
                                )

                            Text(
                                item.category
                                    .shortTitle
                            )
                            .font(
                                .system(
                                    size: 8
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                            .lineLimit(1)
                        }

                        Spacer(
                            minLength: 0
                        )
                    }
                    .padding(8)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 58
                    )
                    .background(
                        Color.black
                            .opacity(0.022),
                        in:
                            RoundedRectangle(
                                cornerRadius: 15,
                                style:
                                    .continuous
                            )
                    )
                }
            }
        }
        .padding(16)
        .background(
            Color.white.opacity(0.94),
            in: RoundedRectangle(
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
                ATHLTHTheme.border
                    .opacity(0.56),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.035),
            radius: 12,
            y: 5
        )
    }

    private func remoteHighlightsCard(
        _ media: [WorkoutMediaRecord]
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "Photos & highlights",
                        norwegian:
                            "Bilder og høydepunkter"
                    ),
                    systemImage:
                        "photo.on.rectangle.angled"
                )
                .font(
                    .title3.weight(.bold)
                )

                Spacer()

                Text(
                    ATHLTHLocalization.choose(
                        english: "Shared",
                        norwegian: "Delt"
                    )
                )
                .font(
                    .caption.weight(.semibold)
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            HStack(spacing: 8) {
                ForEach(
                    Array(media.prefix(4))
                ) { item in
                    AsyncImage(
                        url:
                            URL(
                                string:
                                    item.imageURL
                            )
                    ) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            Rectangle()
                                .fill(
                                    ATHLTHTheme
                                        .accentSoft
                                )
                                .overlay {
                                    Image(
                                        systemName:
                                            "photo"
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .accentDeep
                                    )
                                }
                        }
                    }
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 82)
                    .clipped()
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
                }
            }
        }
        .padding(16)
        .background(
            Color.white.opacity(0.94),
            in: RoundedRectangle(
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
                ATHLTHTheme.border
                    .opacity(0.56),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.035),
            radius: 12,
            y: 5
        )
    }

    private func workoutHistoryCard(
        _ items: [SocialFeedItem]
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(
                    alignment: .firstTextBaseline
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text("Recent Activity")
                            .font(
                                .title3.weight(.bold)
                            )

                        Text(
                            items.isEmpty
                                ? "No shared workouts yet."
                                : "Latest workouts shared on this profile."
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }

                    Spacer()

                    if items.count > 3 {
                        Text(
                            ATHLTHLocalization.format(
                            english: "%d shared",
                            norwegian: "%d delt",
                            items.count
                        )
                        )
                        .font(
                            .caption2.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                    }
                }

                if items.isEmpty {
                    HStack(spacing: 12) {
                        Image(
                            systemName:
                                "figure.run.circle"
                        )
                        .font(
                            .system(
                                size: 22,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                        .frame(width: 44, height: 44)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text(
                                "Nothing shared yet"
                            )
                            .font(
                                .subheadline
                                    .weight(.semibold)
                            )

                            Text(
                                "Public workouts will appear here when this athlete shares them."
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                        }

                        Spacer()
                    }
                    .padding(13)
                    .background(
                        Color.primary.opacity(0.025),
                        in: RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(
                            Array(items.prefix(4))
                        ) { item in
                            remoteActivityRow(item)

                            if item.id !=
                                items.prefix(4).last?.id {
                                Divider()
                                    .padding(.leading, 50)
                            }
                        }
                    }
                }
            }
        }
    }

    private func remoteActivityRow(
        _ item: SocialFeedItem
    ) -> some View {
        HStack(spacing: 11) {
            Image(
                systemName:
                    socialIcon(item)
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
            .frame(width: 40, height: 40)
            .background(
                ATHLTHTheme.accentSoft,
                in: RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(item.activity.title)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(
                        item.activity.createdAt,
                        style: .relative
                    )

                    if let subtitle =
                            item.activity.subtitle,
                       !subtitle.isEmpty {
                        Text("·")
                        Text(subtitle)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()
        }
        .padding(.vertical, 9)
    }

    private func remoteGoalsCard(
        _ goals: [SocialProfileGoalRecord]
    ) -> some View {
        let sorted = goals.sorted {
            if $0.isPrimary != $1.isPrimary {
                return $0.isPrimary && !$1.isPrimary
            }
            return $0.progress > $1.progress
        }

        return ATHLTHCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text("Goals")
                        .font(.headline)
                    Spacer()
                    Text("\(goals.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }

                if let goal = sorted.first {
                    Text(goal.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .lineLimit(2)

                    Text(
                        ATHLTHLocalization.format(
                            english: "%d%% complete",
                            norwegian: "%d %% fullført",
                            Int((goal.progress * 100).rounded())
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ProgressView(value: goal.progress)
                        .tint(.green)

                    if let deadline = goal.deadline {
                        Label(
                            deadline.formatted(date: .abbreviated, time: .omitted),
                            systemImage: "calendar"
                        )
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                }
            }
        }
    }

    private func performanceCard(
        _ performance:
            SocialPerformanceStats
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "Personal records",
                        norwegian:
                            "Personlige rekorder"
                    ),
                    systemImage:
                        "chart.bar.fill"
                )
                .font(
                    .title3.weight(.bold)
                )

                Spacer()

                Text(
                    ATHLTHLocalization.choose(
                        english: "Shared",
                        norwegian: "Delt"
                    )
                )
                .font(
                    .caption.weight(.semibold)
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            HStack(spacing: 8) {
                remoteRecordTile(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Fastest 1K",
                            norwegian: "Raskeste 1 km"
                        ),
                    value:
                        formatTime(
                            performance
                                .fastest1KSeconds
                        ),
                    icon: "1.circle.fill",
                    tint: .blue
                )

                remoteRecordTile(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Fastest 5K",
                            norwegian: "Raskeste 5 km"
                        ),
                    value:
                        formatTime(
                            performance
                                .fastest5KSeconds
                        ),
                    icon: "5.circle.fill",
                    tint: .green
                )

                remoteRecordTile(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Marathon",
                            norwegian: "Maraton"
                        ),
                    value:
                        formatTime(
                            performance
                                .fastestMarathonSeconds
                        ),
                    icon:
                        "flag.checkered",
                    tint: .indigo
                )

                remoteRecordTile(
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Longest run",
                            norwegian:
                                "Lengste løpetur"
                        ),
                    value:
                        formatDistance(
                            performance
                                .longestRunMeters
                        ),
                    icon:
                        "point.topleft.down.to.point.bottomright.curvepath",
                    tint: .purple
                )
            }
        }
        .padding(16)
        .background(
            Color.white.opacity(0.94),
            in: RoundedRectangle(
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
                ATHLTHTheme.border
                    .opacity(0.56),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.035),
            radius: 12,
            y: 5
        )
    }

    private func remoteRecordTile(
        title: String,
        value: String,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 12,
                        weight: .semibold
                    )
                )
                .foregroundStyle(tint)
                .frame(
                    width: 29,
                    height: 29
                )
                .background(
                    tint.opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                )

            Text(title)
                .font(
                    .system(
                        size: 8.8,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .lineLimit(2)
                .minimumScaleFactor(0.66)

            Text(value)
                .font(
                    .system(
                        size: 14,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.56)
        }
        .padding(9)
        .frame(
            maxWidth: .infinity,
            minHeight: 94,
            alignment: .topLeading
        )
        .background(
            Color.black.opacity(0.022),
            in: RoundedRectangle(
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
                tint.opacity(0.09),
                lineWidth: 0.7
            )
        }
    }

    private func trophyCard(
        _ items:
            [SocialTrophyShowcaseItem]
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "Trophy cabinet",
                        norwegian:
                            "Troféskap"
                    ),
                    systemImage:
                        "trophy.fill"
                )
                .font(
                    .title3.weight(.bold)
                )

                Spacer()

                Text(
                    ATHLTHLocalization.choose(
                        english: "Showcase",
                        norwegian: "Utstilling"
                    )
                )
                .font(
                    .caption.weight(.semibold)
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            HStack(
                alignment: .top,
                spacing: 8
            ) {
                ForEach(
                    Array(items.prefix(4))
                ) { item in
                    VStack(spacing: 5) {
                        ZStack {
                            ATHLTHTrophyPlateShape()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .black,
                                            ATHLTHTheme
                                                .accent
                                                .opacity(
                                                    0.62
                                                )
                                        ],
                                        startPoint:
                                            .topLeading,
                                        endPoint:
                                            .bottomTrailing
                                    )
                                )

                            ATHLTHMarkShape()
                                .fill(.white)
                                .frame(
                                    width: 19,
                                    height: 14
                                )
                        }
                        .frame(
                            width: 46,
                            height: 52
                        )

                        Text(item.title)
                            .font(
                                .system(
                                    size: 8.5,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(
                                0.62
                            )
                    }
                    .frame(
                        maxWidth: .infinity
                    )
                }
            }
        }
        .padding(16)
        .background(
            Color.white.opacity(0.94),
            in: RoundedRectangle(
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
                ATHLTHTheme.border
                    .opacity(0.56),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.035),
            radius: 12,
            y: 5
        )
    }

    private func load(force: Bool = false) async {
        loading = true
        async let profileTask = social.loadFriendProfile(
            userID,
            forceRefresh: force
        )
        async let followTask = social.loadFollowOverview(for: userID)

        profile = await profileTask
        followOverview = await followTask
        loading = false
    }

    private func formatTime(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainder = total % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                remainder
            )
        }

        return String(
            format: "%d:%02d",
            minutes,
            remainder
        )
    }

    private func formatDistance(_ meters: Double?) -> String {
        guard let meters, meters > 0 else { return "—" }
        return String(format: "%.1f km", meters / 1_000)
    }

    private func socialIcon(
        _ item: SocialFeedItem
    ) -> String {
        if item.activity.kind == "workout" {
            switch item.activity.metadata?["kind"] {
            case "strength":
                return "dumbbell.fill"
            case "walking", "walk":
                return "figure.walk"
            case "cycling":
                return "bicycle"
            case "running", "run":
                return "figure.run"
            default:
                return "figure.run"
            }
        }

        switch item.activity.kind {
        case "trophy":
            return "trophy.fill"
        case "goal":
            return "target"
        case "challenge":
            return "person.2.fill"
        default:
            return "sparkles"
        }
    }

    private func socialIcon(_ kind: String) -> String {
        switch kind {
        case "workout": return "figure.run"
        case "trophy": return "trophy.fill"
        case "goal": return "target"
        case "challenge": return "person.2.fill"
        default: return "sparkles"
        }
    }
}

struct ProfileConnectionsView: View {
    let title: String
    let profiles: [SocialProfileCard]
    let totalCount: Int

    var body: some View {
        List {
            if profiles.isEmpty {
                ContentUnavailableView(
                    totalCount > 0
                        ? "Profiles unavailable"
                        : "No \(title.lowercased()) yet",
                    systemImage: "person.2",
                    description: Text(
                        totalCount > profiles.count
                            ? "Some profiles are not currently visible to you."
                            : "This list is empty."
                    )
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(profiles) { profile in
                    NavigationLink {
                        FriendProfileView(userID: profile.userID)
                    } label: {
                        HStack(spacing: 12) {
                            SocialAvatar(profile: profile, size: 44)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.resolvedName)
                                    .font(.subheadline.weight(.semibold))

                                Text(profile.usernameLabel)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SocialPrivacySettingsView: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore

    @State private var draft: SocialPrivacySettings?
    @State private var saving = false

    var body: some View {
        Form {
            if let binding = draftBinding {
                Section("Profile") {
                    Picker("Profile visibility", selection: binding.profileVisibility) {
                        Text("Private").tag("private")
                        Text("Followers").tag("friends")
                        Text("Public").tag("public")
                    }

                    Toggle("Allow follow requests", isOn: binding.allowFriendRequests)

                    Toggle(
                        "Show when I’m online",
                        isOn: binding.showOnlineStatus
                    )

                    Text(
                        "Online status is shown only to people who follow you. It turns off when ATHLTH is no longer active and expires automatically if the app cannot update it."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Messages") {
                    Picker("Who can message me", selection: binding.allowDirectMessages) {
                        Text("Mutual follows + requests").tag("requests")
                        Text("Mutual follows only").tag("friends")
                        Text("Nobody").tag("nobody")
                    }

                    Text("Message requests let people you do not mutually follow send one text message. They cannot send another message or share workouts, plans, routes or challenges until you accept. Blocking always stops messaging.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Shared with allowed viewers") {
                    Toggle("Training now", isOn: binding.shareTrainingPresence)

                    Toggle(
                        "Share live workout position",
                        isOn: binding.shareLiveWorkoutLocation
                    )
                    .onChange(
                        of:
                            binding.wrappedValue
                                .shareLiveWorkoutLocation
                    ) { _, enabled in
                        if !enabled {
                            draft?
                                .shareLiveWorkoutHeartRate =
                                false
                        }
                    }

                    if binding.wrappedValue.shareLiveWorkoutLocation {
                        Picker(
                            "Live position audience",
                            selection:
                                binding.liveLocationVisibility
                        ) {
                            Text("Followers")
                                .tag("followers")
                            Text("Mutual follows")
                                .tag("mutuals")
                        }

                        Toggle(
                            "Share live heart rate",
                            isOn:
                                binding
                                    .shareLiveWorkoutHeartRate
                        )

                        Text(
                            binding.wrappedValue
                                .shareLiveWorkoutHeartRate
                                ? "Your current position and current workout heart rate can be shown to the selected live audience. ATHLTH keeps only the latest live point, and it expires after about 90 seconds."
                                : "Your current position is shared only while a supported outdoor workout is active. Heart rate stays private. ATHLTH keeps only the latest point and it expires after about 90 seconds."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Toggle("Performance Stats", isOn: binding.sharePerformanceStats)
                    Toggle("Trophy Cabinet", isOn: binding.shareTrophyCabinet)
                    Toggle("Recent activity", isOn: binding.shareRecentActivity)
                    Toggle("Running PRs", isOn: binding.shareRunningPRs)
                    Toggle("Strength PRs", isOn: binding.shareStrengthPRs)
                    Toggle("Goals", isOn: binding.shareGoals)
                    Toggle("Gear", isOn: binding.shareGear)
                    Toggle("Workout totals", isOn: binding.shareWorkoutTotals)

                    Text("Strength PRs use manually entered reps and weight and are labeled Manual in Activity. Running PRs use qualifying Apple Health workout data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Challenges") {
                    Picker("Challenge invites", selection: binding.allowChallengeInvites) {
                        Text("Mutual follows").tag("friends")
                        Text("Everyone").tag("everyone")
                        Text("Nobody").tag("nobody")
                    }

                    Text("Manual and verified challenge results always keep their verification label.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            Text("Save Social Privacy")
                            Spacer()
                            if saving { ProgressView() }
                        }
                    }
                    .disabled(saving)
                }
            } else {
                ProgressView("Loading privacy settings…")
            }
        }
        .navigationTitle("Social Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if social.privacy == nil {
                await social.refresh()
            }
            draft = social.privacy
        }
    }

    private var draftBinding: Binding<SocialPrivacySettings>? {
        guard draft != nil else { return nil }

        return Binding(
            get: { draft! },
            set: { draft = $0 }
        )
    }

    private func save() async {
        guard let draft else { return }

        saving = true
        let result = await social.updatePrivacy(draft)

        if case .success = result {
            await social.syncOwnGoals(
                goalStore.goals,
                enabled: draft.shareGoals
            )

            await realtime.configureOnlinePresence(
                appIsActive: true,
                enabled: draft.showOnlineStatus
            )

            if !draft.shareLiveWorkoutLocation {
                if realtime.currentSession?
                    .ghostChallengeID != nil {
                    // Ghost Race can continue after the athlete stops
                    // sharing their exact live position.
                    await realtime
                        .setCurrentLiveLocationSharing(
                            false
                        )
                } else {
                    await realtime
                        .leaveCurrentLiveWorkout()
                }
            }
        }

        if let visibility = ProfileVisibility(rawValue: draft.profileVisibility) {
            settings.profileVisibility = visibility
        }
        settings.shareTrainingPresence = draft.shareTrainingPresence

        saving = false
    }
}

struct BlockedUsersView: View {
    @EnvironmentObject private var social: SocialStore

    var body: some View {
        List {
            if social.blockedUsers.isEmpty {
                ContentUnavailableView(
                    "No blocked users",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
            } else {
                ForEach(social.blockedUsers) { blocked in
                    HStack(spacing: 12) {
                        SocialAvatar(profile: blocked.profile, size: 42)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(blocked.profile.resolvedName)
                            Text(blocked.profile.usernameLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Unblock") {
                            Task { await social.unblock(blocked.id) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await social.refresh()
        }
    }
}

struct ReportUserView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore

    let profile: SocialProfileCard

    @State private var reason = "harassment"
    @State private var details = ""
    @State private var submitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SocialProfileRow(profile: profile) {
                        EmptyView()
                    }
                }

                Section("Reason") {
                    Picker("Reason", selection: $reason) {
                        Text("Spam").tag("spam")
                        Text("Harassment").tag("harassment")
                        Text("Impersonation").tag("impersonation")
                        Text("Unsafe content").tag("unsafe_content")
                        Text("Other").tag("other")
                    }

                    TextField(
                        "Additional details (optional)",
                        text: $details,
                        axis: .vertical
                    )
                    .lineLimit(3...7)
                }

                Section {
                    Button("Submit Report") {
                        Task {
                            submitting = true
                            let success = await social.report(
                                profile.userID,
                                reason: reason,
                                details: details
                            )
                            submitting = false
                            if success { dismiss() }
                        }
                    }
                    .disabled(submitting)
                }
            }
            .navigationTitle("Report User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct SocialAvatar: View {
    let profile: SocialProfileCard
    let size: CGFloat

    var body: some View {
        Group {
            if let avatarURL = profile.avatarURL,
               let url = URL(string: avatarURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
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
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        Circle()
            .fill(ATHLTHTheme.accent.opacity(0.12))
            .overlay {
                Text(profile.resolvedName.prefix(1).uppercased())
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(ATHLTHTheme.accent)
            }
    }
}

private struct SocialProfileRow<Accessory: View>: View {
    let profile: SocialProfileCard
    let accessory: Accessory

    init(
        profile: SocialProfileCard,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.profile = profile
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            SocialAvatar(profile: profile, size: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.resolvedName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if !profile.usernameLabel.isEmpty {
                    Text(profile.usernameLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            accessory
        }
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 17)
        )
    }
}

private extension View {
    func socialCard() -> some View {
        self
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            }
    }
}


private struct WorkoutInviteLaunchSheet: View {
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var session:
        AppSessionStore
    @EnvironmentObject private var settings:
        AppSettingsStore
    @EnvironmentObject private var social:
        SocialStore
    @EnvironmentObject private var strengthWorkout:
        StrengthWorkoutStore
    @EnvironmentObject private var watchConnection:
        AppleWatchConnectionStore
    @EnvironmentObject private var spotify:
        SpotifyPlaybackStore
    @EnvironmentObject private var gear:
        ProfileGearStore
    @EnvironmentObject private var phoneWorkout:
        IPhoneWorkoutStore
    @EnvironmentObject private var ghostRace:
        GhostRaceStore

    let invite: SocialWorkoutInviteDisplay

    @State private var captureDevice:
        WorkoutCaptureDevice

    init(invite: SocialWorkoutInviteDisplay) {
        self.invite = invite
        _captureDevice = State(
            initialValue:
                invite.participant.captureDevice ==
                    "apple_watch"
                    ? .appleWatch
                    : .iPhone
        )
    }
    @State private var isStarting = false
    @State private var launchError: String?
    @State private var showingStrengthWorkout = false

    private var payload:
        SocialWorkoutInvitePayload? {
        invite.session.invitePayload
    }

    private var copiedWorkout:
        PlannedSession? {
        guard let payload else {
            return nil
        }

        var copy = payload.recipientCopy()
        copy.sharedSourceOwnerID =
            invite.session.creatorID
        copy.sharedSourceSessionID =
            payload.workout.id
        return copy
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    introCard

                    if let copiedWorkout {
                        workoutSummary(
                            copiedWorkout
                        )
                        devicePicker

                        lobbyStatusCard

                        Button {
                            readyAndWait(
                                copiedWorkout
                            )
                        } label: {
                            HStack(spacing: 9) {
                                if isStarting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(
                                        systemName:
                                            captureDevice ==
                                                .appleWatch
                                            ? "applewatch"
                                            : "iphone"
                                    )
                                }

                                Text(
                                    startButtonTitle
                                )
                                .font(
                                    .headline.weight(
                                        .semibold
                                    )
                                )
                            }
                            .frame(
                                maxWidth: .infinity
                            )
                        }
                        .buttonStyle(
                            .borderedProminent
                        )
                        .controlSize(.large)
                        .tint(ATHLTHTheme.accent)
                        .disabled(
                            isStarting ||
                            (
                                captureDevice ==
                                    .appleWatch &&
                                !watchConnection
                                    .isReady
                            )
                        )
                    } else {
                        ContentUnavailableView(
                            ATHLTHLocalization.choose(
                                english:
                                    "Workout copy unavailable",
                                norwegian:
                                    "Øktkopien er ikke tilgjengelig"
                            ),
                            systemImage:
                                "exclamationmark.triangle",
                            description:
                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Ask the sender to send a new Train Together invitation.",
                                        norwegian:
                                            "Be avsenderen sende en ny Tren sammen-invitasjon."
                                    )
                                )
                        )
                        .padding(.vertical, 28)
                    }

                    if let launchError {
                        Text(launchError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(
                                .center
                            )
                    }
                }
                .padding(16)
            }
            .background(
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHTheme.accent
                            .opacity(0.18)
                )
            )
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Train Together",
                    norwegian: "Tren sammen"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        role:
                            isStarting
                                ? .destructive
                                : nil
                    ) {
                        if isStarting {
                            Task {
                                await social
                                    .declineWorkoutInvite(
                                        invite
                                    )
                                dismiss()
                            }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Text(
                            isStarting
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "Leave",
                                    norwegian:
                                        "Forlat"
                                )
                                : ATHLTHLocalization.choose(
                                    english:
                                        "Not now",
                                    norwegian:
                                        "Ikke nå"
                                )
                        )
                    }
                }
            }
        }
        .interactiveDismissDisabled(
            isStarting
        )
        .fullScreenCover(
            isPresented:
                $showingStrengthWorkout
        ) {
            ActiveStrengthWorkoutView()
                .environmentObject(
                    strengthWorkout
                )
                .environmentObject(
                    session
                )
        }
    }

    private var introCard: some View {
        ATHLTHCard {
            HStack(spacing: 12) {
                if let creator =
                        invite.creator {
                    SocialAvatar(
                        profile: creator,
                        size: 48
                    )
                } else {
                    Image(
                        systemName:
                            "person.2.fill"
                    )
                    .font(.title3)
                    .foregroundStyle(
                        ATHLTHTheme.accent
                    )
                    .frame(
                        width: 48,
                        height: 48
                    )
                    .background(
                        ATHLTHTheme
                            .accent
                            .opacity(0.10),
                        in: Circle()
                    )
                }

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Invitation accepted",
                            norwegian:
                                "Invitasjonen er godtatt"
                        )
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "You get your own copy of the sender's workout.",
                            norwegian:
                                "Du får din egen kopi av økten til avsenderen."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    private func workoutSummary(
        _ workout: PlannedSession
    ) -> some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 10
            ) {
                HStack {
                    Label(
                        workout.title,
                        systemImage:
                            workout.kind
                                .systemImage
                    )
                    .font(
                        .headline.weight(
                            .semibold
                        )
                    )

                    Spacer()
                }

                if workout.kind ==
                    .strength {
                    Text(
                        ATHLTHLocalization.format(
                            english:
                                "%d exercises copied",
                            norwegian:
                                "%d øvelser kopiert",
                            workout.exercises.count
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let route =
                            payload?.route {
                    Text(
                        String(
                            format:
                                "%.1f km · %@",
                            route
                                .distanceKilometers,
                            ATHLTHLocalization.choose(
                                english:
                                    "route copied",
                                norwegian:
                                    "rute kopiert"
                            )
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let running =
                            workout
                                .resolvedRunningWorkouts
                                .first {
                    Text(running.title)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                }

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Device, gear and music stay personal to you.",
                        norwegian:
                            "Enhet, utstyr og musikk velger du selv."
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var devicePicker: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 10
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Where do you want to train?",
                        norwegian:
                            "Hvor vil du trene?"
                    )
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )

                HStack(spacing: 10) {
                    deviceButton(
                        device: .iPhone,
                        title: "iPhone",
                        icon: "iphone",
                        enabled: true
                    )

                    deviceButton(
                        device: .appleWatch,
                        title: "Apple Watch",
                        icon: "applewatch",
                        enabled:
                            watchConnection.isReady
                    )
                }

                if !watchConnection.isReady {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Apple Watch is unavailable right now. You can still start the copied workout on iPhone.",
                            norwegian:
                                "Apple Watch er ikke tilgjengelig akkurat nå. Du kan fortsatt starte øktkopien på iPhone."
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func deviceButton(
        device: WorkoutCaptureDevice,
        title: String,
        icon: String,
        enabled: Bool
    ) -> some View {
        Button {
            guard enabled else { return }
            captureDevice = device
        } label: {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.title3)

                Text(title)
                    .font(
                        .caption
                            .weight(.semibold)
                    )
            }
            .foregroundStyle(
                captureDevice == device
                    ? Color.white
                    : ATHLTHTheme
                        .primaryText
            )
            .frame(
                maxWidth: .infinity,
                minHeight: 72
            )
            .background(
                captureDevice == device
                    ? ATHLTHTheme.accent
                    : Color(
                        .secondarySystemGroupedBackground
                    ),
                in: RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private var startButtonTitle:
        String {
        if isStarting {
            return ATHLTHLocalization.choose(
                english: "Waiting for shared start…",
                norwegian: "Venter på felles start…"
            )
        }

        return ATHLTHLocalization.choose(
            english:
                captureDevice == .appleWatch
                    ? "Ready on Apple Watch"
                    : "Ready on iPhone",
            norwegian:
                captureDevice == .appleWatch
                    ? "Klar på Apple Watch"
                    : "Klar på iPhone"
        )
    }

    private var lobbyStatusCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Shared start",
                        norwegian: "Felles start"
                    )
                )
                .font(.subheadline.weight(.semibold))

                let participants =
                    social.workoutParticipants
                        .filter {
                            $0.sessionID ==
                                invite.session.id
                        }

                ForEach(participants) { participant in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(
                                participant.launchFailedAt != nil
                                    ? Color.red
                                    : participant.workoutStartedAt != nil
                                        ? ATHLTHTheme.accent
                                        : participant.readyAt != nil
                                            ? Color.green
                                            : Color.orange
                            )
                            .frame(width: 8, height: 8)

                        Text(participant.displayNameSnapshot)
                            .font(.caption.weight(.semibold))

                        Spacer()

                        Text(
                            participant.launchFailedAt != nil
                                ? ATHLTHLocalization.choose(
                                    english: "Couldn’t start",
                                    norwegian: "Kunne ikke starte"
                                )
                                : participant.workoutStartedAt != nil
                                    ? ATHLTHLocalization.choose(
                                        english: "Training",
                                        norwegian: "Trener"
                                    )
                                    : participant.readyAt != nil
                                        ? ATHLTHLocalization.choose(
                                            english: "Ready",
                                            norwegian: "Klar"
                                        )
                                        : participant.state == .accepted
                                            ? ATHLTHLocalization.choose(
                                                english: "Accepted",
                                                norwegian: "Godtatt"
                                            )
                                            : ATHLTHLocalization.choose(
                                                english: "Invited",
                                                norwegian: "Invitert"
                                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                if let startAt =
                        social.workoutSessions
                            .first(
                                where: {
                                    $0.id ==
                                        invite.session.id
                                }
                            )?
                            .coordinatedStartAt {
                    TimelineView(
                        .periodic(
                            from: .now,
                            by: 0.2
                        )
                    ) { context in
                        let remaining =
                            max(
                                startAt
                                    .timeIntervalSince(
                                        context.date
                                    ),
                                0
                            )
                        let count =
                            max(
                                Int(
                                    ceil(remaining)
                                ),
                                0
                            )

                        HStack {
                            Spacer()

                            Text(
                                count > 0
                                    ? "\(count)"
                                    : ATHLTHLocalization.choose(
                                        english: "GO",
                                        norwegian: "KJØR"
                                    )
                            )
                            .font(
                                .system(
                                    size: 42,
                                    weight: .black,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme.accent
                            )

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "When the sender starts the group, ATHLTH counts down 3–2–1 and starts your copied workout on your chosen device.",
                        norwegian:
                            "Når avsender starter gruppen, teller ATHLTH ned 3–2–1 og starter øktkopien på enheten du valgte."
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .task {
            try? await social.refreshWorkoutLobby(
                sessionID: invite.session.id
            )
        }
    }

    private func readyAndWait(
        _ workout: PlannedSession
    ) {
        guard !isStarting else { return }

        isStarting = true
        launchError = nil

        Task { @MainActor in
            guard await social.markCurrentUserReady(
                sessionID: invite.session.id,
                captureDevice: captureDevice
            ) else {
                launchError =
                    social.errorMessage ??
                    ATHLTHLocalization.choose(
                        english: "Could not mark you as ready.",
                        norwegian: "Kunne ikke markere deg som klar."
                    )
                isStarting = false
                return
            }

            guard await social.waitForCoordinatedWorkoutStart(
                sessionID: invite.session.id
            ) else {
                launchError =
                    social.errorMessage ??
                    ATHLTHLocalization.choose(
                        english: "The shared workout was cancelled.",
                        norwegian: "Fellesøkten ble avbrutt."
                    )
                isStarting = false
                return
            }

            isStarting = false
            start(workout)
        }
    }

    private func start(
        _ workout: PlannedSession
    ) {
        guard !isStarting else { return }

        isStarting = true
        launchError = nil

        Task { @MainActor in
            do {
                switch workout.kind {
                case .strength:
                    let trackingMode =
                        payload?
                            .strengthTrackingMode ??
                        (
                            workout.exercises
                                .isEmpty
                                ? .simple
                                : .advanced
                        )

                    var advanced =
                        payload?
                            .strengthAdvancedConfiguration ??
                        .standard
                    advanced.spotifyPlaylist = nil
                    advanced.spotifyAutoplay = false

                    let audioCoach =
                        workout
                            .audioCoachConfiguration ??
                        advanced
                            .audioCoach
                            .watchConfiguration

                    let didStart =
                        try await WorkoutLaunchCoordinator
                            .startStrength(
                            workout: workout,
                            captureDevice:
                                captureDevice,
                            trackingMode:
                                trackingMode,
                            selectedFriends: [],
                            audioCoach:
                                audioCoach,
                            advancedConfiguration:
                                advanced,
                            session: session,
                            settings: settings,
                            social: social,
                            strengthWorkout:
                                strengthWorkout,
                            watchConnection:
                                watchConnection,
                            spotify: spotify
                        )

                    guard didStart else {
                        isStarting = false
                        return
                    }

                    showingStrengthWorkout =
                        true

                case .running:
                    let runningWorkout =
                        workout
                            .resolvedRunningWorkouts
                            .first
                    let route =
                        payload?.route
                    let mode:
                        RunQuickStartMode =
                        runningWorkout != nil
                            ? .structured
                            : route != nil
                                ? .route
                                : .free

                    try await WorkoutLaunchCoordinator
                        .startRunQuick(
                            configuration:
                                RunQuickStartConfiguration(
                                    mode: mode,
                                    route: route,
                                    workout:
                                        runningWorkout,
                                    captureDevice:
                                        captureDevice,
                                    audioCoach:
                                        workout
                                            .audioCoachConfiguration ??
                                        .disabled,
                                    routeAlerts:
                                        payload?
                                            .routeAlerts ??
                                        settings
                                            .routeAlertConfiguration,
                                    ghostTargetDurationSeconds:
                                        nil,
                                    ghostUpdates:
                                        nil,
                                    autoPauseEnabled:
                                        workout
                                            .autoPauseEnabled ??
                                        settings
                                            .autoPauseOutdoorWorkouts,
                                    spotifyPlaylist: nil,
                                    spotifyAutoplay: false,
                                    friends: [],
                                    gearIDs: []
                                ),
                            session: session,
                            settings: settings,
                            gear: gear,
                            phoneWorkout:
                                phoneWorkout,
                            watchConnection:
                                watchConnection,
                            spotify: spotify,
                            ghostRace:
                                ghostRace
                        )
                    _ = await social
                        .confirmCurrentJoinedWorkoutStarted()
                    dismiss()

                case .walking:
                    try await WorkoutLaunchCoordinator
                        .startWalkQuick(
                            configuration:
                                WalkQuickStartConfiguration(
                                    captureDevice:
                                        captureDevice,
                                    audioCoach:
                                        workout
                                            .audioCoachConfiguration ??
                                        .disabled,
                                    autoPauseEnabled:
                                        workout
                                            .autoPauseEnabled ??
                                        settings
                                            .autoPauseOutdoorWorkouts,
                                    spotifyPlaylist: nil,
                                    spotifyAutoplay: false,
                                    friends: [],
                                    gearIDs: []
                                ),
                            settings: settings,
                            gear: gear,
                            phoneWorkout:
                                phoneWorkout,
                            watchConnection:
                                watchConnection,
                            spotify: spotify
                        )
                    _ = await social
                        .confirmCurrentJoinedWorkoutStarted()
                    dismiss()

                case .mobility,
                     .recovery,
                     .custom:
                    throw NSError(
                        domain:
                            "ATHLTH.TrainTogether",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                ATHLTHLocalization.choose(
                                    english:
                                        "This copied workout type cannot be launched yet.",
                                    norwegian:
                                        "Denne typen øktkopi kan ikke startes ennå."
                                )
                        ]
                    )
                }
            } catch {
                await social
                    .markCurrentJoinedWorkoutLaunchFailed()
                launchError =
                    error.localizedDescription
            }

            isStarting = false
        }
    }
}
