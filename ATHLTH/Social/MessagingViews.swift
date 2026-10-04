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
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingNewMessage) {
            NewMessageView()
        }
    }
}

struct MessageInboxView: View {
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var session: AppSessionStore

    var onNewMessage: () -> Void = {}

    @State private var searchText = ""
    @State private var showingSearch = false

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

                if let error = displayableError {
                    inboxErrorCard(error)
                }

                if !displayedPersonItems.isEmpty {
                    inboxSectionLabel(
                        normalizedSearch.isEmpty
                            ? "CONVERSATIONS"
                            : "RESULTS",
                        count: displayedPersonItems.count
                    )

                    LazyVStack(spacing: 10) {
                        ForEach(displayedPersonItems) { item in
                            Group {
                                if item.conversation != nil {
                                    NavigationLink {
                                        DirectMessageThreadView(
                                            friend: item.friend
                                        )
                                    } label: {
                                        MessagePersonRow(
                                            item: item
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
                                            item: item
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
                                }
                            }
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
            await social.refresh(
                challengeStore: challenges
            )
            await messaging.refresh()
        }
        .task {
            await social.refresh(
                challengeStore: challenges
            )
            await messaging.refresh()
            messaging.loadPinnedConversations()
        }
    }

    private var messagesHeader: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            HStack(spacing: 10) {
                Label(
                    "SOCIAL",
                    systemImage:
                        "bubble.left.and.bubble.right.fill"
                )
                .font(
                    .caption2
                        .weight(.bold)
                )
                .tracking(1.4)
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )
                .padding(
                    .horizontal,
                    10
                )
                .padding(
                    .vertical,
                    6
                )
                .background(
                    Color.white
                        .opacity(0.58),
                    in: Capsule()
                )

                Spacer()

                headerAction(
                    systemImage:
                        showingSearch
                            ? "xmark"
                            : "magnifyingglass",
                    accessibilityLabel:
                        showingSearch
                            ? "Close message search"
                            : "Search messages"
                ) {
                    withAnimation(
                        .easeInOut(
                            duration: 0.20
                        )
                    ) {
                        showingSearch
                            .toggle()
                        if !showingSearch {
                            searchText = ""
                        }
                    }
                }

                headerAction(
                    systemImage:
                        "square.and.pencil",
                    accessibilityLabel:
                        "New message",
                    action:
                        onNewMessage
                )
            }

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text("Messages")
                    .font(
                        .system(
                            size: 36,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                Text(
                    inboxSummaryText
                )
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
            }

            HStack(spacing: 8) {
                inboxMetric(
                    value:
                        personInboxItems
                            .count,
                    label:
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "People",
                                norwegian:
                                    "Personer"
                            )
                )

                inboxMetric(
                    value:
                        messaging
                            .unreadCount,
                    label:
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Unread",
                                norwegian:
                                    "Ulest"
                            )
                )

                inboxMetric(
                    value:
                        totalRequestCount,
                    label:
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Needs reply",
                                norwegian:
                                    "Venter svar"
                            )
                )
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.92),
                    ATHLTHTheme
                        .cardWarm
                        .opacity(0.88)
                ],
                startPoint: .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in: RoundedRectangle(
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
                Color.white
                    .opacity(0.94),
                lineWidth: 0.9
            )
        }
        .shadow(
            color:
                ATHLTHTheme
                    .accentDeep
                    .opacity(0.05),
            radius: 18,
            y: 7
        )
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
                        ATHLTHTheme.accentSoft,
                        in: Capsule()
                    )
            }

            Spacer()
        }
        .padding(.top, 2)
    }

    private var premiumEmptyState: some View {
        VStack(spacing: 14) {
            Image(
                systemName:
                    normalizedSearch.isEmpty
                        ? "bubble.left.and.bubble.right"
                        : "magnifyingglass"
            )
            .font(.system(size: 28, weight: .medium))
            .foregroundStyle(ATHLTHTheme.accentDeep)
            .frame(width: 66, height: 66)
            .background(
                ATHLTHTheme.accentSoft,
                in: Circle()
            )

            VStack(spacing: 5) {
                Text(
                    normalizedSearch.isEmpty
                        ? "No messages yet"
                        : "No conversations found"
                )
                .font(.title3.weight(.semibold))

                Text(
                    normalizedSearch.isEmpty
                        ? "Your conversations and message requests will appear here."
                        : "Try another name, username or message keyword."
                )
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 24)
        .background(
            Color.white.opacity(0.72),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
    }

    private func inboxErrorCard(
        _ message: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Messages could not refresh")
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
            }
            .buttonStyle(.plain)
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
        let matching =
            personInboxItems.filter { item in
                guard !normalizedSearch.isEmpty else {
                    return true
                }

                return item.friend.resolvedName.lowercased()
                    .contains(normalizedSearch) ||
                    item.friend.usernameLabel.lowercased()
                        .contains(normalizedSearch) ||
                    (item.lastMessage?.body?.lowercased()
                        .contains(normalizedSearch) ?? false) ||
                    (item.lastMessage?.attachmentTitle?
                        .lowercased()
                        .contains(normalizedSearch) ?? false) ||
                    item.pendingChallenges.contains {
                        $0.title.lowercased()
                            .contains(normalizedSearch) ||
                        $0.sport.title.lowercased()
                            .contains(normalizedSearch)
                    } ||
                    item.outgoingChallenges.contains {
                        $0.title.lowercased()
                            .contains(normalizedSearch) ||
                        $0.sport.title.lowercased()
                            .contains(normalizedSearch)
                    }
            }

        return matching.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }

            return lhs.latestActivityAt >
                rhs.latestActivityAt
        }
    }

    private var shouldShowEmptyState: Bool {
        displayedPersonItems.isEmpty
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
            !pendingChallenges.isEmpty
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

private struct MessagePersonRow: View {
    let item: MessagePersonInboxItem

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                SocialAvatar(
                    profile: item.friend,
                    size: 58
                )

                if item.unreadCount > 0 ||
                    item.needsResponse {
                    Circle()
                        .fill(
                            item.needsResponse
                                ? ATHLTHTheme
                                    .premiumGold
                                : ATHLTHTheme
                                    .accentDeep
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

                    if item.isPinned {
                        Image(
                            systemName:
                                "pin.fill"
                        )
                        .font(
                            .system(
                                size: 10,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .accentDeep
                        )
                    }

                    Spacer()
                }

                Text(previewText)
                    .font(.subheadline)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(2)

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
                                        .accentDeep
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
                                        .accentSoft,
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
                        ATHLTHTheme
                            .accentDeep,
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
        .padding(15)
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.96),
                    ATHLTHTheme.cardWarm
                        .opacity(
                            item.needsResponse
                                ? 0.96
                                : 0.80
                        )
                ],
                startPoint: .topLeading,
                endPoint:
                    .bottomTrailing
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
                item.needsResponse
                    ? ATHLTHTheme
                        .premiumGold
                        .opacity(0.22)
                    : Color.white
                        .opacity(0.92),
                lineWidth: 0.9
            )
        }
        .shadow(
            color:
                ATHLTHTheme
                    .accentDeep
                    .opacity(0.045),
            radius: 14,
            y: 6
        )
    }

    private var previewText: String {
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
                    .foregroundStyle(ATHLTHTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(ATHLTHTheme.accentSoft, in: Capsule())
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
                        .tint(ATHLTHTheme.accent)

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
                        .fill(ATHLTHTheme.accent)
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
                                ATHLTHTheme.accentSoft,
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
                                ATHLTHTheme.accentSoft,
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
                        ATHLTHTheme.accentSoft,
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
                        ATHLTHTheme.accentSoft,
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
    @State private var isSending = false
    @State private var loadError: String?
    @State private var savedFeedback: String?

    var body: some View {
        VStack(spacing: 0) {
            if let conversationID {
                messagesView(conversationID)
            } else if let loadError {
                ContentUnavailableView(
                    "Messages unavailable",
                    systemImage: "exclamationmark.bubble",
                    description: Text(loadError)
                )
            } else {
                ProgressView("Opening conversation…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(ATHLTHTheme.canvasTop.ignoresSafeArea())
        .navigationTitle(friend.resolvedName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .sheet(isPresented: $showingSharePicker) {
            MessageSharePicker { draft in
                selectedShare = draft
                showingSharePicker = false
            }
        }
        .alert(
            "Saved to ATHLTH",
            isPresented: Binding(
                get: { savedFeedback != nil },
                set: { if !$0 { savedFeedback = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(savedFeedback ?? "")
        }
        .task(id: friend.userID) {
            await openAndPoll()
        }
    }

    @ViewBuilder
    private func messagesView(_ conversationID: UUID) -> some View {
        let messages =
            messaging.messages(
                in: conversationID
            )
        let challenges =
            pendingChallengesFromFriend
        let outgoingChallenges =
            outgoingChallengesToFriend
        let lifecycleEvents =
            challengeLifecycleEventsWithFriend

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if !challenges.isEmpty {
                        HStack {
                            Text(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "REQUESTS",
                                        norwegian:
                                            "FORESPØRSLER"
                                    )
                            )
                            .font(
                                .caption2
                                    .weight(.bold)
                            )
                            .tracking(1.5)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )

                            Text(
                                "\(challenges.count)"
                            )
                            .font(
                                .caption2
                                    .weight(.bold)
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accentDeep
                            )
                            .padding(
                                .horizontal,
                                7
                            )
                            .padding(
                                .vertical,
                                3
                            )
                            .background(
                                ATHLTHTheme
                                    .accentSoft,
                                in: Capsule()
                            )

                            Spacer()
                        }
                        .padding(
                            .top,
                            4
                        )

                        ForEach(
                            challenges
                        ) { challenge in
                            ThreadChallengeRequestCard(
                                challenge:
                                    challenge,
                                onAccept: {
                                    respondToThreadChallenge(
                                        challenge,
                                        accept:
                                            true
                                    )
                                },
                                onDecline: {
                                    respondToThreadChallenge(
                                        challenge,
                                        accept:
                                            false
                                    )
                                }
                            )
                        }
                    }

                    if !outgoingChallenges.isEmpty {
                        HStack {
                            Text(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "SENT",
                                        norwegian:
                                            "SENDT"
                                    )
                            )
                            .font(
                                .caption2
                                    .weight(.bold)
                            )
                            .tracking(1.5)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )

                            Text(
                                "\(outgoingChallenges.count)"
                            )
                            .font(
                                .caption2
                                    .weight(.bold)
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accentDeep
                            )
                            .padding(
                                .horizontal,
                                7
                            )
                            .padding(
                                .vertical,
                                3
                            )
                            .background(
                                ATHLTHTheme
                                    .accentSoft,
                                in: Capsule()
                            )

                            Spacer()
                        }

                        ForEach(
                            outgoingChallenges
                        ) { challenge in
                            ThreadOutgoingChallengeCard(
                                challenge:
                                    challenge,
                                onCancel: {
                                    withdrawThreadChallenge(
                                        challenge
                                    )
                                }
                            )
                        }
                    }

                    if messages.isEmpty &&
                        challenges.isEmpty &&
                        outgoingChallenges.isEmpty &&
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
                            lifecycleEvents:
                                lifecycleEvents
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
                                    saveAttachment(
                                        message
                                    )
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
                .padding(.top, 12)
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
                   challenges.isEmpty &&
                   outgoingChallenges.isEmpty {
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

    private func threadTimelineItems(
        messages: [DirectMessageRecord],
        lifecycleEvents: [ThreadChallengeLifecycleEvent]
    ) -> [ThreadTimelineItem] {
        (
            messages.map {
                ThreadTimelineItem.message(
                    $0
                )
            } +
            lifecycleEvents.map {
                ThreadTimelineItem
                    .challengeEvent(
                        $0
                    )
            }
        )
        .sorted {
            $0.createdAt <
                $1.createdAt
        }
    }

    private var currentConversation: DirectConversationRecord? {
        guard let conversationID else { return nil }
        return messaging.conversations.first { $0.id == conversationID }
    }

    private var isIncomingRequest: Bool {
        guard let currentConversation,
              let currentUserID = messaging.currentUserID
        else {
            return false
        }

        return currentConversation.requestStatus == .pending &&
            currentConversation.requestedBy != nil &&
            currentConversation.requestedBy != currentUserID
    }

    private var isOutgoingRequest: Bool {
        guard let currentConversation,
              let currentUserID = messaging.currentUserID
        else {
            return false
        }

        return currentConversation.requestStatus == .pending &&
            currentConversation.requestedBy == currentUserID
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
        VStack(spacing: 10) {
            Text("Accept this request before replying or sharing training.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button("Decline") {
                    Task {
                        guard let conversationID else { return }
                        if await messaging.respondToMessageRequest(
                            conversationID,
                            accept: false
                        ) {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Accept") {
                    Task {
                        guard let conversationID else { return }
                        _ = await messaging.respondToMessageRequest(
                            conversationID,
                            accept: true
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accent)
                .frame(maxWidth: .infinity)

                Menu {
                    Button("Block", role: .destructive) {
                        Task {
                            guard let conversationID else { return }
                            _ = await messaging.respondToMessageRequest(
                                conversationID,
                                accept: false
                            )
                            await social.block(friend.userID)
                            await messaging.refresh()
                            dismiss()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 38, height: 38)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var outgoingRequestBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.fill")
                .foregroundStyle(ATHLTHTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Message request sent")
                    .font(.subheadline.weight(.semibold))
                Text("You can send more messages and training items after it is accepted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let selectedShare {
                HStack(spacing: 10) {
                    Image(systemName: selectedShare.kind.systemImage)
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(ATHLTHTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedShare.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(selectedShare.kind.title)
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
                if currentConversation?.requestStatus == .accepted {
                    Button {
                        showingSharePicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .background(ATHLTHTheme.accentSoft, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(conversationID == nil)
                }

                TextField(
                    isOutgoingRequest ? "Write one message request" : "Message",
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 38, height: 38)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                    }
                }
                .background(ATHLTHTheme.accent, in: Circle())
                .buttonStyle(.plain)
                .disabled(!canSend || isSending)
                .opacity(canSend ? 1 : 0.45)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(.ultraThinMaterial)
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
            return isOutgoingRequest && !hasSentRequestMessage && hasText
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
        guard
            let participant =
                challengeStore
                    .invitationParticipant(
                        in: challenge,
                        userID:
                            session.profile
                                .userID
                    )
        else {
            return
        }

        challengeStore
            .setParticipantState(
                challengeID:
                    challenge.id,
                participantID:
                    participant.id,
                state:
                    accept
                        ? .accepted
                        : .declined
            )

        guard
            let updated =
                challengeStore.challenge(
                    id:
                        challenge.id
                )
        else {
            return
        }

        Task {
            let synced =
                await social.syncChallenge(
                    updated
                )

            if !synced {
                challengeStore
                    .setParticipantState(
                        challengeID:
                            challenge.id,
                        participantID:
                            participant.id,
                        state:
                            .invited
                    )
            } else {
                await social
                    .markChallengeInviteRead(
                        challengeID:
                            challenge.id
                    )
            }
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
        let attachment = currentConversation?.requestStatus == .accepted
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

    private func saveAttachment(_ message: DirectMessageRecord) {
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
            savedFeedback = "Challenges stay linked to the original challenge. Open Challenges to accept or view it."

        case .none:
            break
        }
    }
}

private enum ThreadTimelineItem: Identifiable {
    case message(
        DirectMessageRecord
    )
    case challengeEvent(
        ThreadChallengeLifecycleEvent
    )

    var id: String {
        switch self {
        case .message(let message):
            return "message:" +
                message.id.uuidString
        case .challengeEvent(let event):
            return "challenge-event:" +
                event.id
        }
    }

    var createdAt: Date {
        switch self {
        case .message(let message):
            return message.createdAt
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
                    .accentDeep
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

private struct MessageBubble: View {
    @EnvironmentObject private var challengeStore: ChallengeStore

    let message: DirectMessageRecord
    let friend: SocialProfileCard
    let currentUserID: UUID?
    let currentUserProfile: SocialProfileCard
    let onSaveAttachment: () -> Void

    private var isMine: Bool {
        message.senderID == currentUserID
    }

    private var provenanceText: String {
        if let sourceOwnerID = message.sourceOwnerID {
            if sourceOwnerID == currentUserID {
                return "Created by you"
            }
            if sourceOwnerID == friend.userID {
                return "Created by \(friend.resolvedName)"
            }
            return "Original creator preserved"
        }

        return isMine ? "Shared by you" : "Shared by \(friend.resolvedName)"
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
            return .accepted

        case .declined:
            return .declined

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
                english: "Sent · waiting",
                norwegian: "Sendt · venter"
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
                if let attachmentKind = message.attachmentKind {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 8) {
                            Image(systemName: attachmentKind.systemImage)
                                .foregroundStyle(ATHLTHTheme.accent)
                            Text(attachmentKind.title.uppercased())
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

                        Text(provenanceText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        if !isMine {
                            Button {
                                onSaveAttachment()
                            } label: {
                                Label(
                                    attachmentKind == .challenge ? "View details" : "Save a copy",
                                    systemImage: attachmentKind == .challenge ? "bolt.fill" : "square.and.arrow.down"
                                )
                                .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(ATHLTHTheme.accent)
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

                if let body = message.body, !body.isEmpty {
                    Text(body)
                        .font(.body)
                        .foregroundStyle(isMine ? Color.white : ATHLTHTheme.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            isMine ? ATHLTHTheme.accent : Color.white,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
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

            if isMine {
                senderAvatar(currentUserProfile)
            } else {
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
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var challengeStore: ChallengeStore
    @EnvironmentObject private var settings: AppSettingsStore

    let onSelect: (MessageShareDraft) -> Void

    @State private var selectedKind: MessageShareKind = .workout
    @State private var shareError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MessageShareKind.allCases) { kind in
                            Button {
                                selectedKind = kind
                            } label: {
                                Label(kind.title, systemImage: kind.systemImage)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(
                                        selectedKind == kind
                                            ? Color.white
                                            : ATHLTHTheme.primaryText
                                    )
                                    .background(
                                        selectedKind == kind
                                            ? ATHLTHTheme.accent
                                            : Color(.secondarySystemGroupedBackground),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }

                List {
                    shareContent
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Share with Athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Could Not Share",
                isPresented: Binding(
                    get: { shareError != nil },
                    set: { if !$0 { shareError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(shareError ?? "")
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
                    "No saved workouts",
                    systemImage: "dumbbell",
                    description: Text("Create a workout or add one to a training plan first.")
                )
            } else {
                ForEach(workouts) { workout in
                    shareRow(
                        icon: workout.kind.systemImage,
                        title: workout.title,
                        subtitle: workoutSubtitle(workout)
                    ) {
                        createDraft(
                            kind: .workout,
                            title: workout.title,
                            subtitle: workoutSubtitle(workout),
                            snapshot: workout,
                            sourceObjectID: workout.sharedSourceSessionID ?? workout.id,
                            sourceOwnerID: workout.sharedSourceOwnerID ?? session.profile.userID
                        )
                    }
                }
            }

        case .trainingPlan:
            let plans = shareablePlans
            if plans.isEmpty {
                ContentUnavailableView(
                    "No training plans",
                    systemImage: "calendar",
                    description: Text("Create or save a training plan first.")
                )
            } else {
                ForEach(plans) { plan in
                    shareRow(
                        icon: "calendar",
                        title: plan.title,
                        subtitle: "\(plan.weeks.count) weeks · version \(plan.version)"
                    ) {
                        createDraft(
                            kind: .trainingPlan,
                            title: plan.title,
                            subtitle: "\(plan.weeks.count) weeks · snapshot v\(plan.version)",
                            snapshot: plan,
                            sourceObjectID: plan.sharedSourcePlanID ?? plan.id,
                            sourceOwnerID: plan.sharedSourceOwnerID ?? plan.ownerID,
                            shareVersion: plan.sharedSourceVersion ?? plan.version
                        )
                    }
                }
            }

        case .runningWorkout:
            if runningLibrary.customTemplates.isEmpty {
                ContentUnavailableView(
                    "No custom running workouts",
                    systemImage: "figure.run",
                    description: Text("Create a running workout first.")
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
                    "No saved routes",
                    systemImage: "map",
                    description: Text("Save or import a route first.")
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
                    "No challenges",
                    systemImage: "bolt",
                    description: Text("Create or join a challenge first.")
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
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(ATHLTHTheme.accentSoft, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "paperplane.fill")
                    .foregroundStyle(ATHLTHTheme.accent)
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
