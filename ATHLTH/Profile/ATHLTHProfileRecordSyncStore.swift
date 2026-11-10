import Combine
import Foundation
import Supabase

/// Account-owned, minimal display summaries. Raw HealthKit samples, locations
/// and workout histories never leave the source device through this store.
struct ATHLTHSyncedProfileRecord: Codable, Equatable {
    let user_id: UUID
    let record_key: String
    let display_value: String
    let supporting_detail: String
}

private struct ATHLTHProfileRecordSelectionRow: Codable {
    let user_id: UUID
    let selected_kinds: [String]
}

@MainActor
final class ATHLTHProfileRecordSyncStore: ObservableObject {
    @Published private(set) var selectionRaw = ""
    @Published private(set) var values: [String: ATHLTHSyncedProfileRecord] = [:]
    @Published private(set) var lastSyncError: String?

    private let client = SupabaseEnvironment.client
    private var accountID: UUID?
    private var selectionIsPending = false
    private var selectionUploadTask: Task<Void, Never>?
    private var isRefreshing = false

    func switchAccount(_ userID: UUID?) {
        guard accountID != userID else { return }
        selectionUploadTask?.cancel()
        selectionUploadTask = nil
        accountID = userID
        lastSyncError = nil
        selectionIsPending = false
        guard let userID else {
            values = [:]
            selectionRaw = ""
            return
        }
        values = AccountLocalStorage.read(
            [String: ATHLTHSyncedProfileRecord].self,
            name: "profileRecordDisplayCache",
            userID: userID
        ) ?? [:]
        selectionRaw = AccountLocalStorage.read(
            String.self, name: "featuredProfileRecords",
            userID: userID
        ) ?? ""

        // Import the old device-global selection only for the account whose
        // identity was verified and cached before this upgrade. Never copy a
        // previous account's showcase to a different user on a shared iPad.
        if selectionRaw.isEmpty,
           let data = UserDefaults.standard.data(forKey: "session.verifiedOfflineProfile.v1"),
           let verified = try? JSONDecoder().decode(UserProfile.self, from: data),
           verified.userID == userID,
           let legacy = UserDefaults.standard.string(
               forKey: ProfileFeaturedRecordKind.storageKey
           ), !legacy.isEmpty {
            selectionRaw = legacy
            AccountLocalStorage.write(
                legacy, name: "featuredProfileRecords", userID: userID
            )
        }
        selectionIsPending = AccountLocalStorage.read(
            Bool.self, name: "featuredProfileRecordsPending", userID: userID
        ) ?? false
    }

    func value(for kind: ProfileFeaturedRecordKind, local: String) -> String {
        let local = local.trimmingCharacters(in: .whitespacesAndNewlines)
        // iPhone owns the fresh measured result; iPad displays the shared
        // account snapshot instead of replacing it with a stale local PR.
        if !ATHLTHDeviceRole.isIPhone,
           let shared = values[kind.rawValue]?.display_value,
           !shared.isEmpty { return shared }
        if !local.isEmpty && local != "—" { return local }
        return values[kind.rawValue]?.display_value ?? "—"
    }

    func detail(for kind: ProfileFeaturedRecordKind, local: String) -> String {
        if let remote = values[kind.rawValue],
           !remote.supporting_detail.isEmpty {
            return remote.supporting_detail
        }
        return local
    }

    func setSelection(_ raw: String) {
        guard let userID = accountID else { return }
        guard raw != selectionRaw else { return }
        selectionRaw = raw
        selectionIsPending = true
        AccountLocalStorage.write(
            raw, name: "featuredProfileRecords", userID: userID
        )
        AccountLocalStorage.write(
            true, name: "featuredProfileRecordsPending", userID: userID
        )
        selectionUploadTask?.cancel()
        selectionUploadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.uploadSelection(userID: userID)
        }
    }

    private func uploadSelection(userID: UUID) async {
        guard accountID == userID,
              client.auth.currentUser?.id == userID,
              selectionIsPending else { return }
        let captured = selectionRaw
        let keys = ProfileFeaturedRecordKind.decodedSelection(from: captured)
            .map(\.rawValue)
        do {
            try await client.from("athlth_profile_record_selection")
                .upsert(
                    ATHLTHProfileRecordSelectionRow(
                        user_id: userID, selected_kinds: keys
                    ),
                    onConflict: "user_id"
                ).execute()
            guard accountID == userID else { return }
            // An edit made during the request still needs a new upload.
            if selectionRaw == captured {
                selectionIsPending = false
                AccountLocalStorage.write(
                    false, name: "featuredProfileRecordsPending", userID: userID
                )
            }
            lastSyncError = nil
        } catch {
            if accountID == userID {
                lastSyncError = error.localizedDescription
            }
        }
    }

    func refresh(userID: UUID) async {
        guard accountID == userID,
              client.auth.currentUser?.id == userID,
              !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if selectionIsPending {
            await uploadSelection(userID: userID)
        }
        do {
            let rows: [ATHLTHSyncedProfileRecord] = try await client
                .from("athlth_profile_record_values")
                .select("user_id,record_key,display_value,supporting_detail")
                .eq("user_id", value: userID)
                .execute().value
            guard accountID == userID else { return }
            let fetched = Dictionary(
                uniqueKeysWithValues: rows.map { ($0.record_key, $0) }
            )
            if fetched != values {
                // A missing/empty cloud result must never erase locally
                // captured records if an upload has not yet succeeded.
                values.merge(fetched) { _, remote in remote }
                AccountLocalStorage.write(
                    values, name: "profileRecordDisplayCache", userID: userID
                )
            }
            let preferences: [ATHLTHProfileRecordSelectionRow] = try await client
                .from("athlth_profile_record_selection")
                .select("user_id,selected_kinds")
                .eq("user_id", value: userID)
                .limit(1)
                .execute().value
            guard accountID == userID else { return }
            if let remote = preferences.first, !selectionIsPending {
                let raw = ProfileFeaturedRecordKind.encodedSelection(
                    remote.selected_kinds.compactMap(
                        ProfileFeaturedRecordKind.init(rawValue:)
                    )
                )
                selectionRaw = raw
                AccountLocalStorage.write(
                    raw, name: "featuredProfileRecords", userID: userID
                )
            } else if preferences.isEmpty, !selectionRaw.isEmpty {
                selectionIsPending = true
                await uploadSelection(userID: userID)
            }
            lastSyncError = nil
        } catch {
            if accountID == userID { lastSyncError = error.localizedDescription }
        }
    }

    /// Publish only displayed, nonempty summaries from the iPhone's verified
    /// sources. An iPad with no HealthKit history cannot erase an iPhone PR.
    func publishAvailable(
        userID: UUID,
        healthRecords: [HealthPersonalRecord],
        stats: ProfilePerformanceStats?,
        strength: StrengthWorkoutStore,
        performanceWorkouts: [WorkoutSummary]
    ) async {
        guard ATHLTHDeviceRole.isIPhone,
              accountID == userID,
              client.auth.currentUser?.id == userID else { return }
        let writes: [ATHLTHSyncedProfileRecord] = ProfileFeaturedRecordKind.allCases
            .compactMap { kind in
                let display = kind.displayValue(
                    healthRecords: healthRecords,
                    stats: stats,
                    strengthRecords: strength.personalRecords,
                    strengthRepRecords: strength.repPersonalRecords,
                    performanceWorkouts: performanceWorkouts,
                    strengthWorkouts: strength.workoutHistory
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !display.isEmpty, display != "—", display.count <= 140
                else { return nil }
                let detail = String(
                    kind.supportingDetail(healthRecords: healthRecords).prefix(240)
                )
                let row = ATHLTHSyncedProfileRecord(
                    user_id: userID, record_key: kind.rawValue,
                    display_value: display, supporting_detail: detail
                )
                return values[kind.rawValue] == row ? nil : row
            }
        guard !writes.isEmpty else { return }
        do {
            try await client.from("athlth_profile_record_values")
                .upsert(writes, onConflict: "user_id,record_key")
                .execute()
            guard accountID == userID else { return }
            for row in writes { values[row.record_key] = row }
            AccountLocalStorage.write(
                values, name: "profileRecordDisplayCache", userID: userID
            )
            lastSyncError = nil
        } catch {
            if accountID == userID { lastSyncError = error.localizedDescription }
        }
    }
}
