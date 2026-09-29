import SwiftUI

enum SocialHubTab: String, CaseIterable, Identifiable {
    case feed
    case friends
    case messages
    case requests
    case discover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: return "Feed"
        case .friends: return "Following"
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
                    SocialHubView(initialTab: .friends)
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
                                                : ATHLTHTheme.accent,
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
                                    ? ATHLTHTheme.accent
                                    : Color(.secondarySystemGroupedBackground),
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
                case .friends:
                    friendsContent
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
        .background(ATHLTHPremiumCanvas(accent: ATHLTHTheme.accent.opacity(0.20)))
        .navigationTitle("Social")
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

    private var friendsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("\(social.following.count) Following")
                        .font(.title3.bold())
                    Spacer()
                    Button {
                        selectedTab = .discover
                    } label: {
                        Label("Find", systemImage: "person.badge.plus")
                            .font(.caption.weight(.semibold))
                    }
                }

                if !realtime.visibleLiveSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            "Live now",
                            systemImage:
                                "dot.radiowaves.left.and.right"
                        )
                        .font(.headline)
                        .foregroundStyle(
                            ATHLTHTheme.vitality
                        )

                        ForEach(
                            realtime.visibleLiveSessions
                                .prefix(6)
                        ) { session in
                            NavigationLink {
                                ATHLTHLiveWorkoutMapView(
                                    session: session
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    Image(
                                        systemName:
                                            session.ghostChallengeID ==
                                            nil
                                                ? "figure.run"
                                                : "flag.checkered"
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme.vitality
                                    )
                                    .frame(
                                        width: 38,
                                        height: 38
                                    )
                                    .background(
                                        ATHLTHTheme.vitality
                                            .opacity(0.10),
                                        in: Circle()
                                    )

                                    VStack(
                                        alignment: .leading,
                                        spacing: 2
                                    ) {
                                        Text(session.title)
                                            .font(
                                                .subheadline
                                                    .weight(
                                                        .semibold
                                                    )
                                            )
                                            .foregroundStyle(
                                                .primary
                                            )

                                        Text(
                                            session.ghostChallengeID ==
                                                nil
                                                ? "Live workout"
                                                : "Live Ghost Run"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(
                                            .secondary
                                        )
                                    }

                                    Spacer()

                                    Image(
                                        systemName:
                                            "chevron.right"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }
                                .padding(12)
                                .background(
                                    Color(
                                        .secondarySystemGroupedBackground
                                    ),
                                    in: RoundedRectangle(
                                        cornerRadius: 16
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if social.following.isEmpty {
                    ContentUnavailableView(
                        "Not following anyone yet",
                        systemImage: "person.2",
                        description: Text("Find people by their ATHLTH username.")
                    )
                    .padding(.vertical, 50)
                } else {
                    ForEach(social.following) { friend in
                        NavigationLink {
                            FriendProfileView(userID: friend.userID)
                        } label: {
                            SocialProfileRow(profile: friend) {
                                Text("Following")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.accent)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
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
                                        .foregroundStyle(ATHLTHTheme.accent)
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
                                Button("Decline") {
                                    Task {
                                        await social.declineWorkoutInvite(invite)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)

                                Button("Join") {
                                    Task {
                                        await social.acceptWorkoutInvite(invite)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(ATHLTHTheme.accent)
                                .frame(maxWidth: .infinity)
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
                                .tint(ATHLTHTheme.accent)
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

    private var discoverContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Name or @username", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit {
                            Task { await social.search(searchText) }
                        }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            social.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 15)
                )
                .onChange(of: searchText) { _, value in
                    if value.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard value == searchText else { return }
                            await social.search(value)
                        }
                    } else {
                        social.clearSearch()
                    }
                }

                if searchText.isEmpty {
                    ContentUnavailableView(
                        "Find ATHLTH users",
                        systemImage: "person.2.badge.plus",
                        description: Text("Search by name or @username.")
                    )
                    .padding(.vertical, 45)
                } else if social.discoverResults.isEmpty {
                    Text("No matching ATHLTH users.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 35)
                } else {
                    ForEach(social.discoverResults) { profile in
                        NavigationLink {
                            FriendProfileView(userID: profile.userID)
                        } label: {
                            SocialProfileRow(profile: profile) {
                                relationshipAction(profile)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func relationshipAction(
        _ profile: SocialProfileCard
    ) -> some View {
        if social.isFollowing(profile.userID) {
            Text("Following")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accent)
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
            .tint(ATHLTHTheme.accent)
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

            case .friends:
                Button("Follow") {
                    Task {
                        await social.follow(profile)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(ATHLTHTheme.accent)

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
                .tint(ATHLTHTheme.accent)

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

            HStack(spacing: 8) {
                ForEach(SocialActivityReaction.allCases) { reaction in
                    Button {
                        let mine = item.reactions.first {
                            $0.userID == social.currentUserID
                        }

                        Task {
                            await social.setReaction(
                                activityID: item.id,
                                reaction: mine?.reaction == reaction ? nil : reaction
                            )
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(reaction.emoji)
                            let count = item.reactions.filter { $0.reaction == reaction }.count
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption2.bold())
                            }
                        }
                        .padding(.horizontal, 9)
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
            }
        }
        .padding(15)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20)
        )
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
                    followStats(profile)
                    actionBar(profile)

                    if profile.card.isPrivateProfile &&
                        !social.isFollowing(userID) {
                        privateProfileNotice
                    }

                    // Match the owner's profile order. RLS simply returns no
                    // rows for sections the athlete has not shared.
                    if !profile.gear.isEmpty {
                        remoteGearCard(profile.gear)
                    }

                    let workouts = profile.recentActivities.filter {
                        $0.activity.kind == "workout"
                    }
                    if !workouts.isEmpty {
                        workoutHistoryCard(workouts)
                    }

                    if !profile.goals.isEmpty {
                        remoteGoalsCard(profile.goals)
                    }

                    if let performance = profile.performance {
                        performanceCard(performance)
                    }

                    if !profile.trophies.isEmpty {
                        trophyCard(profile.trophies)
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
            .padding(.top, 14)
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
    }

    private func remoteProfileHero(
        _ profile: SocialFriendProfile
    ) -> some View {
        GeometryReader { proxy in
            ZStack {
                Image("ProfileHero")
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: .leading
                    )
                    .clipped()

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.92),
                        ATHLTHTheme.cardWarm.opacity(0.74),
                        ATHLTHTheme.cardWarm.opacity(0.28)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    colors: [
                        Color.clear,
                        ATHLTHTheme.canvasBottom.opacity(0.38)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(alignment: .center, spacing: 16) {
                    SocialAvatar(
                        profile: profile.card,
                        size: 96
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                Color.white.opacity(0.95),
                                lineWidth: 3
                            )
                    }
                    .shadow(
                        color: .black.opacity(0.08),
                        radius: 10,
                        x: 0,
                        y: 5
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text("PROFILE")
                            .font(.caption2.weight(.bold))
                            .tracking(1.6)
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep.opacity(0.62)
                            )

                        Text(profile.card.resolvedName)
                            .font(.system(size: 27, weight: .bold))
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )
                            .lineLimit(2)
                            .minimumScaleFactor(0.76)

                        if !profile.card.usernameLabel.isEmpty {
                            Text(profile.card.usernameLabel)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )
                        }

                        HStack(spacing: 6) {
                            if social.isMutualFollow(userID) {
                                relationshipPill(
                                    "Mutual follow",
                                    systemImage: "person.2.fill"
                                )
                            } else if social.isFollowedBy(userID) {
                                relationshipPill(
                                    "Follows you",
                                    systemImage: "person.fill.checkmark"
                                )
                            }

                            if let focus = profile.trainingFocus {
                                relationshipPill(
                                    focus.title,
                                    systemImage: focus.systemImage
                                )
                            }
                        }

                        if let bio = profile.card.bio?
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ),
                           !bio.isEmpty {
                            Text(bio)
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText.opacity(0.72)
                                )
                                .lineLimit(2)
                                .padding(.top, 1)
                        }
                    }

                    Spacer(minLength: 6)
                }
                .padding(.horizontal, 24)
                .padding(.top, 72)
                .padding(.bottom, 24)
            }
        }
        .frame(height: 236)
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
                        title: "Followers"
                    )
                }
                .buttonStyle(.plain)
            } else {
                followStat(
                    value: followOverview.followerCount,
                    title: "Followers"
                )
            }

            Divider()
                .frame(height: 34)

            if canBrowseConnections {
                NavigationLink {
                    ProfileConnectionsView(
                        title: "Following",
                        profiles: followOverview.following,
                        totalCount: followOverview.followingCount
                    )
                } label: {
                    followStat(
                        value: followOverview.followingCount,
                        title: "Following"
                    )
                }
                .buttonStyle(.plain)
            } else {
                followStat(
                    value: followOverview.followingCount,
                    title: "Following"
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
        title: String
    ) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(ATHLTHTheme.primaryText)

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func actionBar(_ profile: SocialFriendProfile) -> some View {
        let isMutual = social.isMutualFollow(userID)

        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                mainFollowButton(profile)

                NavigationLink {
                    DirectMessageThreadView(friend: profile.card)
                } label: {
                    Label(
                        isMutual ? "Message" : "Message request",
                        systemImage: "message.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.bordered)
                .tint(ATHLTHTheme.accentDeep)
            }

            if isMutual {
                Button {
                    showingChallenge = true
                } label: {
                    Label("Challenge", systemImage: "bolt.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .buttonStyle(.bordered)
                .tint(ATHLTHTheme.accent)
            }
        }
    }

    @ViewBuilder
    private func mainFollowButton(
        _ profile: SocialFriendProfile
    ) -> some View {
        let relationship = social.relationshipState(with: userID)
        let followsYou = social.isFollowedBy(userID)

        if social.isFollowing(userID) {
            Button {
                Task {
                    await social.unfollow(userID)
                    followOverview = await social.loadFollowOverview(
                        for: userID
                    )
                }
            } label: {
                Label("Following", systemImage: "person.fill.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.bordered)
            .tint(ATHLTHTheme.accentDeep)
        } else if relationship == .outgoingPending {
            Label("Requested", systemImage: "clock.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.mutedText)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    Color.primary.opacity(0.05),
                    in: Capsule()
                )
        } else if relationship == .blocked {
            Label("Blocked", systemImage: "nosign")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        } else if relationship == .selfUser {
            EmptyView()
        } else if profile.card.isPrivateProfile {
            Button {
                Task {
                    await social.sendFollowRequest(to: profile.card)
                }
            } label: {
                Label(
                    followsYou ? "Request to follow back" : "Request to follow",
                    systemImage: "person.badge.plus"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accentDeep)
        } else {
            Button {
                Task {
                    await social.follow(profile.card)
                    followOverview = await social.loadFollowOverview(
                        for: userID
                    )
                }
            } label: {
                Label(
                    followsYou ? "Follow back" : "Follow",
                    systemImage: "person.badge.plus"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accentDeep)
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
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Gear")
                        .font(.headline)
                    Spacer()
                    Text("\(items.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }

                ForEach(Array(items.prefix(4))) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.category.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 42, height: 42)
                            .background(
                                ATHLTHTheme.accentSoft,
                                in: RoundedRectangle(
                                    cornerRadius: 13,
                                    style: .continuous
                                )
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )
                            Text(item.category.shortTitle)
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )
                        }

                        Spacer()

                        if item.isFeatured {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme.premiumGold
                                )
                        }
                    }
                }
            }
        }
    }

    private func workoutHistoryCard(
        _ items: [SocialFeedItem]
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Workout History")
                    .font(.headline)

                ForEach(Array(items.prefix(5))) { item in
                    HStack(spacing: 10) {
                        Image(systemName: socialIcon(item.activity.kind))
                            .foregroundStyle(ATHLTHTheme.accent)
                            .frame(width: 36, height: 36)
                            .background(
                                ATHLTHTheme.accentSoft,
                                in: RoundedRectangle(
                                    cornerRadius: 11,
                                    style: .continuous
                                )
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.activity.title)
                                .font(.subheadline.weight(.semibold))
                            if let subtitle = item.activity.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text(item.activity.createdAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
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
                        "\(Int((goal.progress * 100).rounded()))% complete"
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
        _ performance: SocialPerformanceStats
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Performance")
                    .font(.headline)

                remoteStatRow(
                    "Fastest 1K",
                    value: formatTime(performance.fastest1KSeconds)
                )
                remoteStatRow(
                    "Fastest 5K",
                    value: formatTime(performance.fastest5KSeconds)
                )
                remoteStatRow(
                    "Marathon",
                    value: formatTime(performance.fastestMarathonSeconds)
                )
                remoteStatRow(
                    "Longest Run",
                    value: formatDistance(performance.longestRunMeters)
                )
                remoteStatRow(
                    "Workouts",
                    value: "\(performance.totalWorkoutCount)"
                )
                remoteStatRow(
                    "Running",
                    value: formatDistance(
                        performance.totalRunningDistanceMeters
                    )
                )
            }
        }
    }

    private func remoteStatRow(
        _ title: String,
        value: String
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
        }
    }

    private func trophyCard(
        _ items: [SocialTrophyShowcaseItem]
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Trophies")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items) { item in
                            VStack(spacing: 8) {
                                ZStack {
                                    ATHLTHTrophyPlateShape()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    .black,
                                                    ATHLTHTheme.accent
                                                        .opacity(0.62)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )

                                    ATHLTHMarkShape()
                                        .fill(.white)
                                        .frame(width: 30, height: 22)
                                }
                                .frame(width: 72, height: 82)

                                Text(item.title)
                                    .font(.caption2.bold())
                                    .lineLimit(1)

                                Text(item.stageLabel)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 105)
                        }
                    }
                }
            }
        }
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

                        Text(
                            "Your current position is shared only while a supported outdoor workout is active. ATHLTH keeps only the latest point and it expires after about 90 seconds."
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

            if !draft.shareLiveWorkoutLocation,
               realtime.currentSession?.ghostChallengeID == nil {
                await realtime.leaveCurrentLiveWorkout()
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
