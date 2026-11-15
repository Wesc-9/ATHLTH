import Foundation
import Supabase

struct ATHLTHConversationPreference: Codable, Hashable {
    let conversationID: UUID
    var pinnedAt: Date?
    var unpinnedAt: Date?
    var archivedAt: Date?
    var unarchivedAt: Date?

    var isPinned: Bool {
        guard let pinnedAt else { return false }
        return unpinnedAt.map { pinnedAt > $0 } ?? true
    }

    var isArchived: Bool {
        guard let archivedAt else { return false }
        return unarchivedAt.map { archivedAt > $0 } ?? true
    }

    static func merged(
        _ lhs: ATHLTHConversationPreference,
        _ rhs: ATHLTHConversationPreference
    ) -> ATHLTHConversationPreference {
        precondition(lhs.conversationID == rhs.conversationID)
        return Self(
            conversationID: lhs.conversationID,
            pinnedAt: latest(lhs.pinnedAt, rhs.pinnedAt),
            unpinnedAt: latest(lhs.unpinnedAt, rhs.unpinnedAt),
            archivedAt: latest(lhs.archivedAt, rhs.archivedAt),
            unarchivedAt: latest(lhs.unarchivedAt, rhs.unarchivedAt)
        )
    }

    private static func latest(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case let (a?, b?): max(a, b)
        case (let a?, nil): a
        case (nil, let b?): b
        case (nil, nil): nil
        }
    }
}

private struct ATHLTHCloudConversationPreference: Codable {
    let user_id: UUID
    let conversation_id: UUID
    let pinned_at: String?
    let unpinned_at: String?
    let archived_at: String?
    let unarchived_at: String?

    static func make(
        userID: UUID, preference: ATHLTHConversationPreference
    ) -> Self {
        func stamp(_ date: Date?) -> String? {
            date.map { ISO8601DateFormatter().string(from: $0) }
        }
        return .init(user_id: userID, conversation_id: preference.conversationID,
                     pinned_at: stamp(preference.pinnedAt),
                     unpinned_at: stamp(preference.unpinnedAt),
                     archived_at: stamp(preference.archivedAt),
                     unarchived_at: stamp(preference.unarchivedAt))
    }

    var preference: ATHLTHConversationPreference {
        func parse(_ raw: String?) -> Date? {
            guard let raw else { return nil }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        }
        return .init(conversationID: conversation_id,
                     pinnedAt: parse(pinned_at),
                     unpinnedAt: parse(unpinned_at),
                     archivedAt: parse(archived_at),
                     unarchivedAt: parse(unarchived_at))
    }
}

@MainActor
enum ATHLTHConversationPreferenceSyncService {
    static func merged(
        local: [UUID: ATHLTHConversationPreference],
        remote: [UUID: ATHLTHConversationPreference]
    ) -> [UUID: ATHLTHConversationPreference] {
        var result = remote
        for (key, value) in local {
            if let old = result[key] {
                result[key] = .merged(value, old)
            } else {
                result[key] = value
            }
        }
        return result
    }

    static func reconcile(
        userID: UUID,
        local: [UUID: ATHLTHConversationPreference]
    ) async throws -> [UUID: ATHLTHConversationPreference] {
        let client = SupabaseEnvironment.client
        guard client.auth.currentUser?.id == userID else {
            throw CancellationError()
        }
        let rows: [ATHLTHCloudConversationPreference] = try await client
            .from("athlth_account_conversation_preferences")
            .select("user_id,conversation_id,pinned_at,unpinned_at,archived_at,unarchived_at")
            .eq("user_id", value: userID)
            .limit(500)
            .execute().value
        guard !Task.isCancelled, client.auth.currentUser?.id == userID
        else { throw CancellationError() }

        let remote = Dictionary(
            rows.filter { $0.user_id == userID }
                .map { ($0.conversation_id, $0.preference) },
            uniquingKeysWith: { first, _ in first }
        )
        let combined = merged(local: local, remote: remote)
        let updates = combined.values.filter { candidate in
            candidate != remote[candidate.conversationID]
        }
        if !updates.isEmpty {
            let payload = updates.map {
                ATHLTHCloudConversationPreference.make(
                    userID: userID, preference: $0
                )
            }
            for start in stride(from: 0, to: payload.count, by: 60) {
                guard !Task.isCancelled, client.auth.currentUser?.id == userID
                else { throw CancellationError() }
                try await client.from("athlth_account_conversation_preferences")
                    .upsert(Array(payload[start..<min(start + 60, payload.count)]),
                            onConflict: "user_id,conversation_id")
                    .execute()
            }
        }
        return combined
    }
}
