import Foundation
import Supabase

final class SupabaseMessagingService {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    func getOrCreateConversation(with otherUserID: UUID) async throws -> UUID {
        guard currentUserID != nil else {
            throw SocialServiceError.notAuthenticated
        }

        let conversationID: UUID = try await client
            .rpc(
                "get_or_create_direct_conversation",
                params: DirectConversationParams(otherUser: otherUserID)
            )
            .execute()
            .value

        return conversationID
    }

    func loadConversations() async throws -> [DirectConversationRecord] {
        try await client
            .from("direct_conversations")
            .select()
            .order("last_message_at", ascending: false)
            .execute()
            .value
    }

    func loadRecentMessages(limit: Int = 500) async throws -> [DirectMessageRecord] {
        try await client
            .from("direct_messages")
            .select()
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    func loadMessages(
        conversationID: UUID,
        limit: Int = 300
    ) async throws -> [DirectMessageRecord] {
        try await client
            .from("direct_messages")
            .select()
            .eq("conversation_id", value: conversationID)
            .order("created_at", ascending: true)
            .limit(limit)
            .execute()
            .value
    }

    func sendMessage(
        conversationID: UUID,
        to recipientID: UUID,
        body: String?,
        attachment: MessageShareDraft?
    ) async throws {
        guard let senderID = currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        let cleanBody = body?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let insert = DirectMessageInsert(
            conversationID: conversationID,
            senderID: senderID,
            recipientID: recipientID,
            body: cleanBody?.isEmpty == false ? cleanBody : nil,
            attachmentKind: attachment?.kind.rawValue,
            attachmentTitle: attachment?.title,
            attachmentSubtitle: attachment?.subtitle,
            attachmentPayload: attachment?.payload,
            shareVersion: attachment?.shareVersion ?? 1,
            sourceObjectID: attachment?.sourceObjectID,
            sourceOwnerID: attachment?.sourceOwnerID
        )

        try await client
            .from("direct_messages")
            .insert(insert)
            .execute()
    }

    func markConversationRead(_ conversationID: UUID) async throws {
        guard let currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        try await client
            .from("direct_messages")
            .update(["read_at": ISO8601DateFormatter().string(from: Date())])
            .eq("conversation_id", value: conversationID)
            .eq("recipient_id", value: currentUserID)
            .execute()
    }
}
