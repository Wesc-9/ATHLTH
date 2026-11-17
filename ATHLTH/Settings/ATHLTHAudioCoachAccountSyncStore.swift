import Combine
import Foundation
import Supabase

/// User-authenticated Audio Coach settings only. No live workout recordings,
/// HealthKit samples, strength records or route GPS traces are uploaded.
struct ATHLTHAudioCoachAccountSnapshot: Codable, Hashable {
    var configuration: WatchAudioCoachConfiguration
    var savedRuleSets: [ATHLTHAudioCoachRuleSet]
    var profiles: [ATHLTHAudioCoachProfile]
    var activeProfileID: UUID?
    var editedAt: Date

    @MainActor
    init(settings: AppSettingsStore) {
        configuration = settings.audioCoachConfiguration(
            enabled: settings.audioCoachEnabledByDefault
        )
        savedRuleSets = settings.audioCoachSavedRuleSets
        profiles = settings.audioCoachProfiles
        activeProfileID = settings.activeAudioCoachProfileID
        editedAt = settings.audioCoachEditedAt
    }
}

enum ATHLTHAudioCoachAccountSyncDecision {
    enum Action { case unchanged, upload, download }
    static func choose(
        local: String, remote: String, lastAcknowledged: String?,
        localEditedAt: Date, remoteEditedAt: Date
    ) -> Action {
        if local == remote { return .unchanged }
        if let lastAcknowledged {
            if local == lastAcknowledged { return .download }
            if remote == lastAcknowledged { return .upload }
        }
        // Concurrent edits never blindly replace a newer authored snapshot.
        // The losing copy is first preserved in per-account local storage.
        return localEditedAt > remoteEditedAt ? .upload : .download
    }
}

/// Same account-owned Supabase synchronization as training plans, separately
/// scoped to Audio Coach to prevent a plan sync from overwriting voice edits.
@MainActor
final class ATHLTHAudioCoachAccountSyncStore: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var lastSuccessfulSync: Date?
    @Published private(set) var status = ""

    private struct Remote: Decodable {
        let revision: Int64
        let body_base64: String
    }
    private struct Save: Encodable {
        let p_expected_revision: Int64
        let p_body_base64: String
    }

    private static var accountsBusy = Set<UUID>()
    private let client = SupabaseEnvironment.client
    private var accountID: UUID?
    private var task: Task<Void, Never>?

    func switchAccount(_ userID: UUID?) {
        guard accountID != userID else { return }
        task?.cancel()
        task = nil
        accountID = userID
        lastSuccessfulSync = nil
        status = userID == nil ? "" : ATHLTHLocalization.choose(
            english: "Voice settings will sync through your account.",
            norwegian: "Stemmeinnstillinger synkroniseres via kontoen din."
        )
    }

    func scheduleSync(session: AppSessionStore, settings: AppSettingsStore) {
        guard session.signedIn else { return }
        switchAccount(session.profile.userID)
        task?.cancel()
        task = Task { [weak self, weak session, weak settings] in
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            guard !Task.isCancelled, let self, let session, let settings else { return }
            await self.sync(session: session, settings: settings)
        }
    }

    func sync(session: AppSessionStore, settings: AppSettingsStore) async {
        guard session.signedIn,
              let userID = accountID,
              userID == session.profile.userID,
              client.auth.currentUser?.id == userID,
              !isBusy, !Self.accountsBusy.contains(userID) else { return }

        Self.accountsBusy.insert(userID)
        isBusy = true
        defer {
            Self.accountsBusy.remove(userID)
            isBusy = false
        }

        do {
            let rows: [Remote] = try await client.from("audio_coach_account_state")
                .select("revision,body_base64")
                .eq("user_id", value: userID)
                .limit(1)
                .execute().value
            guard accountID == userID, client.auth.currentUser?.id == userID else { return }

            let previousOwner = UserDefaults.standard.string(
                forKey: "settings.audioCoach.accountOwner.v1"
            ).flatMap(UUID.init(uuidString:))
            let localOwnedBySomeoneElse = previousOwner != nil && previousOwner != userID
            var local = ATHLTHAudioCoachAccountSnapshot(settings: settings)
            if let row = rows.first {
                guard let encoded = Data(base64Encoded: row.body_base64),
                      encoded.count <= 1_400_000 else {
                    throw NSError(
                        domain: "ATHLTH.AudioCoachSync", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid account Audio Coach payload."]
                    )
                }
                let remote = try JSONDecoder().decode(
                    ATHLTHAudioCoachAccountSnapshot.self, from: encoded
                )
                let remoteHash = try fingerprint(remote)
                if localOwnedBySomeoneElse {
                    // Never upload an earlier account's personal voice messages.
                    preserve(local, name: "audioCoachPreviousAccountBackup", userID: previousOwner!)
                    settings.applyAccountAudioCoach(remote)
                    acknowledge(remoteHash, userID: userID)
                } else {
                    let localHash = try fingerprint(local)
                    let acknowledged = AccountLocalStorage.read(
                        String.self, name: "audioCoachSyncAcknowledgement", userID: userID
                    )
                    let action = ATHLTHAudioCoachAccountSyncDecision.choose(
                        local: localHash,
                        remote: remoteHash,
                        lastAcknowledged: acknowledged,
                        localEditedAt: local.editedAt,
                        remoteEditedAt: remote.editedAt
                    )
                    switch action {
                    case .unchanged:
                        acknowledge(remoteHash, userID: userID)
                    case .download:
                        if acknowledged != localHash {
                            preserve(local, name: "audioCoachSyncConflictLocal", userID: userID)
                        }
                        settings.applyAccountAudioCoach(remote)
                        acknowledge(remoteHash, userID: userID)
                    case .upload:
                        if acknowledged != remoteHash {
                            preserve(remote, name: "audioCoachSyncConflictRemote", userID: userID)
                        }
                        try await upload(local, expected: row.revision, userID: userID)
                    }
                }
            } else {
                if localOwnedBySomeoneElse {
                    preserve(local, name: "audioCoachPreviousAccountBackup", userID: previousOwner!)
                    var standard = AudioCoachDraft()
                    standard.applySimpleAudioCoach()
                    local = ATHLTHAudioCoachAccountSnapshot(settings: settings)
                    local.configuration = standard.configuration()
                    local.profiles = []
                    local.savedRuleSets = []
                    local.activeProfileID = nil
                    local.editedAt = Date()
                    settings.applyAccountAudioCoach(local)
                }
                try await upload(local, expected: 0, userID: userID)
            }
            guard accountID == userID else { return }
            UserDefaults.standard.set(
                userID.uuidString, forKey: "settings.audioCoach.accountOwner.v1"
            )
            lastSuccessfulSync = Date()
            status = ATHLTHLocalization.choose(
                english: "Audio Coach is synchronized.",
                norwegian: "Audio Coach er synkronisert."
            )
        } catch {
            // Offline or version-conflict failures do not overwrite local edits.
            status = ATHLTHLocalization.choose(
                english: "Voice sync is pending. Local edits are safe.",
                norwegian: "Stemmesynkronisering venter. Lokale endringer er bevart."
            )
        }
    }

    private func upload(
        _ snapshot: ATHLTHAudioCoachAccountSnapshot,
        expected: Int64, userID: UUID
    ) async throws {
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 1_400_000, accountID == userID else {
            throw NSError(domain: "ATHLTH.AudioCoachSync", code: 2)
        }
        let revision: Int64 = try await client.rpc(
            "save_audio_coach_state",
            params: Save(
                p_expected_revision: expected,
                p_body_base64: data.base64EncodedString()
            )
        ).execute().value
        guard revision > expected, accountID == userID else { return }
        // Only acknowledge if no changes happened during the network request.
        let uploaded = try fingerprint(snapshot)
        acknowledge(uploaded, userID: userID)
    }

    private func acknowledge(_ fingerprint: String, userID: UUID) {
        AccountLocalStorage.write(
            fingerprint, name: "audioCoachSyncAcknowledgement", userID: userID
        )
    }

    private func preserve(
        _ snapshot: ATHLTHAudioCoachAccountSnapshot,
        name: String, userID: UUID
    ) {
        AccountLocalStorage.write(snapshot, name: name, userID: userID)
    }

    private func fingerprint(_ snapshot: ATHLTHAudioCoachAccountSnapshot) throws -> String {
        var comparable = snapshot
        // Different clocks must not force uploads for identical content.
        comparable.editedAt = .distantPast
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let bytes = try encoder.encode(comparable)
        return bytes.base64EncodedString()
    }
}
