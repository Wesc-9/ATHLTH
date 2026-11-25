import CoreLocation
import SwiftUI

struct MessageInboxDestinationView: View {
    @State private var showingNewMessage = false

    /// Used for dismissing the inbox from iPhone navigation or the iPad inspector.
    var onBack: (() -> Void)? = nil
    /// iPad inspector collapses to the right; iPhone navigation goes back left.
    var isInspectorPanel = false
    var initialWorkoutInviteID: UUID? = nil

    var body: some View {
        MessageInboxView(
            onBack: onBack,
            isInspectorPanel: isInspectorPanel,
            initialWorkoutInviteID: initialWorkoutInviteID,
            onNewMessage: { showingNewMessage = true }
        )
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
    case invitations
    case groups
    case archive

    // Unread first, then people, groups and invitations.
    static let mainFilters: [MessageInboxFilter] = [
        .unread, .all, .groups, .invitations, .direct
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return ATHLTHLocalization.choose(english: "People", norwegian: "Folk")
        case .unread:
            return ATHLTHLocalization.choose(english: "Unread", norwegian: "Uleste")
        case .direct:
            return ATHLTHLocalization.choose(english: "Messages", norwegian: "Meldinger")
        case .invitations:
            return ATHLTHLocalization.choose(english: "Invitations", norwegian: "Invitasjoner")
        case .groups:
            return ATHLTHLocalization.choose(english: "Groups", norwegian: "Grupper")
        case .archive:
            return ATHLTHLocalization.choose(english: "Archive", norwegian: "Arkiv")
        }
    }

    var icon: String {
        switch self {
        case .all: return "person.2"
        case .unread: return "envelope.badge"
        case .direct: return "bubble.left"
        case .invitations: return "envelope.open"
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

    // Keep onNewMessage last so existing trailing-closure callers still
    // open the composer rather than unintentionally wiring a back action.
    var onBack: (() -> Void)? = nil
    var isInspectorPanel = false
    var initialWorkoutInviteID: UUID? = nil
    var onNewMessage: () -> Void = {}

    @State private var arenaInboxVisibleCount = 0
    @State private var tournamentInboxVisibleCount = 0
    @State private var searchText = ""
    @State private var showingSearch = false
    @State private var selectedFilter:
        MessageInboxFilter = .all
    @State private var clubSectionExpanded = false
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
                    selectedFilter != .invitations &&
                    !recentConversations.isEmpty {
                    recentConversationsStrip
                }

                inboxFilterBar

                // Same invitation records and actions as Tren sammen.
                // Accepting here updates SocialStore before the other
                // screen is opened; no duplicate message is generated.
                if selectedFilter == .all || selectedFilter == .invitations {
                    ATHLTHWorkoutInvitationSection(
                        showsAccepted: true,
                        showsEmptyState: selectedFilter == .invitations,
                        searchText: searchText,
                        highlightedSessionID: initialWorkoutInviteID
                    )
                }

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


                // New club messages share the normal white conversation-row
                // presentation; the club-name prefix identifies the source.
                if !unreadClubs.isEmpty {
                    inboxSectionLabel(
                        ATHLTHLocalization.choose(
                            english: "NEW CLUB MESSAGES",
                            norwegian: "NYE KLUBBMELDINGER"
                        ),
                        count: unreadClubs.count
                    )
                    LazyVStack(spacing: 10) {
                        ForEach(unreadClubs) { club in
                            if let message = groups.recentClubMessagesByGroup[club.id] {
                                ATHLTHUnreadClubMessageRow(
                                    group: club, message: message
                                )
                            }
                        }
                    }
                }

                if selectedFilter == .groups {
                    ATHLTHCommunityClubInboxSection()
                }

                if selectedFilter == .all || selectedFilter == .groups {
                    ATHLTHClubChatInboxSection(
                        searchText: searchText,
                        isExpanded: $clubSectionExpanded
                    )
                }

                ATHLTHTournamentInboxSection(
                    filterKey: selectedFilter.rawValue,
                    onVisibleCountChanged: { tournamentInboxVisibleCount = $0 }
                )

                ATHLTHArenaInboxSection(
                    filterKey: selectedFilter.rawValue,
                    onVisibleCountChanged: { arenaInboxVisibleCount = $0 }
                )

                if let error = displayableError {
                    inboxErrorCard(error)
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
            if initialWorkoutInviteID != nil {
                selectedFilter = .invitations
            }
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
            if initialWorkoutInviteID != nil {
                selectedFilter = .invitations
            }
            refreshCoachInboxState()
        }
        .onChange(of: selectedFilter) { _, next in
            if next == .groups { clubSectionExpanded = true }
            else if next == .all { clubSectionExpanded = false }
        }
        .task {
            // Poll only while Inbox is on screen; do not treat club
            // invitations as direct messages.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(45)) }
                catch { break }
                await groups.refreshRecentChatActivity(force: true)
            }
        }
        .onChange(of: initialWorkoutInviteID) { _, inviteID in
            if inviteID != nil {
                selectedFilter = .invitations
                searchText = ""
            }
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
        VStack(alignment: .leading, spacing: 16) {
            // The inbox owns its navigation controls on iPhone and iPad.
            // No duplicate profile shortcut or wordmark is needed here.
            HStack(alignment: .center, spacing: 12) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: isInspectorPanel ? "chevron.right" : "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .frame(width: 48, height: 48)
                            .background(
                                ATHLTHTheme.premiumGoldSoft.opacity(0.72),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        ATHLTHTheme.premiumGold.opacity(0.24),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        isInspectorPanel
                            ? ATHLTHLocalization.choose(
                                english: "Hide Inbox",
                                norwegian: "Skjul innboks"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Back to Home",
                                norwegian: "Tilbake til Hjem"
                            )
                    )
                    .accessibilityIdentifier(
                        isInspectorPanel
                            ? "athlth-ipad-hide-inspector"
                            : "athlth-inbox-back-to-home"
                    )
                }

                Spacer(minLength: 0)

                HStack(spacing: 9) {
                    headerAction(
                        systemImage: showingSearch ? "xmark" : "magnifyingglass",
                        accessibilityLabel: showingSearch
                            ? ATHLTHLocalization.choose(
                                english: "Close search",
                                norwegian: "Lukk søk"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Search messages",
                                norwegian: "Søk i meldinger"
                            )
                    ) {
                        withAnimation(.easeInOut(duration: 0.20)) {
                            showingSearch.toggle()
                            if !showingSearch {
                                searchText = ""
                            }
                        }
                    }

                    headerAction(
                        systemImage: "plus",
                        accessibilityLabel: ATHLTHLocalization.choose(
                            english: "New message",
                            norwegian: "Ny melding"
                        ),
                        action: onNewMessage
                    )
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "INNER CIRCLE",
                        norwegian: "INNER CIRCLE"
                    )
                )
                .font(.system(size: 10, weight: .semibold))
                .tracking(3.2)
                .foregroundStyle(ATHLTHTheme.mutedText)

                Text(
                    ATHLTHLocalization.choose(
                        english: "Messages",
                        norwegian: "Meldinger"
                    )
                )
                .font(.system(size: 40, weight: .bold, design: .serif))
                .foregroundStyle(ATHLTHTheme.primaryText)

                Text(
                    ATHLTHLocalization.choose(
                        english: "The people who move you forward.",
                        norwegian: "Menneskene som får deg videre."
                    )
                )
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
        }
        .padding(.top, 0)
        // Preserve the iPad inspector's header-only close gesture without
        // interfering with gestures inside actual conversations.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard isInspectorPanel,
                          let onBack,
                          ATHLTHStudioInboxPanelGesturePolicy.shouldClose(
                            translation: value.translation
                          )
                    else { return }
                    onBack()
                }
        )
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
                        if filter == .unread {
                            let unreadCount = messaging.unreadCount +
                                groups.unreadClubGroupIDs.count
                            if unreadCount > 0 {
                                Text("\(min(unreadCount, 99))")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(ATHLTHTheme.accentSoft, in: Capsule())
                            }
                        }
                        if filter == .invitations {
                            let unansweredCount = social.workoutInvites.filter {
                                $0.participant.state == .invited
                            }.count
                            if unansweredCount > 0 {
                                Text("\(min(unansweredCount, 99))")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(ATHLTHTheme.accentSoft, in: Capsule())
                            }
                        }
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
                                english: "Back to people",
                                norwegian: "Tilbake til folk"
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
        let pendingWorkouts = social.workoutInvites.filter {
            $0.participant.state == .invited
        }.count
        if pendingWorkouts > 0 {
            return ATHLTHLocalization.choose(
                english: pendingWorkouts == 1
                    ? "1 workout invitation waiting"
                    : "\(pendingWorkouts) workout invitations waiting",
                norwegian: pendingWorkouts == 1
                    ? "1 treningsinvitasjon venter"
                    : "\(pendingWorkouts) treningsinvitasjoner venter"
            )
        }
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
        case .invitations:
            return ATHLTHLocalization.choose(
                english: "No invitations", norwegian: "Ingen invitasjoner"
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
        case .invitations:
            return ATHLTHLocalization.choose(
                english: "Your workout invitations will appear here.",
                norwegian: "Treningsinvitasjonene dine vises her."
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
                case .invitations:
                    return false
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
        requestPersonItems.count + groups.ownInvites.reduce(into: 0) { count, invite in
            if invite.status == "pending" { count += 1 }
        }
    }

    private var unreadClubs: [CommunityGroupRecord] {
        guard selectedFilter == .all || selectedFilter == .unread else { return [] }
        let query = normalizedSearch
        return groups.joinedGroups.filter { club in
            guard groups.unreadClubGroupIDs.contains(club.id),
                  let message = groups.recentClubMessagesByGroup[club.id] else {
                return false
            }
            return query.isEmpty ||
                club.name.localizedCaseInsensitiveContains(query) ||
                message.body.localizedCaseInsensitiveContains(query)
        }
        .sorted {
            let left = groups.recentClubMessagesByGroup[$0.id]?.createdAt ??
                .distantPast
            let right = groups.recentClubMessagesByGroup[$1.id]?.createdAt ??
                .distantPast
            return left > right
        }
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
        return selectedFilter != .invitations &&
            (selectedFilter != .all || social.workoutInvites.isEmpty) &&
            displayedPersonItems.isEmpty &&
            arenaInboxVisibleCount == 0 &&
            tournamentInboxVisibleCount == 0 &&
            !hasClubInvites &&
            !hasVisibleClubChats &&
            unreadClubs.isEmpty &&
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

        // Workout invitations are displayed once as actionable Inbox cards.
        // Never synthesize a second invite-only DM row for the same request.

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

struct MessageSharePicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var challengeStore: ChallengeStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore

    let onSelect: (MessageShareDraft) -> Void
    let allowedKinds: [MessageShareKind]

    @State private var selectedKind: MessageShareKind
    @State private var exerciseCategory: ATHLTHExerciseActivity?
    @State private var workoutActivity: WorkoutKind?
    @State private var routeDistance: ATHLTHRouteShareDistanceFilter?
    @State private var favoritesOnly = false
    @State private var shareError: String?

    private var isExerciseOnly: Bool {
        allowedKinds.count == 1 && allowedKinds[0] == .exercise
    }

    // The friend-to-friend workout flow includes both saved sessions and
    // saved running templates; these share one activity filter without
    // changing either attachment type.
    private var isWorkoutSharing: Bool {
        allowedKinds.contains(.workout) &&
        allowedKinds.allSatisfy { $0 == .workout || $0 == .runningWorkout }
    }

    private var isPlanOnly: Bool {
        allowedKinds.count == 1 && allowedKinds[0] == .trainingPlan
    }

    private var isRouteOnly: Bool {
        allowedKinds.count == 1 && allowedKinds[0] == .route
    }

    private var usesActivityFilters: Bool {
        isExerciseOnly || isWorkoutSharing || isPlanOnly || isRouteOnly
    }

    private func allowsFavorite(_ kind: LibraryFavoriteKind, id: UUID) -> Bool {
        !favoritesOnly || favorites.isFavorite(kind, itemID: id.uuidString)
    }

    private var eligibleExercises: [ExerciseLibraryEntry] {
        exerciseLibrary.customExercises.filter {
            ATHLTHPersonalExerciseSharing.isEligible(
                $0, ownerID: session.profile.userID
            )
        }
    }

    private var filteredExercises: [ExerciseLibraryEntry] {
        eligibleExercises.filter { entry in
            allowsFavorite(.exercise, id: entry.id) &&
            (exerciseCategory == nil ||
             (entry.exercise.activityCategory ?? .strength) == exerciseCategory)
        }
    }

    private var shareTitle: String {
        if isExerciseOnly {
            return ATHLTHLocalization.choose(
                english: "Share exercise", norwegian: "Del øvelse"
            )
        }
        if isRouteOnly {
            return ATHLTHLocalization.choose(english: "Share route", norwegian: "Del rute")
        }
        if isWorkoutSharing {
            return ATHLTHLocalization.choose(
                english: "Share workout", norwegian: "Del treningsøkt"
            )
        }
        if isPlanOnly {
            return ATHLTHLocalization.choose(
                english: "Share training plan", norwegian: "Del treningsplan"
            )
        }
        return ATHLTHLocalization.choose(
            english: "Share content", norwegian: "Del innhold"
        )
    }

    private var shareEyebrow: String {
        if isExerciseOnly {
            return ATHLTHLocalization.choose(
                english: "Exercise sharing", norwegian: "Øvelsesdeling"
            )
        }
        if isRouteOnly {
            return ATHLTHLocalization.choose(english: "Route sharing", norwegian: "Rutedeling")
        }
        if isWorkoutSharing {
            return ATHLTHLocalization.choose(
                english: "Workout sharing", norwegian: "Øktdeling"
            )
        }
        if isPlanOnly {
            return ATHLTHLocalization.choose(
                english: "Training plan sharing", norwegian: "Plandeling"
            )
        }
        return ATHLTHLocalization.choose(
            english: "Sharing", norwegian: "Deling"
        )
    }

    init(
        allowedKinds: [MessageShareKind] = MessageShareKind.allCases,
        onSelect: @escaping (MessageShareDraft) -> Void
    ) {
        self.allowedKinds = allowedKinds.isEmpty
            ? MessageShareKind.allCases : allowedKinds
        self.onSelect = onSelect
        _selectedKind = State(initialValue: self.allowedKinds[0])
    }

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
                        // Titles sit next to Done; single-purpose share
                        // screens use genuine activity filters, not a lone
                        // redundant content-kind chip.
                        if usesActivityFilters {
                            if isExerciseOnly {
                                exerciseActivityFilters
                            } else if isRouteOnly {
                                routeDistanceFilters
                            } else {
                                workoutActivityFilters
                            }
                        } else {
                        ScrollView(
                            .horizontal,
                            showsIndicators: false
                        ) {
                            HStack(spacing: 8) {
                                ForEach(
                                    allowedKinds
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
            // Navigation toolbar items can collapse the leading title into
            // a tiny circle on narrow iPhones. Keep the heading in a real
            // full-width layout for every share kind instead.
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(shareEyebrow.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(ATHLTHTheme.premiumGold)
                        Text(shareTitle)
                            .font(.system(size: 23, weight: .semibold, design: .serif))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)

                    Button(ATHLTHLocalization.choose(
                        english: "Done", norwegian: "Ferdig"
                    )) {
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(.white.opacity(0.88), in: Capsule())
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(ATHLTHPlanDesign.canvas)
            }
            .task(id: session.profile.userID) {
                await favorites.refresh()
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

    private var exerciseActivityFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                favoritesFilterChip
                exerciseFilterChip(
                    title: ATHLTHLocalization.choose(
                        english: "All", norwegian: "Alle"
                    ),
                    symbol: "square.grid.2x2",
                    selected: !favoritesOnly && exerciseCategory == nil
                ) {
                    favoritesOnly = false
                    exerciseCategory = nil
                }
                ForEach(ATHLTHExerciseActivity.allCases) { category in
                    exerciseFilterChip(
                        title: category.title,
                        symbol: category.systemImage,
                        selected: exerciseCategory == category
                    ) {
                        favoritesOnly = false
                        exerciseCategory = category
                    }
                }
            }
        }
    }

    private var workoutActivityFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                favoritesFilterChip
                exerciseFilterChip(
                    title: ATHLTHLocalization.choose(
                        english: "All", norwegian: "Alle"
                    ),
                    symbol: "square.grid.2x2",
                    selected: !favoritesOnly && workoutActivity == nil
                ) {
                    favoritesOnly = false
                    workoutActivity = nil
                }
                ForEach(WorkoutKind.allCases) { kind in
                    exerciseFilterChip(
                        title: shareWorkoutActivityTitle(kind),
                        symbol: kind.systemImage,
                        selected: workoutActivity == kind
                    ) {
                        favoritesOnly = false
                        workoutActivity = kind
                    }
                }
            }
        }
    }

    private var routeDistanceFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                favoritesFilterChip
                exerciseFilterChip(
                    title: ATHLTHLocalization.choose(english: "All", norwegian: "Alle"),
                    symbol: "square.grid.2x2",
                    selected: !favoritesOnly && routeDistance == nil
                ) {
                    favoritesOnly = false
                    routeDistance = nil
                }
                ForEach(ATHLTHRouteShareDistanceFilter.allCases) { distance in
                    exerciseFilterChip(
                        title: distance.title,
                        symbol: "point.topleft.down.to.point.bottomright.curvepath",
                        selected: routeDistance == distance
                    ) {
                        favoritesOnly = false
                        routeDistance = distance
                    }
                }
            }
        }
    }

    private var favoritesFilterChip: some View {
        exerciseFilterChip(
            title: ATHLTHLocalization.choose(
                english: "Favorites", norwegian: "Favoritter"
            ),
            symbol: "star.fill",
            selected: favoritesOnly
        ) {
            favoritesOnly = true
            exerciseCategory = nil
            workoutActivity = nil
            routeDistance = nil
        }
    }

    private func shareWorkoutActivityTitle(_ kind: WorkoutKind) -> String {
        switch kind {
        case .running:
            return ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
        case .walking:
            return ATHLTHLocalization.choose(english: "Walking", norwegian: "Gåing")
        case .strength:
            return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
        case .mobility:
            return ATHLTHLocalization.choose(english: "Mobility", norwegian: "Mobilitet")
        case .recovery:
            return ATHLTHLocalization.choose(english: "Recovery", norwegian: "Restitusjon")
        case .custom:
            return ATHLTHLocalization.choose(english: "Other", norwegian: "Annet")
        }
    }

    private func exerciseFilterChip(
        title: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? Color.white : ATHLTHTheme.primaryText)
                .padding(.horizontal, 12)
                .frame(minHeight: 37)
                .background(
                    selected ? ATHLTHTheme.premiumGold : Color.white.opacity(0.7),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var shareContent: some View {
        switch selectedKind {
        case .workout:
            let workouts = isWorkoutSharing || favoritesOnly ? filteredWorkouts : shareableWorkouts
            let runningTemplates = isWorkoutSharing ? filteredRunningTemplates : []
            if workouts.isEmpty && runningTemplates.isEmpty {
                ContentUnavailableView(
                    isWorkoutSharing && workoutActivity != nil &&
                        (!shareableWorkouts.isEmpty || !shareableRunningTemplates.isEmpty)
                        ? ATHLTHLocalization.choose(
                            english: "No workouts in this activity",
                            norwegian: "Ingen treningsøkter i denne aktiviteten"
                        )
                        : ATHLTHLocalization.choose(
                            english: "No saved workouts", norwegian: "Ingen lagrede økter"
                        ),
                    systemImage: workoutActivity?.systemImage ?? "dumbbell",
                    description: Text(ATHLTHLocalization.choose(
                        english: "Choose another activity, or create and save a workout first.",
                        norwegian: "Velg en annen aktivitet, eller opprett og lagre en treningsøkt først."
                    ))
                )
            } else {
                ForEach(workouts) { workout in
                    shareRow(
                        icon: workout.kind.systemImage,
                        title: workout.title,
                        subtitle: workoutSubtitle(workout),
                        favoriteKind: .workout,
                        favoriteID: workout.id
                    ) {
                        do {
                            onSelect(try ATHLTHShareDraftFactory.workout(
                                workout,
                                library: exerciseLibrary.allExercises,
                                ownerID: session.profile.userID,
                                savedWorkouts: session.savedWorkoutTemplates
                            ))
                        } catch {
                            shareError = error.localizedDescription
                        }
                    }
                }
                // These are a different persisted model, but belong in the
                // same running category and keep their existing safe payload.
                ForEach(runningTemplates) { workout in
                    shareRow(
                        icon: "figure.run",
                        title: workout.title,
                        subtitle: workout.summary,
                        favoriteKind: .workout,
                        favoriteID: workout.id
                    ) {
                        shareRunningTemplate(workout)
                    }
                }
            }

        case .exercise:
            let exercises = filteredExercises
            if eligibleExercises.isEmpty {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(
                        english: "No personal exercises yet",
                        norwegian: "Ingen egne øvelser ennå"
                    ),
                    systemImage: "dumbbell",
                    description: Text(ATHLTHLocalization.choose(
                        english: "Create an exercise in My Exercises to share it. Catalog exercises are already available to everyone.",
                        norwegian: "Opprett en øvelse i Mine øvelser for å dele den. Øvelser fra biblioteket har alle allerede."
                    ))
                )
            } else if exercises.isEmpty {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(
                        english: "No exercises in this activity",
                        norwegian: "Ingen øvelser i denne aktiviteten"
                    ),
                    systemImage: exerciseCategory?.systemImage ?? "dumbbell",
                    description: Text(ATHLTHLocalization.choose(
                        english: "Try another category or set the activity on an exercise in My Exercises.",
                        norwegian: "Prøv en annen kategori, eller endre aktivitet på øvelsen under Mine øvelser."
                    ))
                )
            } else {
                ForEach(exercises) { exercise in
                    shareRow(
                        icon: (exercise.exercise.activityCategory ?? .strength).systemImage,
                        title: exerciseLibrary.localizedExerciseName(exercise),
                        subtitle: (exercise.exercise.activityCategory ?? .strength).title +
                            " · " + ATHLTHLocalization.choose(
                                english: "My Exercises", norwegian: "Mine øvelser"
                            ),
                        favoriteKind: .exercise,
                        favoriteID: exercise.id
                    ) {
                        do {
                            onSelect(try ATHLTHShareDraftFactory.exercise(
                                exercise, ownerID: session.profile.userID,
                                creatorUsername: session.profile.username,
                                savedExercises: exerciseLibrary.customExercises
                            ))
                        } catch {
                            shareError = error.localizedDescription
                        }
                    }
                }
            }

        case .trainingPlan:
            let plans = isPlanOnly ? filteredPlans : shareablePlans
            if plans.isEmpty {
                ContentUnavailableView(
                    isPlanOnly && workoutActivity != nil && !shareablePlans.isEmpty
                        ? ATHLTHLocalization.choose(
                            english: "No training plans in this activity",
                            norwegian: "Ingen treningsplaner i denne aktiviteten"
                        )
                        : ATHLTHLocalization.choose(
                            english: "No training plans", norwegian: "Ingen treningsplaner"
                        ),
                    systemImage: workoutActivity?.systemImage ?? "calendar",
                    description: Text(ATHLTHLocalization.choose(
                        english: "Choose another activity, or create and save your own plan first.",
                        norwegian: "Velg en annen aktivitet, eller opprett og lagre din egen treningsplan først."
                    ))
                )
            } else {
                ForEach(plans) { plan in
                    shareRow(
                        icon: "calendar",
                        title: plan.title,
                        subtitle: "\(plan.weeks.count) weeks · version \(plan.version)",
                        favoriteKind: .plan,
                        favoriteID: plan.id
                    ) {
                        do {
                            onSelect(try ATHLTHShareDraftFactory.plan(
                                plan,
                                library: exerciseLibrary.allExercises,
                                ownerID: session.profile.userID,
                                savedPlans: session.planTemplates + session.scheduledPlans
                            ))
                        } catch {
                            shareError = error.localizedDescription
                        }
                    }
                }
            }

        case .runningWorkout:
            let workouts = favoritesOnly ? filteredRunningTemplates : shareableRunningTemplates
            if workouts.isEmpty {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(english: "No custom running workouts", norwegian: "Ingen lagrede løpeøkter"),
                    systemImage: "figure.run",
                    description: Text(ATHLTHLocalization.choose(english: "Create a running workout first.", norwegian: "Opprett en løpeøkt først."))
                )
            } else {
                ForEach(workouts) { workout in
                    shareRow(
                        icon: "figure.run",
                        title: workout.title,
                        subtitle: workout.summary,
                        favoriteKind: .workout,
                        favoriteID: workout.id
                    ) {
                        shareRunningTemplate(workout)
                    }
                }
            }

        case .route:
            let routes = filteredRoutes
            if routes.isEmpty {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(english: "No saved routes", norwegian: "Ingen lagrede ruter"),
                    systemImage: "map",
                    description: Text(ATHLTHLocalization.choose(english: "Create and save your own route first.", norwegian: "Opprett og lagre din egen rute først."))
                )
            } else {
                ForEach(routes) { route in
                    let safeRoute = privacySafeRoute(route)
                    shareRow(
                        icon: "map.fill",
                        title: route.title,
                        subtitle: routeSubtitle(route),
                        routePreview: safeRoute,
                        favoriteKind: .route,
                        favoriteID: route.id,
                        favoriteSubtitle: String(format: "%.2f km", route.distanceKilometers)
                    ) {
                        guard ATHLTHPersonalSharePolicy.route(
                            route, ownerID: session.profile.userID
                        ), session.savedRoutes.contains(where: {
                            $0.id == route.id &&
                            ATHLTHPersonalSharePolicy.route(
                                $0, ownerID: session.profile.userID
                            )
                        }) else {
                            shareError = ATHLTHDirectShareError.onlySavedPersonalContent.localizedDescription
                            return
                        }
                        // Never transmit an untrimmed start/end coordinate
                        // when the athlete has enabled endpoint protection.
                        if settings.hideRouteStartAndEnd &&
                           safeRoute.coordinates == route.coordinates {
                            shareError = ATHLTHLocalization.choose(
                                english: "This route is too short to hide its start and end safely.",
                                norwegian: "Denne ruten kan ikke deles med skjult start og slutt på en trygg måte."
                            )
                            return
                        }
                        createDraft(
                            kind: .route,
                            title: route.title,
                            subtitle: String(format: "%.2f km", safeRoute.distanceKilometers),
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

    private var filteredRoutes: [TrainingRoute] {
        ATHLTHPersonalSharePolicy.savedRoutes(
            session.savedRoutes, ownerID: session.profile.userID
        ).filter {
            allowsFavorite(.route, id: $0.id) &&
            (routeDistance?.matches($0.distanceKilometers) ?? true)
        }
    }

    private var shareablePlans: [TrainingPlan] {
        ATHLTHPersonalSharePolicy.savedPlans(
            session.planTemplates + session.scheduledPlans,
            ownerID: session.profile.userID
        )
    }

    private var filteredPlans: [TrainingPlan] {
        shareablePlans.filter { plan in
            guard allowsFavorite(.plan, id: plan.id) else { return false }
            guard let workoutActivity else { return true }
            let sessionKinds = plan.weeks
                .flatMap(\.days).flatMap(\.sessions).map(\.kind)
            // Plans may contain more than one sport, and can appear in
            // multiple filters. Never guess from a plan's free-text title.
            if !sessionKinds.isEmpty {
                return sessionKinds.contains(workoutActivity)
            }
            return plan.builderProfile?.simpleWorkoutKinds?.contains(workoutActivity)
                ?? false
        }
    }

    private var shareableWorkouts: [PlannedSession] {
        ATHLTHPersonalSharePolicy.savedWorkouts(session.savedWorkoutTemplates)
    }

    private var filteredWorkouts: [PlannedSession] {
        shareableWorkouts.filter {
            allowsFavorite(.workout, id: $0.id) &&
            (workoutActivity == nil || $0.kind == workoutActivity)
        }
    }

    private var shareableRunningTemplates: [RunningWorkoutTemplate] {
        runningLibrary.customTemplates.filter {
            ATHLTHPersonalSharePolicy.runningWorkout($0)
        }
    }

    private var filteredRunningTemplates: [RunningWorkoutTemplate] {
        shareableRunningTemplates.filter {
            allowsFavorite(.workout, id: $0.id) &&
            (workoutActivity == nil || workoutActivity == .running)
        }
    }

    private func shareRunningTemplate(_ workout: RunningWorkoutTemplate) {
        guard ATHLTHPersonalSharePolicy.runningWorkout(workout),
              runningLibrary.customTemplates.contains(where: {
                  $0.id == workout.id && ATHLTHPersonalSharePolicy.runningWorkout($0)
              }) else {
            shareError = ATHLTHDirectShareError.onlySavedPersonalContent.localizedDescription
            return
        }
        createDraft(
            kind: .runningWorkout,
            title: workout.title,
            subtitle: workout.summary,
            snapshot: workout,
            sourceObjectID: workout.sharedSourceWorkoutID ?? workout.id,
            sourceOwnerID: workout.sharedSourceOwnerID ?? session.profile.userID
        )
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
        // Display the original starting place only on the owner's picker.
        // The attachment still receives the privacy-sanitized route.
        let start = route.startName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = start?.isEmpty == false ? start! :
            ATHLTHLocalization.choose(
                english: "Start not specified", norwegian: "Startsted ikke angitt"
            )
        return String(format: "%.2f km", route.distanceKilometers) + " · " + label
    }

    private func privacySafeRoute(_ route: TrainingRoute) -> TrainingRoute {
        guard settings.hideRouteStartAndEnd else { return route }
        var copy = route
        // Never export named endpoints when privacy settings hide them.
        copy.startName = nil
        copy.endName = nil
        guard route.coordinates.count > 4 else { return copy }

        let trimmed = trimRoute(route.coordinates, bufferMeters: 250)
        guard trimmed.count >= 2 else { return copy }

        copy.coordinates = trimmed.enumerated().map { index, point in
            RouteCoordinate(
                latitude: point.latitude,
                longitude: point.longitude,
                altitude: point.altitude,
                sequence: index
            )
        }
        copy.distanceKilometers = routeDistanceKilometers(copy.coordinates)
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

    /// A favorite star is a sibling of Share, never a nested button.
    private func shareRow(
        icon: String,
        title: String,
        subtitle: String,
        routePreview: TrainingRoute? = nil,
        favoriteKind: LibraryFavoriteKind? = nil,
        favoriteID: UUID? = nil,
        favoriteSubtitle: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 5) {
            Button(action: action) {
                HStack(spacing: 11) {
                    if let routePreview {
                        RouteMapSnapshotThumbnail(route: routePreview, height: 64)
                            .frame(width: 84, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.premiumGold)
                            .frame(width: 46, height: 52)
                            .background(
                                ATHLTHTheme.premiumGoldSoft,
                                in: RoundedRectangle(cornerRadius: 13)
                            )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(ATHLTHTheme.premiumGold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let favoriteKind, let favoriteID {
                LibraryFavoriteButton(
                    kind: favoriteKind,
                    itemID: favoriteID.uuidString,
                    title: title,
                    subtitle: favoriteSubtitle ?? subtitle,
                    icon: icon
                )
            }
        }
        .padding(11)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.95), ATHLTHTheme.cardWarm.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.9), lineWidth: 0.8)
        }
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
