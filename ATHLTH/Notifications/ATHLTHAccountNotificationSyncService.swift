import Foundation
import Supabase

struct ATHLTHNotificationTombstone: Codable, Hashable {
    let item: ATHLTHNotificationItem
    let deletedAt: Date
}

struct ATHLTHAccountNotificationSnapshot: Codable {
    var items: [ATHLTHNotificationItem]
    var tombstones: [ATHLTHNotificationTombstone]

    static let empty = Self(items: [], tombstones: [])

    /// The remote account and a device may have different read states while
    /// offline. Merge by stable event key, never by random local UUID.
    static func merged(
        _ local: Self, _ remote: Self
    ) -> Self {
        var indexed = Dictionary(
            local.items.map { ($0.eventKey, $0) },
            uniquingKeysWith: { old, new in
                new.createdAt > old.createdAt ? new : old
            }
        )
        for item in remote.items {
            if var existing = indexed[item.eventKey] {
                // Retain locally hydrated routing identifiers when an older
                // synced version didn't yet include those fields.
                if existing.socialEntityID == nil {
                    existing.socialEntityID = item.socialEntityID
                }
                if existing.socialEntityType == nil {
                    existing.socialEntityType = item.socialEntityType
                }
                if existing.groupID == nil {
                    existing.groupID = item.groupID
                }
                existing.readAt = latest(existing.readAt, item.readAt)
                indexed[item.eventKey] = existing
            } else {
                indexed[item.eventKey] = item
            }
        }

        var deleted: [String: ATHLTHNotificationTombstone] = [:]
        for entry in local.tombstones + remote.tombstones {
            if let previous = deleted[entry.item.eventKey],
               previous.deletedAt >= entry.deletedAt {
                continue
            }
            deleted[entry.item.eventKey] = entry
        }
        for key in deleted.keys { indexed.removeValue(forKey: key) }
        return Self(
            items: indexed.values
                .filter { $0.kind != .workoutCompleted }
                .sorted { $0.createdAt > $1.createdAt },
            tombstones: deleted.values.sorted {
                $0.deletedAt > $1.deletedAt
            }
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

private struct ATHLTHAccountNotificationCloudRow: Codable {
    let user_id: UUID
    let event_key: String
    let payload_json: String
    let read_at: String?
    let deleted_at: String?

    static func make(
        userID: UUID, item: ATHLTHNotificationItem,
        deletedAt: Date? = nil
    ) -> Self? {
        guard let data = try? JSONEncoder().encode(item),
              let json = String(data: data, encoding: .utf8),
              !item.eventKey.isEmpty, item.eventKey.count <= 240,
              json.count <= 12000 else { return nil }
        return Self(user_id: userID, event_key: item.eventKey,
                    payload_json: json,
                    read_at: item.readAt.map { stamp($0) },
                    deleted_at: deletedAt.map { stamp($0) })
    }

    static func stamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: raw) { return parsed }
        return ISO8601DateFormatter().date(from: raw)
    }

    var restored: (item: ATHLTHNotificationItem, deletedAt: Date?)? {
        guard let data = payload_json.data(using: .utf8),
              var item = try? JSONDecoder().decode(
                ATHLTHNotificationItem.self, from: data
              ),
              item.eventKey == event_key,
              item.kind != .workoutCompleted
        else { return nil }
        item.readAt = Self.latest(item.readAt, Self.parse(read_at))
        return (item, Self.parse(deleted_at))
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

@MainActor
enum ATHLTHAccountNotificationSyncService {
    static func reconcile(
        accountID: UUID,
        local: ATHLTHAccountNotificationSnapshot
    ) async throws -> ATHLTHAccountNotificationSnapshot {
        let client = SupabaseEnvironment.client
        guard client.auth.currentUser?.id == accountID else {
            throw CancellationError()
        }

        let rows: [ATHLTHAccountNotificationCloudRow] = try await client
            .from("athlth_account_notifications")
            .select("user_id,event_key,payload_json,read_at,deleted_at")
            .eq("user_id", value: accountID)
            .order("updated_at", ascending: false)
            .limit(500)
            .execute().value

        guard !Task.isCancelled, client.auth.currentUser?.id == accountID
        else { throw CancellationError() }

        var remote = ATHLTHAccountNotificationSnapshot.empty
        for row in rows where row.user_id == accountID {
            guard let restored = row.restored else { continue }
            if let deletedAt = restored.deletedAt {
                remote.tombstones.append(.init(
                    item: restored.item, deletedAt: deletedAt
                ))
            } else {
                remote.items.append(restored.item)
            }
        }

        let merged = ATHLTHAccountNotificationSnapshot.merged(local, remote)
        let saved = Dictionary(
            rows.map { ($0.event_key, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var changed: [ATHLTHAccountNotificationCloudRow] = []
        for item in merged.items {
            guard let proposed = ATHLTHAccountNotificationCloudRow.make(
                userID: accountID, item: item
            ) else { continue }
            if let old = saved[item.eventKey] {
                guard old.restored?.item.readAt != item.readAt ||
                      old.restored?.item.socialEntityID != item.socialEntityID ||
                      old.restored?.item.groupID != item.groupID else { continue }
            }
            changed.append(proposed)
        }
        for tombstone in merged.tombstones {
            guard let proposed = ATHLTHAccountNotificationCloudRow.make(
                userID: accountID, item: tombstone.item,
                deletedAt: tombstone.deletedAt
            ) else { continue }
            if let old = saved[tombstone.item.eventKey],
               old.restored?.deletedAt != nil { continue }
            changed.append(proposed)
        }

        // Small write batches preserve offline edits without a huge
        // per-card network request on a fresh install.
        for start in stride(from: 0, to: changed.count, by: 75) {
            guard !Task.isCancelled,
                  client.auth.currentUser?.id == accountID
            else { throw CancellationError() }
            try await client.from("athlth_account_notifications")
                .upsert(
                    Array(changed[start..<min(start + 75, changed.count)]),
                    onConflict: "user_id,event_key"
                )
                .execute()
        }

        // Read back the server's monotonic result to resolve any simultaneous
        // updates from another device, especially read/delete timestamps.
        if !changed.isEmpty {
            let fresh: [ATHLTHAccountNotificationCloudRow] = try await client
                .from("athlth_account_notifications")
                .select("user_id,event_key,payload_json,read_at,deleted_at")
                .eq("user_id", value: accountID)
                .order("updated_at", ascending: false)
                .limit(500)
                .execute().value
            var confirmed = ATHLTHAccountNotificationSnapshot.empty
            for row in fresh where row.user_id == accountID {
                guard let restored = row.restored else { continue }
                if let deletedAt = restored.deletedAt {
                    confirmed.tombstones.append(.init(
                        item: restored.item, deletedAt: deletedAt
                    ))
                } else {
                    confirmed.items.append(restored.item)
                }
            }
            return .merged(merged, confirmed)
        }
        return merged
    }
}
