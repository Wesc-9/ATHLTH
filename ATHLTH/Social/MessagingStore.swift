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

    private let service: SupabaseMessagingService
    private var lastRefreshAt: Date?

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

    func loadPinnedConversations() {
        guard let key = pinnedStorageKey else {
            pinnedConversationIDs = []
            return
        }

        let storedIDs = UserDefaults.standard.stringArray(forKey: key) ?? []
        pinnedConversationIDs = Set(storedIDs.compactMap(UUID.init(uuidString:)))

        if let archiveKey = archiveStorageKey {
            let archivedIDs =
                UserDefaults.standard
                    .stringArray(
                        forKey: archiveKey
                    ) ?? []
            archivedConversationIDs =
                Set(
                    archivedIDs.compactMap {
                        UUID(
                            uuidString: $0
                        )
                    }
                )
        } else {
            archivedConversationIDs = []
        }
    }

    func isPinned(_ conversationID: UUID) -> Bool {
        pinnedConversationIDs.contains(conversationID)
    }

    func togglePinned(_ conversationID: UUID) {
        if pinnedConversationIDs.contains(conversationID) {
            pinnedConversationIDs.remove(conversationID)
        } else {
            pinnedConversationIDs.insert(conversationID)
        }

        persistPinnedConversations()
    }

    func isArchived(
        _ conversationID: UUID
    ) -> Bool {
        archivedConversationIDs
            .contains(
                conversationID
            )
    }

    func toggleArchived(
        _ conversationID: UUID
    ) {
        if archivedConversationIDs
            .contains(
                conversationID
            ) {
            archivedConversationIDs
                .remove(
                    conversationID
                )
        } else {
            archivedConversationIDs
                .insert(
                    conversationID
                )
        }

        persistArchivedConversations()
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
        guard currentUserID != nil,
              !isRefreshing
        else {
            return
        }

        if !force,
           let lastRefreshAt,
           Date().timeIntervalSince(lastRefreshAt) < 60 {
            return
        }

        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            async let conversationsTask = service.loadConversations()
            async let messagesTask = service.loadRecentMessages()

            let refreshedConversations =
                try await conversationsTask
            let refreshedMessages =
                try await messagesTask

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
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func openConversation(with userID: UUID) async throws -> UUID {
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

        // Refresh the normal inbox first, then hydrate the exact row last.
        // A brand-new pending conversation has no message/last_message_at yet;
        // keeping the exact row as the final source of truth prevents the
        // first-request composer from falling back to a disabled state.
        await refresh()

        if let conversation =
                try await service
                    .loadConversation(
                        id: conversationID
                    ) {
            upsertConversation(
                conversation
            )
        }

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
        errorMessage = nil

        do {
            try await service.respondToMessageRequest(
                conversationID: conversationID,
                accept: accept
            )
            await refresh()
            if accept {
                await refreshConversation(conversationID)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshConversation(_ conversationID: UUID) async {
        do {
            let messages = try await service.loadMessages(
                conversationID: conversationID
            )
            messagesByConversation[conversationID] = messages

            if let currentUserID {
                let hasUnread =
                    messages.contains {
                        $0.recipientID ==
                            currentUserID &&
                        $0.readAt == nil
                    }

                if hasUnread {
                    try await service
                        .markConversationRead(
                            conversationID
                        )

                    let markedAt = Date()
                    markConversationReadLocally(
                        conversationID:
                            conversationID,
                        currentUserID:
                            currentUserID,
                        markedAt:
                            markedAt
                    )
                }

                await clearDeliveredNotifications(
                    for:
                        conversationID
                )
            }

            // Force this refresh. A normal refresh may be throttled for
            // 60 seconds, which previously left the inbox unread badge stuck
            // after the thread had already been marked read on the backend.
            await refresh(force: true)

            // Full inbox refreshes must not make a just-created pending
            // request disappear locally before its first message is sent.
            if let conversation =
                    try await service
                        .loadConversation(
                            id: conversationID
                        ) {
                upsertConversation(
                    conversation
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func markConversationReadLocally(
        conversationID: UUID,
        currentUserID: UUID,
        markedAt: Date
    ) {
        func marked(
            _ message:
                DirectMessageRecord
        ) -> DirectMessageRecord {
            guard message.conversationID ==
                    conversationID,
                  message.recipientID ==
                    currentUserID,
                  message.readAt == nil
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

    func messages(in conversationID: UUID) -> [DirectMessageRecord] {
        messagesByConversation[conversationID] ?? []
    }

    func send(
        to recipientID: UUID,
        conversationID: UUID,
        body: String?,
        attachment: MessageShareDraft? = nil
    ) async -> Bool {
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
            await refreshConversation(conversationID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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
