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

    /// Subscribe to content-free, account-scoped server invalidations.
    /// REST remains authoritative and the caller retains fallback polling.
    @MainActor
    func observeThreadChanges(
        owner: UUID, conversation: UUID,
        onChange: @escaping @MainActor @Sendable () -> Void,
        onStatus: @escaping @MainActor @Sendable (Bool) -> Void
    ) async {
        guard currentUserID == owner, !Task.isCancelled else { return }
        let topic = "athlth-direct:\(owner.uuidString.lowercased()):\(conversation.uuidString.lowercased())"
        let channel = await client.channel(topic) { $0.isPrivate = true }
        let changes = await channel.broadcastStream(event: "refresh")
        let statuses = channel.statusChange
        do {
            try await channel.subscribeWithError()
            guard !Task.isCancelled, currentUserID == owner else {
                await channel.unsubscribe()
                return
            }
            onStatus(channel.status == .subscribed)
            onChange() // Cover the fetch-to-subscribe gap.
            await withTaskGroup(of: Void.self) { group in
                // Child tasks consume Sendable streams without inheriting UI
                // isolation. Only callbacks hop to the main actor.
                group.addTask { [self, changes, onChange] in
                    for await _ in changes {
                        guard !Task.isCancelled, self.currentUserID == owner else { break }
                        await onChange()
                    }
                }
                group.addTask { [self, statuses, onStatus, onChange] in
                    for await status in statuses {
                        guard !Task.isCancelled, self.currentUserID == owner else { break }
                        await onStatus(status == .subscribed)
                        if status == .subscribed { await onChange() }
                    }
                }
                await group.next()
                group.cancelAll()
            }
        } catch {
            // Missing permissions, network loss or older backend: poll normally.
        }
        onStatus(false)
        await channel.unsubscribe()
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
        let messages: [DirectMessageRecord] = try await client
            .from("athlth_direct_messages_visible")
            .select()
            .eq("conversation_id", value: conversationID)
            .order("created_at", ascending: false)
            .order("id", ascending: false)
            .limit(limit)
            .execute()
            .value
        return Array(messages.reversed())
    }

    func sendMessage(
        conversationID: UUID,
        to recipientID: UUID,
        body: String?,
        attachment: MessageShareDraft?,
        messageID: UUID = UUID()
    ) async throws {
        guard let senderID = currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        let cleanBody = body?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let insert = DirectMessageInsert(
            id: messageID,
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

        do {
            try await client
                .from("direct_messages")
                .insert(insert)
                .execute()
        } catch {
            // A connection may fail after the insert has been committed.
            // Confirm the exact immutable row, never a matching text alone.
            let insertError = error
            guard !Task.isCancelled, currentUserID == senderID else { throw insertError }
            let confirmed: [DirectMessageRecord]
            do {
                confirmed = try await client
                    .from("athlth_direct_messages_visible")
                    .select()
                    .eq("id", value: messageID)
                    .eq("conversation_id", value: conversationID)
                    .eq("sender_id", value: senderID)
                    .limit(1)
                    .execute()
                    .value
            } catch { throw insertError }
            guard currentUserID == senderID, let row = confirmed.first,
                  row.deletedAt == nil, row.recipientID == recipientID,
                  row.body == insert.body, row.attachmentKindRaw == insert.attachmentKind,
                  row.attachmentTitle == insert.attachmentTitle,
                  row.attachmentSubtitle == insert.attachmentSubtitle,
                  row.attachmentPayload == insert.attachmentPayload,
                  row.shareVersion == insert.shareVersion,
                  row.sourceObjectID == insert.sourceObjectID,
                  row.sourceOwnerID == insert.sourceOwnerID else { throw insertError }
        }
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
        guard let owner = currentUserID else { throw SocialServiceError.notAuthenticated }
        guard !messageIDs.isEmpty else { return }
        let readAt = ISO8601DateFormatter().string(from: Date())

        func checkOwner() throws {
            try Task.checkCancellation()
            guard currentUserID == owner else { throw CancellationError() }
        }

        // Keep PostgREST URL length bounded when the user loads older history.
        // Mark only those messages actually loaded, not the entire conversation.
        let uniqueIDs = Array(Set(messageIDs))
        for start in stride(from: 0, to: uniqueIDs.count, by: 100) {
            try checkOwner()
            let ids = Array(uniqueIDs[start..<min(start + 100, uniqueIDs.count)])
            try await client
                .from("direct_messages")
                .update(["read_at": readAt])
                .eq("conversation_id", value: conversationID)
                .eq("recipient_id", value: owner)
                .in("id", values: ids)
                .execute()

            try checkOwner()
            try await client
                .from("social_inbox_events")
                .update(["read_at": readAt])
                .eq("recipient_id", value: owner)
                .eq("entity_type", value: "direct_conversation")
                .eq("entity_id", value: conversationID)
                .in("direct_message_id", values: ids)
                .execute()
        }

        // Acceptance is a conversation event, not an actual message.
        try checkOwner()
        try await client
            .from("social_inbox_events")
            .update(["read_at": readAt])
            .eq("recipient_id", value: owner)
            .eq("kind", value: "message_request_accepted")
            .eq("entity_type", value: "direct_conversation")
            .eq("entity_id", value: conversationID)
            .execute()
    }
}
