import Foundation
import Supabase

private struct MessagingInboxBadgeRow:
    Decodable,
    Sendable
{
    let id: UUID
    let readAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case readAt = "read_at"
    }
}

final class SupabaseMessagingService: Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    func unreadInboxEventCount()
        async throws -> Int {
        guard let currentUserID else {
            throw SocialServiceError
                .notAuthenticated
        }

        let rows:
            [MessagingInboxBadgeRow] =
            try await client
                .from(
                    "social_inbox_events"
                )
                .select(
                    "id,read_at"
                )
                .eq(
                    "recipient_id",
                    value:
                        currentUserID
                )
                .limit(250)
                .execute()
                .value

        return rows.filter {
            $0.readAt == nil
        }
        .count
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

    func loadConversation(
        id: UUID
    ) async throws -> DirectConversationRecord? {
        let rows: [DirectConversationRecord] =
            try await client
                .from("direct_conversations")
                .select()
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value

        return rows.first
    }

    func loadRecentMessages(limit: Int = 500) async throws -> [DirectMessageRecord] {
        try await client
            .from("athlth_direct_messages_visible")
            .select()
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// Fetch the complete visible invitation conversation for one planned
    /// session. This intentionally queries by source ID instead of relying
    /// on the general inbox's limited recent-message cache.
    func loadPlannedWorkoutInvitationMessages(
        sourceWorkoutID: UUID
    ) async throws -> [DirectMessageRecord] {
        try await client
            .from("athlth_direct_messages_visible")
            .select()
            .eq("source_object_id", value: sourceWorkoutID)
            .eq("attachment_kind", value: MessageShareKind.workout.rawValue)
            .order("created_at", ascending: false)
            .limit(200)
            .execute()
            .value
    }

    func loadMessages(
        conversationID: UUID,
        limit: Int = 300
    ) async throws -> [DirectMessageRecord] {
        try await client
            .from("athlth_direct_messages_visible")
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

    func respondToMessageRequest(
        conversationID: UUID,
        accept: Bool
    ) async throws {
        guard currentUserID != nil else {
            throw SocialServiceError.notAuthenticated
        }

        try await client
            .rpc(
                "respond_to_direct_message_request",
                params: DirectMessageRequestResponseParams(
                    conversationID: conversationID,
                    acceptRequest: accept
                )
            )
            .execute()
    }

    func groupReadReceipts(kind: String, messageIDs: [UUID], markRead: Bool = true) async throws -> [UUID: [String]] {
        struct Params: Encodable {
            let p_kind: String
            let p_ids: [UUID]
            let p_mark_read: Bool
        }
        struct Row: Decodable {
            let message_id: UUID
            let reader_name: String
        }
        guard !messageIDs.isEmpty else { return [:] }
        var result: [UUID: [String]] = [:]
        // The RPC bounds each request. Preserve all loaded messages.
        for start in stride(from: 0, to: messageIDs.count, by: 300) {
            let ids = Array(messageIDs[start..<min(start + 300, messageIDs.count)])
            let rows: [Row] = try await client.rpc(
                "athlth_group_message_receipts",
                params: Params(p_kind: kind, p_ids: ids, p_mark_read: markRead)
            ).execute().value
            for row in rows { result[row.message_id, default: []].append(row.reader_name) }
        }
        return result
    }

    func retractUnreadMessage(_ id: UUID) async throws -> Bool {
        struct Params: Encodable { let p_message_id: UUID }
        return try await client.rpc("athlth_retract_unread_direct_message", params: Params(p_message_id: id))
            .execute().value
    }

    func readReceiptPreference() async throws -> Bool {
        try await client.rpc("athlth_my_read_receipts").execute().value
    }

    func setReadReceiptPreference(_ enabled: Bool) async throws -> Bool {
        struct Params: Encodable { let p_enabled: Bool }
        return try await client.rpc("athlth_my_read_receipts", params: Params(p_enabled: enabled))
            .execute().value
    }

    func markConversationRead(_ conversationID: UUID, messageIDs: [UUID]) async throws {
        guard let currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        let readAt = ISO8601DateFormatter().string(from: Date())

        guard !messageIDs.isEmpty else { return }
        try await client
            .from("direct_messages")
            .update(["read_at": readAt])
            .eq("conversation_id", value: conversationID)
            .eq("recipient_id", value: currentUserID)
            .in("id", values: messageIDs)
            .execute()

        for kind in [
            "message",
            "message_request",
            "message_request_accepted",
            "mention"
        ] {
            try await client
                .from("social_inbox_events")
                .update(["read_at": readAt])
                .eq(
                    "recipient_id",
                    value: currentUserID
                )
                .eq("kind", value: kind)
                .eq(
                    "entity_type",
                    value:
                        "direct_conversation"
                )
                .eq(
                    "entity_id",
                    value:
                        conversationID
                )
                .execute()
        }
    }
}
