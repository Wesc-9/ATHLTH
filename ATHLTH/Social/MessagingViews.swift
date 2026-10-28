import CoreLocation
import SwiftUI

struct MessageInboxDestinationView: View {
    @State private var showingNewMessage = false

    var body: some View {
        MessageInboxView {
            showingNewMessage = true
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingNewMessage) {
            NewMessageView()
        }
    }
}

private enum MessageInboxFilter: String, CaseIterable, Identifiable {
    case all
    case unread
    case direct
    case groups
    case archive

    // Open private messages first for every account. Group and mixed
    // conversations remain available as separate, explicit filters.
    static let mainFilters: [MessageInboxFilter] = [
        .direct, .unread, .groups, .all
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return ATHLTHLocalization.choose(english: "All", norwegian: "Alle")
        case .unread:
            return ATHLTHLocalization.choose(english: "Unread", norwegian: "Uleste")
        case .direct:
            return ATHLTHLocalization.choose(english: "Messages", norwegian: "Meldinger")
        case .groups:
            return ATHLTHLocalization.choose(english: "Groups", norwegian: "Grupper")
        case .archive:
            return ATHLTHLocalization.choose(english: "Archive", norwegian: "Arkiv")
        }
    }

    var icon: String {
        switch self {
        case .all: return "tray.full"
        case .unread: return "envelope.badge"
        case .direct: return "bubble.left"
        case .groups: return "person.3"
        case .archive: return "archivebox"
        }
    }
}

struct MessageInboxView: View {
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var groups: CommunityGroupStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var realtime:
        ATHLTHRealtimeSocialStore

    var onNewMessage: () -> Void = {}

    @State private var arenaInboxVisibleCount = 0
    @State private var searchText = ""
    @State private var showingSearch = false
    @State private var selectedFilter:
        MessageInboxFilter = .direct
    @State private var selectedWorkoutInvite:
        SocialWorkoutInviteDisplay?
    @State private var coachPinned = true
    @State private var coachConversationState:
        RecoveryCoachConversationState?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                messagesHeader

                if showingSearch {
                    inboxSearch
                        .transition(
                            .move(edge: .top)
                                .combined(with: .opacity)
                        )
                }

                // Recent conversations are shortcuts, not part of the
                // selected inbox filter. Keep them above the tabs even
                // when private Messages is the default.
                if selectedFilter != .archive &&
                    !recentConversations.isEmpty {
                    recentConversationsStrip
                }

                inboxFilterBar

                if selectedFilter == .all && requestCount > 0 {
                    inboxSectionLabel(
                        ATHLTHLocalization.choose(
                            english: "NEEDS YOUR RESPONSE",
                            norwegian: "KREVER SVAR"
                        ),
                        count: requestCount
                    )
                    LazyVStack(spacing: 10) {
                        ForEach(requestPersonItems) { item in
                            inboxPersonRow(item)
                        }
                        ATHLTHCommunityClubInboxSection()
                    }
                }

                if selectedFilter == .groups {
                    ATHLTHCommunityClubInboxSection()
                }

                if selectedFilter == .all || selectedFilter == .groups {
                    ATHLTHClubChatInboxSection(searchText: searchText)
                }

                ATHLTHArenaInboxSection(
                    filterKey: selectedFilter.rawValue,
                    onVisibleCountChanged: { arenaInboxVisibleCount = $0 }
                )

                if let error = displayableError {
                    inboxErrorCard(error)
                }

                if !regularPersonItems.isEmpty ||
                    shouldShowCoachConversation {
                    inboxSectionLabel(
                        normalizedSearch.isEmpty
                            ? selectedFilter.title
                                .uppercased()
                            : ATHLTHLocalization.choose(
                                english: "RESULTS",
                                norwegian: "RESULTATER"
                            ),
                        count:
                            regularPersonItems.count +
                            (
                                shouldShowCoachConversation
                                    ? 1
                                    : 0
                            )
                    )

                    LazyVStack(spacing: 10) {
                        if shouldShowCoachConversation &&
                            coachPinned {
                            coachInboxLink
                        }

                        ForEach(regularPersonItems) { item in
                            inboxPersonRow(item)
                        }

                        if shouldShowCoachConversation &&
                            !coachPinned {
                            coachInboxLink
                        }
                    }
                }

                if shouldShowEmptyState {
                    premiumEmptyState
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 0)
            .padding(.bottom, 34)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.accent.opacity(0.10)
            )
        )
        .refreshable {
            async let socialRefresh: Void = social.refresh(
                challengeStore: challenges
            )
            async let messageRefresh: Void = messaging.refresh(force: true)
            async let clubRefresh: Void = groups.refresh(force: true)
            _ = await (socialRefresh, messageRefresh, clubRefresh)
            await groups.refreshRecentChatActivity(force: true)
        }
        .task {
            refreshCoachInboxState()
            await social.refresh(
                challengeStore: challenges
            )
            await messaging.refresh()
            await groups.refresh()
            await groups.refreshRecentChatActivity()
            messaging.loadPinnedConversations()
            await realtime.refreshOnlineUsers()
        }
        .onAppear {
            refreshCoachInboxState()
        }
        .sheet(
            item: $selectedWorkoutInvite
        ) { invite in
            WorkoutInviteLaunchSheet(
                invite: invite
            )
        }
    }

    @ViewBuilder
    private func inboxPersonRow(_ item: MessagePersonInboxItem) -> some View {
                            Group {
                                if let workoutInvite =
                                        item.pendingWorkoutInvites.first {
                                    Button {
                                        selectedWorkoutInvite =
                                            workoutInvite
                                    } label: {
                                        MessagePersonRow(
                                            item: item,
                                            isOnline:
                                                realtime.isOnline(
                                                    item.friend.userID
                                                )
                                        )
                                    }
                                } else if item.conversation != nil {
                                    NavigationLink {
                                        DirectMessageThreadView(
                                            friend: item.friend
                                        )
                                    } label: {
                                        MessagePersonRow(
                                            item: item,
                                            isOnline:
                                                realtime.isOnline(
                                                    item.friend.userID
                                                )
                                        )
                                    }
                                } else if let firstChallenge =
                                            (
                                                item.pendingChallenges.first ??
                                                item.outgoingChallenges.first
                                            ) {
                                    NavigationLink {
                                        ChallengeDetailView(
                                            challengeID:
                                                firstChallenge.id
                                        )
                                    } label: {
                                        MessagePersonRow(
                                            item: item,
                                            isOnline:
                                                realtime.isOnline(
                                                    item.friend.userID
                                                )
                                        )
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if let conversation =
                                        item.conversation {
                                    Button {
                                        withAnimation(
                                            .easeInOut(duration: 0.18)
                                        ) {
                                            messaging.togglePinned(
                                                conversation.id
                                            )
                                        }
                                    } label: {
                                        Label(
                                            messaging.isPinned(
                                                conversation.id
                                            )
                                                ? "Unpin conversation"
                                                : "Pin conversation",
                                            systemImage:
                                                messaging.isPinned(
                                                    conversation.id
                                                )
                                                    ? "pin.slash"
                                                    : "pin.fill"
                                        )
                                    }

                                    Button {
                                        withAnimation(
                                            .easeInOut(duration: 0.18)
                                        ) {
                                            messaging.toggleArchived(
                                                conversation.id
                                            )
                                        }
                                    } label: {
                                        Label(
                                            messaging.isArchived(
                                                conversation.id
                                            )
                                                ? ATHLTHLocalization.choose(
                                                    english: "Move to inbox",
                                                    norwegian: "Flytt til innboks"
                                                )
                                                : ATHLTHLocalization.choose(
                                                    english: "Archive",
                                                    norwegian: "Arkiver"
                                                ),
                                            systemImage:
                                                messaging.isArchived(
                                                    conversation.id
                                                )
                                                    ? "tray.and.arrow.up"
                                                    : "archivebox"
                                        )
                                    }
                                }
                            }
    }

    private var messagesHeader: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            HStack(alignment: .center) {
                NavigationLink {
                    ATHLTHProfileView()
                } label: {
                    ownProfileAvatar
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    ATHLTHLocalization.choose(
                        english: "Open your profile",
                        norwegian: "Åpne profilen din"
                    )
                )

                Spacer()

                Text("ATHLTH")
                    .font(
                        .system(
                            size: 23,
                            weight: .medium,
                            design: .rounded
                        )
                    )
                    .tracking(7)
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .padding(.leading, 7)

                Spacer()

                HStack(spacing: 9) {
                    headerAction(
                        systemImage:
                            showingSearch
                                ? "xmark"
                                : "magnifyingglass",
                        accessibilityLabel:
                            showingSearch
                                ? ATHLTHLocalization.choose(
                                    english: "Close search",
                                    norwegian: "Lukk søk"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Search messages",
                                    norwegian: "Søk i meldinger"
                                )
                    ) {
                        withAnimation(
                            .easeInOut(
                                duration: 0.20
                            )
                        ) {
                            showingSearch.toggle()

                            if !showingSearch {
                                searchText = ""
                            }
                        }
                    }

                    headerAction(
                        systemImage: "plus",
                        accessibilityLabel:
                            ATHLTHLocalization.choose(
                                english: "New message",
                                norwegian: "Ny melding"
                            ),
                        action: onNewMessage
                    )
                }
            }

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "INNER CIRCLE",
                        norwegian: "INNER CIRCLE"
                    )
                )
                .font(
                    .system(
                        size: 10,
                        weight: .semibold
                    )
                )
                .tracking(3.2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

                Text(
                    ATHLTHLocalization.choose(
                        english: "Messages",
                        norwegian: "Meldinger"
                    )
                )
                .font(
                    .system(
                        size: 40,
                        weight: .bold,
                        design: .serif
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "The people who move you forward.",
                        norwegian:
                            "Menneskene som får deg videre."
                    )
                )
                .font(
                    .system(
                        size: 16,
                        weight: .regular
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var ownProfileAvatar:
        some View {
        if let avatarURL =
                session.profile.avatarURL {
            ATHLTHStorageImage(
                url: avatarURL
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    ownProfileAvatarFallback
                }
            }
            .frame(
                width: 48,
                height: 48
            )
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(
                        Color.white.opacity(
                            0.96
                        ),
                        lineWidth: 2
                    )
            }
        } else {
            ownProfileAvatarFallback
                .frame(
                    width: 48,
                    height: 48
                )
        }
    }

    private var ownProfileAvatarFallback:
        some View {
        Circle()
            .fill(
                ATHLTHTheme.accentSoft
            )
            .overlay {
                Image(
                    systemName: "person.fill"
                )
                .font(
                    .system(
                        size: 21,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
            }
    }

    private struct RecentInboxConversation: Identifiable {
        enum Destination {
            case person(MessagePersonInboxItem)
            case club(CommunityGroupRecord)
        }

        let id: String
        let lastActivityAt: Date
        let destination: Destination
    }

    /// One chronological row for people and joined clubs with real messages.
    /// Invite-only entries and clubs with no chat history are not recents.
    private var recentConversations: [RecentInboxConversation] {
        let people: [RecentInboxConversation] =
            personInboxItems.compactMap { item in
                guard let conversation = item.conversation,
                      !messaging.isArchived(conversation.id),
                      let lastActivityAt =
                        item.lastMessage?.createdAt ??
                        conversation.lastMessageAt
                else { return nil }

                return RecentInboxConversation(
                    id: "person:\(item.id.uuidString)",
                    lastActivityAt: lastActivityAt,
                    destination: .person(item)
                )
            }

        let clubs: [RecentInboxConversation] =
            groups.joinedGroups.compactMap { club in
                let loadedLastMessageAt =
                    groups.messages(in: club.id).last?.createdAt
                let fetchedLastMessageAt =
                    groups.recentChatActivityByGroup[club.id]
                // Compare the two optional timestamps directly; no array
                // allocation or traversal is needed for every club.
                let lastActivityAt: Date?
                switch (loadedLastMessageAt, fetchedLastMessageAt) {
                case let (loaded?, fetched?):
                    lastActivityAt = max(loaded, fetched)
                case let (loaded?, nil):
                    lastActivityAt = loaded
                case let (nil, fetched?):
                    lastActivityAt = fetched
                case (nil, nil):
                    lastActivityAt = nil
                }

                guard let lastActivityAt else { return nil }

                return RecentInboxConversation(
                    id: "club:\(club.id.uuidString)",
                    lastActivityAt: lastActivityAt,
                    destination: .club(club)
                )
            }

        return Array(
            (people + clubs)
                .sorted {
                    if $0.lastActivityAt == $1.lastActivityAt {
                        return $0.id < $1.id
                    }
                    return $0.lastActivityAt > $1.lastActivityAt
                }
                .prefix(8)
        )
    }

    private var recentConversationsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(recentConversations) { recent in
                    switch recent.destination {
                    case .person(let person):
                        recentPersonLink(person)
                    case .club(let club):
                        recentClubLink(club)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func recentPersonLink(
        _ item: MessagePersonInboxItem
    ) -> some View {
        NavigationLink {
            DirectMessageThreadView(friend: item.friend)
        } label: {
            recentPersonBadge(item)
        }
        .buttonStyle(.plain)
    }

    private func recentClubLink(
        _ club: CommunityGroupRecord
    ) -> some View {
        NavigationLink {
            CommunityGroupDetailView(group: club, initialTab: .chat)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    CommunityGroupIdentityAvatar(group: club, size: 60)
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.94), lineWidth: 2)
                        }

                    Image(systemName: "person.3.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 21, height: 21)
                        .background(ATHLTHTheme.accentDeep, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white, lineWidth: 2)
                        }
                }

                Text(club.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)
                    .frame(width: 74)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            ATHLTHLocalization.choose(
                english: "Club chat: \(club.name)",
                norwegian: "Klubbchat: \(club.name)"
            )
        )
    }

    private func recentPersonBadge(
        _ item: MessagePersonInboxItem
    ) -> some View {
        VStack(spacing: 6) {
            ZStack(
                alignment:
                    .bottomTrailing
            ) {
                SocialAvatar(
                    profile: item.friend,
                    size: 60
                )
                .overlay {
                    Circle()
                        .stroke(
                            Color.white.opacity(
                                0.94
                            ),
                            lineWidth: 2
                        )
                }

                if realtime.isOnline(
                    item.friend.userID
                ) {
                    Circle()
                        .fill(
                            Color.green
                        )
                        .frame(
                            width: 14,
                            height: 14
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white,
                                    lineWidth: 2
                                )
                        }
                } else if item.needsResponse {
                    Circle()
                        .fill(
                            ATHLTHTheme
                                .premiumGold
                        )
                        .frame(
                            width: 14,
                            height: 14
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white,
                                    lineWidth: 2
                                )
                        }
                }
            }

            Text(
                item.friend
                    .resolvedName
            )
            .font(
                .system(
                    size: 11,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme.primaryText
            )
            .lineLimit(1)
            .frame(
                width: 74
            )
        }
    }

    private var inboxFilterBar: some View {
        HStack(spacing: 5) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(MessageInboxFilter.mainFilters) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedFilter = filter
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: filter.icon)
                            .font(.system(size: 12, weight: .medium))
                        Text(filter.title)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        selectedFilter == filter
                            ? ATHLTHTheme.accentDeep
                            : ATHLTHTheme.mutedText
                    )
                    .padding(.horizontal, 9)
                    .frame(height: 40)
                    .background(
                        selectedFilter == filter
                            ? ATHLTHTheme.accentSoft
                            : Color.white.opacity(0.74),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.035),
                                          lineWidth: 0.7)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    selectedFilter == filter ? .isSelected : []
                )
                    }
                }
            }

            Menu {
                Button {
                    selectedFilter = .archive
                } label: {
                    Label(MessageInboxFilter.archive.title,
                          systemImage: "archivebox")
                }
                if selectedFilter == .archive {
                    Button {
                        selectedFilter = .all
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Back to all messages",
                                norwegian: "Tilbake til alle meldinger"
                            ),
                            systemImage: "tray.full"
                        )
                    }
                }
            } label: {
                Image(systemName:
                        selectedFilter == .archive ? "archivebox" : "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .frame(width: 37, height: 40)
                    .background(
                        selectedFilter == .archive
                            ? ATHLTHTheme.accentSoft
                            : Color.white.opacity(0.74),
                        in: Capsule()
                    )
            }
            .accessibilityLabel(MessageInboxFilter.archive.title)
        }
    }

    private func inboxMetric(
        value: Int,
        label: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 2
        ) {
            Text("\(value)")
                .font(
                    .system(
                        size: 17,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )

            Text(label)
                .font(
                    .system(
                        size: 10,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(1)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(
            .horizontal,
            12
        )
        .padding(
            .vertical,
            10
        )
        .background(
            Color.white
                .opacity(0.56),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
    }

    private var inboxSummaryText: String {
        if messaging.unreadCount > 0 {
            return ATHLTHLocalization.choose(
                english:
                    messaging.unreadCount == 1
                        ? "1 unread message"
                        : "\(messaging.unreadCount) unread messages",
                norwegian:
                    messaging.unreadCount == 1
                        ? "1 ulest melding"
                        : "\(messaging.unreadCount) uleste meldinger"
            )
        }

        if totalRequestCount > 0 {
            return ATHLTHLocalization.choose(
                english:
                    totalRequestCount == 1
                        ? "1 person needs your response"
                        : "\(totalRequestCount) people need your response",
                norwegian:
                    totalRequestCount == 1
                        ? "1 person venter på svar"
                        : "\(totalRequestCount) personer venter på svar"
            )
        }

        if personInboxItems.isEmpty {
            return ATHLTHLocalization.choose(
                english:
                    "Your conversations",
                norwegian:
                    "Dine samtaler"
            )
        }

        return ATHLTHLocalization.choose(
            english:
                personInboxItems.count == 1
                    ? "1 conversation"
                    : "\(personInboxItems.count) conversations",
            norwegian:
                personInboxItems.count == 1
                    ? "1 samtale"
                    : "\(personInboxItems.count) samtaler"
        )
    }

    private func headerAction(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .frame(width: 42, height: 42)
                .background(
                    Color.white.opacity(0.74),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(
                            Color.white.opacity(0.90),
                            lineWidth: 0.8
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var inboxSearch: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ATHLTHTheme.mutedText)

            TextField(
                "Search messages, people or keywords…",
                text: $searchText
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 50)
        .background(
            Color.white.opacity(0.82),
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
                Color.white.opacity(0.94),
                lineWidth: 1
            )
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(0.035),
            radius: 10,
            y: 4
        )
    }

    private func inboxSectionLabel(
        _ title: String,
        count: Int
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

            if count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        ATHLTHTheme.premiumGoldSoft,
                        in: Capsule()
                    )
            }

            Spacer()
        }
        .padding(.top, 2)
    }

    private var inboxEmptyTitle: String {
        guard normalizedSearch.isEmpty else {
            return ATHLTHLocalization.choose(
                english: "No conversations found",
                norwegian: "Ingen samtaler funnet"
            )
        }
        switch selectedFilter {
        case .all:
            return ATHLTHLocalization.choose(
                english: "No messages yet", norwegian: "Ingen meldinger ennå"
            )
        case .unread:
            return ATHLTHLocalization.choose(
                english: "You're all caught up", norwegian: "Du er ajour"
            )
        case .direct:
            return ATHLTHLocalization.choose(
                english: "No messages yet", norwegian: "Ingen meldinger ennå"
            )
        case .groups:
            return ATHLTHLocalization.choose(
                english: "No group conversations", norwegian: "Ingen gruppesamtaler"
            )
        case .archive:
            return ATHLTHLocalization.choose(
                english: "Your archive is empty", norwegian: "Arkivet er tomt"
            )
        }
    }

    private var inboxEmptyDescription: String {
        guard normalizedSearch.isEmpty else {
            return ATHLTHLocalization.choose(
                english: "Try another name, username or message keyword.",
                norwegian: "Prøv et annet navn, brukernavn eller søkeord."
            )
        }
        switch selectedFilter {
        case .all:
            return ATHLTHLocalization.choose(
                english: "Your conversations and requests appear here.",
                norwegian: "Samtaler og forespørsler vises her."
            )
        case .unread:
            return ATHLTHLocalization.choose(
                english: "There are no unread conversations.",
                norwegian: "Du har ingen uleste samtaler."
            )
        case .direct:
            return ATHLTHLocalization.choose(
                english: "Start a conversation with someone you follow.",
                norwegian: "Start en samtale med noen du følger."
            )
        case .groups:
            return ATHLTHLocalization.choose(
                english: "Your Arena and group conversations appear here.",
                norwegian: "Arena- og gruppesamtaler vises her."
            )
        case .archive:
            return ATHLTHLocalization.choose(
                english: "Archived conversations will appear here.",
                norwegian: "Arkiverte samtaler vises her."
            )
        }
    }

    private var premiumEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: normalizedSearch.isEmpty
                  ? selectedFilter.icon : "magnifyingglass")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 66, height: 66)
                .background(ATHLTHTheme.premiumGoldSoft, in: Circle())

            VStack(spacing: 5) {
                Text(inboxEmptyTitle)
                    .font(.title3.weight(.semibold))
                Text(inboxEmptyDescription)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 24)
        .background(
            Color.white.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private func inboxErrorCard(
        _ message: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(ATHLTHLocalization.choose(
                    english: "Messages could not refresh",
                    norwegian: "Kunne ikke oppdatere meldinger"
                ))
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineLimit(2)
            }

            Spacer()

            Button {
                Task {
                    await messaging.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .frame(width: ATHLTHPlanDesign.minTapHeight,
                           height: ATHLTHPlanDesign.minTapHeight)
                    .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Try updating messages again",
                norwegian: "Prøv å oppdatere meldingene igjen"
            ))
        }
        .padding(14)
        .background(
            Color.white.opacity(0.78),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private var displayableError: String? {
        guard let error = messaging.errorMessage else {
            return nil
        }

        if error.localizedCaseInsensitiveContains(
            "CancellationError"
        ) {
            return nil
        }

        return error
    }

    private var normalizedSearch: String {
        searchText
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()
    }

    private var displayedPersonItems:
        [MessagePersonInboxItem] {
        var matching =
            personInboxItems.filter {
                item in

                guard
                    !normalizedSearch.isEmpty
                else {
                    return true
                }

                return item.friend
                    .resolvedName
                    .lowercased()
                    .contains(
                        normalizedSearch
                    ) ||
                    item.friend
                        .usernameLabel
                        .lowercased()
                        .contains(
                            normalizedSearch
                        ) ||
                    (
                        item.lastMessage?
                            .body?
                            .lowercased()
                            .contains(
                                normalizedSearch
                            ) ?? false
                    ) ||
                    (
                        item.lastMessage?
                            .attachmentTitle?
                            .lowercased()
                            .contains(
                                normalizedSearch
                            ) ?? false
                    ) ||
                    item.pendingChallenges
                        .contains {
                            $0.title
                                .lowercased()
                                .contains(
                                    normalizedSearch
                                ) ||
                            $0.sport
                                .title
                                .lowercased()
                                .contains(
                                    normalizedSearch
                                )
                        } ||
                    item.outgoingChallenges
                        .contains {
                            $0.title
                                .lowercased()
                                .contains(
                                    normalizedSearch
                                ) ||
                            $0.sport
                                .title
                                .lowercased()
                                .contains(
                                    normalizedSearch
                                )
                        }
            }

        matching =
            matching.filter { item in
                let archived =
                    item.conversation.map {
                        messaging
                            .isArchived(
                                $0.id
                            )
                    } ?? false

                switch selectedFilter {
                case .archive:
                    return archived
                case .all:
                    return !archived
                case .unread:
                    return !archived && item.unreadCount > 0
                case .direct:
                    // Only actual one-to-one conversations (including
                    // pending message requests), never invite-only people.
                    return !archived && item.conversation != nil
                case .groups:
                    // Actual group conversations are presented by Arena and Clubs,
                    // not inferred from workout/challenge invitations in a DM.
                    return false
                }

            }

        return matching.sorted {
            lhs,
            rhs in

            if selectedFilter ==
                .all {
                if lhs.priorityRank !=
                    rhs.priorityRank {
                    return lhs.priorityRank >
                        rhs.priorityRank
                }
            }

            return lhs.latestActivityAt >
                rhs.latestActivityAt
        }
    }

    private var requestPersonItems: [MessagePersonInboxItem] {
        guard selectedFilter == .all else { return [] }
        return displayedPersonItems.filter { $0.needsResponse }
    }

    private var regularPersonItems: [MessagePersonInboxItem] {
        guard selectedFilter == .all else { return displayedPersonItems }
        return displayedPersonItems.filter { !$0.needsResponse }
    }

    private var requestCount: Int {
        requestPersonItems.count + groups.ownInvites.filter {
            $0.status == "pending"
        }.count
    }

    private var hasVisibleClubChats: Bool {
        guard selectedFilter == .all || selectedFilter == .groups else {
            return false
        }
        let query = normalizedSearch
        return groups.joinedGroups.contains { club in
            query.isEmpty ||
            club.name.localizedCaseInsensitiveContains(query) ||
            groups.messages(in: club.id).contains {
                $0.body.localizedCaseInsensitiveContains(query)
            }
        }
    }

    private var shouldShowEmptyState: Bool {
        let hasClubInvites = (selectedFilter == .all || selectedFilter == .groups)
            && groups.ownInvites.contains { $0.status == "pending" }
        return displayedPersonItems.isEmpty &&
            arenaInboxVisibleCount == 0 &&
            !hasClubInvites &&
            !hasVisibleClubChats &&
            !shouldShowCoachConversation
    }

    private var shouldShowCoachConversation:
        Bool {
        guard selectedFilter == .all ||
                selectedFilter == .direct
        else {
            return false
        }

        guard !normalizedSearch.isEmpty
        else {
            return true
        }

        let searchable = [
            "athlth coach",
            "coach",
            ATHLTHLocalization.choose(
                english:
                    "personal training coach",
                norwegian:
                    "personlig treningscoach"
            ),
            coachPreviewText
        ]
        .joined(separator: " ")
        .lowercased()

        return searchable.contains(
            normalizedSearch
        )
    }

    private var coachPreviewText:
        String {
        if let latest =
                coachConversationState?
                    .messages.last {
            return latest.text
        }

        return ATHLTHLocalization.choose(
            english:
                "Your personal training and recovery coach.",
            norwegian:
                "Din personlige trenings- og restitusjonscoach."
        )
    }

    private var coachLatestActivityAt:
        Date? {
        coachConversationState?
            .messages
            .last?
            .createdAt
    }

    @ViewBuilder
    private var coachInboxLink:
        some View {
        NavigationLink {
            RecoveryCoachInboxDestinationView()
        } label: {
            RecoveryCoachInboxRow(
                preview:
                    coachPreviewText,
                timestamp:
                    coachLatestActivityAt,
                isPinned:
                    coachPinned
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                withAnimation(
                    .easeInOut(
                        duration: 0.18
                    )
                ) {
                    coachPinned.toggle()
                    RecoveryCoachInboxPreferences
                        .setPinned(
                            coachPinned,
                            userID:
                                session
                                    .profile
                                    .userID
                        )
                }
            } label: {
                Label(
                    coachPinned
                        ? ATHLTHLocalization
                            .choose(
                                english:
                                    "Unpin conversation",
                                norwegian:
                                    "Løsne samtalen"
                            )
                        : ATHLTHLocalization
                            .choose(
                                english:
                                    "Pin conversation",
                                norwegian:
                                    "Fest samtalen"
                            ),
                    systemImage:
                        coachPinned
                            ? "pin.slash"
                            : "pin.fill"
                )
            }
        }
    }

    private func refreshCoachInboxState() {
        coachPinned =
            RecoveryCoachInboxPreferences
                .isPinned(
                    userID:
                        session.profile
                            .userID
                )
        coachConversationState =
            RecoveryCoachConversationPersistence
                .load(
                    userID:
                        session.profile
                            .userID
                )
    }

    private var incomingChallengeRequests:
        [ATHLTHChallenge] {
        challenges.incomingInvitations(
            for: session.profile.userID
        )
    }

    private var outgoingChallengeRequests:
        [ATHLTHChallenge] {
        challenges.visibleChallenges.filter { challenge in
            challenge.creatorID ==
                session.profile.userID &&
            challenge.status != .completed &&
            challenge.status != .cancelled &&
            challenge.participants.contains {
                $0.state == .invited &&
                $0.userID != session.profile.userID
            }
        }
    }

    private var filteredRequestCount: Int {
        displayedPersonItems.filter {
            $0.needsResponse
        }.count
    }

    private var totalRequestCount: Int {
        personInboxItems.filter {
            $0.needsResponse
        }.count
    }

    private var personInboxItems:
        [MessagePersonInboxItem] {
        var grouped:
            [UUID: MessagePersonInboxItem] = [:]

        for item in activeConversations +
            incomingRequestItems {
            let userID = item.friend.userID
            var current =
                grouped[userID] ??
                MessagePersonInboxItem(
                    friend: item.friend
                )

            current.merge(
                conversation: item.conversation,
                lastMessage: item.lastMessage,
                unreadCount:
                    messaging.unreadCount(
                        for: item.conversation.id
                    ),
                isPinned:
                    messaging.isPinned(
                        item.conversation.id
                    ),
                isIncomingMessageRequest:
                    item.conversation.requestStatus ==
                        .pending &&
                    item.conversation.requestedBy !=
                        messaging.currentUserID,
                isOutgoingMessageRequest:
                    item.conversation.requestStatus ==
                        .pending &&
                    item.conversation.requestedBy ==
                        messaging.currentUserID
            )

            grouped[userID] = current
        }

        for invite in social.workoutInvites
        where invite.participant.state == .invited {
            guard let friend =
                    invite.creator ??
                    profile(
                        for:
                            invite.session.creatorID
                    )
            else {
                continue
            }

            var current =
                grouped[friend.userID] ??
                MessagePersonInboxItem(
                    friend: friend
                )

            current.pendingWorkoutInvites
                .append(invite)
            grouped[friend.userID] =
                current
        }

        for challenge in incomingChallengeRequests {
            guard
                let friend =
                    challengeCreatorProfile(
                        challenge
                    )
            else {
                continue
            }

            var current =
                grouped[friend.userID] ??
                MessagePersonInboxItem(
                    friend: friend
                )

            current.pendingChallenges
                .append(challenge)
            grouped[friend.userID] = current
        }

        for challenge in outgoingChallengeRequests {
            for participant in challenge.participants
            where participant.state == .invited {
                guard
                    let userID = participant.userID,
                    userID != session.profile.userID,
                    let friend = profile(for: userID)
                else {
                    continue
                }

                var current =
                    grouped[userID] ??
                    MessagePersonInboxItem(
                        friend: friend
                    )

                current.outgoingChallenges
                    .append(challenge)
                grouped[userID] = current
            }
        }

        return Array(
            grouped.values
        )
    }

    private func challengeCreatorProfile(
        _ challenge: ATHLTHChallenge
    ) -> SocialProfileCard? {
        profile(for: challenge.creatorID)
    }

    private var activeConversations:
        [MessageConversationItem] {
        items(
            from: messaging.conversations.filter {
                if $0.requestStatus == .accepted {
                    return true
                }

                guard $0.requestStatus == .pending,
                      $0.requestedBy == messaging.currentUserID
                else {
                    return false
                }

                return messaging.lastMessage(for: $0.id) != nil
            }
        )
    }

    private var incomingRequestItems:
        [MessageConversationItem] {
        items(from: messaging.incomingMessageRequests)
            .filter { $0.lastMessage != nil }
    }

    private func items(
        from conversations: [DirectConversationRecord]
    ) -> [MessageConversationItem] {
        guard let currentUserID =
                messaging.currentUserID
        else {
            return []
        }

        return conversations.compactMap { conversation in
            guard let otherID =
                    conversation.otherUserID(
                        for: currentUserID
                    ),
                  let profile = profile(for: otherID)
            else {
                return nil
            }

            return MessageConversationItem(
                conversation: conversation,
                friend: profile,
                lastMessage:
                    messaging.lastMessage(
                        for: conversation.id
                    )
            )
        }
        .sorted {
            ($0.conversation.lastMessageAt ??
                $0.conversation.createdAt) >
            ($1.conversation.lastMessageAt ??
                $1.conversation.createdAt)
        }
    }

    private func profile(
        for userID: UUID
    ) -> SocialProfileCard? {
        social.mutualFollows.first {
            $0.userID == userID
        } ??
        social.visibleProfiles.first {
            $0.userID == userID
        } ??
        social.discoverResults.first {
            $0.userID == userID
        }
    }

}

private struct MessagePersonInboxItem: Identifiable {
    var id: UUID { friend.userID }

    let friend: SocialProfileCard
    var conversation: DirectConversationRecord?
    var lastMessage: DirectMessageRecord?
    var unreadCount = 0
    var isPinned = false
    var isIncomingMessageRequest = false
    var isOutgoingMessageRequest = false
    var pendingWorkoutInvites:
        [SocialWorkoutInviteDisplay] = []
    var pendingChallenges: [ATHLTHChallenge] = []
    var outgoingChallenges: [ATHLTHChallenge] = []

    init(friend: SocialProfileCard) {
        self.friend = friend
    }

    mutating func merge(
        conversation: DirectConversationRecord,
        lastMessage: DirectMessageRecord?,
        unreadCount: Int,
        isPinned: Bool,
        isIncomingMessageRequest: Bool,
        isOutgoingMessageRequest: Bool
    ) {
        let currentDate =
            self.conversation?.lastMessageAt ??
            self.conversation?.createdAt ??
            .distantPast
        let candidateDate =
            conversation.lastMessageAt ??
            conversation.createdAt

        if self.conversation == nil ||
            candidateDate >= currentDate {
            self.conversation = conversation
            self.lastMessage = lastMessage
        }

        self.unreadCount =
            max(
                self.unreadCount,
                unreadCount
            )
        self.isPinned =
            self.isPinned || isPinned
        self.isIncomingMessageRequest =
            self.isIncomingMessageRequest ||
            isIncomingMessageRequest
        self.isOutgoingMessageRequest =
            self.isOutgoingMessageRequest ||
            isOutgoingMessageRequest
    }

    var needsResponse: Bool {
        isIncomingMessageRequest ||
            !pendingWorkoutInvites.isEmpty ||
            !pendingChallenges.isEmpty
    }

    var hasGroupLikeActivity:
        Bool {
        !pendingWorkoutInvites.isEmpty ||
        !pendingChallenges.isEmpty ||
        !outgoingChallenges.isEmpty
    }

    var isVoiceNote: Bool {
        let raw =
            [
                lastMessage?
                    .attachmentKindRaw,
                lastMessage?
                    .attachmentTitle,
                lastMessage?
                    .body
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        return
            raw.contains("voice") ||
            raw.contains("audio") ||
            raw.contains("lydnotat") ||
            raw.contains("talemelding")
    }

    var priorityRank: Int {
        var value = 0

        if isPinned {
            value += 4
        }

        if needsResponse {
            value += 3
        }

        if unreadCount > 0 {
            value += 2
        }

        if isVoiceNote {
            value += 1
        }

        return value
    }

    var latestActivityAt: Date {
        var dates: [Date] = []

        if let lastMessage {
            dates.append(
                lastMessage.createdAt
            )
        } else if let conversation {
            dates.append(
                conversation.lastMessageAt ??
                conversation.createdAt
            )
        }

        dates.append(
            contentsOf:
                pendingWorkoutInvites.map {
                    $0.participant.invitedAt
                }
        )
        dates.append(
            contentsOf:
                pendingChallenges.map(
                    \.createdAt
                )
        )
        dates.append(
            contentsOf:
                outgoingChallenges.map(
                    \.createdAt
                )
        )

        return dates.max() ??
            .distantPast
    }
}

private struct RecoveryCoachInboxRow:
    View {
    let preview: String
    let timestamp: Date?
    let isPinned: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image("ATHLTHCoachAvatar")
                .resizable()
                .scaledToFill()
                .frame(
                    width: 58,
                    height: 58
                )
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(
                            Color.white
                                .opacity(0.78),
                            lineWidth: 1.5
                        )
                }

            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                HStack(spacing: 7) {
                    if isPinned {
                        Image(
                            systemName:
                                "pin.fill"
                        )
                        .font(
                            .system(
                                size: 11,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            Color.orange
                        )
                    }

                    Text("ATHLTH Coach")
                        .font(
                            .system(
                                size: 16,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )
                        .lineLimit(1)

                    Text("ATHLTH+")
                        .font(
                            .system(
                                size: 8.5,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .accentDeep
                        )
                        .padding(
                            .horizontal,
                            6
                        )
                        .padding(
                            .vertical,
                            3
                        )
                        .background(
                            ATHLTHTheme
                                .champagneSoft,
                            in: Capsule()
                        )

                    Spacer()
                }

                Text(preview)
                    .font(
                        .subheadline
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(2)
            }

            VStack(
                alignment: .trailing,
                spacing: 10
            ) {
                if let timestamp {
                    Text(
                        timestamp.formatted(
                            date: .omitted,
                            time: .shortened
                        )
                    )
                    .font(
                        .system(
                            size: 11,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(
                    .system(
                        size: 12,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
            }
        }
        .padding(
            .horizontal,
            14
        )
        .padding(
            .vertical,
            12
        )
        .background(
            Color.white
                .opacity(0.72),
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
                Color.primary
                    .opacity(0.04),
                lineWidth: 0.8
            )
        }
    }
}

private struct MessagePersonRow: View {
    let item: MessagePersonInboxItem
    let isOnline: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                SocialAvatar(
                    profile: item.friend,
                    size: 58
                )

                if isOnline ||
                    item.unreadCount > 0 ||
                    item.needsResponse {
                    Circle()
                        .fill(
                            isOnline
                                ? Color.green
                                : (
                                    item.needsResponse
                                        ? ATHLTHTheme
                                            .premiumGold
                                        : Color.orange
                                )
                        )
                        .frame(
                            width: 12,
                            height: 12
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white,
                                    lineWidth: 2
                                )
                        }
                }
            }

            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                HStack(spacing: 7) {
                    if item.isPinned {
                        Image(
                            systemName:
                                "pin.fill"
                        )
                        .font(
                            .system(
                                size: 11,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            Color.orange
                        )
                    } else if item.needsResponse {
                        Image(
                            systemName:
                                "star.fill"
                        )
                        .font(
                            .system(
                                size: 11,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            Color.orange
                        )
                    }

                    Text(
                        item.friend
                            .resolvedName
                    )
                    .font(
                        .system(
                            size: 16,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)

                    Spacer()
                }

                if item.isVoiceNote {
                    HStack(spacing: 7) {
                        Image(
                            systemName:
                                "play.fill"
                        )
                        .font(
                            .system(
                                size: 9,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                        .frame(
                            width: 24,
                            height: 24
                        )
                        .background(
                            ATHLTHTheme
                                .accentSoft,
                            in: Circle()
                        )

                        Image(
                            systemName:
                                "waveform"
                        )
                        .font(
                            .system(
                                size: 15,
                                weight: .medium
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english: "Voice note",
                                norwegian: "Lydnotat"
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }
                } else {
                    Text(previewText)
                        .font(.subheadline)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(2)
                }

                if !statusChips.isEmpty {
                    HStack(
                        spacing: 6
                    ) {
                        ForEach(
                            statusChips,
                            id: \.self
                        ) { chip in
                            Text(chip)
                                .font(
                                    .system(
                                        size: 10,
                                        weight:
                                            .semibold
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .premiumGold
                                )
                                .padding(
                                    .horizontal,
                                    8
                                )
                                .padding(
                                    .vertical,
                                    4
                                )
                                .background(
                                    ATHLTHTheme
                                        .premiumGoldSoft,
                                    in: Capsule()
                                )
                        }
                    }
                }
            }

            VStack(
                alignment: .trailing,
                spacing: 10
            ) {
                if item.latestActivityAt >
                    .distantPast {
                    Text(
                        timestamp(
                            item.latestActivityAt
                        )
                    )
                    .font(
                        .system(
                            size: 11,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                if item.unreadCount > 0 {
                    Text(
                        item.unreadCount > 99
                            ? "99+"
                            : "\(item.unreadCount)"
                    )
                    .font(
                        .caption2
                            .weight(.bold)
                            .monospacedDigit()
                    )
                    .foregroundStyle(
                        .white
                    )
                    .frame(
                        minWidth: 24,
                        minHeight: 24
                    )
                    .background(
                        Color.orange,
                        in: Capsule()
                    )
                } else {
                    Image(
                        systemName:
                            "chevron.right"
                    )
                    .font(
                        .system(
                            size: 12,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                            .opacity(0.65)
                    )
                }
            }
        }
        .padding(
            .horizontal,
            14
        )
        .padding(
            .vertical,
            12
        )
        .background(
            Color.white.opacity(
                0.88
            ),
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
                item.needsResponse
                    ? Color.orange
                        .opacity(0.13)
                    : Color.black
                        .opacity(0.025),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black
                    .opacity(0.035),
            radius: 10,
            y: 4
        )
    }

    private var previewText: String {
        if item.pendingWorkoutInvites.count > 1 {
            return ATHLTHLocalization.choose(
                english:
                    "\(item.pendingWorkoutInvites.count) workout invites waiting",
                norwegian:
                    "\(item.pendingWorkoutInvites.count) treningsforespørsler venter"
            )
        }

        if let workoutInvite =
                item.pendingWorkoutInvites.first {
            return ATHLTHLocalization.choose(
                english:
                    "Wants to train together · \(workoutInvite.session.title)",
                norwegian:
                    "Vil trene sammen · \(workoutInvite.session.title)"
            )
        }

        if item.pendingChallenges.count > 1 {
            return
                ATHLTHLocalization
                    .choose(
                        english:
                            "\(item.pendingChallenges.count) challenges waiting",
                        norwegian:
                            "\(item.pendingChallenges.count) utfordringer venter"
                    )
        }

        if let challenge =
                item.pendingChallenges.first {
            return challenge.title
        }

        if item.outgoingChallenges.count > 1 {
            return
                ATHLTHLocalization.choose(
                    english:
                        "\(item.outgoingChallenges.count) challenges sent · waiting",
                    norwegian:
                        "\(item.outgoingChallenges.count) utfordringer sendt · venter"
                )
        }

        if let challenge =
                item.outgoingChallenges.first {
            return
                ATHLTHLocalization.choose(
                    english:
                        "Sent · \(challenge.title)",
                    norwegian:
                        "Sendt · \(challenge.title)"
                )
        }

        if let body =
                item.lastMessage?.body,
           !body.isEmpty {
            return body
        }

        if let title =
                item.lastMessage?
                    .attachmentTitle,
           !title.isEmpty {
            return title
        }

        if item.isIncomingMessageRequest {
            return ATHLTHLocalization
                .choose(
                    english:
                        "Message request",
                    norwegian:
                        "Meldingsforespørsel"
                )
        }

        if item.isOutgoingMessageRequest {
            return ATHLTHLocalization
                .choose(
                    english:
                        "Waiting for response",
                    norwegian:
                        "Venter på svar"
                )
        }

        return ATHLTHLocalization
            .choose(
                english:
                    "Start a conversation",
                norwegian:
                    "Start en samtale"
            )
    }

    private var statusChips: [String] {
        var values: [String] = []

        if !item
            .pendingWorkoutInvites
            .isEmpty {
            values.append(
                ATHLTHLocalization.choose(
                    english:
                        item.pendingWorkoutInvites.count == 1
                            ? "Train Together request"
                            : "\(item.pendingWorkoutInvites.count) Train Together requests",
                    norwegian:
                        item.pendingWorkoutInvites.count == 1
                            ? "Tren sammen-forespørsel"
                            : "\(item.pendingWorkoutInvites.count) Tren sammen-forespørsler"
                )
            )
        }

        if !item
            .pendingChallenges
            .isEmpty {
            values.append(
                ATHLTHLocalization
                    .choose(
                        english:
                            item.pendingChallenges
                                .count == 1
                                ? "Challenge"
                                : "\(item.pendingChallenges.count) challenges",
                        norwegian:
                            item.pendingChallenges
                                .count == 1
                                ? "Utfordring"
                                : "\(item.pendingChallenges.count) utfordringer"
                    )
            )
        }

        if !item.outgoingChallenges.isEmpty {
            values.append(
                ATHLTHLocalization.choose(
                    english:
                        item.outgoingChallenges.count == 1
                            ? "Sent · waiting"
                            : "\(item.outgoingChallenges.count) sent",
                    norwegian:
                        item.outgoingChallenges.count == 1
                            ? "Sendt · venter"
                            : "\(item.outgoingChallenges.count) sendt"
                )
            )
        }

        if item
            .isIncomingMessageRequest {
            values.append(
                ATHLTHLocalization
                    .choose(
                        english:
                            "Message request",
                        norwegian:
                            "Meldingsforespørsel"
                    )
            )
        } else if item
            .isOutgoingMessageRequest {
            values.append(
                ATHLTHLocalization
                    .choose(
                        english:
                            "Pending",
                        norwegian:
                            "Venter"
                    )
            )
        }

        return values
    }

    private func timestamp(
        _ date: Date
    ) -> String {
        let calendar =
            Calendar.current

        if calendar
            .isDateInToday(
                date
            ) {
            return date.formatted(
                date: .omitted,
                time: .shortened
            )
        }

        if calendar
            .isDateInYesterday(
                date
            ) {
            return ATHLTHLocalization
                .choose(
                    english:
                        "Yesterday",
                    norwegian:
                        "I går"
                )
        }

        return date.formatted(
            .dateTime
                .day()
                .month(
                    .abbreviated
                )
        )
    }
}

private struct ChallengeInboxRequestRow: View {
    let challenge: ATHLTHChallenge
    let creator: SocialProfileCard?
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            NavigationLink {
                ChallengeDetailView(
                    challengeID: challenge.id
                )
            } label: {
                HStack(spacing: 12) {
                    if let creator {
                        SocialAvatar(
                            profile: creator,
                            size: 46
                        )
                    } else {
                        Image(
                            systemName:
                                "bolt.fill"
                        )
                        .font(
                            .system(
                                size: 18,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            .orange
                        )
                        .frame(
                            width: 46,
                            height: 46
                        )
                        .background(
                            Color.orange.opacity(
                                0.10
                            ),
                            in: Circle()
                        )
                    }

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(
                            creator?.resolvedName
                                ?? "Challenge request"
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                        Text(challenge.title)
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                            .lineLimit(1)

                        Text(
                            challenge.sport.title +
                            " · " +
                            challenge.rules.scoring.title
                        )
                        .font(.caption2)
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
                    .foregroundStyle(.tertiary)
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
        .padding(14)
        .background(
            Color.white.opacity(0.82),
            in: RoundedRectangle(
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
                Color.white.opacity(0.92),
                lineWidth: 0.8
            )
        }
    }
}

private enum MessageRequestDirection: Equatable {
    case incoming
    case outgoing
}

private struct MessageRequestRow: View {
    let friend: SocialProfileCard
    let message: DirectMessageRecord?
    let direction: MessageRequestDirection
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onBlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 13) {
                SocialAvatar(profile: friend, size: 50)

                VStack(alignment: .leading, spacing: 3) {
                    Text(friend.resolvedName)
                        .font(.subheadline.weight(.semibold))
                    Text(friend.usernameLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(direction == .incoming ? "Request" : "Pending")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.premiumGold)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(ATHLTHTheme.premiumGoldSoft, in: Capsule())
            }

            if let body = message?.body, !body.isEmpty {
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            if direction == .incoming {
                HStack(spacing: 8) {
                    Button("Accept", action: onAccept)
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.premiumGold)

                    Button("Decline", action: onDecline)
                        .buttonStyle(.bordered)

                    Spacer()

                    Menu {
                        Button("Block", role: .destructive, action: onBlock)
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 32, height: 32)
                    }
                }
            } else {
                Label(
                    "Waiting for acceptance",
                    systemImage: "clock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            Color.white.opacity(0.96),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    direction == .incoming
                        ? ATHLTHTheme.accent.opacity(0.26)
                        : ATHLTHTheme.border,
                    lineWidth: 1
                )
        }
    }
}

private struct MessageConversationItem: Identifiable {
    var id: UUID { conversation.id }

    let conversation: DirectConversationRecord
    let friend: SocialProfileCard
    let lastMessage: DirectMessageRecord?
}

private struct MessageConversationRow: View {
    let friend: SocialProfileCard
    let lastMessage: DirectMessageRecord?
    let unreadCount: Int
    let requestLabel: String?
    let isPinned: Bool

    var body: some View {
        HStack(spacing: 13) {
            ZStack(alignment: .bottomTrailing) {
                SocialAvatar(
                    profile: friend,
                    size: 56
                )

                if unreadCount > 0 {
                    Circle()
                        .fill(ATHLTHTheme.premiumGold)
                        .frame(width: 11, height: 11)
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white,
                                    lineWidth: 2
                                )
                        }
                        .offset(x: 1, y: 1)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    if unreadCount > 0 {
                        Image(systemName: "star.fill")
                            .font(
                                .system(
                                    size: 10,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme.premiumGold
                            )
                    }

                    Text(friend.resolvedName)
                        .font(
                            .system(
                                size: 16,
                                weight:
                                    unreadCount > 0
                                        ? .bold
                                        : .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .lineLimit(1)

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(
                                .system(
                                    size: 10,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep
                            )
                            .accessibilityLabel(
                                "Pinned conversation"
                            )
                    }

                    if let requestLabel {
                        Text(requestLabel)
                            .font(
                                .system(
                                    size: 9,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep
                            )
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                ATHLTHTheme.premiumGoldSoft,
                                in: Capsule()
                            )
                    }

                    if let label = attachmentLabel {
                        Text(label)
                            .font(
                                .system(
                                    size: 9,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep
                            )
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                ATHLTHTheme.premiumGoldSoft,
                                in: Capsule()
                            )
                    }
                }

                previewContent
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                if let date = lastMessage?.createdAt {
                    Text(
                        inboxTimestamp(date)
                    )
                    .font(
                        .system(
                            size: 12,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if unreadCount > 0 {
                        Text(
                            unreadCount > 99
                                ? "99+"
                                : "\(unreadCount)"
                        )
                        .font(
                            .caption2.weight(.bold)
                                .monospacedDigit()
                        )
                        .foregroundStyle(.white)
                        .frame(
                            minWidth: 24,
                            minHeight: 24
                        )
                        .padding(
                            .horizontal,
                            unreadCount > 9 ? 3 : 0
                        )
                        .background(
                            ATHLTHTheme.accentDeep,
                            in: Capsule()
                        )
                    }

                    Image(systemName: "chevron.right")
                        .font(
                            .system(
                                size: 12,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.mutedText.opacity(0.66)
                        )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors:
                    unreadCount > 0
                        ? [
                            Color.white.opacity(0.98),
                            ATHLTHTheme.cardWarm.opacity(0.90)
                        ]
                        : [
                            Color.white.opacity(0.92),
                            Color.white.opacity(0.82)
                        ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
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
                unreadCount > 0
                    ? ATHLTHTheme.premiumGold.opacity(0.14)
                    : Color.white.opacity(0.86),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(
                unreadCount > 0
                    ? 0.045
                    : 0.025
            ),
            radius: 10,
            y: 4
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var previewContent: some View {
        if isVoiceMessage {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 25, height: 25)
                    .background(
                        ATHLTHTheme.premiumGoldSoft,
                        in: Circle()
                    )

                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<13, id: \.self) { index in
                        Capsule()
                            .fill(
                                ATHLTHTheme.accentDeep.opacity(
                                    0.34 + Double(index % 4) * 0.11
                                )
                            )
                            .frame(
                                width: 2,
                                height:
                                    CGFloat(
                                        5 + ((index * 7) % 13)
                                    )
                            )
                    }
                }

                Text("Voice note")
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
            }
            .lineLimit(1)
        } else if let kind = lastMessage?.attachmentKind {
            HStack(spacing: 8) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 27, height: 27)
                    .background(
                        ATHLTHTheme.premiumGoldSoft,
                        in: RoundedRectangle(
                            cornerRadius: 8,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 1) {
                    if let title = lastMessage?.attachmentTitle,
                       !title.isEmpty {
                        Text(title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(
                                ATHLTHTheme.primaryText.opacity(0.86)
                            )
                            .lineLimit(1)
                    }

                    Text(
                        previewText
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineLimit(1)
                }
            }
        } else {
            Text(previewText)
                .font(
                    .system(
                        size: 14,
                        weight:
                            unreadCount > 0
                                ? .medium
                                : .regular
                    )
                )
                .foregroundStyle(
                    unreadCount > 0
                        ? ATHLTHTheme.primaryText.opacity(0.82)
                        : ATHLTHTheme.mutedText
                )
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    private var attachmentLabel: String? {
        guard let raw =
                lastMessage?
                    .attachmentKindRaw?
                    .lowercased()
        else {
            return nil
        }

        if raw.contains("voice") ||
            raw.contains("audio") {
            return "VOICE"
        }

        return lastMessage?
            .attachmentKind?
            .title
            .uppercased()
    }

    private var isVoiceMessage: Bool {
        guard let raw =
                lastMessage?
                    .attachmentKindRaw?
                    .lowercased()
        else {
            return false
        }

        return raw.contains("voice") ||
            raw.contains("audio")
    }

    private var previewText: String {
        guard let lastMessage else {
            return "Start a conversation"
        }

        if let body = lastMessage.body,
           !body.isEmpty {
            return body
        }

        if let kind = lastMessage.attachmentKind {
            let title =
                lastMessage.attachmentTitle?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ) ?? ""

            return title.isEmpty
                ? "Shared \(kind.title.lowercased())"
                : "Shared \(kind.title.lowercased())"
        }

        return "Message"
    }

    private func inboxTimestamp(
        _ date: Date
    ) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return date.formatted(
                date: .omitted,
                time: .shortened
            )
        }

        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        if let days =
                calendar.dateComponents(
                    [.day],
                    from:
                        calendar.startOfDay(for: date),
                    to:
                        calendar.startOfDay(for: Date())
                )
                .day,
           days < 7 {
            return date.formatted(
                .dateTime.weekday(.abbreviated)
            )
        }

        return date.formatted(
            date: .abbreviated,
            time: .omitted
        )
    }
}

struct DirectMessageThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var challengeStore: ChallengeStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @EnvironmentObject private var social: SocialStore

    let friend: SocialProfileCard

    @State private var conversationID: UUID?
    @State private var text = ""
    @State private var selectedShare: MessageShareDraft?
    @State private var showingSharePicker = false
    @State private var selectedPreviewAttachment: DirectMessageRecord?
    @State private var isSending = false
    @State private var loadError: String?
    @State private var savedFeedback: String?
    @State private var requestResponseInFlight = false
    @State private var requestResponseAccepting: Bool?
    @State private var requestResponseError: String?
    @State private var respondingToPlannedInviteID: UUID?
    @State private var respondingToWorkoutProposalID: UUID?
    @State private var workoutInvitationForProposal: DirectMessageRecord?
    @State private var plannedInviteError: String?
    @State private var respondingToChallengeID: UUID?
    @State private var respondingToProposalID: UUID?
    @State private var challengeDetailsDestination: ThreadChallengeDetailsDestination?
    @State private var showingFriendProfile = false
    @State private var cancellingChallengeID: UUID?
    @State private var cancellationError: String?

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.12)
            )

            VStack(spacing: 0) {
                threadHero
                    .frame(
                        maxWidth: .infinity
                    )
                    .zIndex(0)

                Group {
                    if let conversationID {
                        messagesView(
                            conversationID
                        )
                    } else if let loadError {
                        ContentUnavailableView(
                            ATHLTHLocalization.choose(
                                english:
                                    "Messages unavailable",
                                norwegian:
                                    "Meldinger utilgjengelig"
                            ),
                            systemImage:
                                "exclamationmark.bubble",
                            description:
                                Text(loadError)
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                    } else {
                        ProgressView(
                            ATHLTHLocalization.choose(
                                english:
                                    "Opening conversation…",
                                norwegian:
                                    "Åpner samtalen…"
                            )
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .athlthConversationPanelChrome()
                .padding(
                    .horizontal,
                    6
                )
                // The white conversation sheet intentionally overlaps
                // the lower part of the hero image, matching the rest
                // of ATHLTH's pinned-card visual language.
                .padding(
                    .top,
                    -52
                )
                .zIndex(2)
            }
        }
        .ignoresSafeArea(
            .container,
            edges: .top
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(
            .hidden,
            for: .navigationBar
        )
        .toolbar(
            .hidden,
            for: .tabBar
        )
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .sheet(isPresented: $showingSharePicker) {
            MessageSharePicker { draft in
                selectedShare = draft
                showingSharePicker = false
            }
        }
        .sheet(item: $selectedPreviewAttachment) { message in
            ATHLTHReceivedTrainingPreview(message: message) {
                saveAttachment(message)
            }
        }
        .sheet(item: $workoutInvitationForProposal) { invitation in
            if let original = invitation.decodeSnapshot(PlannedSession.self) {
                SessionEditorView(
                    standaloneDate: original.scheduledStart ?? Date(),
                    initialSourceWorkout: latestAgreedWorkout(
                        for: invitation,
                        in: conversationID.map {
                            messaging.messages(in: $0)
                        } ?? []
                    ) ?? original,
                    preserveSourceID: true,
                    onPreparedWorkout: { proposed in
                        sendWorkoutChangeProposal(
                            invitation: invitation, proposed: proposed
                        )
                    }
                )
            }
        }
        .alert(
            "Saved to ATHLTH",
            isPresented: Binding(
                get: {
                    savedFeedback != nil
                },
                set: {
                    if !$0 {
                        savedFeedback = nil
                    }
                }
            )
        ) {
            Button(
                "OK",
                role: .cancel
            ) {}
        } message: {
            Text(
                savedFeedback ?? ""
            )
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Could not cancel challenge", norwegian: "Kunne ikke avlyse"
            ),
            isPresented: Binding(
                get: { cancellationError != nil },
                set: { if !$0 { cancellationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cancellationError ?? "")
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Could not respond to invitation",
                norwegian: "Kunne ikke svare på invitasjonen"
            ),
            isPresented: Binding(
                get: { plannedInviteError != nil },
                set: { if !$0 { plannedInviteError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(plannedInviteError ?? "")
        }
        .sheet(isPresented: $showingFriendProfile) {
            NavigationStack {
                FriendProfileView(userID: friend.userID)
            }
        }
        .sheet(item: $challengeDetailsDestination) { destination in
            NavigationStack {
                ChallengeDetailView(challengeID: destination.id)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(ATHLTHLocalization.choose(
                                english: "Done", norwegian: "Ferdig"
                            )) { challengeDetailsDestination = nil }
                        }
                    }
            }
        }
        .task(id: friend.userID) {
            await openAndPoll()
        }
    }

    private var threadHero: some View {
        ATHLTHConversationHero(
            title:
                friend.resolvedName,
            subtitle:
                threadStatusText,
            backgroundAsset: ATHLTHConversationArtwork.directMessageHeader,
            onBack: {
                dismiss()
            },
            onProfileTap: {
                showingFriendProfile = true
            }
        ) {
            SocialAvatar(
                profile: friend,
                size: 44
            )
            .overlay {
                Circle()
                    .stroke(
                        Color.white
                            .opacity(0.86),
                        lineWidth: 1.4
                    )
            }
        } trailing: {
            Menu {
                if let conversationID {
                    Button {
                        messaging
                            .togglePinned(
                                conversationID
                            )
                    } label: {
                        Label(
                            messaging
                                .isPinned(
                                    conversationID
                                )
                                ? ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Unpin conversation",
                                        norwegian:
                                            "Løsne samtalen"
                                    )
                                : ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Pin conversation",
                                        norwegian:
                                            "Fest samtalen"
                                    ),
                            systemImage:
                                messaging
                                    .isPinned(
                                        conversationID
                                    )
                                    ? "pin.slash"
                                    : "pin.fill"
                        )
                    }

                    Button {
                        messaging
                            .toggleArchived(
                                conversationID
                            )
                    } label: {
                        Label(
                            messaging
                                .isArchived(
                                    conversationID
                                )
                                ? ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Restore conversation",
                                        norwegian:
                                            "Gjenopprett samtalen"
                                    )
                                : ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Archive conversation",
                                        norwegian:
                                            "Arkiver samtalen"
                                    ),
                            systemImage:
                                messaging
                                    .isArchived(
                                        conversationID
                                    )
                                    ? "tray.and.arrow.up"
                                    : "archivebox"
                        )
                    }
                }

                Divider()

                Button(
                    ATHLTHLocalization.choose(
                        english: "Block",
                        norwegian: "Blokker"
                    ),
                    role: .destructive
                ) {
                    Task {
                        await social.block(
                            friend.userID
                        )
                        dismiss()
                    }
                }
            } label: {
                Image(
                    systemName:
                        "ellipsis"
                )
                .font(
                    .system(
                        size: 17,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    .white
                )
                .frame(
                    width: 42,
                    height: 42
                )
                .background(
                    .ultraThinMaterial,
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(
                            Color.white
                                .opacity(0.30),
                            lineWidth: 0.8
                        )
                }
            }
        }
    }

    private var threadStatusText: String {
        if isIncomingRequest {
            return ATHLTHLocalization.choose(
                english:
                    "Message request · needs your reply",
                norwegian:
                    "Meldingsforespørsel · venter på svar"
            )
        }

        if isOutgoingRequest {
            return ATHLTHLocalization.choose(
                english:
                    "Message request sent",
                norwegian:
                    "Meldingsforespørsel sendt"
            )
        }

        return ATHLTHLocalization.choose(
            english:
                "ATHLTH conversation",
            norwegian:
                "ATHLTH-samtale"
        )
    }

    private var threadStatusIcon: String {
        if isIncomingRequest {
            return "envelope.badge.fill"
        }

        if isOutgoingRequest {
            return "paperplane.fill"
        }

        if !pendingChallengesFromFriend.isEmpty ||
            !outgoingChallengesToFriend.isEmpty {
            return "trophy.fill"
        }

        return "message.fill"
    }

    @ViewBuilder
    private func messagesView(_ conversationID: UUID) -> some View {
        let messages =
            messaging.messages(
                in: conversationID
            )
        let lifecycleEvents = challengeLifecycleEventsWithFriend
        let standaloneInvites = challengeInvitationsWithoutMessages(messages)

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messages.isEmpty &&
                        standaloneInvites.isEmpty &&
                        lifecycleEvents.isEmpty {
                        ContentUnavailableView(
                            ATHLTHLocalization
                                .choose(
                                    english:
                                        "Start the conversation",
                                    norwegian:
                                        "Start samtalen"
                                ),
                            systemImage:
                                "message",
                            description: Text(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Send a message or share a workout, plan, route or challenge.",
                                        norwegian:
                                            "Send en melding eller del en økt, plan, rute eller utfordring."
                                    )
                            )
                        )
                        .padding(
                            .top,
                            80
                        )
                    }

                    ForEach(
                        threadTimelineItems(
                            messages: messages,
                            lifecycleEvents: lifecycleEvents,
                            challengeInvitations: standaloneInvites
                        )
                    ) { item in
                        switch item {
                        case .message(let message):
                            MessageBubble(
                                message: message,
                                friend: friend,
                                currentUserID:
                                    messaging
                                        .currentUserID,
                                currentUserProfile:
                                    currentUserProfileCard,
                                onSaveAttachment: {
                                    saveAttachment(message)
                                },
                                onPreviewAttachment: {
                                    selectedPreviewAttachment = message
                                },
                                inviteResponse: plannedInviteResponse(
                                    for: message, in: messages
                                ),
                                respondingToInvite: respondingToPlannedInviteID == message.id,
                                onRespondToInvite: { accept in
                                    respondToPlannedInvite(message, accept: accept)
                                },
                                agreedWorkout: latestAgreedWorkout(
                                    for: message, in: messages
                                ),
                                workoutChangeDecision: workoutChangeDecision(
                                    for: message, in: messages
                                ),
                                reviewingWorkoutChange: respondingToWorkoutProposalID ==
                                    message.id,
                                onProposeWorkoutChange: {
                                    workoutInvitationForProposal = message
                                },
                                onReviewWorkoutChange: { approve in
                                    reviewWorkoutProposal(message, approve: approve)
                                },
                                respondingToChallenge: respondingToChallengeID ==
                                    message.sourceObjectID,
                                onRespondToChallenge: { challenge, accept in
                                    respondToThreadChallenge(challenge, accept: accept)
                                },
                                onOpenChallenge: { id in
                                    openChallengeDetails(id)
                                },
                                cancellingChallenge: cancellingChallengeID ==
                                    message.sourceObjectID,
                                onCancelChallenge: { challenge in
                                    cancelSharedChallenge(challenge)
                                },
                                challengeChangeResponse: proposalResponse(
                                    for: message, in: messages
                                ),
                                respondingToProposal: respondingToProposalID ==
                                    message.id,
                                onReviewProposal: { accept in
                                    reviewChallengeChange(message, accept: accept)
                                }
                            )
                            .id(item.id)

                        case .challengeInvite(let challenge, let invitedAt):
                            ThreadChallengeTimelineRow(
                                challenge: challenge,
                                friend: friend,
                                currentUserID: session.profile.userID,
                                invitedAt: invitedAt,
                                responding: respondingToChallengeID == challenge.id,
                                onAccept: {
                                    respondToThreadChallenge(challenge, accept: true)
                                },
                                onDecline: {
                                    respondToThreadChallenge(challenge, accept: false)
                                },
                                onDetails: {
                                    openChallengeDetails(challenge.id)
                                },
                                cancelling: cancellingChallengeID == challenge.id,
                                onCancel: {
                                    cancelSharedChallenge(challenge)
                                }
                            )
                            .id(item.id)
                        case .challengeEvent(let event):
                            NavigationLink {
                                ChallengeDetailView(
                                    challengeID:
                                        event.challengeID
                                )
                            } label: {
                                ThreadChallengeLifecycleEventRow(
                                    event: event
                                )
                            }
                            .buttonStyle(.plain)
                            .id(item.id)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 8)
            }
            .onChange(
                of: messages.count
            ) { _, _ in
                if let last =
                        messages.last {
                    withAnimation(
                        .easeOut(
                            duration:
                                0.2
                        )
                    ) {
                        proxy.scrollTo(
                            last.id,
                            anchor:
                                .bottom
                        )
                    }
                }
            }
            .task {
                if let last =
                        messages.last,
                   standaloneInvites.isEmpty {
                    proxy.scrollTo(
                        last.id,
                        anchor:
                            .bottom
                    )
                }
            }
        }
    }

    private var pendingChallengesFromFriend:
        [ATHLTHChallenge] {
        challengeStore
            .incomingInvitations(
                for:
                    session.profile
                        .userID
            )
            .filter {
                $0.creatorID ==
                    friend.userID
            }
            .sorted {
                $0.createdAt >
                    $1.createdAt
            }
    }

    private var outgoingChallengesToFriend:
        [ATHLTHChallenge] {
        challengeStore.visibleChallenges
            .filter { challenge in
                challenge.creatorID ==
                    session.profile.userID &&
                challenge.status !=
                    .completed &&
                challenge.status !=
                    .cancelled &&
                challenge.participants
                    .contains {
                        $0.userID ==
                            friend.userID &&
                        $0.state ==
                            .invited
                    }
            }
            .sorted {
                $0.createdAt >
                    $1.createdAt
            }
    }

    private var challengeLifecycleEventsWithFriend:
        [ThreadChallengeLifecycleEvent] {
        var events:
            [ThreadChallengeLifecycleEvent] = []
        let now = Date()

        for challenge in
            challengeStore.visibleChallenges {
            let isCreator =
                challenge.creatorID ==
                    session.profile.userID
            let isFriendCreator =
                challenge.creatorID ==
                    friend.userID

            guard
                isCreator ||
                isFriendCreator
            else {
                continue
            }

            let participantUserID =
                isCreator
                    ? friend.userID
                    : session.profile.userID

            guard
                let participant =
                    challenge.participants
                        .first(
                            where: {
                                $0.userID ==
                                    participantUserID
                            }
                        )
            else {
                continue
            }

            let kind:
                ThreadChallengeLifecycleKind
            let eventDate: Date

            switch participant.state {
            case .accepted:
                kind = .accepted
                eventDate =
                    participant.respondedAt ??
                    participant.invitedAt

            case .declined:
                kind = .declined
                eventDate =
                    participant.respondedAt ??
                    participant.invitedAt

            case .withdrawn:
                kind = .withdrawn
                eventDate =
                    participant.respondedAt ??
                    participant.invitedAt

            case .invited:
                guard
                    let endsAt =
                        challenge.rules.endsAt,
                    endsAt <= now
                else {
                    continue
                }

                kind = .expired
                eventDate = endsAt

            case .creator:
                continue
            }

            events.append(
                ThreadChallengeLifecycleEvent(
                    challengeID:
                        challenge.id,
                    participantID:
                        participant.id,
                    challengeTitle:
                        challenge.title,
                    kind: kind,
                    message:
                        lifecycleMessage(
                            kind: kind,
                            creatorIsCurrentUser:
                                isCreator
                        ),
                    createdAt:
                        eventDate
                )
            )
        }

        return events.sorted {
            $0.createdAt >
                $1.createdAt
        }
    }

    private func lifecycleMessage(
        kind: ThreadChallengeLifecycleKind,
        creatorIsCurrentUser: Bool
    ) -> String {
        switch kind {
        case .accepted:
            return creatorIsCurrentUser
                ? ATHLTHLocalization.choose(
                    english:
                        "\(friend.resolvedName) accepted the challenge.",
                    norwegian:
                        "\(friend.resolvedName) godtok utfordringen."
                )
                : ATHLTHLocalization.choose(
                    english:
                        "You accepted the challenge.",
                    norwegian:
                        "Du godtok utfordringen."
                )

        case .declined:
            return creatorIsCurrentUser
                ? ATHLTHLocalization.choose(
                    english:
                        "\(friend.resolvedName) declined the challenge.",
                    norwegian:
                        "\(friend.resolvedName) avslo utfordringen."
                )
                : ATHLTHLocalization.choose(
                    english:
                        "You declined the challenge.",
                    norwegian:
                        "Du avslo utfordringen."
                )

        case .withdrawn:
            return creatorIsCurrentUser
                ? ATHLTHLocalization.choose(
                    english:
                        "You withdrew the invite to \(friend.resolvedName).",
                    norwegian:
                        "Du trakk tilbake invitasjonen til \(friend.resolvedName)."
                )
                : ATHLTHLocalization.choose(
                    english:
                        "\(friend.resolvedName) withdrew the challenge invite.",
                    norwegian:
                        "\(friend.resolvedName) trakk tilbake challenge-invitasjonen."
                )

        case .expired:
            return creatorIsCurrentUser
                ? ATHLTHLocalization.choose(
                    english:
                        "The invite expired without a response from \(friend.resolvedName).",
                    norwegian:
                        "Invitasjonen utløp uten svar fra \(friend.resolvedName)."
                )
                : ATHLTHLocalization.choose(
                    english:
                        "The challenge expired before you responded.",
                    norwegian:
                        "Utfordringen utløp før du svarte."
                )
        }
    }

    private func challengeInvitationsWithoutMessages(
        _ messages: [DirectMessageRecord]
    ) -> [(challenge: ATHLTHChallenge, invitedAt: Date)] {
        let referenced = Set(messages.compactMap { message -> UUID? in
            guard message.attachmentKind == .challenge else { return nil }
            return message.sourceObjectID ??
                message.decodeSnapshot(ATHLTHChallenge.self)?.id
        })
        return challengeStore.visibleChallenges.compactMap { challenge in
            guard !referenced.contains(challenge.id),
                  challenge.creatorID == friend.userID ||
                  challenge.creatorID == session.profile.userID
            else { return nil }

            let userID = challenge.creatorID == friend.userID
                ? session.profile.userID : friend.userID
            guard let participant = challenge.participants.first(where: {
                $0.userID == userID && $0.state != .creator
            }) else { return nil }
            return (challenge: challenge, invitedAt: participant.invitedAt)
        }
    }

    private func openChallengeDetails(_ id: UUID) {
        guard challengeStore.challenge(id: id) != nil else {
            plannedInviteError = ATHLTHLocalization.choose(
                english: "This challenge is no longer available.",
                norwegian: "Denne utfordringen er ikke lenger tilgjengelig."
            )
            return
        }
        challengeDetailsDestination = ThreadChallengeDetailsDestination(id: id)
    }

    private func threadTimelineItems(
        messages: [DirectMessageRecord],
        lifecycleEvents: [ThreadChallengeLifecycleEvent],
        challengeInvitations: [(challenge: ATHLTHChallenge, invitedAt: Date)]
    ) -> [ThreadTimelineItem] {
        (
            messages.map { ThreadTimelineItem.message($0) } +
            lifecycleEvents.map { ThreadTimelineItem.challengeEvent($0) } +
            challengeInvitations.map {
                ThreadTimelineItem.challengeInvite($0.challenge, $0.invitedAt)
            }
        )
        .sorted { $0.createdAt < $1.createdAt }
    }

    private var currentConversation: DirectConversationRecord? {
        if let conversationID,
           let exact =
                messaging.conversations.first(
                    where: {
                        $0.id ==
                            conversationID
                    }
                ) {
            return exact
        }

        return messaging.conversation(
            with: friend.userID
        )
    }

    private var isIncomingRequest: Bool {
        guard let currentConversation,
              let currentUserID =
                messaging.currentUserID,
              hasSentRequestMessage
        else {
            return false
        }

        return currentConversation.requestStatus ==
                .pending &&
            currentConversation.requestedBy !=
                nil &&
            currentConversation.requestedBy !=
                currentUserID
    }

    private var isOutgoingRequest: Bool {
        guard let currentConversation,
              let currentUserID =
                messaging.currentUserID
        else {
            return false
        }

        guard currentConversation.requestStatus ==
                .pending
        else {
            return false
        }

        // Opening a non-mutual thread reserves a pending conversation
        // before anyone sends. Until the first real request exists, either
        // participant may become the requester by sending first.
        return !hasSentRequestMessage ||
            currentConversation.requestedBy ==
                currentUserID
    }

    private var hasSentRequestMessage: Bool {
        guard let conversationID else { return false }
        return !messaging.messages(in: conversationID).isEmpty
    }

    @ViewBuilder
    private var bottomBar: some View {
        if isIncomingRequest {
            incomingRequestBar
        } else if isOutgoingRequest && hasSentRequestMessage {
            outgoingRequestBar
        } else {
            composer
        }
    }

    private var incomingRequestBar: some View {
        VStack(spacing: 13) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                    .fill(
                        ATHLTHTheme
                            .premiumGoldSoft
                    )

                    Image(
                        systemName:
                            "envelope.badge.fill"
                    )
                    .font(
                        .system(
                            size: 16,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .premiumGold
                    )
                }
                .frame(
                    width: 42,
                    height: 42
                )

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Message request",
                            norwegian:
                                "Meldingsforespørsel"
                        )
                    )
                    .font(
                        .subheadline
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Accept before replying or sharing training.",
                            norwegian:
                                "Godta før du svarer eller deler trening."
                        )
                    )
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

                Spacer()
            }

            if let requestResponseError {
                HStack(spacing: 7) {
                    Image(
                        systemName:
                            "exclamationmark.circle.fill"
                    )

                    Text(
                        requestResponseError
                    )
                    .lineLimit(2)

                    Spacer()
                }
                .font(
                    .caption
                        .weight(.medium)
                )
                .foregroundStyle(
                    .red
                        .opacity(0.82)
                )
            }

            HStack(spacing: 10) {
                Button {
                    respondToIncomingRequest(
                        accept: false
                    )
                } label: {
                    HStack(spacing: 7) {
                        if requestResponseInFlight &&
                            requestResponseAccepting == false {
                            ProgressView()
                                .tint(
                                    ATHLTHTheme
                                        .primaryText
                                )
                        } else {
                            Image(
                                systemName:
                                    "xmark"
                            )
                            .font(
                                .system(
                                    size: 14,
                                    weight: .bold
                                )
                            )
                        }

                        Text(
                            ATHLTHLocalization.choose(
                                english: "Decline",
                                norwegian: "Avslå"
                            )
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                    }
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 48)
                    .background(
                        Color.white
                            .opacity(0.76),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                ATHLTHTheme
                                    .border,
                                lineWidth: 0.9
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(
                    requestResponseInFlight
                )
                .opacity(
                    requestResponseInFlight &&
                    requestResponseAccepting == true
                        ? 0.58
                        : 1
                )

                Button {
                    respondToIncomingRequest(
                        accept: true
                    )
                } label: {
                    HStack(spacing: 7) {
                        if requestResponseInFlight &&
                            requestResponseAccepting == true {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(
                                systemName:
                                    "checkmark"
                            )
                            .font(
                                .system(
                                    size: 14,
                                    weight: .bold
                                )
                            )
                        }

                        Text(
                            ATHLTHLocalization.choose(
                                english: "Accept",
                                norwegian: "Godta"
                            )
                        )
                        .font(
                            .subheadline
                                .weight(.bold)
                        )
                    }
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 48)
                    .background(
                        LinearGradient(
                            colors: [
                                ATHLTHTheme
                                    .champagne,
                                ATHLTHTheme
                                    .premiumGold
                            ],
                            startPoint:
                                .topLeading,
                            endPoint:
                                .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .shadow(
                        color:
                            ATHLTHTheme
                                .premiumGold
                                .opacity(0.20),
                        radius: 10,
                        y: 5
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    requestResponseInFlight
                )
                .opacity(
                    requestResponseInFlight &&
                    requestResponseAccepting == false
                        ? 0.58
                        : 1
                )

                Menu {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Block",
                            norwegian: "Blokker"
                        ),
                        role: .destructive
                    ) {
                        Task { @MainActor in
                            guard
                                let conversationID,
                                !requestResponseInFlight
                            else {
                                return
                            }

                            requestResponseInFlight =
                                true
                            requestResponseError =
                                nil

                            let declined =
                                await messaging
                                    .respondToMessageRequest(
                                        conversationID,
                                        accept: false
                                    )

                            if declined {
                                await social.block(
                                    friend.userID
                                )
                                await messaging
                                    .refresh(
                                        force: true
                                    )
                                dismiss()
                            } else {
                                requestResponseError =
                                    messaging
                                        .errorMessage ??
                                    ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Could not update the request. Try again.",
                                            norwegian:
                                                "Kunne ikke oppdatere forespørselen. Prøv igjen."
                                        )
                            }

                            requestResponseInFlight =
                                false
                        }
                    }
                } label: {
                    Image(
                        systemName:
                            "ellipsis"
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .frame(
                        width: 48,
                        height: 48
                    )
                    .background(
                        Color.white
                            .opacity(0.76),
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                ATHLTHTheme
                                    .border,
                                lineWidth: 0.9
                            )
                    }
                }
                .disabled(
                    requestResponseInFlight
                )
            }
        }
        .padding(14)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme
                        .card,
                    ATHLTHTheme
                        .cardWarm
                        .opacity(0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
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
                Color.white
                    .opacity(0.78),
                lineWidth: 0.9
            )
        }
        .shadow(
            color:
                ATHLTHTheme
                    .accentDeep
                    .opacity(0.08),
            radius: 14,
            y: 6
        )
        .padding(
            .horizontal,
            12
        )
        .padding(
            .vertical,
            8
        )
        .background(
            ATHLTHTheme
                .canvasBottom
                .opacity(0.92)
        )
    }

    private func respondToIncomingRequest(
        accept: Bool
    ) {
        guard
            let conversationID,
            !requestResponseInFlight
        else {
            return
        }

        requestResponseInFlight = true
        requestResponseAccepting = accept
        requestResponseError = nil

        Task { @MainActor in
            let success =
                await messaging
                    .respondToMessageRequest(
                        conversationID,
                        accept: accept
                    )

            requestResponseInFlight = false
            requestResponseAccepting = nil

            guard success else {
                requestResponseError =
                    messaging.errorMessage ??
                    ATHLTHLocalization.choose(
                        english:
                            "Could not update the request. Try again.",
                        norwegian:
                            "Kunne ikke oppdatere forespørselen. Prøv igjen."
                    )
                return
            }

            if !accept {
                dismiss()
            }
        }
    }

    private var outgoingRequestBar: some View {
        HStack(spacing: 11) {
            Image(
                systemName:
                    "paperplane.fill"
            )
            .foregroundStyle(
                ATHLTHTheme
                    .premiumGold
            )
            .frame(
                width: 38,
                height: 38
            )
            .background(
                ATHLTHTheme
                    .premiumGoldSoft,
                in: RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Message request sent",
                        norwegian:
                            "Meldingsforespørsel sendt"
                    )
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "More messages and training items unlock after acceptance.",
                        norwegian:
                            "Flere meldinger og treningsdeling åpnes etter godkjenning."
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
        .padding(14)
        .background(
            ATHLTHTheme.card,
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
                ATHLTHTheme.border,
                lineWidth: 0.8
            )
        }
        .padding(
            .horizontal,
            12
        )
        .padding(
            .vertical,
            8
        )
        .background(
            ATHLTHTheme
                .canvasBottom
                .opacity(0.92)
        )
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let selectedShare {
                HStack(spacing: 10) {
                    Image(systemName: selectedShare.kind.systemImage)
                        .foregroundStyle(ATHLTHTheme.premiumGold)
                        .frame(width: 34, height: 34)
                        .background(ATHLTHTheme.premiumGoldSoft, in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedShare.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(selectedShare.kind.localizedTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        self.selectedShare = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
            }

            if !mentionSuggestions.isEmpty {
                ATHLTHMentionSuggestionList(
                    suggestions: mentionSuggestions
                ) { suggestion in
                    text = ATHLTHMentionSupport.inserting(
                        suggestion,
                        into: text
                    )
                }
                .padding(.horizontal)
            }

            HStack(alignment: .bottom, spacing: 10) {
                if currentConversation?.requestStatus == .accepted ||
                    (
                        isOutgoingRequest &&
                        !hasSentRequestMessage
                    ) {
                    Button {
                        showingSharePicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .background(
                                Color.white
                                    .opacity(0.86),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(
                                        ATHLTHTheme
                                            .border,
                                        lineWidth: 0.8
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(conversationID == nil)
                }

                TextField(
                    isOutgoingRequest
                        ? ATHLTHLocalization.choose(
                            english:
                                "Send one request…",
                            norwegian:
                                "Send én forespørsel …"
                        )
                        : ATHLTHLocalization.choose(
                            english:
                                "Write a message…",
                            norwegian:
                                "Skriv en melding …"
                        ),
                    text: $text,
                    axis: .vertical
                )
                    .lineLimit(1...5)
                    .submitLabel(.send)
                    .onSubmit {
                        Task {
                            await send()
                        }
                    }
                    .padding(
                        .horizontal,
                        15
                    )
                    .padding(
                        .vertical,
                        11
                    )
                    .background(
                        Color.white
                            .opacity(0.93),
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
                            Color.white
                                .opacity(0.92),
                            lineWidth: 0.8
                        )
                    }
                    .shadow(
                        color:
                            ATHLTHTheme
                                .accentDeep
                                .opacity(0.035),
                        radius: 8,
                        y: 3
                    )

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                }
                .background(
                    // Match the conversation's outgoing message bubble.
                    ATHLTHPlanDesign.outgoingMessage,
                    in: Circle()
                )
                .buttonStyle(.plain)
                .disabled(!canSend || isSending)
                .opacity(canSend ? 1 : 0.45)
            }
            .padding(
                .horizontal,
                14
            )
            .padding(
                .bottom,
                9
            )
        }
        .padding(
            .top,
            9
        )
        .padding(
            .bottom,
            4
        )
        .athlthConversationComposerChrome()
    }

    private var mentionSuggestions: [ATHLTHMentionSuggestion] {
        ATHLTHMentionSupport.suggestions(
            in: text,
            candidates: [friend]
        )
    }

    private var currentUserProfileCard:
        SocialProfileCard {
        SocialProfileCard(
            userID: session.profile.userID,
            username:
                session.profile.username.isEmpty
                    ? nil
                    : session.profile.username,
            displayName:
                session.profile.displayName.isEmpty
                    ? nil
                    : session.profile.displayName,
            bio:
                session.profile.bio.isEmpty
                    ? nil
                    : session.profile.bio,
            avatarURL:
                session.profile.avatarURL?
                    .absoluteString,
            profileVisibility: "public",
            createdAt: nil,
            updatedAt: nil
        )
    }

    private var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        guard let currentConversation else {
            return false
        }

        switch currentConversation.requestStatus {
        case .accepted:
            return hasText || selectedShare != nil
        case .pending:
            return isOutgoingRequest &&
                !hasSentRequestMessage &&
                (
                    hasText ||
                    selectedShare != nil
                )
        case .declined:
            return false
        }
    }

    private func openAndPoll() async {
        do {
            let id = try await messaging.openConversation(with: friend.userID)

            // Keep the thread in its loading state until the backend status
            // and messages have been refreshed. This avoids briefly showing
            // a stale "message request" composer after a pending conversation
            // has already been promoted to accepted.
            await messaging.refreshConversation(id)
            session.syncApprovedSharedWorkouts(from: messaging.messages(in: id))
            await social.refreshChallenges(
                challengeStore:
                    challengeStore
            )
            await social.markChallengeEventsRead(
                from: friend.userID
            )
            conversationID = id
            markLocalMessageNotificationsRead(conversationID: id)

            var pollTick = 0
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds:
                        4_000_000_000
                )
                if Task.isCancelled {
                    break
                }

                await messaging
                    .refreshConversation(
                        id
                    )

                session.syncApprovedSharedWorkouts(from: messaging.messages(in: id))

                pollTick += 1
                if pollTick.isMultiple(
                    of: 2
                ) {
                    await social
                        .refreshChallenges(
                            challengeStore:
                                challengeStore
                        )
                }
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func markLocalMessageNotificationsRead(conversationID: UUID) {
        for item in notifications.items
        where (item.socialEventKind == "message" ||
               item.socialEventKind == "mention" ||
               item.socialEventKind == "message_request" ||
               item.socialEventKind == "message_request_accepted") &&
              item.socialEntityID == conversationID &&
              item.isUnread {
            notifications.markRead(item.id)
        }
    }

    private func respondToThreadChallenge(
        _ challenge: ATHLTHChallenge,
        accept: Bool
    ) {
        guard respondingToChallengeID == nil,
              let current = challengeStore.challenge(id: challenge.id),
              current.creatorID == friend.userID,
              current.status != .cancelled,
              current.status != .completed,
              current.rules.endsAt.map({ $0 > Date() }) ?? true,
              let participant = challengeStore.invitationParticipant(
                  in: current, userID: session.profile.userID
              ),
              participant.state == .invited
        else { return }

        respondingToChallengeID = current.id
        challengeStore.setParticipantState(
            challengeID: current.id,
            participantID: participant.id,
            state: accept ? .accepted : .declined
        )

        guard let updated = challengeStore.challenge(id: current.id) else {
            respondingToChallengeID = nil
            return
        }

        Task {
            let synced = await social.syncChallenge(updated)
            if synced {
                await social.markChallengeInviteRead(challengeID: current.id)
            } else {
                challengeStore.setParticipantState(
                    challengeID: current.id,
                    participantID: participant.id,
                    state: .invited
                )
                plannedInviteError = social.errorMessage ??
                    ATHLTHLocalization.choose(
                        english: "Please try again.",
                        norwegian: "Prøv igjen."
                    )
            }
            respondingToChallengeID = nil
        }
    }

    private func cancelSharedChallenge(_ challenge: ATHLTHChallenge) {
        guard cancellingChallengeID == nil,
              challenge.creatorID == session.profile.userID,
              challenge.status != .cancelled,
              challenge.status != .completed
        else { return }

        cancellingChallengeID = challenge.id
        Task {
            defer { cancellingChallengeID = nil }
            guard await social.cancelChallenge(challengeID: challenge.id) else {
                cancellationError = social.errorMessage ??
                    ATHLTHLocalization.choose(
                        english: "Could not cancel the challenge.",
                        norwegian: "Kunne ikke avlyse utfordringen."
                    )
                return
            }

            var cancelled = challenge
            cancelled.status = .cancelled
            challengeStore.update(cancelled)

            if let conversationID {
                let body = ATHLTHLocalization.choose(
                    english: "The challenge \(challenge.title) has been cancelled.",
                    norwegian: "Utfordringen \(challenge.title) er avlyst."
                )
                _ = await messaging.send(
                    to: friend.userID,
                    conversationID: conversationID,
                    body: body,
                    attachment: nil
                )
                await messaging.refreshConversation(conversationID)
            }
            await social.refreshChallenges(challengeStore: challengeStore)
        }
    }

    private func withdrawThreadChallenge(
        _ challenge: ATHLTHChallenge
    ) {
        guard
            let participant =
                challenge.participants
                    .first(
                        where: {
                            $0.userID ==
                                friend.userID &&
                            $0.state ==
                                .invited
                        }
                    )
        else {
            return
        }

        Task {
            let withdrawn =
                await social
                    .withdrawChallengeInvite(
                        participantID:
                            participant.id
                    )

            guard withdrawn else {
                return
            }

            challengeStore
                .setParticipantState(
                    challengeID:
                        challenge.id,
                    participantID:
                        participant.id,
                    state: .withdrawn
                )

            await social.refresh(
                challengeStore:
                    challengeStore
            )
        }
    }

    private func send() async {
        guard let conversationID, canSend else { return }

        isSending = true
        let body = text
        let attachment =
            (
                currentConversation?
                    .requestStatus ==
                    .accepted ||
                (
                    isOutgoingRequest &&
                    !hasSentRequestMessage
                )
            )
                ? selectedShare
                : nil

        if await messaging.send(
            to: friend.userID,
            conversationID: conversationID,
            body: body,
            attachment: attachment
        ) {
            text = ""
            selectedShare = nil
        }

        isSending = false
    }

    private func proposalResponse(
        for message: DirectMessageRecord,
        in messages: [DirectMessageRecord]
    ) -> ChallengeChangeProposalResponse? {
        guard message.attachmentKind == .challenge,
              message.shareVersion == 2,
              let proposal = message.decodeSnapshot(ChallengeChangeProposal.self)
        else { return nil }

        return messages
            .filter {
                $0.attachmentKind == .challenge &&
                $0.shareVersion == 3 &&
                $0.senderID == proposal.original.creatorID &&
                $0.createdAt >= message.createdAt
            }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap {
                $0.decodeSnapshot(ChallengeChangeProposalResponse.self)
            }
            .first { $0.proposalID == proposal.id &&
                $0.challengeID == proposal.challengeID }
    }

    private func reviewChallengeChange(
        _ message: DirectMessageRecord, accept: Bool
    ) {
        guard let proposal = message.decodeSnapshot(ChallengeChangeProposal.self),
              message.shareVersion == 2,
              message.attachmentKind == .challenge,
              proposal.challengerID == friend.userID,
              proposal.original.creatorID == session.profile.userID,
              respondingToProposalID == nil,
              let conversationID
        else { return }

        respondingToProposalID = message.id
        Task {
            defer { respondingToProposalID = nil }
            if accept {
                guard let current = challengeStore.challenge(id: proposal.challengeID),
                      current.creatorID == session.profile.userID,
                      !current.rulesAreLocked,
                      current.status != .completed,
                      current.status != .cancelled,
                      current.title == proposal.original.title,
                      current.sport == proposal.original.sport,
                      current.rules == proposal.original.rules,
                      Set(current.participants.compactMap(\.userID)) ==
                          Set(proposal.original.participants.compactMap(\.userID))
                else {
                    plannedInviteError = ATHLTHLocalization.choose(
                        english: "The challenge has changed or started. Ask for a new proposal.",
                        norwegian: "Utfordringen er endret eller startet. Be om et nytt forslag."
                    )
                    return
                }

                var approved = current
                approved.title = proposal.proposed.title
                approved.sport = proposal.proposed.sport
                approved.rules = proposal.proposed.rules
                approved.visibility = .privateOnly

                // Preserve the current creator identity and participant response
                // state; proposals may change invitees, not impersonate athletes.
                let creator = current.participants.first(where: {
                    $0.userID == current.creatorID
                })
                let proposedInvitees = proposal.proposed.participants.filter {
                    $0.userID != current.creatorID
                }
                guard let creator,
                      !proposedInvitees.isEmpty,
                      proposedInvitees.allSatisfy({ $0.userID != nil }),
                      Set(proposedInvitees.compactMap(\.userID)).count ==
                          proposedInvitees.count,
                      approved.rules.endsAt.map({
                          $0 > approved.rules.startsAt
                      }) ?? true else {
                    plannedInviteError = ATHLTHLocalization.choose(
                        english: "Invalid proposal. Please revise it.",
                        norwegian: "Forslaget er ugyldig. Be om et nytt forslag."
                    )
                    return
                }

                approved.participants = [creator] + proposedInvitees.map {
                    participant in
                    current.participants.first(where: {
                        $0.userID == participant.userID
                    }) ?? participant
                }

                let incomingIDs = Set(proposedInvitees.compactMap(\.userID))
                let withdrawn = current.participants.filter {
                    $0.userID != current.creatorID &&
                    $0.userID.map { !incomingIDs.contains($0) } == true
                }
                guard withdrawn.allSatisfy({ $0.state == .invited }) else {
                    plannedInviteError = ATHLTHLocalization.choose(
                        english: "Accepted participants cannot be removed from an active agreement.",
                        norwegian: "Deltakere som har godtatt, kan ikke fjernes fra avtalen."
                    )
                    return
                }

                guard await social.syncChallenge(approved) else {
                    plannedInviteError = social.errorMessage ??
                        ATHLTHLocalization.choose(
                            english: "Could not approve changes.",
                            norwegian: "Kunne ikke godkjenne endringene."
                        )
                    return
                }
                for participant in withdrawn {
                    guard await social.withdrawChallengeInvite(
                        participantID: participant.id
                    ) else {
                        plannedInviteError = social.errorMessage ??
                            ATHLTHLocalization.choose(
                                english: "Some invitations could not be withdrawn.",
                                norwegian: "Noen invitasjoner kunne ikke trekkes tilbake."
                            )
                        await social.refreshChallenges(challengeStore: challengeStore)
                        return
                    }
                }
                challengeStore.update(approved)
            }

            do {
                let response = ChallengeChangeProposalResponse(
                    proposalID: proposal.id,
                    challengeID: proposal.challengeID,
                    accepted: accept
                )
                let payload = try MessageShareDraft(
                    kind: .challenge,
                    title: proposal.proposed.title,
                    subtitle: accept
                        ? ATHLTHLocalization.choose(
                            english: "Approved", norwegian: "Godkjent"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Rejected", norwegian: "Avslått"
                        ),
                    snapshot: response,
                    sourceObjectID: proposal.challengeID,
                    sourceOwnerID: proposal.original.creatorID,
                    shareVersion: 3
                )
                let sent = await messaging.send(
                    to: friend.userID,
                    conversationID: conversationID,
                    body: accept
                        ? ATHLTHLocalization.choose(
                            english: "I approved the proposed changes.",
                            norwegian: "Jeg har godkjent endringene."
                        )
                        : ATHLTHLocalization.choose(
                            english: "I rejected the proposed changes.",
                            norwegian: "Jeg har avslått endringsforslaget."
                        ),
                    attachment: payload
                )
                if !sent {
                    plannedInviteError = messaging.errorMessage ??
                        ATHLTHLocalization.choose(
                            english: "Could not deliver the decision.",
                            norwegian: "Kunne ikke sende svaret."
                        )
                } else {
                    await messaging.refreshConversation(conversationID)
                }
            } catch {
                plannedInviteError = error.localizedDescription
            }
        }
    }

    private func workoutChangeDecision(
        for message: DirectMessageRecord,
        in messages: [DirectMessageRecord]
    ) -> WorkoutChangeDecision? {
        guard message.attachmentKind == .workout,
              message.shareVersion == 4,
              let proposal = message.decodeSnapshot(WorkoutChangeProposal.self)
        else { return nil }
        return messages
            .filter {
                $0.attachmentKind == .workout &&
                $0.shareVersion == 5 &&
                $0.sourceObjectID == proposal.workoutID &&
                $0.senderID == proposal.ownerID
            }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { $0.decodeSnapshot(WorkoutChangeDecision.self) }
            .first { $0.proposalID == proposal.id }
    }

    private func latestAgreedWorkout(
        for invitation: DirectMessageRecord,
        in messages: [DirectMessageRecord]
    ) -> PlannedSession? {
        guard invitation.shareVersion == 2,
              let id = invitation.sourceObjectID else { return nil }
        return messages
            .filter {
                $0.attachmentKind == .workout &&
                $0.shareVersion == 5 &&
                $0.sourceObjectID == id &&
                $0.senderID == invitation.senderID
            }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { $0.decodeSnapshot(WorkoutChangeDecision.self) }
            .first { $0.approved && $0.workoutID == id }?
            .approvedWorkout
    }

    private func sendWorkoutChangeProposal(
        invitation: DirectMessageRecord,
        proposed: PlannedSession
    ) {
        guard invitation.attachmentKind == .workout,
              invitation.shareVersion == 2,
              invitation.senderID == friend.userID,
              let original = invitation.decodeSnapshot(PlannedSession.self),
              let conversationID,
              proposed.id == original.id,
              original.scheduledStart.map({ $0 > Date() }) ?? true
        else { return }

        let agreed = latestAgreedWorkout(
            for: invitation,
            in: messaging.messages(in: conversationID)
        ) ?? original
        let proposal = WorkoutChangeProposal(
            id: UUID(),
            proposedBy: session.profile.userID,
            ownerID: invitation.senderID,
            original: agreed,
            proposed: proposed,
            submittedAt: Date()
        )
        guard WorkoutInviteExercisePolicy.canPropose(
            original: agreed, proposed: proposed
        ) else {
            plannedInviteError = ATHLTHLocalization.choose(
                english: "The organizer has not allowed adding new exercises to this workout.",
                norwegian: "Arrangøren har ikke tillatt at du legger til nye øvelser i denne økten."
            )
            return
        }
        guard proposal.hasChanges else {
            plannedInviteError = ATHLTHLocalization.choose(
                english: "Change at least one detail before sending.",
                norwegian: "Endre minst én detalj før du sender."
            )
            return
        }

        Task {
            do {
                let payload = try MessageShareDraft(
                    kind: .workout,
                    title: proposed.title,
                    subtitle: ATHLTHLocalization.choose(
                        english: "Workout changes pending approval",
                        norwegian: "Øktendringer venter på godkjenning"
                    ),
                    snapshot: proposal,
                    sourceObjectID: original.id,
                    sourceOwnerID: invitation.senderID,
                    shareVersion: 4
                )
                let sent = await messaging.send(
                    to: invitation.senderID,
                    conversationID: conversationID,
                    body: ATHLTHLocalization.choose(
                        english: "I suggest changes to our workout. See the red details.",
                        norwegian: "Jeg foreslår endringer i økten vår. Se detaljene merket rødt."
                    ),
                    attachment: payload
                )
                if !sent {
                    plannedInviteError = messaging.errorMessage ??
                        ATHLTHLocalization.choose(
                            english: "Could not send the changes.",
                            norwegian: "Kunne ikke sende endringene."
                        )
                } else {
                    await messaging.refreshConversation(conversationID)
                }
            } catch {
                plannedInviteError = error.localizedDescription
            }
        }
    }

    private func reviewWorkoutProposal(
        _ message: DirectMessageRecord, approve: Bool
    ) {
        guard message.shareVersion == 4,
              message.attachmentKind == .workout,
              let proposal = message.decodeSnapshot(WorkoutChangeProposal.self),
              proposal.ownerID == session.profile.userID,
              proposal.proposedBy == friend.userID,
              message.senderID == friend.userID,
              respondingToWorkoutProposalID == nil,
              let conversationID
        else { return }

        respondingToWorkoutProposalID = message.id
        Task {
            defer { respondingToWorkoutProposalID = nil }
            var revision: PlannedSession?
            if approve {
                let inStandalone = session.standalonePlannedSessions.contains {
                    $0.id == proposal.workoutID
                }
                let inPlan = session.activePlan.flatMap { plan in
                    plan.weeks.flatMap(\.days).flatMap(\.sessions)
                        .first(where: { $0.id == proposal.workoutID })
                }
                guard let current = session.standalonePlannedSessions.first(
                    where: { $0.id == proposal.workoutID }
                ) ?? inPlan,
                current.id == proposal.original.id,
                current.scheduledStart.map({ $0 > Date() }) ?? true,
                WorkoutChangeComparison.rows(WorkoutChangeProposal(
                    id: proposal.id,
                    proposedBy: proposal.proposedBy,
                    ownerID: proposal.ownerID,
                    original: proposal.original,
                    proposed: current,
                    submittedAt: proposal.submittedAt
                )).isEmpty,
                proposal.proposed.id == current.id,
                WorkoutInviteExercisePolicy.canPropose(
                    original: current, proposed: proposal.proposed
                ),
                !proposal.proposed.title
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                proposal.proposed.scheduledStart.map({ $0 > Date() }) ?? true
                else {
                    plannedInviteError = ATHLTHLocalization.choose(
                        english: "The workout has changed or started. Ask for a new proposal.",
                        norwegian: "Økten er endret eller startet. Be om et nytt forslag."
                    )
                    return
                }
                var approved = proposal.proposed
                // The original creator's gear and music preferences are
                // private and must never be replaced by the recipient.
                approved.gearIDs = current.gearIDs
                approved.spotifyPlaylist = current.spotifyPlaylist
                approved.spotifyAutoplayOnStart = current.spotifyAutoplayOnStart
                // Invitee-supplied changes cannot alter organizer permissions,
                // ownership or the identity of the invited athlete.
                approved.allowInviteeExercises = current.allowInviteeExercises
                approved.invitedPartnerID = current.invitedPartnerID
                approved.trainTogetherMode = current.trainTogetherMode
                approved.sharedSourceOwnerID = current.sharedSourceOwnerID
                approved.sharedSourceSessionID = current.sharedSourceSessionID
                revision = approved

                if inStandalone {
                    session.updateStandalonePlannedSession(approved)
                } else if let planID = session.activePlan?.id {
                    session.updateSession(approved, inPlan: planID)
                }
            }

            do {
                let decision = WorkoutChangeDecision(
                    proposalID: proposal.id,
                    workoutID: proposal.workoutID,
                    approved: approve,
                    approvedWorkout: revision
                )
                let payload = try MessageShareDraft(
                    kind: .workout,
                    title: proposal.proposed.title,
                    subtitle: approve
                        ? ATHLTHLocalization.choose(
                            english: "Changes approved", norwegian: "Endringene er godkjent"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Changes declined", norwegian: "Endringene er avslått"
                        ),
                    snapshot: decision,
                    sourceObjectID: proposal.workoutID,
                    sourceOwnerID: proposal.ownerID,
                    shareVersion: 5
                )
                let sent = await messaging.send(
                    to: friend.userID,
                    conversationID: conversationID,
                    body: approve
                        ? ATHLTHLocalization.choose(
                            english: "I approved your changes to our workout.",
                            norwegian: "Jeg har godkjent endringene i økten vår."
                        )
                        : ATHLTHLocalization.choose(
                            english: "I declined the proposed changes.",
                            norwegian: "Jeg har avslått endringsforslaget."
                        ),
                    attachment: payload
                )
                if !sent {
                    plannedInviteError = messaging.errorMessage ??
                        ATHLTHLocalization.choose(
                            english: "Could not deliver the decision.",
                            norwegian: "Kunne ikke sende svaret."
                        )
                } else {
                    await messaging.refreshConversation(conversationID)
                }
            } catch {
                plannedInviteError = error.localizedDescription
            }
        }
    }

    private func plannedInviteResponse(
        for invitation: DirectMessageRecord,
        in messages: [DirectMessageRecord]
    ) -> PlannedWorkoutInviteResponse? {
        guard invitation.attachmentKind == .workout,
              invitation.shareVersion == 2,
              let sourceID = invitation.sourceObjectID else { return nil }
        let responderID = invitation.senderID == session.profile.userID
            ? friend.userID : session.profile.userID
        return messages
            .filter {
                $0.attachmentKind == .workout &&
                $0.shareVersion == 3 &&
                $0.sourceObjectID == sourceID &&
                $0.senderID == responderID
            }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap {
                $0.decodeSnapshot(PlannedWorkoutInviteResponse.self)
            }
            .first { $0.sourceWorkoutID == sourceID }
    }

    private func respondToPlannedInvite(
        _ invitation: DirectMessageRecord,
        accept: Bool
    ) {
        guard invitation.senderID == friend.userID,
              invitation.attachmentKind == .workout,
              invitation.shareVersion == 2,
              respondingToPlannedInviteID == nil,
              let conversationID,
              let originalWorkout = invitation.decodeSnapshot(PlannedSession.self),
              let sourceID = invitation.sourceObjectID
        else { return }

        let workout = latestAgreedWorkout(
            for: invitation, in: messaging.messages(in: conversationID)
        ) ?? originalWorkout
        respondingToPlannedInviteID = invitation.id
        Task {
            defer { respondingToPlannedInviteID = nil }
            do {
                let decision: PlannedWorkoutInviteDecision = accept
                    ? .accepted : .declined
                let response = PlannedWorkoutInviteResponse(
                    sourceWorkoutID: sourceID,
                    decision: decision
                )
                let shared = try MessageShareDraft(
                    kind: .workout,
                    title: workout.title,
                    subtitle: accept
                        ? ATHLTHLocalization.choose(
                            english: "Invitation accepted", norwegian: "Invitasjonen er godtatt"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Invitation declined", norwegian: "Invitasjonen er avslått"
                        ),
                    snapshot: response,
                    sourceObjectID: sourceID,
                    sourceOwnerID: invitation.senderID,
                    shareVersion: 3
                )
                let body = accept
                    ? ATHLTHLocalization.choose(
                        english: "I will join the planned workout.",
                        norwegian: "Jeg blir med på den planlagte økten."
                    )
                    : ATHLTHLocalization.choose(
                        english: "I cannot join this workout.",
                        norwegian: "Jeg kan ikke bli med på denne økten."
                    )
                guard await messaging.send(
                    to: friend.userID,
                    conversationID: conversationID,
                    body: body,
                    attachment: shared
                ) else {
                    plannedInviteError = messaging.errorMessage ??
                        ATHLTHLocalization.choose(
                            english: "Could not send a response.",
                            norwegian: "Kunne ikke sende svar."
                        )
                    return
                }

                if accept {
                    var copy = workout
                    copy.gearIDs = []
                    copy.spotifyPlaylist = nil
                    copy.spotifyAutoplayOnStart = false
                    copy.sharedSourceOwnerID = invitation.senderID
                    copy.sharedSourceSessionID = sourceID
                    if copy.scheduledStart != nil {
                        session.addStandalonePlannedSession(copy)
                    } else {
                        session.saveSharedWorkout(
                            copy,
                            sourceOwnerID: invitation.senderID,
                            sourceSessionID: sourceID
                        )
                    }
                }
                await messaging.refreshConversation(conversationID)
            } catch {
                plannedInviteError = error.localizedDescription
            }
        }
    }

    private func saveAttachment(_ message: DirectMessageRecord) {
        // Special response versions apply only to their attachment kind.
        // A legitimate version-2/3/4 training plan must still be saveable.
        if message.attachmentKind == .workout &&
           [2, 3, 4, 5].contains(message.shareVersion) {
            return
        }
        if message.attachmentKind == .challenge &&
           message.shareVersion == 2 {
            return
        }

        guard message.senderID != messaging.currentUserID else { return }

        switch message.attachmentKind {
        case .workout:
            if let workout = message.decodeSnapshot(PlannedSession.self) {
                session.saveSharedWorkout(
                    workout,
                    sourceOwnerID: message.sourceOwnerID,
                    sourceSessionID: message.sourceObjectID
                )
                savedFeedback = "\(workout.title) was saved to your workout library."
            }

        case .exercise:
            // Recipients review/import an exercise in the library detail
            // screen. Never auto-import as a consequence of opening the inbox.
            break

        case .trainingPlan:
            if let plan = message.decodeSnapshot(TrainingPlan.self) {
                session.saveSharedPlan(
                    plan,
                    sourceOwnerID: message.sourceOwnerID,
                    sourcePlanID: message.sourceObjectID,
                    sourceVersion: message.shareVersion
                )
                savedFeedback = "\(plan.title) was saved as your own private copy."
            }

        case .runningWorkout:
            if let workout = message.decodeSnapshot(RunningWorkoutTemplate.self) {
                _ = runningLibrary.saveShared(
                    workout,
                    sourceOwnerID: message.sourceOwnerID,
                    sourceWorkoutID: message.sourceObjectID
                )
                savedFeedback = "\(workout.title) was saved to Running Workouts."
            }

        case .route:
            if let route = message.decodeSnapshot(TrainingRoute.self) {
                session.saveSharedRoute(
                    route,
                    sourceOwnerID: message.sourceOwnerID,
                    sourceRouteID: message.sourceObjectID
                )
                savedFeedback = "\(route.title) was saved as a private route."
            }

        case .challenge:
            if let challengeID = message.sourceObjectID ??
                message.decodeSnapshot(ATHLTHChallenge.self)?.id {
                openChallengeDetails(challengeID)
            }

        case .none:
            break
        }
    }
}

private struct ThreadChallengeDetailsDestination: Identifiable {
    let id: UUID
}

private enum ThreadTimelineItem: Identifiable {
    case message(DirectMessageRecord)
    case challengeInvite(ATHLTHChallenge, Date)
    case challengeEvent(
        ThreadChallengeLifecycleEvent
    )

    var id: String {
        switch self {
        case .message(let message):
            return "message:" + message.id.uuidString
        case .challengeInvite(let challenge, _):
            return "challenge-invite:" + challenge.id.uuidString
        case .challengeEvent(let event):
            return "challenge-event:" +
                event.id
        }
    }

    var createdAt: Date {
        switch self {
        case .message(let message):
            return message.createdAt
        case .challengeInvite(_, let date):
            return date
        case .challengeEvent(let event):
            return event.createdAt
        }
    }
}

private enum ThreadChallengeLifecycleKind: String {
    case accepted
    case declined
    case withdrawn
    case expired

    var systemImage: String {
        switch self {
        case .accepted:
            return "checkmark.circle.fill"
        case .declined:
            return "xmark.circle.fill"
        case .withdrawn:
            return "arrow.uturn.backward.circle.fill"
        case .expired:
            return "clock.badge.xmark"
        }
    }
}

private struct ThreadChallengeLifecycleEvent: Identifiable {
    var id: String {
        challengeID.uuidString +
        ":" +
        participantID.uuidString +
        ":" +
        kind.rawValue
    }

    let challengeID: UUID
    let participantID: UUID
    let challengeTitle: String
    let kind: ThreadChallengeLifecycleKind
    let message: String
    let createdAt: Date
}

private struct ThreadChallengeLifecycleEventRow: View {
    let event: ThreadChallengeLifecycleEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(
                systemName:
                    event.kind
                        .systemImage
            )
            .font(
                .system(
                    size: 13,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme
                    .premiumGold
            )
            .frame(
                width: 30,
                height: 30
            )
            .background(
                ATHLTHTheme
                    .accentSoft,
                in: Circle()
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(event.message)
                    .font(
                        .caption
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                Text(
                    event.challengeTitle +
                    " · " +
                    event.createdAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption2)
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
            .font(
                .caption
                    .weight(.semibold)
            )
            .foregroundStyle(
                ATHLTHTheme
                    .mutedText
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
        .background(
            Color.white
                .opacity(0.64),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
    }
}

private struct ThreadOutgoingChallengeCard: View {
    let challenge: ATHLTHChallenge
    let onCancel: () -> Void

    @State private var showingCancelConfirmation = false

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack(spacing: 12) {
                Image(
                    systemName:
                        "paperplane.fill"
                )
                .font(
                    .system(
                        size: 16,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )
                .frame(
                    width: 42,
                    height: 42
                )
                .background(
                    ATHLTHTheme
                        .accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                )

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Sent · waiting for response",
                                norwegian:
                                    "Sendt · venter på svar"
                            )
                    )
                    .font(
                        .caption2
                            .weight(.bold)
                    )
                    .tracking(0.6)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )

                    Text(
                        challenge.title
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)

                    Text(
                        challenge.sport.title +
                        " · " +
                        challenge.rules
                            .scoring.title
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(1)
                }

                Spacer()
            }

            HStack(spacing: 9) {
                NavigationLink {
                    ChallengeDetailView(
                        challengeID:
                            challenge.id
                    )
                } label: {
                    Text(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "View",
                                norwegian:
                                    "Vis"
                            )
                    )
                    .frame(
                        maxWidth:
                            .infinity
                    )
                }
                .buttonStyle(.bordered)

                Button(
                    role: .destructive
                ) {
                    showingCancelConfirmation = true
                } label: {
                    Text(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Cancel invite",
                                norwegian:
                                    "Avlys invitasjon"
                            )
                    )
                    .frame(
                        maxWidth:
                            .infinity
                    )
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.98),
                    ATHLTHTheme
                        .cardWarm
                        .opacity(0.88)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in: RoundedRectangle(
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
                ATHLTHTheme
                    .accentDeep
                    .opacity(0.12),
                lineWidth: 0.9
            )
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english:
                    "Cancel this challenge invite?",
                norwegian:
                    "Avlyse denne challenge-invitasjonen?"
            ),
            isPresented:
                $showingCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                ATHLTHLocalization.choose(
                    english:
                        "Cancel invite",
                    norwegian:
                        "Avlys invitasjon"
                ),
                role: .destructive,
                action: onCancel
            )

            Button(
                ATHLTHLocalization.choose(
                    english:
                        "Keep invite",
                    norwegian:
                        "Behold invitasjonen"
                ),
                role: .cancel
            ) {}
        }
    }
}

private struct ThreadChallengeRequestCard: View {
    let challenge: ATHLTHChallenge
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            NavigationLink {
                ChallengeDetailView(
                    challengeID:
                        challenge.id
                )
            } label: {
                HStack(spacing: 12) {
                    Image(
                        systemName:
                            challenge.sport
                                .systemImage
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                    .frame(
                        width: 42,
                        height: 42
                    )
                    .background(
                        ATHLTHTheme
                            .accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 13,
                            style:
                                .continuous
                        )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(
                            ATHLTHLocalization
                                .choose(
                                    english:
                                        "Challenge",
                                    norwegian:
                                        "Utfordring"
                                )
                        )
                        .font(
                            .caption2
                                .weight(.bold)
                        )
                        .tracking(1)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )

                        Text(
                            challenge.title
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )
                        .lineLimit(1)

                        Text(
                            challenge.sport
                                .title +
                            " · " +
                            challenge.rules
                                .scoring.title
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
                    .font(
                        .caption.bold()
                    )
                    .foregroundStyle(
                        .tertiary
                    )
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 9) {
                Button(
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Decline",
                            norwegian:
                                "Avslå"
                        ),
                    action:
                        onDecline
                )
                .buttonStyle(.bordered)
                .frame(
                    maxWidth:
                        .infinity
                )

                Button(
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Accept",
                            norwegian:
                                "Godta"
                        ),
                    action:
                        onAccept
                )
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme
                        .accentDeep
                )
                .frame(
                    maxWidth:
                        .infinity
                )
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.98),
                    ATHLTHTheme
                        .cardWarm
                        .opacity(0.92)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in: RoundedRectangle(
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
                ATHLTHTheme
                    .premiumGold
                    .opacity(0.18),
                lineWidth: 0.9
            )
        }
    }
}

/// Inline invitation used by both backend challenges and chat attachments.
private struct ThreadChallengeInvitationBubble: View {
    let challenge: ATHLTHChallenge?
    let fallbackTitle: String
    let fallbackSubtitle: String?
    let currentUserID: UUID?
    let friendUserID: UUID
    let isMine: Bool
    let responding: Bool
    let onDetails: () -> Void
    let onAccept: () -> Void
    let onDecline: () -> Void
    let cancelling: Bool
    let onCancel: () -> Void
    @State private var confirmCancellation = false

    private var invitee: ChallengeParticipant? {
        guard let challenge, let currentUserID else { return nil }
        let inviteeID = challenge.creatorID == currentUserID
            ? friendUserID : currentUserID
        return challenge.participants.first(where: { $0.userID == inviteeID })
    }

    private var expired: Bool {
        if let date = challenge?.rules.endsAt { return date <= Date() }
        return false
    }

    private var mayRespond: Bool {
        guard let challenge, let currentUserID else { return false }
        return challenge.creatorID != currentUserID &&
            !isMine && invitee?.state == .invited &&
            !expired && challenge.status != .cancelled &&
            challenge.status != .completed
    }

    private var status: (text: String, icon: String) {
        guard let challenge else {
            return (ATHLTHLocalization.choose(
                english: "No longer available",
                norwegian: "Ikke lenger tilgjengelig"
            ), "exclamationmark.circle")
        }
        if challenge.status == .cancelled {
            return (ATHLTHLocalization.choose(
                english: "CANCELLED", norwegian: "AVLYST"
            ), "xmark.octagon.fill")
        }
        switch invitee?.state {
        case .accepted:
            return (ATHLTHLocalization.choose(
                english: "Accepted", norwegian: "Godtatt"
            ), "checkmark.circle.fill")
        case .declined:
            return (ATHLTHLocalization.choose(
                english: "Declined", norwegian: "Avslått"
            ), "xmark.circle.fill")
        case .withdrawn:
            return (ATHLTHLocalization.choose(
                english: "Withdrawn", norwegian: "Trukket tilbake"
            ), "arrow.uturn.backward")
        case .invited:
            if expired || challenge.status == .completed {
                return (ATHLTHLocalization.choose(
                    english: "Expired", norwegian: "Utløpt"
                ), "clock.badge.xmark")
            }
            return isMine
                ? (ATHLTHLocalization.choose(
                    english: "Waiting for a reply",
                    norwegian: "Venter på svar"
                ), "clock")
                : (ATHLTHLocalization.choose(
                    english: "Awaiting your response",
                    norwegian: "Venter på ditt svar"
                ), "clock")
        case .creator, .none:
            return (ATHLTHLocalization.choose(
                english: "Shared challenge",
                norwegian: "Delt utfordring"
            ), "bolt.fill")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onDetails) {
                HStack(alignment: .top, spacing: 10) {
                    if let challenge {
                        ChallengeCoverArtworkView(
                            sport: challenge.sport,
                            artworkName: challenge.rules.coverArtworkName,
                            remoteURL: challenge.rules.coverImageURL
                        )
                        .frame(width: 58, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(Color.white.opacity(0.84), lineWidth: 0.8)
                        }
                        .accessibilityHidden(true)
                    } else {
                    Image(systemName: challenge?.sport.systemImage ?? "bolt.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.70),
                            in: RoundedRectangle(cornerRadius: 13))
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(ATHLTHLocalization.choose(
                            english: "ATHLTH · CHALLENGE",
                            norwegian: "ATHLTH · UTFORDRING"
                        ))
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        Text(challenge?.title ?? fallbackTitle)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .multilineTextAlignment(.leading)
                        Text(challenge.map {
                            $0.sport.title + " · " + $0.rules.scoring.title
                        } ?? fallbackSubtitle ?? "")
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(challenge == nil)

            Label(status.text, systemImage: status.icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(challenge?.status == .cancelled ? Color.red :
                    invitee?.state == .declined ? Color.red :
                    ATHLTHTheme.accentDeep)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.59), in: Capsule())

            if let endsAt = challenge?.rules.endsAt {
                Label(
                    endsAt.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "calendar"
                )
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }

            if isMine,
               challenge?.status != .cancelled,
               challenge?.status != .completed {
                Button(role: .destructive) {
                    confirmCancellation = true
                } label: {
                    HStack {
                        if cancelling { ProgressView().controlSize(.mini) }
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Cancel challenge", norwegian: "Avlys utfordring"
                            ),
                            systemImage: "xmark.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(cancelling)
            }

            if mayRespond {
                HStack(spacing: 8) {
                    Button(action: onDecline) {
                        Text(ATHLTHLocalization.choose(
                            english: "Decline", norwegian: "Avslå"
                        ))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button(action: onAccept) {
                        HStack(spacing: 5) {
                            if responding {
                                ProgressView().controlSize(.mini)
                            }
                            Text(ATHLTHLocalization.choose(
                                english: "Accept", norwegian: "Godta"
                            ))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                }
                .disabled(responding)
            }

            Button(action: onDetails) {
                HStack(spacing: 6) {
                    Text(ATHLTHLocalization.choose(
                        english: "View details", norwegian: "Se detaljer"
                    ))
                    Image(systemName: "arrow.up.right")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(ATHLTHTheme.premiumGold)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(challenge == nil)
        }
        .padding(15)
        .frame(maxWidth: 310, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Color.white.opacity(0.97),
                        ATHLTHTheme.surfaceStone.opacity(0.88),
                        ATHLTHTheme.cardWarm.opacity(0.68)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(LinearGradient(
                    colors: [
                        Color.white.opacity(0.99),
                        ATHLTHTheme.accent.opacity(0.22),
                        Color.white.opacity(0.70)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 1)
        }
        .shadow(color: ATHLTHTheme.accentDeep.opacity(0.08),
                radius: 14, x: 0, y: 6)
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Cancel this challenge for everyone?",
                norwegian: "Avlyse utfordringen for alle?"
            ),
            isPresented: $confirmCancellation,
            titleVisibility: .visible
        ) {
            Button(
                ATHLTHLocalization.choose(
                    english: "Cancel challenge", norwegian: "Avlys utfordring"
                ),
                role: .destructive,
                action: onCancel
            )
            Button(ATHLTHLocalization.choose(
                english: "Keep challenge", norwegian: "Behold utfordringen"
            ), role: .cancel) {}
        }
    }
}

private struct ThreadChallengeTimelineRow: View {
    let challenge: ATHLTHChallenge
    let friend: SocialProfileCard
    let currentUserID: UUID?
    let invitedAt: Date
    let responding: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onDetails: () -> Void
    let cancelling: Bool
    let onCancel: () -> Void

    private var isMine: Bool { challenge.creatorID == currentUserID }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !isMine {
                SocialAvatar(profile: friend, size: 32)
            } else {
                Spacer(minLength: 48)
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                ThreadChallengeInvitationBubble(
                    challenge: challenge,
                    fallbackTitle: challenge.title,
                    fallbackSubtitle: nil,
                    currentUserID: currentUserID,
                    friendUserID: friend.userID,
                    isMine: isMine,
                    responding: responding,
                    onDetails: onDetails,
                    onAccept: onAccept,
                    onDecline: onDecline,
                    cancelling: cancelling,
                    onCancel: onCancel
                )
                Text(invitedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if !isMine { Spacer(minLength: 48) }
        }
    }
}

private struct MessageBubble: View {
    @EnvironmentObject private var challengeStore: ChallengeStore

    let message: DirectMessageRecord
    let friend: SocialProfileCard
    let currentUserID: UUID?
    let currentUserProfile: SocialProfileCard
    let onSaveAttachment: () -> Void
    let onPreviewAttachment: () -> Void
    let inviteResponse: PlannedWorkoutInviteResponse?
    let respondingToInvite: Bool
    let onRespondToInvite: (Bool) -> Void
    let agreedWorkout: PlannedSession?
    let workoutChangeDecision: WorkoutChangeDecision?
    let reviewingWorkoutChange: Bool
    let onProposeWorkoutChange: () -> Void
    let onReviewWorkoutChange: (Bool) -> Void
    let respondingToChallenge: Bool
    let onRespondToChallenge: (ATHLTHChallenge, Bool) -> Void
    let onOpenChallenge: (UUID) -> Void
    let cancellingChallenge: Bool
    let onCancelChallenge: (ATHLTHChallenge) -> Void
    let challengeChangeResponse: ChallengeChangeProposalResponse?
    let respondingToProposal: Bool
    let onReviewProposal: (Bool) -> Void

    private var isPlannedInvitation: Bool {
        message.attachmentKind == .workout && message.shareVersion == 2
    }

    private var isPlannedInviteResponse: Bool {
        message.attachmentKind == .workout && message.shareVersion == 3
    }

    private var isMine: Bool {
        message.senderID == currentUserID
    }

    private var provenanceText: String {
        if let sourceOwnerID = message.sourceOwnerID {
            if sourceOwnerID == currentUserID {
                return ATHLTHLocalization.choose(
                    english: "Created by you", norwegian: "Opprettet av deg"
                )
            }
            if sourceOwnerID == friend.userID {
                return ATHLTHLocalization.choose(
                    english: "Created by \(friend.resolvedName)",
                    norwegian: "Opprettet av \(friend.resolvedName)"
                )
            }
            return ATHLTHLocalization.choose(
                english: "Original creator preserved",
                norwegian: "Opprinnelig oppretter er bevart"
            )
        }

        return isMine
            ? ATHLTHLocalization.choose(
                english: "Shared by you", norwegian: "Delt av deg"
            )
            : ATHLTHLocalization.choose(
                english: "Shared by \(friend.resolvedName)",
                norwegian: "Delt av \(friend.resolvedName)"
            )
    }

    private enum ChallengeStatusKind {
        case waitingOutgoing
        case waitingIncoming
        case accepted
        case declined
        case withdrawn
        case expired
        case cancelled
    }

    private var challengeStatusKind:
        ChallengeStatusKind? {
        guard
            message.attachmentKind ==
                .challenge,
            let challengeID =
                message.sourceObjectID,
            let challenge =
                challengeStore.challenge(
                    id: challengeID
                )
        else {
            return nil
        }

        if challenge.status == .cancelled {
            return .cancelled
        }

        let participantUserID =
            challenge.creatorID ==
                currentUserID
                ? friend.userID
                : currentUserID

        guard
            let participant =
                challenge.participants
                    .first(
                        where: {
                            $0.userID ==
                                participantUserID
                        }
                    )
        else {
            return nil
        }

        switch participant.state {
        case .creator:
            return nil

        case .invited:
            if let endsAt =
                    challenge.rules.endsAt,
               endsAt <= Date() {
                return .expired
            }

            return challenge.creatorID ==
                currentUserID
                ? .waitingOutgoing
                : .waitingIncoming

        case .accepted:
            return challenge.creatorID ==
                currentUserID
                ? .waitingOutgoing
                : .accepted

        case .declined:
            return challenge.creatorID ==
                currentUserID
                ? .waitingOutgoing
                : .declined

        case .withdrawn:
            return .withdrawn
        }
    }

    private var challengeStatusText: String? {
        guard let challengeStatusKind else {
            return nil
        }

        switch challengeStatusKind {
        case .waitingOutgoing:
            return ATHLTHLocalization.choose(
                english: "Sent",
                norwegian: "Sendt"
            )

        case .waitingIncoming:
            return ATHLTHLocalization.choose(
                english: "Waiting for response",
                norwegian: "Venter på svar"
            )

        case .accepted:
            return ATHLTHLocalization.choose(
                english: "Accepted",
                norwegian: "Godtatt"
            )

        case .declined:
            return ATHLTHLocalization.choose(
                english: "Declined",
                norwegian: "Avslått"
            )

        case .withdrawn:
            return ATHLTHLocalization.choose(
                english: "Withdrawn",
                norwegian: "Trukket tilbake"
            )

        case .expired:
            return ATHLTHLocalization.choose(
                english: "Expired",
                norwegian: "Utløpt"
            )

        case .cancelled:
            return ATHLTHLocalization.choose(
                english: "Cancelled",
                norwegian: "Avlyst"
            )
        }
    }

    private var challengeStatusSystemImage: String {
        switch challengeStatusKind {
        case .accepted:
            return "checkmark.circle.fill"
        case .declined:
            return "xmark.circle.fill"
        case .withdrawn:
            return "arrow.uturn.backward.circle.fill"
        case .expired:
            return "clock.badge.xmark"
        case .cancelled:
            return "nosign"
        case .waitingOutgoing,
             .waitingIncoming:
            return "clock.fill"
        case .none:
            return "bolt.fill"
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !isMine {
                senderAvatar(friend)
            } else {
                Spacer(minLength: 48)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                if message.attachmentKind == .challenge &&
                   message.shareVersion == 2,
                   let proposal = message.decodeSnapshot(ChallengeChangeProposal.self) {
                    ChallengeProposalCard(
                        proposal: proposal,
                        response: challengeChangeResponse,
                        currentUserID: currentUserID,
                        sending: respondingToProposal,
                        onApprove: { onReviewProposal(true) },
                        onReject: { onReviewProposal(false) }
                    )
                } else if message.attachmentKind == .challenge &&
                          message.shareVersion == 3,
                          let response = message.decodeSnapshot(ChallengeChangeProposalResponse.self) {
                    ChallengeProposalResponseCard(response: response)
                } else if message.attachmentKind == .challenge {
                    let challengeID = message.sourceObjectID ??
                        message.decodeSnapshot(ATHLTHChallenge.self)?.id
                    let linkedChallenge = challengeID.flatMap {
                        challengeStore.challenge(id: $0)
                    }
                    ThreadChallengeInvitationBubble(
                        challenge: linkedChallenge,
                        fallbackTitle: message.attachmentTitle ??
                            ATHLTHLocalization.choose(
                                english: "Challenge", norwegian: "Utfordring"
                            ),
                        fallbackSubtitle: message.attachmentSubtitle,
                        currentUserID: currentUserID,
                        friendUserID: friend.userID,
                        isMine: isMine,
                        responding: respondingToChallenge,
                        onDetails: {
                            if let challengeID { onOpenChallenge(challengeID) }
                        },
                        onAccept: {
                            if let linkedChallenge {
                                onRespondToChallenge(linkedChallenge, true)
                            }
                        },
                        onDecline: {
                            if let linkedChallenge {
                                onRespondToChallenge(linkedChallenge, false)
                            }
                        },
                        cancelling: cancellingChallenge,
                        onCancel: {
                            if let linkedChallenge {
                                onCancelChallenge(linkedChallenge)
                            }
                        }
                    )
                } else if message.attachmentKind == .workout &&
                          message.shareVersion == 4,
                          let proposal = message.decodeSnapshot(WorkoutChangeProposal.self) {
                    ThreadWorkoutChangeProposalCard(
                        proposal: proposal,
                        decision: workoutChangeDecision,
                        currentUserID: currentUserID,
                        isWorking: reviewingWorkoutChange,
                        onApprove: { onReviewWorkoutChange(true) },
                        onDecline: { onReviewWorkoutChange(false) }
                    )
                } else if message.attachmentKind == .workout &&
                          message.shareVersion == 5,
                          let decision = message.decodeSnapshot(WorkoutChangeDecision.self) {
                    Label(
                        decision.approved
                            ? ATHLTHLocalization.choose(
                                english: "Workout changes approved",
                                norwegian: "Endringene i økten er godkjent"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Workout changes declined",
                                norwegian: "Endringene i økten er avslått"
                            ),
                        systemImage: decision.approved
                            ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .padding(14)
                    .background(.ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 16))
                } else if isPlannedInvitation,
                          let workout = message.decodeSnapshot(PlannedSession.self) {
                    ThreadWorkoutInvitationCard(
                        workout: agreedWorkout ?? workout,
                        response: inviteResponse,
                        isMine: isMine,
                        isResponding: respondingToInvite,
                        onAccept: { onRespondToInvite(true) },
                        onDecline: { onRespondToInvite(false) },
                        onProposeChanges: onProposeWorkoutChange
                    )
                } else if let attachmentKind = message.attachmentKind {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 8) {
                            Image(systemName: attachmentKind.systemImage)
                                .foregroundStyle(ATHLTHTheme.premiumGold)
                            Text(isPlannedInvitation
                                 ? ATHLTHLocalization.choose(
                                     english: "WORKOUT INVITATION",
                                     norwegian: "TRENINGSINVITASJON"
                                   )
                                 : isPlannedInviteResponse
                                     ? ATHLTHLocalization.choose(
                                         english: "INVITATION RESPONSE",
                                         norwegian: "SVAR PÅ INVITASJON"
                                       )
                                     : attachmentKind.title.uppercased())
                                .font(.caption2.weight(.semibold))
                                .tracking(1)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }

                        Text(message.attachmentTitle ?? attachmentKind.title)
                            .font(.headline)

                        if let subtitle = message.attachmentSubtitle,
                           !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let challengeStatusText {
                            Label(
                                challengeStatusText,
                                systemImage:
                                    challengeStatusSystemImage
                            )
                            .font(
                                .caption2
                                    .weight(.semibold)
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accentDeep
                            )
                            .padding(
                                .horizontal,
                                8
                            )
                            .padding(
                                .vertical,
                                5
                            )
                            .background(
                                ATHLTHTheme
                                    .accentSoft,
                                in: Capsule()
                            )
                        }

                        if isPlannedInvitation {
                            if let meeting = message.decodeSnapshot(PlannedSession.self)?.meetingPoint {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(meeting.name, systemImage: "mappin.circle.fill")
                                        .font(.caption.weight(.semibold))
                                    Text(meeting.address)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if let url = URL(string: "https://maps.apple.com/?ll=\(meeting.latitude),\(meeting.longitude)") {
                                        Link(
                                            ATHLTHLocalization.choose(
                                                english: "Open in Maps",
                                                norwegian: "Åpne i Kart"
                                            ),
                                            destination: url
                                        )
                                        .font(.caption.weight(.semibold))
                                    }
                                }
                            }

                            if let inviteResponse {
                                Label(
                                    inviteResponse.decision == .accepted
                                        ? ATHLTHLocalization.choose(
                                            english: "Accepted", norwegian: "Godtatt"
                                        )
                                        : ATHLTHLocalization.choose(
                                            english: "Declined", norwegian: "Avslått"
                                        ),
                                    systemImage: inviteResponse.decision == .accepted
                                        ? "checkmark.circle.fill" : "xmark.circle.fill"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                            } else if isMine {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Waiting for a reply",
                                        norwegian: "Venter på svar"
                                    ),
                                    systemImage: "clock"
                                )
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            } else {
                                HStack(spacing: 9) {
                                    Button(ATHLTHLocalization.choose(
                                        english: "Decline", norwegian: "Avslå"
                                    )) {
                                        onRespondToInvite(false)
                                    }
                                    .buttonStyle(.bordered)
                                    Button(ATHLTHLocalization.choose(
                                        english: "Accept", norwegian: "Godta"
                                    )) {
                                        onRespondToInvite(true)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(ATHLTHTheme.premiumGold)
                                }
                                .disabled(respondingToInvite)
                            }
                        }

                        Text(provenanceText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        if !isMine && !isPlannedInvitation && !isPlannedInviteResponse {
                            HStack(spacing: 8) {
                                if attachmentKind == .challenge {
                                    Button {
                                        onSaveAttachment()
                                    } label: {
                                        Label("View details", systemImage: "bolt.fill")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    Button {
                                        onPreviewAttachment()
                                    } label: {
                                        Label(
                                            ATHLTHLocalization.choose(
                                                english: "View content",
                                                norwegian: "Se innhold"
                                            ),
                                            systemImage: "eye"
                                        )
                                        .font(.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.bordered)
                                    if attachmentKind != .exercise {
                                        Button {
                                            onSaveAttachment()
                                        } label: {
                                            Label(
                                                ATHLTHLocalization.choose(
                                                    english: "Save copy",
                                                    norwegian: "Lagre kopi"
                                                ),
                                                systemImage: "square.and.arrow.down"
                                            )
                                            .font(.caption.weight(.semibold))
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                            .tint(ATHLTHTheme.premiumGold)
                        }
                    }
                    .padding(13)
                    .frame(maxWidth: 300, alignment: .leading)
                    .background(
                        Color.white,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(ATHLTHTheme.border, lineWidth: 1)
                    }
                }

                if let body = message.body,
                   !body.isEmpty {
                    Text(body)
                        .font(.body)
                        .foregroundStyle(
                            isMine
                                ? Color.white
                                : ATHLTHTheme
                                    .primaryText
                        )
                        .lineSpacing(2)
                        .padding(
                            .horizontal,
                            15
                        )
                        .padding(
                            .vertical,
                            11
                        )
                        .background(
                            isMine
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [
                                            ATHLTHPlanDesign.outgoingMessage,
                                            ATHLTHPlanDesign.outgoingMessage.opacity(0.94)
                                        ],
                                        startPoint:
                                            .topLeading,
                                        endPoint:
                                            .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(
                                    Color.white
                                        .opacity(0.96)
                                ),
                            in:
                                RoundedRectangle(
                                    cornerRadius: 20,
                                    style: .continuous
                                )
                        )
                        .overlay {
                            if !isMine {
                                RoundedRectangle(
                                    cornerRadius: 20,
                                    style: .continuous
                                )
                                .stroke(
                                    Color.white
                                        .opacity(0.92),
                                    lineWidth: 0.8
                                )
                            }
                        }
                        .shadow(
                            color:
                                isMine
                                    ? ATHLTHPlanDesign
                                        .outgoingMessage
                                        .opacity(0.10)
                                    : ATHLTHTheme
                                        .accentDeep
                                        .opacity(0.04),
                            radius: 8,
                            y: 3
                        )
                }

                HStack(spacing: 4) {
                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    if isMine {
                        Image(systemName: message.readAt == nil ? "checkmark" : "checkmark.circle.fill")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            if !isMine {
                Spacer(minLength: 48)
            }
        }
    }

    private func senderAvatar(
        _ profile: SocialProfileCard
    ) -> some View {
        NavigationLink {
            FriendProfileView(
                userID: profile.userID
            )
        } label: {
            SocialAvatar(
                profile: profile,
                size: 32
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Open sender profile"
        )
    }
}

struct MessageSharePicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var challengeStore: ChallengeStore
    @EnvironmentObject private var settings: AppSettingsStore

    let onSelect: (MessageShareDraft) -> Void

    @State private var selectedKind: MessageShareKind = .workout
    @State private var shareError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHTheme
                            .premiumGold
                            .opacity(0.16)
                )

                ScrollView {
                    LazyVStack(
                        alignment: .leading,
                        spacing: 16
                    ) {
                        ATHLTHMessagingCompactHeader(
                            eyebrow: ATHLTHLocalization.choose(
                                english: "Share", norwegian: "Del"
                            ),
                            title: ATHLTHLocalization.choose(
                                english: "Share with athlete",
                                norwegian: "Del med utøver"
                            ),
                            symbol: "square.and.arrow.up"
                        )

                        ScrollView(
                            .horizontal,
                            showsIndicators: false
                        ) {
                            HStack(spacing: 8) {
                                ForEach(
                                    MessageShareKind
                                        .allCases
                                ) { kind in
                                    Button {
                                        selectedKind =
                                            kind
                                    } label: {
                                        Label(
                                            kind.localizedTitle,
                                            systemImage:
                                                kind.systemImage
                                        )
                                        .font(
                                            .caption
                                                .weight(
                                                    .semibold
                                                )
                                        )
                                        .padding(
                                            .horizontal,
                                            12
                                        )
                                        .padding(
                                            .vertical,
                                            9
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme.primaryText
                                        )
                                        .background(
                                            selectedKind ==
                                                kind
                                                ? ATHLTHTheme
                                                    .premiumGold
                                                : Color.white
                                                    .opacity(
                                                        0.68
                                                    ),
                                            in: Capsule()
                                        )
                                    }
                                    .buttonStyle(
                                        .plain
                                    )
                                }
                            }
                        }

                        LazyVStack(
                            spacing: 10
                        ) {
                            shareContent
                        }
                    }
                    .padding(16)
                    .padding(
                        .bottom,
                        28
                    )
                    .frame(
                        maxWidth: 680
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .scrollIndicators(
                    .hidden
                )
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbarBackground(
                .hidden,
                for: .navigationBar
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Done",
                            norwegian: "Ferdig"
                        )
                    ) {
                        dismiss()
                    }
                }
            }
            .alert(
                ATHLTHLocalization.choose(
                    english:
                        "Could Not Share",
                    norwegian:
                        "Kunne ikke dele"
                ),
                isPresented: Binding(
                    get: {
                        shareError != nil
                    },
                    set: {
                        if !$0 {
                            shareError = nil
                        }
                    }
                )
            ) {
                Button(
                    "OK",
                    role: .cancel
                ) {}
            } message: {
                Text(
                    shareError ?? ""
                )
            }
        }
    }

    @ViewBuilder
    private var shareContent: some View {
        switch selectedKind {
        case .workout:
            let workouts = shareableWorkouts
            if workouts.isEmpty {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(english: "No saved workouts", norwegian: "Ingen lagrede økter"),
                    systemImage: "dumbbell",
                    description: Text(ATHLTHLocalization.choose(english: "Create a workout or add one to a training plan first.", norwegian: "Opprett en økt eller legg en til i treningsplanen først."))
                )
            } else {
                ForEach(workouts) { workout in
                    shareRow(
                        icon: workout.kind.systemImage,
                        title: workout.title,
                        subtitle: workoutSubtitle(workout)
                    ) {
                        do {
                            onSelect(try ATHLTHShareDraftFactory.workout(
                                workout,
                                library: exerciseLibrary.allExercises,
                                ownerID: session.profile.userID
                            ))
                        } catch {
                            shareError = error.localizedDescription
                        }
                    }
                }
            }

        case .exercise:
            let exercises = exerciseLibrary.allExercises
            if exercises.isEmpty {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(english: "No exercises", norwegian: "Ingen øvelser"),
                    systemImage: "dumbbell"
                )
            } else {
                ForEach(exercises) { exercise in
                    shareRow(
                        icon: "dumbbell.fill",
                        title: exerciseLibrary.localizedExerciseName(exercise),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Exercise from the library",
                            norwegian: "Øvelse fra biblioteket"
                        )
                    ) {
                        do {
                            onSelect(try ATHLTHShareDraftFactory.exercise(
                                exercise, ownerID: session.profile.userID
                            ))
                        } catch {
                            shareError = error.localizedDescription
                        }
                    }
                }
            }

        case .trainingPlan:
            let plans = shareablePlans
            if plans.isEmpty {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(english: "No training plans", norwegian: "Ingen treningsplaner"),
                    systemImage: "calendar",
                    description: Text(ATHLTHLocalization.choose(english: "Create or save a training plan first.", norwegian: "Opprett eller lagre en treningsplan først."))
                )
            } else {
                ForEach(plans) { plan in
                    shareRow(
                        icon: "calendar",
                        title: plan.title,
                        subtitle: "\(plan.weeks.count) weeks · version \(plan.version)"
                    ) {
                        do {
                            onSelect(try ATHLTHShareDraftFactory.plan(
                                plan,
                                library: exerciseLibrary.allExercises,
                                ownerID: session.profile.userID
                            ))
                        } catch {
                            shareError = error.localizedDescription
                        }
                    }
                }
            }

        case .runningWorkout:
            if runningLibrary.customTemplates.isEmpty {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(english: "No custom running workouts", norwegian: "Ingen lagrede løpeøkter"),
                    systemImage: "figure.run",
                    description: Text(ATHLTHLocalization.choose(english: "Create a running workout first.", norwegian: "Opprett en løpeøkt først."))
                )
            } else {
                ForEach(runningLibrary.customTemplates) { workout in
                    shareRow(
                        icon: "figure.run",
                        title: workout.title,
                        subtitle: workout.summary
                    ) {
                        createDraft(
                            kind: .runningWorkout,
                            title: workout.title,
                            subtitle: workout.summary,
                            snapshot: workout,
                            sourceObjectID: workout.sharedSourceWorkoutID ?? workout.id,
                            sourceOwnerID: workout.sharedSourceOwnerID ?? session.profile.userID
                        )
                    }
                }
            }

        case .route:
            if session.savedRoutes.isEmpty {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(english: "No saved routes", norwegian: "Ingen lagrede ruter"),
                    systemImage: "map",
                    description: Text(ATHLTHLocalization.choose(english: "Save or import a route first.", norwegian: "Lagre eller importer en rute først."))
                )
            } else {
                ForEach(session.savedRoutes) { route in
                    let safeRoute = privacySafeRoute(route)
                    shareRow(
                        icon: "map.fill",
                        title: route.title,
                        subtitle: routeSubtitle(safeRoute)
                    ) {
                        createDraft(
                            kind: .route,
                            title: route.title,
                            subtitle: routeSubtitle(safeRoute),
                            snapshot: safeRoute,
                            sourceObjectID: route.sharedSourceRouteID ?? route.id,
                            sourceOwnerID: route.sharedSourceOwnerID ?? route.ownerID
                        )
                    }
                }
            }

        case .challenge:
            if shareableChallenges.isEmpty {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(english: "No challenges", norwegian: "Ingen utfordringer"),
                    systemImage: "bolt",
                    description: Text(ATHLTHLocalization.choose(english: "Create or join a challenge first.", norwegian: "Opprett eller bli med i en utfordring først."))
                )
            } else {
                ForEach(shareableChallenges) { challenge in
                    shareRow(
                        icon: challenge.sport.systemImage,
                        title: challenge.title,
                        subtitle: "\(challenge.sport.title) · \(challenge.rules.scoring.title)"
                    ) {
                        createDraft(
                            kind: .challenge,
                            title: challenge.title,
                            subtitle: "\(challenge.sport.title) · \(challenge.rules.scoring.title)",
                            snapshot: challenge,
                            sourceObjectID: challenge.id,
                            sourceOwnerID: challenge.creatorID
                        )
                    }
                }
            }
        }
    }

    private var shareableChallenges: [ATHLTHChallenge] {
        challengeStore.visibleChallenges.filter { challenge in
            challenge.creatorID == session.profile.userID ||
            challenge.participants.contains {
                $0.userID == session.profile.userID &&
                ($0.state == .creator || $0.state == .accepted)
            }
        }
    }

    private var shareablePlans: [TrainingPlan] {
        var result: [TrainingPlan] = []
        if let activePlan = session.activePlan {
            result.append(activePlan)
        }
        result.append(contentsOf: session.planTemplates)
        return result
    }

    private var shareableWorkouts: [PlannedSession] {
        var result = session.savedWorkoutTemplates

        if let plan = session.activePlan {
            result.append(
                contentsOf: plan.weeks
                    .flatMap(\.days)
                    .flatMap(\.sessions)
            )
        }

        var seen = Set<UUID>()
        return result.filter { seen.insert($0.id).inserted }
    }

    private func workoutSubtitle(_ workout: PlannedSession) -> String {
        var parts: [String] = [workout.kind.title]
        if let duration = workout.durationMinutes {
            parts.append("\(duration) min")
        }
        if !workout.exercises.isEmpty {
            parts.append("\(workout.exercises.count) exercises")
        }
        return parts.joined(separator: " · ")
    }

    private func routeSubtitle(_ route: TrainingRoute) -> String {
        var value = String(format: "%.2f km", route.distanceKilometers)
        if settings.hideRouteStartAndEnd {
            value += " · start/end hidden"
        }
        return value
    }

    private func privacySafeRoute(_ route: TrainingRoute) -> TrainingRoute {
        guard settings.hideRouteStartAndEnd,
              route.coordinates.count > 4
        else {
            return route
        }

        let trimmed = trimRoute(route.coordinates, bufferMeters: 250)
        guard trimmed.count >= 2 else { return route }

        var copy = route
        copy.coordinates = trimmed.enumerated().map { index, point in
            RouteCoordinate(
                latitude: point.latitude,
                longitude: point.longitude,
                altitude: point.altitude,
                sequence: index
            )
        }
        copy.distanceKilometers = routeDistanceKilometers(copy.coordinates)
        copy.startName = nil
        copy.endName = nil
        return copy
    }

    private func routeDistanceKilometers(
        _ coordinates: [RouteCoordinate]
    ) -> Double {
        guard coordinates.count > 1 else { return 0 }

        return zip(coordinates, coordinates.dropFirst())
            .reduce(0) { total, pair in
                let start = CLLocation(
                    latitude: pair.0.latitude,
                    longitude: pair.0.longitude
                )
                let end = CLLocation(
                    latitude: pair.1.latitude,
                    longitude: pair.1.longitude
                )
                return total + start.distance(from: end)
            } / 1_000
    }

    private func trimRoute(
        _ coordinates: [RouteCoordinate],
        bufferMeters: CLLocationDistance
    ) -> [RouteCoordinate] {
        guard coordinates.count > 2 else { return coordinates }

        func location(_ point: RouteCoordinate) -> CLLocation {
            CLLocation(latitude: point.latitude, longitude: point.longitude)
        }

        var startIndex = 0
        var distance: CLLocationDistance = 0
        while startIndex + 1 < coordinates.count {
            distance += location(coordinates[startIndex]).distance(
                from: location(coordinates[startIndex + 1])
            )
            startIndex += 1
            if distance >= bufferMeters { break }
        }

        var endIndex = coordinates.count - 1
        distance = 0
        while endIndex - 1 > startIndex {
            distance += location(coordinates[endIndex]).distance(
                from: location(coordinates[endIndex - 1])
            )
            endIndex -= 1
            if distance >= bufferMeters { break }
        }

        guard startIndex < endIndex else { return coordinates }
        return Array(coordinates[startIndex...endIndex])
    }

    private func shareRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(
            action: action
        ) {
            HStack(spacing: 13) {
                Image(
                    systemName: icon
                )
                .font(
                    .system(
                        size: 16,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .premiumGold
                )
                .frame(
                    width: 42,
                    height: 42
                )
                .background(
                    ATHLTHTheme
                        .premiumGoldSoft,
                    in: RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                )

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(title)
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
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(2)
                }

                Spacer()

                Image(
                    systemName:
                        "paperplane.fill"
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .premiumGold
                )
            }
            .padding(13)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .background(
                LinearGradient(
                    colors: [
                        Color.white
                            .opacity(0.95),
                        ATHLTHTheme
                            .cardWarm
                            .opacity(0.72)
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                ),
                in: RoundedRectangle(
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
                    Color.white
                        .opacity(0.9),
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func createDraft<T: Encodable>(
        kind: MessageShareKind,
        title: String,
        subtitle: String,
        snapshot: T,
        sourceObjectID: UUID?,
        sourceOwnerID: UUID?,
        shareVersion: Int = 1
    ) {
        do {
            let draft = try MessageShareDraft(
                kind: kind,
                title: title,
                subtitle: subtitle,
                snapshot: snapshot,
                sourceObjectID: sourceObjectID,
                sourceOwnerID: sourceOwnerID,
                shareVersion: shareVersion
            )
            onSelect(draft)
        } catch {
            shareError = error.localizedDescription
        }
    }
}
