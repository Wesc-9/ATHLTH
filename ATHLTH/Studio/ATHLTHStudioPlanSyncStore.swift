import Combine
import CryptoKit
import Foundation
import Supabase

/// Optional, account-scoped synchronization of *planned* training programs.
/// This never uploads HealthKit samples, completed workout data or GPS traces.
/// Plans can still contain manually entered personal notes, so consent starts off.
@MainActor
final class ATHLTHStudioPlanSyncStore: ObservableObject {
    struct Conflict: Identifiable, Hashable {
        let id: UUID
        let title: String
    }

    @Published private(set) var enabled = false
    @Published private(set) var isBusy = false
    @Published private(set) var conflicts: [Conflict] = []
    @Published private(set) var status = "Plan sync is off."
    @Published private(set) var lastSuccessfulSync: Date?

    private struct ConsentWrite: Encodable {
        let user_id: UUID
        let enabled: Bool
    }
    private struct RemotePlan: Decodable {
        let plan_id: UUID
        let revision: Int64
        let body_base64: String
    }
    private struct SaveParams: Encodable {
        let p_plan_id: UUID
        let p_expected_revision: Int64
        let p_body_base64: String
    }

    private let client = SupabaseEnvironment.client
    private var accountID: UUID?
    private var acknowledgements: [String: ATHLTHStudioPlanSyncDecision.Acknowledgement] = [:]
    private var scheduledTask: Task<Void, Never>?

    func switchAccount(_ userID: UUID?) {
        guard accountID != userID else { return }
        scheduledTask?.cancel()
        scheduledTask = nil
        accountID = userID
        conflicts = []
        isBusy = false
        enabled = userID.flatMap {
            AccountLocalStorage.read(
                Bool.self, name: "studioPlanSyncConsent", userID: $0
            )
        } ?? false
        acknowledgements = userID.flatMap {
            AccountLocalStorage.read(
                [String: ATHLTHStudioPlanSyncDecision.Acknowledgement].self,
                name: "studioPlanSyncAcknowledgements",
                userID: $0
            )
        } ?? [:]
        status = enabled
            ? ATHLTHLocalization.choose(
                english: "Plan sync is enabled on this device.",
                norwegian: "Plansynkronisering er aktivert på denne enheten."
              )
            : ATHLTHLocalization.choose(
                english: "Plan sync is off.",
                norwegian: "Plansynkronisering er av."
              )
    }

    func setEnabled(_ shouldEnable: Bool, session: AppSessionStore) async {
        guard !isBusy, session.signedIn,
              accountID == session.profile.userID
        else { return }

        let userID = session.profile.userID
        isBusy = true
        defer { isBusy = false }
        if shouldEnable {
            do {
                guard client.auth.currentUser?.id == userID else {
                    throw NSError(
                        domain: "ATHLTH.PlanSync", code: 401,
                        userInfo: [NSLocalizedDescriptionKey:
                            "An online signed-in session is required to enable synchronization."]
                    )
                }
                try await client.from("studio_plan_sync_consents")
                    .upsert(ConsentWrite(user_id: userID, enabled: true),
                            onConflict: "user_id")
                    .execute()
                guard accountID == userID else { return }
                enabled = true
                AccountLocalStorage.write(
                    true, name: "studioPlanSyncConsent", userID: userID
                )
                status = ATHLTHLocalization.choose(
                    english: "Plan sync enabled. Check for changes on this device or the other device.",
                    norwegian: "Plansynkronisering er aktivert. Se etter endringer på denne eller den andre enheten."
                )
            } catch {
                status = ATHLTHLocalization.choose(
                    english: "Could not enable plan sync: ",
                    norwegian: "Kunne ikke aktivere plansynkronisering: "
                ) + error.localizedDescription
            }
        } else {
            // Immediately stop new network work, even if remote deletion fails.
            enabled = false
            scheduledTask?.cancel()
            AccountLocalStorage.write(
                false, name: "studioPlanSyncConsent", userID: userID
            )
            do {
                // Delete documents *before* revoking consent. RLS requires consent
                // for access, so reversing this order would strand the copies.
                try await client.from("studio_plan_documents")
                    .delete().eq("user_id", value: userID).execute()
                try await client.from("studio_plan_sync_consents")
                    .delete().eq("user_id", value: userID).execute()
                guard accountID == userID else { return }
                acknowledgements = [:]
                persistAcknowledgements(for: userID)
                conflicts = []
                status = ATHLTHLocalization.choose(
                    english: "Plan sync stopped; remote plan copies deleted. Your local plans remain.",
                    norwegian: "Plansynkronisering stoppet og sky-kopier slettet. Lokale planer er beholdt."
                )
            } catch {
                status = ATHLTHLocalization.choose(
                    english: "Plan sync stopped on this device, but cloud copies could not be confirmed deleted. Reconnect and try disabling again: ",
                    norwegian: "Synkronisering stoppet lokalt, men sletting av sky-kopier er ikke bekreftet. Koble til og prøv å slå av igjen: "
                ) + error.localizedDescription
            }
        }
    }

    func scheduleSync(session: AppSessionStore) {
        guard enabled, accountID == session.profile.userID, session.signedIn else { return }
        scheduledTask?.cancel()
        scheduledTask = Task { [weak self, weak session] in
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled, let self, let session else { return }
            await self.sync(session: session)
        }
    }

    func sync(session: AppSessionStore) async {
        guard enabled, !isBusy, session.signedIn,
              let userID = accountID, userID == session.profile.userID,
              client.auth.currentUser?.id == userID
        else { return }

        isBusy = true
        defer { isBusy = false }
        var unresolved: [Conflict] = []

        do {
            let remoteRows: [RemotePlan] = try await client
                .from("studio_plan_documents")
                .select("plan_id,revision,body_base64")
                .eq("user_id", value: userID)
                .limit(250)
                .execute().value
            guard enabled, accountID == userID else { return }

            let remoteByID = Dictionary(uniqueKeysWithValues: remoteRows.map {
                ($0.plan_id, $0)
            })
            let localPlans = session.trainingPlans.filter { $0.ownerID == userID }
            let localByID = Dictionary(uniqueKeysWithValues: localPlans.map { ($0.id, $0) })
            let allIDs = Set(remoteByID.keys).union(localByID.keys)

            for planID in allIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard enabled, accountID == userID else { return }

                let local = localByID[planID]
                let remote = remoteByID[planID]
                let localFingerprint = try local.map { try fingerprint(for: $0) }
                let remotePlan = try remote.flatMap { try decode($0.body_base64, owner: userID, id: planID) }
                let remoteFingerprint = try remotePlan.map { try fingerprint(for: $0) }
                let previous = acknowledgements[planID.uuidString]
                let action = ATHLTHStudioPlanSyncDecision.choose(
                    localFingerprint: localFingerprint,
                    remoteFingerprint: remoteFingerprint,
                    remoteRevision: remote?.revision,
                    acknowledged: previous
                )

                switch action {
                case .unchanged:
                    if let remote, let remoteFingerprint {
                        acknowledge(planID, revision: remote.revision,
                                    fingerprint: remoteFingerprint, owner: userID)
                    }
                case let .upload(expected):
                    guard let local,
                          session.trainingPlan(withID: planID) == local else {
                        unresolved.append(Conflict(id: planID, title: local?.title ?? "Training plan"))
                        continue
                    }
                    do {
                        let revision = try await save(local, expected: expected)
                        guard accountID == userID else { return }
                        acknowledge(planID, revision: revision,
                                    fingerprint: localFingerprint ?? "", owner: userID)
                    } catch {
                        // CAS detects remote edits between fetch and save.
                        unresolved.append(Conflict(id: planID, title: local.title))
                    }
                case .download:
                    guard let remote, let remotePlan else { continue }
                    // Never replace a plan edited while the network call was pending.
                    guard session.trainingPlan(withID: planID) == local,
                          session.addTrainingPlan(remotePlan) else {
                        unresolved.append(Conflict(id: planID, title: remotePlan.title))
                        continue
                    }
                    acknowledge(planID, revision: remote.revision,
                                fingerprint: remoteFingerprint ?? "", owner: userID)
                case .conflict:
                    unresolved.append(Conflict(
                        id: planID, title: local?.title ?? remotePlan?.title ?? "Training plan"
                    ))
                }
            }

            conflicts = unresolved
            lastSuccessfulSync = Date()
            status = unresolved.isEmpty
                ? ATHLTHLocalization.choose(
                    english: "Training plans are up to date on this device.",
                    norwegian: "Treningsplanene er oppdatert på denne enheten."
                  )
                : ATHLTHLocalization.choose(
                    english: "\(unresolved.count) plan conflict(s) need your decision. No changes were overwritten.",
                    norwegian: "\(unresolved.count) plankonflikt(er) krever et valg. Ingen endringer ble overskrevet."
                  )
        } catch {
            if accountID == userID {
                status = ATHLTHLocalization.choose(
                    english: "Could not sync plans. Local changes remain safe: ",
                    norwegian: "Kunne ikke synkronisere. Lokale endringer er bevart: "
                ) + error.localizedDescription
            }
        }
    }

    /// User-controlled conflict resolution; never auto-select by timestamp.
    func resolve(
        planID: UUID,
        preferRemote: Bool,
        session: AppSessionStore
    ) async {
        guard enabled, !isBusy,
              let userID = accountID,
              userID == session.profile.userID, session.signedIn
        else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let rows: [RemotePlan] = try await client.from("studio_plan_documents")
                .select("plan_id,revision,body_base64")
                .eq("user_id", value: userID)
                .eq("plan_id", value: planID)
                .limit(1).execute().value
            guard accountID == userID, enabled else { return }
            guard let row = rows.first else {
                status = ATHLTHLocalization.choose(
                    english: "Remote plan no longer exists. Sync again.",
                    norwegian: "Sky-planen finnes ikke lenger. Synkroniser på nytt."
                )
                return
            }

            if preferRemote {
                guard let decoded = try decode(row.body_base64, owner: userID, id: planID),
                      session.addTrainingPlan(decoded) else {
                    status = ATHLTHLocalization.choose(
                        english: "Cannot import plan while another plan conflicts in the calendar.",
                        norwegian: "Planen kan ikke importeres på grunn av en overlappende kalenderplan."
                    )
                    return
                }
                acknowledge(planID, revision: row.revision,
                            fingerprint: try fingerprint(for: decoded), owner: userID)
            } else {
                guard let local = session.trainingPlan(withID: planID) else { return }
                let revision = try await save(local, expected: row.revision)
                guard accountID == userID else { return }
                acknowledge(planID, revision: revision,
                            fingerprint: try fingerprint(for: local), owner: userID)
            }
            conflicts.removeAll { $0.id == planID }
            status = ATHLTHLocalization.choose(
                english: "Plan conflict resolved.", norwegian: "Plankonflikten er løst."
            )
        } catch {
            status = ATHLTHLocalization.choose(
                english: "Conflict changed while resolving. Sync again: ",
                norwegian: "Konflikten endret seg under lagring. Synkroniser igjen: "
            ) + error.localizedDescription
        }
    }

    private func save(_ plan: TrainingPlan, expected: Int64) async throws -> Int64 {
        guard enabled, accountID == plan.ownerID else {
            throw NSError(domain: "ATHLTH.PlanSync", code: 1)
        }
        let encoded = try JSONEncoder().encode(plan)
        guard encoded.count <= 2_000_000 else {
            throw NSError(domain: "ATHLTH.PlanSync", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Plan exceeds safe cloud size limit."])
        }
        let params = SaveParams(
            p_plan_id: plan.id,
            p_expected_revision: expected,
            p_body_base64: encoded.base64EncodedString()
        )
        let revision: Int64 = try await client
            .rpc("studio_save_plan", params: params).execute().value
        return revision
    }

    private func decode(_ base64: String, owner: UUID, id: UUID) throws -> TrainingPlan? {
        guard let data = Data(base64Encoded: base64), data.count <= 2_000_000 else {
            throw NSError(domain: "ATHLTH.PlanSync", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid remote plan payload."])
        }
        let plan = try JSONDecoder().decode(TrainingPlan.self, from: data)
        guard plan.ownerID == owner, plan.id == id else {
            throw NSError(domain: "ATHLTH.PlanSync", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Remote plan owner/identity mismatch."])
        }
        return plan
    }

    private func fingerprint(for plan: TrainingPlan) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let bytes = try encoder.encode(plan)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private func acknowledge(
        _ planID: UUID, revision: Int64, fingerprint: String, owner: UUID
    ) {
        acknowledgements[planID.uuidString] = .init(
            revision: revision, fingerprint: fingerprint
        )
        persistAcknowledgements(for: owner)
    }

    private func persistAcknowledgements(for userID: UUID) {
        AccountLocalStorage.write(
            acknowledgements, name: "studioPlanSyncAcknowledgements", userID: userID
        )
    }
}
