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
        case .friends: return "Friends"
        case .messages: return "Messages"
        case .requests: return "Requests"
        case .discover: return "Discover"
        }
    }
}

struct ProfileFriendsSection: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var messaging: MessagingStore

    var body: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Friends")
                        .font(.title3.weight(.bold))
                    Text("Train, compare and challenge each other.")
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

            if social.friends.isEmpty {
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
                            Text("Search by @username and send a friend request.")
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
                        ForEach(social.friends.prefix(6)) { friend in
                            NavigationLink {
                                FriendProfileView(userID: friend.userID)
                            } label: {
                                VStack(spacing: 7) {
                                    SocialAvatar(profile: friend, size: 54)

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
    }
}

struct SocialHubView: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var messaging: MessagingStore

    let initialTab: SocialHubTab

    @State private var selectedTab: SocialHubTab
    @State private var searchText = ""

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
                    MessageInboxView()
                case .requests:
                    requestsContent
                case .discover:
                    discoverContent
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Social")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SocialPrivacySettingsView()
                } label: {
                    Image(systemName: "hand.raised.fill")
                }
            }
        }
        .task {
            await social.refresh()
            await messaging.refresh()
        }
        .refreshable {
            await social.refresh()
            await messaging.refresh()
        }
    }

    private var friendsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("\(social.friends.count) Friends")
                        .font(.title3.bold())
                    Spacer()
                    Button {
                        selectedTab = .discover
                    } label: {
                        Label("Find", systemImage: "person.badge.plus")
                            .font(.caption.weight(.semibold))
                    }
                }

                if social.friends.isEmpty {
                    ContentUnavailableView(
                        "No friends yet",
                        systemImage: "person.2",
                        description: Text("Find people by their ATHLTH username.")
                    )
                    .padding(.vertical, 50)
                } else {
                    ForEach(social.friends) { friend in
                        NavigationLink {
                            FriendProfileView(userID: friend.userID)
                        } label: {
                            SocialProfileRow(profile: friend) {
                                Text("Friends")
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
                        description: Text("Friend and workout invitations will appear here.")
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
                                            ?? "A friend"
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
                    sectionTitle("Incoming")

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
                    sectionTitle("Sent")

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

                    TextField("@username", text: $searchText)
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
                        "Find ATHLTH friends",
                        systemImage: "person.2.badge.plus",
                        description: Text("Search for a unique @username.")
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
    private func relationshipAction(_ profile: SocialProfileCard) -> some View {
        switch social.relationshipState(with: profile.userID) {
        case .friends:
            Text("Friends")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accent)

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

        case .none:
            Button("Add") {
                Task { await social.sendFriendRequest(to: profile) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(ATHLTHTheme.accent)

        case .selfUser:
            EmptyView()
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
                        description: Text("Friend workouts, trophies, goals and challenges can appear here when they choose to share them.")
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
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var health: HealthKitManager

    let userID: UUID

    @State private var profile: SocialFriendProfile?
    @State private var ownStats: ProfilePerformanceStats?
    @State private var loading = true
    @State private var showingChallenge = false
    @State private var showingReport = false
    @State private var confirmRemove = false
    @State private var confirmBlock = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if loading && profile == nil {
                    ProgressView("Loading profile…")
                        .padding(.top, 70)
                } else if let profile {
                    profileHeader(profile)
                    actionBar(profile)

                    if let performance = profile.performance {
                        compareCard(friend: performance)
                    }

                    if !profile.trophies.isEmpty {
                        trophyCard(profile.trophies)
                    }

                    if !profile.recentActivities.isEmpty {
                        recentActivityCard(profile.recentActivities)
                    }
                } else {
                    ContentUnavailableView(
                        "Profile unavailable",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("This profile may be private or unavailable.")
                    )
                    .padding(.top, 70)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(profile?.card.usernameLabel ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if profile != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if social.relationshipState(with: userID) == .friends {
                            Button("Remove Friend", role: .destructive) {
                                confirmRemove = true
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
                ChallengeCreationView(preselectedFriends: [profile.card])
            }
        }
        .sheet(isPresented: $showingReport) {
            if let profile {
                ReportUserView(profile: profile.card)
            }
        }
        .confirmationDialog(
            "Remove this friend?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove Friend", role: .destructive) {
                Task {
                    await social.removeFriend(userID)
                }
            }
        }
        .confirmationDialog(
            "Block this user?",
            isPresented: $confirmBlock,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                Task {
                    await social.block(userID)
                }
            }
        }
    }

    private func profileHeader(_ profile: SocialFriendProfile) -> some View {
        VStack(spacing: 13) {
            SocialAvatar(profile: profile.card, size: 104)

            VStack(spacing: 4) {
                Text(profile.card.resolvedName)
                    .font(.title.bold())

                if !profile.card.usernameLabel.isEmpty {
                    Text(profile.card.usernameLabel)
                        .foregroundStyle(.secondary)
                }
            }

            if let bio = profile.card.bio, !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if let focus = profile.trainingFocus {
                Label(focus.title, systemImage: focus.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: Capsule()
                    )
            }

            if let presence = profile.presence {
                Label(
                    presence.state == "training"
                        ? "Training now\(presence.workoutTitle.map { " · \($0)" } ?? "")"
                        : "Available",
                    systemImage: presence.state == "training"
                        ? "figure.run"
                        : "circle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func actionBar(_ profile: SocialFriendProfile) -> some View {
        let relationship = social.relationshipState(with: userID)

        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                relationshipButton(profile.card)

                NavigationLink {
                    DirectMessageThreadView(friend: profile.card)
                } label: {
                    Label(
                        relationship == .friends ? "Message" : "Message request",
                        systemImage: "message.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if relationship == .friends {
                Button {
                    showingChallenge = true
                } label: {
                    Label("Challenge", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accent)
            }
        }
    }

    @ViewBuilder
    private func relationshipButton(_ card: SocialProfileCard) -> some View {
        switch social.relationshipState(with: userID) {
        case .friends:
            Label("Friends", systemImage: "checkmark")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())

        case .outgoingPending:
            Text("Request sent")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())

        case .incomingPending:
            if let request = social.incomingRequests.first(where: {
                $0.profile.userID == userID
            }) {
                HStack(spacing: 8) {
                    Button("Decline") {
                        Task {
                            await social.decline(request)
                            await load(force: true)
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button("Accept") {
                        Task {
                            await social.accept(request)
                            await load(force: true)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)
                    .frame(maxWidth: .infinity)
                }
            } else {
                Text("Friend request pending")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: Capsule()
                    )
            }

        case .none:
            Button {
                Task { await social.sendFriendRequest(to: card) }
            } label: {
                Label("Add Friend", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

        case .blocked:
            Text("Blocked")
                .frame(maxWidth: .infinity)
                .foregroundStyle(.red)

        case .selfUser:
            EmptyView()
        }
    }

    private func compareCard(friend: SocialPerformanceStats) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Compare")
                    .font(.title3.bold())
                Text("You vs \(profile?.card.resolvedName ?? "Friend")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            comparisonHeader

            compareRow(
                "Fastest 1K",
                own: formatTime(ownStats?.fastestOneKilometer?.duration),
                friend: formatTime(friend.fastest1KSeconds)
            )
            compareRow(
                "Fastest 5K",
                own: formatTime(ownStats?.fastestFiveKilometers?.duration),
                friend: formatTime(friend.fastest5KSeconds)
            )
            compareRow(
                "Marathon",
                own: formatTime(ownStats?.fastestMarathon?.duration),
                friend: formatTime(friend.fastestMarathonSeconds)
            )
            compareRow(
                "Longest Run",
                own: formatDistance(ownStats?.longestRunMeters),
                friend: formatDistance(friend.longestRunMeters)
            )
            compareRow(
                "Workouts",
                own: ownStats.map { "\($0.totalWorkoutCount)" } ?? "—",
                friend: "\(friend.totalWorkoutCount)"
            )
            compareRow(
                "Running",
                own: formatDistance(ownStats?.totalRunningDistanceMeters),
                friend: formatDistance(friend.totalRunningDistanceMeters)
            )
        }
        .padding()
        .socialCard()
    }

    private var comparisonHeader: some View {
        HStack {
            Text("STAT")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("YOU")
                .frame(width: 90, alignment: .trailing)
            Text("FRIEND")
                .frame(width: 90, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .bold))
        .tracking(1)
        .foregroundStyle(.secondary)
    }

    private func compareRow(
        _ title: String,
        own: String,
        friend: String
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(own)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(width: 90, alignment: .trailing)

            Text(friend)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private func trophyCard(_ items: [SocialTrophyShowcaseItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trophy Cabinet")
                .font(.title3.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        VStack(spacing: 8) {
                            ZStack {
                                ATHLTHTrophyPlateShape()
                                    .fill(
                                        LinearGradient(
                                            colors: [.black, ATHLTHTheme.accent.opacity(0.62)],
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
        .padding()
        .socialCard()
    }

    private func recentActivityCard(_ items: [SocialFeedItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.title3.bold())

            ForEach(items.prefix(5)) { item in
                HStack(spacing: 10) {
                    Image(systemName: socialIcon(item.activity.kind))
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 30, height: 30)
                        .background(ATHLTHTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))

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

                if item.id != items.prefix(5).last?.id {
                    Divider().opacity(0.4)
                }
            }
        }
        .padding()
        .socialCard()
    }

    private func load(force: Bool = false) async {
        loading = true
        async let profileTask = social.loadFriendProfile(userID, forceRefresh: force)
        async let ownTask = try? health.profilePerformanceStats(forceRefresh: force)

        profile = await profileTask
        ownStats = await ownTask
        loading = false
    }

    private func formatTime(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainder = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }

        return String(format: "%d:%02d", minutes, remainder)
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

struct SocialPrivacySettingsView: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var draft: SocialPrivacySettings?
    @State private var saving = false

    var body: some View {
        Form {
            if let binding = draftBinding {
                Section("Profile") {
                    Picker("Who can view my profile", selection: binding.profileVisibility) {
                        Text("Private").tag("private")
                        Text("Friends").tag("friends")
                        Text("Public").tag("public")
                    }

                    Toggle("Appear in username search", isOn: binding.discoverable)
                    Toggle("Allow friend requests", isOn: binding.allowFriendRequests)
                }

                Section("Messages") {
                    Picker("Who can message me", selection: binding.allowDirectMessages) {
                        Text("Friends + requests").tag("requests")
                        Text("Friends only").tag("friends")
                        Text("Nobody").tag("nobody")
                    }

                    Text("Message requests let people who are not your friends send one text message. They cannot send another message or share workouts, plans, routes or challenges until you accept. Blocking always stops messaging.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Shared with allowed viewers") {
                    Toggle("Training now", isOn: binding.shareTrainingPresence)
                    Toggle("Performance Stats", isOn: binding.sharePerformanceStats)
                    Toggle("Trophy Cabinet", isOn: binding.shareTrophyCabinet)
                    Toggle("Recent activity", isOn: binding.shareRecentActivity)
                    Toggle("Running PRs", isOn: binding.shareRunningPRs)
                    Toggle("Strength PRs", isOn: binding.shareStrengthPRs)
                    Toggle("Completed goals", isOn: binding.shareGoals)
                    Toggle("Workout totals", isOn: binding.shareWorkoutTotals)

                    Text("Strength PRs use manually entered reps and weight and are labeled Manual in Activity. Running PRs use qualifying Apple Health workout data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Challenges") {
                    Picker("Challenge invites", selection: binding.allowChallengeInvites) {
                        Text("Friends").tag("friends")
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
        await social.updatePrivacy(draft)

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
