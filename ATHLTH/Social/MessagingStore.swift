import Foundation

@MainActor
final class MessagingStore: ObservableObject {
    @Published private(set) var conversations: [DirectConversationRecord] = []
    @Published private(set) var recentMessages: [DirectMessageRecord] = []
    @Published private(set) var messagesByConversation: [UUID: [DirectMessageRecord]] = [:]
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    private let service: SupabaseMessagingService

    init(service: SupabaseMessagingService = SupabaseMessagingService()) {
        self.service = service
    }

    var currentUserID: UUID? {
        service.currentUserID
    }

    var unreadCount: Int {
        guard let currentUserID else { return 0 }
        return recentMessages.filter {
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
        incomingMessageRequests.count
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

    func refresh() async {
        guard currentUserID != nil, !isRefreshing else { return }

        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            async let conversationsTask = service.loadConversations()
            async let messagesTask = service.loadRecentMessages()

            conversations = try await conversationsTask
            recentMessages = try await messagesTask
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openConversation(with userID: UUID) async throws -> UUID {
        if let existing = conversation(with: userID) {
            guard existing.requestStatus != .declined else {
                throw MessagingStoreError.requestDeclined
            }
            return existing.id
        }

        let conversationID = try await service.getOrCreateConversation(with: userID)
        await refresh()
        return conversationID
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

            if let currentUserID,
               messages.contains(where: {
                   $0.recipientID == currentUserID && $0.readAt == nil
               }) {
                try await service.markConversationRead(conversationID)
                let markedAt = Date()
                messagesByConversation[conversationID] = messages.map { message in
                    guard message.recipientID == currentUserID,
                          message.readAt == nil
                    else {
                        return message
                    }

                    return DirectMessageRecord(
                        id: message.id,
                        conversationID: message.conversationID,
                        senderID: message.senderID,
                        recipientID: message.recipientID,
                        body: message.body,
                        attachmentKindRaw: message.attachmentKindRaw,
                        attachmentTitle: message.attachmentTitle,
                        attachmentSubtitle: message.attachmentSubtitle,
                        attachmentPayload: message.attachmentPayload,
                        shareVersion: message.shareVersion,
                        sourceObjectID: message.sourceObjectID,
                        sourceOwnerID: message.sourceOwnerID,
                        createdAt: message.createdAt,
                        readAt: markedAt,
                        deletedAt: message.deletedAt
                    )
                }
            }

            await refresh()
        } catch {
            errorMessage = error.localizedDescription
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
