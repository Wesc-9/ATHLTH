import CryptoKit
import Foundation
import Supabase

/// Only completed exercise/interval/route names and aggregate counts are
/// synchronized. Raw workout samples, GPS coordinates and HealthKit records
/// never enter this account-private profile preview.
@MainActor
enum ATHLTHProfileMostTrainedSyncService {
    typealias Item = ATHLTHProfileHighlights.TrainedItem

    private static let keyPrefix = "most-trained.v1."

    private struct Detail: Codable {
        let identity: String
        let kind: String
        let count: Int
        let lastCompleted: Date
    }

    private struct CloudRow: Codable {
        let user_id: UUID
        let record_key: String
        let display_value: String
        let supporting_detail: String

        @MainActor
        var item: Item? {
            guard record_key.hasPrefix(ATHLTHProfileMostTrainedSyncService.keyPrefix),
                  let data = supporting_detail.data(using: .utf8),
                  let detail = try? JSONDecoder().decode(Detail.self, from: data),
                  let kind = ATHLTHProfileHighlights.ActivityKind(rawValue: detail.kind),
                  kind != .all,
                  detail.count > 0, detail.count < 1_000_000,
                  !detail.identity.isEmpty,
                  !display_value.isEmpty
            else { return nil }
            return Item(id: detail.identity, title: display_value, kind: kind,
                        count: detail.count, lastCompleted: detail.lastCompleted)
        }
    }

    private static func key(for item: Item) -> String {
        let hash = SHA256.hash(data: Data(item.id.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return keyPrefix + hash
    }

    /// A device may have only some of the user's HealthKit history. Never
    /// replace a richer cloud snapshot with a smaller local session count.
    /// Totals are best-known per activity, not an unsafe sum of overlapping
    /// device histories.
    static func merged(local: [Item], remote: [Item]) -> [Item] {
        var byID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        for item in local where item.count > 0 {
            if let previous = byID[item.id] {
                if item.count > previous.count ||
                    (item.count == previous.count &&
                     item.lastCompleted > previous.lastCompleted) {
                    byID[item.id] = item
                }
            } else {
                byID[item.id] = item
            }
        }
        return byID.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.lastCompleted != $1.lastCompleted {
                return $0.lastCompleted > $1.lastCompleted
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    /// Fetch the verified signed-in account before comparing the device's
    /// completed history. Empty local history is a read, never a deletion.
    static func synchronize(userID: UUID, local: [Item]) async -> [Item] {
        let client = SupabaseEnvironment.client
        // Offline account restoration may precede Keychain-backed Supabase
        // restoration on a newly installed iPad. Retry briefly while it
        // finishes rather than treating the account as having zero history.
        for _ in 0..<4 where client.auth.currentUser == nil {
            guard !Task.isCancelled else { return local }
            do { try await Task.sleep(for: .milliseconds(600)) }
            catch { return local }
        }
        guard client.auth.currentUser?.id == userID else { return local }
        do {
            let rows: [CloudRow] = try await client
                .from("athlth_profile_record_values")
                .select("user_id,record_key,display_value,supporting_detail")
                .eq("user_id", value: userID)
                .like("record_key", pattern: keyPrefix + "%")
                .limit(250)
                .execute().value

            guard !Task.isCancelled, client.auth.currentUser?.id == userID
            else { return local }

            let remote = rows.filter { $0.user_id == userID }.compactMap(\.item)
            let best = merged(local: local, remote: remote)

            let remoteByID = Dictionary(
                remote.map { ($0.id, $0) },
                uniquingKeysWith: { old, new in
                    new.count > old.count ? new : old
                }
            )
            // Home displays at most three, but keep a small account-backed
            // candidate set for each filter without saving full history.
            let candidates = best.filter { item in
                guard local.contains(where: { $0.id == item.id }) else {
                    return false
                }
                guard let old = remoteByID[item.id] else { return true }
                return item.count > old.count ||
                    (item.count == old.count && item.lastCompleted > old.lastCompleted)
            }.prefix(120)

            var writes: [CloudRow] = []
            for item in candidates {
                let detail = Detail(identity: item.id, kind: item.kind.rawValue,
                                    count: item.count, lastCompleted: item.lastCompleted)
                guard let encoded = try? JSONEncoder().encode(detail),
                      let value = String(data: encoded, encoding: .utf8),
                      value.count < 1500 else { continue }
                writes.append(CloudRow(
                    user_id: userID, record_key: key(for: item),
                    display_value: String(item.title.prefix(120)),
                    supporting_detail: value
                ))
            }

            if !writes.isEmpty {
                guard !Task.isCancelled, client.auth.currentUser?.id == userID
                else { return local }
                try await client.from("athlth_profile_record_values")
                    .upsert(writes, onConflict: "user_id,record_key").execute()
            }
            return best
        } catch {
            // Offline-first: never replace the locally verified preview with
            // an empty card on a network error.
            return local
        }
    }
}
