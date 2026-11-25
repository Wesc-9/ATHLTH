import Foundation
import UserNotifications

@MainActor
final class MessagingStore: ObservableObject {
    @Published private(set) var conversations: [DirectConversationRecord] = []
    @Published private(set) var recentMessages: [DirectMessageRecord] = []
    @Published private(set) var messagesByConversation: [UUID: [DirectMessageRecord]] = [:]
    @Published private(set) var pinnedConversationIDs: Set<UUID> = []
    @Published private(set) var archivedConversationIDs: Set<UUID> = []
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?
    @Published private(set) var preferenceSyncError: String?

    private let service: SupabaseMessagingService
    private var lastRefreshAt: Date?
    private var preferenceAccountID: UUID?
    private var preferences: [UUID: ATHLTHConversationPreference] = [:]
    private var preferenceSyncTask: Task<Void, Never>?
    private var isPreferencesSyncing = false
    private var withdrawalsInFlight: Set<UUID> = []
    private var accountGeneration = UUID()

    private func ownsRequest(_ owner: UUID, generation: UUID) -> Bool {
        !Task.isCancelled && accountGeneration == generation &&
            preferenceAccountID == owner && currentUserID == owner
    }

    init(service: SupabaseMessagingService = SupabaseMessagingService()) {
        self.service = service
    }

    var currentUserID: UUID? {
        service.currentUserID
    }

    var unreadCount: Int {
        guard let currentUserID else { return 0 }
        let acceptedConversationIDs = Set(
            conversations
                .filter { $0.requestStatus == .accepted }
                .map(\.id)
        )

        return recentMessages.filter {
            acceptedConversationIDs.contains($0.conversationID) &&
            $0.recipientID == currentUserID &&
            $0.readAt == nil &&
            $0.deletedAt == nil
        }.count
    }

    var incomingMessageRequests: [DirectConversationRecord] {
        guard let currentUserID else { return [] }
        return conversations
            .filter {
                $0.requestStatus == .pending &&
                $0.requestedBy != nil &&
                $0.requestedBy != currentUserID
            }
            .sorted {
                ($0.lastMessageAt ?? $0.createdAt) >
                ($1.lastMessageAt ?? $1.createdAt)
            }
    }

    var outgoingMessageRequests: [DirectConversationRecord] {
        guard let currentUserID else { return [] }
        return conversations
            .filter {
                $0.requestStatus == .pending &&
                $0.requestedBy == currentUserID
            }
            .sorted {
                ($0.lastMessageAt ?? $0.createdAt) >
                ($1.lastMessageAt ?? $1.createdAt)
            }
    }

    var messageRequestCount: Int {
        incomingMessageRequests.filter {
            lastMessage(for: $0.id) != nil
        }.count
    }

    func unreadCount(for conversationID: UUID) -> Int {
        guard let currentUserID else { return 0 }
        return recentMessages.filter {
            $0.conversationID == conversationID &&
            $0.recipientID == currentUserID &&
            $0.readAt == nil &&
            $0.deletedAt == nil
        }.count
    }

    func conversation(with userID: UUID) -> DirectConversationRecord? {
        guard let currentUserID else { return nil }
        return conversations.first {
            $0.otherUserID(for: currentUserID) == userID
        }
    }

    func lastMessage(for conversationID: UUID) -> DirectMessageRecord? {
        recentMessages
            .filter { $0.conversationID == conversationID && $0.deletedAt == nil }
            .max { $0.createdAt < $1.createdAt }
    }

    func switchAccount(_ userID: UUID?) {
        guard preferenceAccountID != userID else { return }
        preferenceSyncTask?.cancel()
        preferenceSyncTask = nil
        preferenceAccountID = userID
        accountGeneration = UUID()
        isRefreshing = false
        isPreferencesSyncing = false
        errorMessage = nil
        lastRefreshAt = nil
        preferenceSyncError = nil
        conversations = []
        recentMessages = []
        messagesByConversation = [:]
        pinnedConversationIDs = []
        archivedConversationIDs = []
        preferences = [:]
        guard let userID else { return }

        let defaults = UserDefaults.standard
        let key = preferenceStorageKey(userID)
        if let data = defaults.data(forKey: key),
           let cached = try? JSONDecoder().decode(
               [ATHLTHConversationPreference].self, from: data
           ) {
            preferences = Dictionary(
                cached.map { ($0.conversationID, $0) },
                uniquingKeysWith: { current, _ in current }
            )
        } else {
            // Device-only lists from earlier versions are converted into
            // low-priority snapshots. Server changes win over these imports.
            let initial = Date(timeIntervalSince1970: 1)
            let pinKey = "athlth.messaging.pinned.\(userID.uuidString.lowercased())"
            let archiveKey = "athlth.messaging.archived.\(userID.uuidString.lowercased())"
            let pinned = Set((defaults.stringArray(forKey: pinKey) ?? [])
                .compactMap(UUID.init(uuidString:)))
            let archived = Set((defaults.stringArray(forKey: archiveKey) ?? [])
                .compactMap(UUID.init(uuidString:)))
            for id in pinned.union(archived) {
                preferences[id] = ATHLTHConversationPreference(
                    conversationID: id,
                    pinnedAt: pinned.contains(id) ? initial : nil,
                    unpinnedAt: nil,
                    archivedAt: archived.contains(id) ? initial : nil,
                    unarchivedAt: nil
                )
            }
        }
        applyPreferences()
        schedulePreferenceSync()
    }

    func loadPinnedConversations() {
        // The signed-in AppSession identity owns account switching. A
        // still-restoring or stale Supabase session must never replace it
        // with another account's local conversation preferences.
        schedulePreferenceSync()
    }

    private func applyPreferences() {
        let pinned = Set(preferences.values.filter(\.isPinned).map(\.conversationID))
        let archived = Set(preferences.values.filter(\.isArchived).map(\.conversationID))
        if pinnedConversationIDs != pinned { pinnedConversationIDs = pinned }
        if archivedConversationIDs != archived { archivedConversationIDs = archived }
    }

    private func preferenceStorageKey(_ userID: UUID) -> String {
        "athlth.messaging.preferences.\(userID.uuidString.lowercased())"
    }

    private func savePreferences() {
        guard let userID = preferenceAccountID,
              let data = try? JSONEncoder().encode(
                Array(preferences.values)
              ) else { return }
        UserDefaults.standard.set(data, forKey: preferenceStorageKey(userID))
        schedulePreferenceSync()
    }

    private func schedulePreferenceSync() {
        guard preferenceAccountID != nil else { return }
        preferenceSyncTask?.cancel()
        preferenceSyncTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(450)) }
            catch { return }
            await self?.refreshPreferences()
        }
    }

    func refreshPreferences() async {
        guard !isPreferencesSyncing, let userID = preferenceAccountID,
              currentUserID == userID else { return }
        let generation = accountGeneration
        isPreferencesSyncing = true
        defer { if accountGeneration == generation { isPreferencesSyncing = false } }
        do {
            let merged = try await ATHLTHConversationPreferenceSyncService
                .reconcile(userID: userID, local: preferences)
            guard ownsRequest(userID, generation: generation) else {
                return
            }
            // Never lose a pin/archive edit made while the request ran.
            preferences = ATHLTHConversationPreferenceSyncService.merged(
                local: preferences, remote: merged
            )
            applyPreferences()
            if let data = try? JSONEncoder().encode(Array(preferences.values)) {
                UserDefaults.standard.set(data, forKey: preferenceStorageKey(userID))
            }
            preferenceSyncError = nil
        } catch is CancellationError {
            return
        } catch {
            guard ownsRequest(userID, generation: generation) else { return }
            preferenceSyncError = ATHLTHLocalization.choose(
                english: "Conversation preferences are saved locally until sync succeeds.",
                norwegian: "Samtalevalg er lagret lokalt til synkronisering lykkes."
            )
        }
    }

    func isPinned(_ conversationID: UUID) -> Bool {
        pinnedConversationIDs.contains(conversationID)
    }

    func togglePinned(_ conversationID: UUID) {
        guard preferenceAccountID != nil else { return }
        var value = preferences[conversationID] ??
            ATHLTHConversationPreference(
                conversationID: conversationID,
                pinnedAt: nil, unpinnedAt: nil,
                archivedAt: nil, unarchivedAt: nil
            )
        if value.isPinned {
            value.unpinnedAt = Date()
        } else {
            value.pinnedAt = Date()
        }
        preferences[conversationID] = value
        applyPreferences()
        persistPinnedConversations()
        savePreferences()
    }

    func isArchived(
        _ conversationID: UUID
    ) -> Bool {
        archivedConversationIDs
            .contains(
                conversationID
            )
    }

    func toggleArchived(_ conversationID: UUID) {
        guard preferenceAccountID != nil else { return }
        var value = preferences[conversationID] ??
            ATHLTHConversationPreference(
                conversationID: conversationID,
                pinnedAt: nil, unpinnedAt: nil,
                archivedAt: nil, unarchivedAt: nil
            )
        if value.isArchived {
            value.unarchivedAt = Date()
        } else {
            value.archivedAt = Date()
        }
        preferences[conversationID] = value
        applyPreferences()
        persistArchivedConversations()
        savePreferences()
    }

    private var pinnedStorageKey: String? {
        guard let currentUserID else { return nil }
        return "athlth.messaging.pinned.\(currentUserID.uuidString.lowercased())"
    }

    private var archiveStorageKey:
        String? {
        guard let currentUserID else {
            return nil
        }

        return
            "athlth.messaging.archived." +
            currentUserID.uuidString
                .lowercased()
    }

    private func persistPinnedConversations() {
        guard let key = pinnedStorageKey else { return }

        UserDefaults.standard.set(
            pinnedConversationIDs
                .map(\.uuidString)
                .sorted(),
            forKey: key
        )
    }

    private func persistArchivedConversations() {
        guard let key =
                archiveStorageKey
        else {
            return
        }

        UserDefaults.standard.set(
            archivedConversationIDs
                .map(\.uuidString)
                .sorted(),
            forKey: key
        )
    }

    func refresh(
        force: Bool = false
    ) async {
        guard let owner = currentUserID, preferenceAccountID == owner,
              !isRefreshing
        else {
            return
        }

        if !force,
           let lastRefreshAt,
           Date().timeIntervalSince(lastRefreshAt) < 60 {
            return
        }

        let generation = accountGeneration
        isRefreshing = true
        errorMessage = nil
        defer { if accountGeneration == generation { isRefreshing = false } }

        do {
            async let conversationsTask = service.loadConversations()
            async let messagesTask = service.loadRecentMessages()

            let refreshedConversations =
                try await conversationsTask
            let refreshedMessages =
                try await messagesTask
            guard ownsRequest(owner, generation: generation) else { return }

            if conversations !=
                refreshedConversations {
                conversations =
                    refreshedConversations
            }
            if recentMessages !=
                refreshedMessages {
                recentMessages =
                    refreshedMessages
            }
            lastRefreshAt = Date()
            await syncApplicationIconBadge()
            guard ownsRequest(owner, generation: generation) else { return }
            await refreshPreferences()
        } catch is CancellationError {
            return
        } catch {
            guard ownsRequest(owner, generation: generation) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func syncApplicationIconBadge()
        async {
        // The root tab owns the app-icon badge so Messages cannot overwrite
        // notification/import counts (or revive stale hidden inbox rows).
    }

    func openConversation(with userID: UUID) async throws -> UUID {
        guard let owner = currentUserID, preferenceAccountID == owner else { throw CancellationError() }
        let generation = accountGeneration
        if let existing = conversation(with: userID),
           existing.requestStatus == .accepted {
            return existing.id
        }

        // Pending conversations are intentionally re-checked by the backend.
        // If the two athletes have become mutual followers since the request
        // was created, the conversation can be promoted to accepted without
        // forcing a second request.
        let conversationID =
            try await service
                .getOrCreateConversation(
                    with: userID
                )

        guard ownsRequest(owner, generation: generation) else { throw CancellationError() }
        // Refresh the normal inbox first, then hydrate the exact row last.
        // A brand-new pending conversation has no message/last_message_at yet;
        // keeping the exact row as the final source of truth prevents the
        // first-request composer from falling back to a disabled state.
        await refresh()
        guard ownsRequest(owner, generation: generation) else { throw CancellationError() }

        if let conversation =
                try await service
                    .loadConversation(
                        id: conversationID
                    ) {
            guard ownsRequest(owner, generation: generation) else { throw CancellationError() }
            upsertConversation(
                conversation
            )
        }

        guard ownsRequest(owner, generation: generation) else { throw CancellationError() }
        return conversationID
    }

    private func upsertConversation(
        _ conversation:
            DirectConversationRecord
    ) {
        if let index =
                conversations
                    .firstIndex(
                        where: {
                            $0.id ==
                                conversation.id
                        }
                    ) {
            conversations[index] =
                conversation
        } else {
            conversations.append(
                conversation
            )
        }

        conversations.sort {
            ($0.lastMessageAt ??
                $0.createdAt) >
            ($1.lastMessageAt ??
                $1.createdAt)
        }
    }

    func respondToMessageRequest(
        _ conversationID: UUID,
        accept: Bool
    ) async -> Bool {
        guard let owner = currentUserID, preferenceAccountID == owner else { return false }
        let generation = accountGeneration
        errorMessage = nil

        do {
            try await service.respondToMessageRequest(
                conversationID: conversationID,
                accept: accept
            )
            guard ownsRequest(owner, generation: generation) else { return false }

            if accept {
                // Hydrate the thread immediately so the request bar can turn
                // into the normal composer without waiting for the inbox
                // refresh throttle.
                await refreshConversation(
                    conversationID
                )
            } else {
                // A declined request leaves the thread, but its delivered push
                // should disappear from Notification Center immediately.
                await clearDeliveredNotifications(
                    for:
                        conversationID
                )
                guard ownsRequest(owner, generation: generation) else { return false }
                await refresh(
                    force: true
                )
            }

            return ownsRequest(owner, generation: generation)
        } catch {
            guard ownsRequest(owner, generation: generation) else { return false }
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    func refreshConversation(_ conversationID: UUID) async {
        guard let owner = currentUserID, preferenceAccountID == owner else { return }
        let generation = accountGeneration
        do {
            let messages = try await service.loadMessages(conversationID: conversationID)
            guard ownsRequest(owner, generation: generation) else { return }

            if let currentUserID {
                let unread = messages.filter {
                    $0.recipientID == currentUserID && $0.readAt == nil && $0.deletedAt == nil
                }.map(\.id)

                if !unread.isEmpty {
                    // Commit actual read state before publishing the text. A
                    // concurrent successful retraction must not appear here.
                    try await service.markConversationRead(conversationID, messageIDs: unread)
                    let confirmed = try await service.loadMessages(conversationID: conversationID)
                    guard ownsRequest(owner, generation: generation) else { return }
                    let loadedIDs = Set(messages.map(\.id))
                    messagesByConversation[conversationID] = confirmed.filter {
                        loadedIDs.contains($0.id) || $0.senderID == currentUserID
                    }
                    markConversationReadLocally(conversationID: conversationID,
                                                currentUserID: currentUserID, markedAt: Date(), messageIDs: Set(unread))
                } else {
                    messagesByConversation[conversationID] = messages
                }

                await clearDeliveredNotifications(
                    for:
                        conversationID
                )
            }

            // Force this refresh. A normal refresh may be throttled for
            // 60 seconds, which previously left the inbox unread badge stuck
            // after the thread had already been marked read on the backend.
            guard ownsRequest(owner, generation: generation) else { return }
            await refresh(force: true)
            guard ownsRequest(owner, generation: generation) else { return }

            // Full inbox refreshes must not make a just-created pending
            // request disappear locally before its first message is sent.
            if let conversation =
                    try await service
                        .loadConversation(
                            id: conversationID
                        ) {
                guard ownsRequest(owner, generation: generation) else { return }
                upsertConversation(
                    conversation
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard ownsRequest(owner, generation: generation) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func markConversationReadLocally(
        conversationID: UUID,
        currentUserID: UUID,
        markedAt: Date,
        messageIDs: Set<UUID>
    ) {
        func marked(
            _ message:
                DirectMessageRecord
        ) -> DirectMessageRecord {
            guard message.conversationID ==
                    conversationID,
                  message.recipientID ==
                    currentUserID,
                  message.readAt == nil,
                  messageIDs.contains(message.id)
            else {
                return message
            }

            return DirectMessageRecord(
                id: message.id,
                conversationID:
                    message.conversationID,
                senderID:
                    message.senderID,
                recipientID:
                    message.recipientID,
                body: message.body,
                attachmentKindRaw:
                    message.attachmentKindRaw,
                attachmentTitle:
                    message.attachmentTitle,
                attachmentSubtitle:
                    message.attachmentSubtitle,
                attachmentPayload:
                    message.attachmentPayload,
                shareVersion:
                    message.shareVersion,
                sourceObjectID:
                    message.sourceObjectID,
                sourceOwnerID:
                    message.sourceOwnerID,
                createdAt:
                    message.createdAt,
                readAt: markedAt,
                deletedAt:
                    message.deletedAt
            )
        }

        if let thread =
                messagesByConversation[
                    conversationID
                ] {
            messagesByConversation[
                conversationID
            ] = thread.map(marked)
        }

        recentMessages =
            recentMessages.map(marked)
    }

    private func clearDeliveredNotifications(
        for conversationID: UUID
    ) async {
        let center =
            UNUserNotificationCenter
                .current()

        let identifiers:
            [String] =
            await withCheckedContinuation {
                continuation in
                center.getDeliveredNotifications {
                    notifications in

                    // UNNotification is not Sendable. Resolve the identifiers
                    // inside NotificationCenter's callback and only pass the
                    // value-type String array across the continuation.
                    let matchingIdentifiers =
                        notifications.compactMap {
                            notification -> String?
                            in
                            let userInfo =
                                notification.request
                                    .content
                                    .userInfo

                            guard
                                userInfo[
                                    "athlth_entity_type"
                                ] as? String ==
                                    "direct_conversation",
                                let rawID =
                                    userInfo[
                                        "athlth_entity_id"
                                    ] as? String,
                                UUID(
                                    uuidString:
                                        rawID
                                ) ==
                                    conversationID
                            else {
                                return nil
                            }

                            return notification
                                .request
                                .identifier
                        }

                    continuation.resume(
                        returning:
                            matchingIdentifiers
                    )
                }
            }

        guard !identifiers.isEmpty
        else {
            return
        }

        center
            .removeDeliveredNotifications(
                withIdentifiers:
                    identifiers
            )
    }

    func retractTextMessage(_ message: DirectMessageRecord) async -> Bool {
        guard let owner = currentUserID, preferenceAccountID == owner, message.senderID == owner,
              message.attachmentKindRaw == nil, message.readAt == nil,
              message.deletedAt == nil, !withdrawalsInFlight.contains(message.id) else { return false }
        let generation = accountGeneration
        withdrawalsInFlight.insert(message.id)
        defer { withdrawalsInFlight.remove(message.id) }
        do {
            let removed = try await service.retractUnreadMessage(message.id)
            guard ownsRequest(owner, generation: generation) else { return false }
            if removed {
                recentMessages.removeAll { $0.id == message.id }
                messagesByConversation[message.conversationID]?.removeAll { $0.id == message.id }
            }
            await refreshConversation(message.conversationID)
            guard ownsRequest(owner, generation: generation) else { return false }
            if !removed {
                errorMessage = ATHLTHLocalization.choose(
                    english: "The message can no longer be withdrawn.",
                    norwegian: "Meldingen kan ikke lenger trekkes tilbake.")
            }
            return removed
        } catch {
            guard ownsRequest(owner, generation: generation) else { return false }
            errorMessage = ATHLTHLocalization.choose(english: "Could not withdraw the message.", norwegian: "Kunne ikke trekke tilbake meldingen.")
            return false
        }
    }

    func messages(in conversationID: UUID) -> [DirectMessageRecord] {
        messagesByConversation[conversationID] ?? []
    }

    func send(
        to recipientID: UUID,
        conversationID: UUID,
        body: String?,
        attachment: MessageShareDraft? = nil
    ) async -> Bool {
        guard let owner = currentUserID, preferenceAccountID == owner else { return false }
        let generation = accountGeneration
        errorMessage = nil

        let cleanBody = body?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleanBody?.isEmpty == false || attachment != nil else {
            return false
        }

        do {
            try await service.sendMessage(
                conversationID: conversationID,
                to: recipientID,
                body: cleanBody,
                attachment: attachment
            )
            guard ownsRequest(owner, generation: generation) else { return false }
            await refreshConversation(conversationID)
            return ownsRequest(owner, generation: generation)
        } catch {
            guard ownsRequest(owner, generation: generation) else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Shared by Messages, Calendar, Train and the planned lobby.
    /// Never remove the organizer's entry until all invitations are notified.
    func withdrawPlannedWorkout(
        sourceID: UUID, session: AppSessionStore, social: SocialStore
    ) async throws {
        func failure(_ english: String, _ norwegian: String) -> NSError {
            NSError(domain: "ATHLTH.WorkoutWithdrawal", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    ATHLTHLocalization.choose(english: english, norwegian: norwegian)])
        }
        guard let organizerID = currentUserID,
              organizerID == session.profile.userID,
              session.recordedTimes(for: sourceID) == nil else {
            throw failure("This workout cannot be withdrawn.", "Denne økten kan ikke trekkes tilbake.")
        }
        guard withdrawalsInFlight.insert(sourceID).inserted else {
            throw failure("Withdrawal is already in progress.", "Tilbaketrekking pågår allerede.")
        }
        defer { withdrawalsInFlight.remove(sourceID) }
        let messages = try await service.loadPlannedWorkoutInvitationMessages(sourceWorkoutID: sourceID)
        guard currentUserID == organizerID, session.profile.userID == organizerID else {
            throw failure("Account changed.", "Kontoen er endret.")
        }
        let invitations = PlannedWorkoutWithdrawalPolicy.invitations(
            in: messages, sourceID: sourceID, organizerID: organizerID
        )
        guard !invitations.isEmpty else {
            throw failure("No sent invitation was found.", "Fant ingen sendt invitasjon.")
        }
        await social.refresh()
        let matchingLobbies = social.workoutSessions.filter {
            $0.creatorID == organizerID && $0.status == .active &&
            $0.invitePayload?.workout.id == sourceID
        }
        let lobbyIDs = Set(matchingLobbies.map(\.id))
        guard session.recordedTimes(for: sourceID) == nil,
              !social.workoutParticipants.contains(where: {
                  lobbyIDs.contains($0.sessionID) && $0.workoutStartedAt != nil
              }) else {
            throw failure("The shared workout has already started.", "Fellesøkten er allerede startet.")
        }
        // The database cancels the lobby and draft atomically with the message.

        let change = WorkoutInviteLifecycleUpdate(
            sourceWorkoutID: sourceID, organizerID: organizerID,
            kind: .cancelled, updatedWorkout: nil, occurredAt: Date()
        )
        for invitation in invitations {
            guard currentUserID == organizerID, session.profile.userID == organizerID else {
                throw failure("Account changed.", "Kontoen er endret.")
            }
            if PlannedWorkoutWithdrawalPolicy.cancellation(
                in: messages, sourceID: sourceID, organizerID: organizerID,
                recipientID: invitation.recipientID
            ) != nil { continue }
            let attachment = try MessageShareDraft(
                kind: .workout, title: invitation.attachmentTitle ?? "ATHLTH",
                subtitle: ATHLTHLocalization.choose(
                    english: "Invitation withdrawn", norwegian: "Invitasjon trukket tilbake"),
                snapshot: change, sourceObjectID: sourceID,
                sourceOwnerID: organizerID, shareVersion: 6
            )
            try await service.sendMessage(
                conversationID: invitation.conversationID, to: invitation.recipientID,
                body: ATHLTHLocalization.choose(
                    english: "The planned shared workout has been cancelled.",
                    norwegian: "Den planlagte fellesøkten er avlyst."),
                attachment: attachment
            )
            await refreshConversation(invitation.conversationID)
        }
        guard currentUserID == organizerID, session.profile.userID == organizerID else { return }
        let latest = try await service.loadPlannedWorkoutInvitationMessages(sourceWorkoutID: sourceID)
        session.syncSharedWorkoutLifecycles(from: latest)
    }

    func reset() {
        conversations = []
        recentMessages = []
        messagesByConversation = [:]
        pinnedConversationIDs = []
        archivedConversationIDs = []
        errorMessage = nil
    }
}


enum MessagingStoreError: LocalizedError {
    case requestDeclined

    var errorDescription: String? {
        switch self {
        case .requestDeclined:
            return "This message request was declined."
        }
    }
}
