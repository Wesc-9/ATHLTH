import Combine
import CryptoKit
import Foundation
import Supabase

/// Account-scoped synchronization of planned programs and reusable templates.
/// This never uploads HealthKit samples, completed workout data or GPS traces.
/// Account sync is part of authenticated plans. Legacy explicit opt-outs remain respected.
@MainActor
final class ATHLTHStudioPlanSyncStore: ObservableObject {
    struct Conflict: Identifiable, Hashable {
        let id: UUID
        let title: String
    }

    @Published private(set) var enabled = false
    @Published private(set) var isBusy = false
    @Published private(set) var conflicts: [Conflict] = []
    @Published private(set) var status = "Sign in to synchronize training plans."
    @Published private(set) var lastSuccessfulSync: Date?

    private struct ConsentWrite: Codable {
        let user_id: UUID
        let enabled: Bool
    }
    private struct RemotePlan: Decodable {
        let plan_id: UUID
        let revision: Int64
        let body_base64: String
    }
    private struct DeletedPlan: Decodable {
        let plan_id: UUID
    }
    private struct SaveParams: Encodable {
        let p_plan_id: UUID
        let p_expected_revision: Int64
        let p_body_base64: String
    }

    // MainActor serializes plan writes across multiple Stage Manager windows
    // using different ATHLTHStudioPlanSyncStore instances for one account.
    private static var accountsWithNetworkMutation = Set<UUID>()

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
        // Existing explicit opt-outs must not be silently reversed by an update.
        enabled = userID.map {
            AccountLocalStorage.read(
                Bool.self, name: "studioPlanSyncConsent", userID: $0
            ) != false
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
                english: "Your signed-in training plans sync across devices.",
                norwegian: "Treningsplanene synkroniseres gjennom kontoen din."
              )
            : ATHLTHLocalization.choose(
                english: "Sign in to sync or review your previous privacy choice.",
                norwegian: "Logg inn for å synkronisere, eller se ditt tidligere personvernvalg."
              )
    }

    /// Upgrades an explicit legacy opt-out only on the user's request.
    /// New accounts do not require an additional synchronization switch.
    func acknowledgeLegacyOptOut(session: AppSessionStore) async {
        guard session.signedIn, accountID == session.profile.userID,
              client.auth.currentUser?.id == session.profile.userID else { return }
        let userID = session.profile.userID
        do {
            try await client.from("studio_plan_sync_consents")
                .upsert(ConsentWrite(user_id: userID, enabled: true),
                        onConflict: "user_id").execute()
            guard accountID == userID else { return }
            AccountLocalStorage.write(true, name: "studioPlanSyncConsent", userID: userID)
            enabled = true
            scheduleSync(session: session)
        } catch {
            status = ATHLTHLocalization.choose(
                english: "Could not update the previous sync preference: ",
                norwegian: "Kunne ikke oppdatere tidligere synkroniseringsvalg: "
            ) + error.localizedDescription
        }
    }

    func scheduleSync(session: AppSessionStore) {
        guard session.signedIn else { return }
        switchAccount(session.profile.userID)
        scheduledTask?.cancel()
        scheduledTask = Task { [weak self, weak session] in
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled, let self, let session else { return }
            await self.sync(session: session)
        }
    }

    func sync(session: AppSessionStore) async {
        guard !isBusy, session.signedIn,
              let userID = accountID, userID == session.profile.userID,
              client.auth.currentUser?.id == userID
        else { return }

        guard !Self.accountsWithNetworkMutation.contains(userID) else {
            status = ATHLTHLocalization.choose(
                english: "Another ATHLTH window is synchronizing this account.",
                norwegian: "Et annet ATHLTH-vindu synkroniserer denne kontoen."
            )
            return
        }
        Self.accountsWithNetworkMutation.insert(userID)
        isBusy = true
        defer {
            Self.accountsWithNetworkMutation.remove(userID)
            isBusy = false
        }
        var unresolved: [Conflict] = []

        do {
            // Legacy opt-outs remain a hard block until the user explicitly
            // acknowledges the change. New accounts need no separate opt-in.
            let preferences: [ConsentWrite] = try await client.from("studio_plan_sync_consents")
                .select("user_id,enabled").eq("user_id", value: userID).limit(1).execute().value
            guard accountID == userID else { return }
            if preferences.first?.enabled == false ||
                AccountLocalStorage.read(
                    Bool.self, name: "studioPlanSyncConsent", userID: userID
                ) == false {
                enabled = false
                status = ATHLTHLocalization.choose(
                    english: "Your previous sync opt-out is respected. Review it in account settings.",
                    norwegian: "Tidligere fravalg av synkronisering er beholdt. Se kontoinnstillinger."
                )
                return
            }
            enabled = true
            // Fetch every page before interpreting an absent document as deleted.
            var remoteRows: [RemotePlan] = []
            let pageSize = 250
            while true {
                let page: [RemotePlan] = try await client
                    .from("studio_plan_documents")
                    .select("plan_id,revision,body_base64")
                    .eq("user_id", value: userID)
                    .order("plan_id")
                    .range(from: remoteRows.count, to: remoteRows.count + pageSize - 1)
                    .execute().value
                guard enabled, accountID == userID else { return }
                remoteRows.append(contentsOf: page)
                if page.count < pageSize { break }
            }

            guard enabled, accountID == userID else { return }

            let remoteByID = Dictionary(uniqueKeysWithValues: remoteRows.map {
                ($0.plan_id, $0)
            })
            let localPlans = session.accountPlanDocuments.filter { $0.ownerID == userID }
            // Corrupted/legacy duplicate local plan IDs must never crash sync.
            let localByID = Dictionary(
                localPlans.map { ($0.id, $0) },
                uniquingKeysWith: { first, second in
                    first.updatedAt >= second.updatedAt ? first : second
                }
            )
            let allIDs = Set(remoteByID.keys).union(localByID.keys)

            // Reconcile sanitized account copies, not private device notes.
            for planID in allIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard enabled, accountID == userID else { return }

                let local = localByID[planID]
                let remote = remoteByID[planID]
                let localFingerprint = try local.map { try fingerprint(for: Self.accountCopy(of: $0)) }
                let remotePlan = try remote.flatMap { try decode($0.body_base64, owner: userID, id: planID) }
                let remoteFingerprint = try remotePlan.map { try fingerprint(for: Self.accountCopy(of: $0)) }
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
                          session.accountPlanDocument(withID: planID) == local else {
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
                    guard session.accountPlanDocument(withID: planID) == local,
                          session.importAccountPlanDocument(
                              Self.restoringDeviceOnlyFields(
                                  from: local, into: Self.accountCopy(of: remotePlan)
                              )
                          ) else {
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
                    english: "Account plans are up to date. Private notes stay on this device.",
                    norwegian: "Kontoplanene er oppdatert. Private notater beholdes på denne enheten."
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
              userID == session.profile.userID, session.signedIn,
              client.auth.currentUser?.id == userID
        else { return }
        // A historic opt-out also blocks conflict resolution.
        guard enabled,
              AccountLocalStorage.read(
                  Bool.self, name: "studioPlanSyncConsent", userID: userID
              ) != false else { return }
        guard !Self.accountsWithNetworkMutation.contains(userID) else {
            status = ATHLTHLocalization.choose(
                english: "Plan changes are in progress in another window.",
                norwegian: "Planendringer pågår i et annet vindu."
            )
            return
        }
        Self.accountsWithNetworkMutation.insert(userID)
        isBusy = true
        defer {
            Self.accountsWithNetworkMutation.remove(userID)
            isBusy = false
        }
        do {
            // Capture the exact document the athlete reviewed. A later
            // on-device edit must not be overwritten by a stale resolution.
            let reviewedLocal = session.accountPlanDocument(withID: planID)
            let rows: [RemotePlan] = try await client.from("studio_plan_documents")
                .select("plan_id,revision,body_base64")
                .eq("user_id", value: userID)
                .eq("plan_id", value: planID)
                .limit(1).execute().value
            guard accountID == userID, enabled,
                  session.accountPlanDocument(withID: planID) == reviewedLocal else {
                status = ATHLTHLocalization.choose(
                    english: "The plan changed while reviewing. Check the current version before deciding.",
                    norwegian: "Planen ble endret under gjennomgangen. Kontroller den oppdaterte versjonen før du velger."
                )
                return
            }
            if let row = rows.first {
                if preferRemote {
                    guard let decoded = try decode(row.body_base64, owner: userID, id: planID),
                          session.importAccountPlanDocument(
                              Self.restoringDeviceOnlyFields(
                                  from: session.accountPlanDocument(withID: planID),
                                  into: Self.accountCopy(of: decoded)
                              )
                          ) else {
                        status = ATHLTHLocalization.choose(
                            english: "Cannot import plan while another plan conflicts in the calendar.",
                            norwegian: "Planen kan ikke importeres på grunn av en overlappende kalenderplan."
                        )
                        return
                    }
                    acknowledge(planID, revision: row.revision,
                                fingerprint: try fingerprint(for: decoded), owner: userID)
                } else if let local = reviewedLocal {
                    let revision = try await save(local, expected: row.revision)
                    guard accountID == userID else { return }
                    acknowledge(planID, revision: revision,
                                fingerprint: try fingerprint(for: local), owner: userID)
                } else {
                    // Explicitly keep the local deletion, but only if the
                    // remote revision still matches the one the user reviewed.
                    let removed: [DeletedPlan] = try await client
                        .from("studio_plan_documents")
                        .delete()
                        .eq("user_id", value: userID)
                        .eq("plan_id", value: planID)
                        .eq("revision", value: String(row.revision))
                        .select("plan_id")
                        .execute().value
                    guard removed.count == 1 else {
                        throw NSError(domain: "ATHLTH.PlanSync", code: 409,
                            userInfo: [NSLocalizedDescriptionKey: "Remote revision changed."])
                    }
                    acknowledgements.removeValue(forKey: planID.uuidString)
                    persistAcknowledgements(for: userID)
                }
            } else if preferRemote {
                // Remote absence is meaningful only after explicit conflict
                // review. Never delete local plans automatically in sync().
                if session.accountPlanDocument(withID: planID) != nil {
                    session.deleteAccountPlanDocument(planID)
                }
                acknowledgements.removeValue(forKey: planID.uuidString)
                persistAcknowledgements(for: userID)
            } else if let local = reviewedLocal {
                // Recreate a previously deleted cloud copy only after the
                // athlete explicitly chooses to keep their local plan.
                let revision = try await save(local, expected: 0)
                guard accountID == userID else { return }
                acknowledge(planID, revision: revision,
                            fingerprint: try fingerprint(for: local), owner: userID)
            } else {
                status = ATHLTHLocalization.choose(
                    english: "The plan no longer exists on either device.",
                    norwegian: "Planen finnes ikke lenger på noen av enhetene."
                )
                return
            }
            guard accountID == userID else { return }
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

    /// Only structured plan prescriptions cross devices. Free-form health,
    /// injury and location notes stay with the original device. A projection
    /// is also used for fingerprints, so editing a private note does not
    /// produce a false sync conflict.
    static func accountCopy(of plan: TrainingPlan) -> TrainingPlan {
        var copy = plan
        copy.summary = ""
        copy.builderProfile?.injuriesOrLimitations = nil
        copy.builderProfile?.goalDetail = nil
        copy.trainingBlocks = copy.trainingBlocks?.map { block in
            var clean = block
            clean.goal = ""
            return clean
        }
        copy.weeks = copy.weeks.map { week in
            var updatedWeek = week
            updatedWeek.days = week.days.map { day in
                var updatedDay = day
                updatedDay.sessions = day.sessions.map { workout in
                    var clean = workout
                    clean.notes = nil
                    clean.meetingPoint = nil
                    clean.plannedTrainingPlace = nil
                    // Recovery snapshots may retain full exercise notes even
                    // after the current exercise has been sanitized.
                    clean.recoveryOriginalExercises = nil
                    clean.recoveryAdjustedExercises = nil
                    // A previous one-day replacement can contain an entire
                    // historical workout including private user-entered text.
                    clean.dailyAlternativeOriginal = nil
                    // Nested structured blocks also carry free-text fields.
                    clean.workoutBlocks = clean.workoutBlocks?.map { block in
                        var safeBlock = block
                        safeBlock.notes = nil
                        safeBlock.loadNote = nil
                        return safeBlock
                    }
                    clean.exercises = workout.exercises.map { exercise in
                        var cleaned = exercise
                        cleaned.notes = nil
                        cleaned.setTargets = cleaned.setTargets?.map { target in
                            var set = target
                            set.notes = nil
                            return set
                        }
                        return cleaned
                    }
                    return clean
                }
                return updatedDay
            }
            return updatedWeek
        }
        return copy
    }

    /// Reattach this device's notes to matching document identities after
    /// importing a cloud copy; never apply private fields to a new account.
    static func restoringDeviceOnlyFields(
        from local: TrainingPlan?,
        into remote: TrainingPlan
    ) -> TrainingPlan {
        guard let local, local.id == remote.id,
              local.ownerID == remote.ownerID else { return remote }
        var restored = remote
        restored.summary = local.summary
        restored.builderProfile?.injuriesOrLimitations =
            local.builderProfile?.injuriesOrLimitations
        restored.builderProfile?.goalDetail = local.builderProfile?.goalDetail
        restored.trainingBlocks = restored.trainingBlocks?.map { block in
            var merged = block
            if let old = local.trainingBlocks?.first(where: { $0.id == block.id }) {
                merged.goal = old.goal
            }
            return merged
        }
        restored.weeks = restored.weeks.map { week in
            var mergedWeek = week
            mergedWeek.days = week.days.map { day in
                var mergedDay = day
                mergedDay.sessions = day.sessions.map { workout in
                    var merged = workout
                    if let old = local.weeks.flatMap(\.days)
                        .flatMap(\.sessions).first(where: { $0.id == workout.id }) {
                        merged.notes = old.notes
                        merged.meetingPoint = old.meetingPoint
                        merged.plannedTrainingPlace = old.plannedTrainingPlace
                        merged.recoveryOriginalExercises = old.recoveryOriginalExercises
                        merged.recoveryAdjustedExercises = old.recoveryAdjustedExercises
                        merged.dailyAlternativeOriginal = old.dailyAlternativeOriginal
                        merged.workoutBlocks = merged.workoutBlocks?.map { block in
                            var result = block
                            if let previous = old.workoutBlocks?.first(where: {
                                $0.sequence == block.sequence && $0.kind == block.kind
                            }) {
                                result.notes = previous.notes
                                result.loadNote = previous.loadNote
                            }
                            return result
                        }
                        merged.exercises = merged.exercises.map { exercise in
                            var clean = exercise
                            if let oldExercise = old.exercises.first(where: { $0.id == exercise.id }) {
                                clean.notes = oldExercise.notes
                                clean.setTargets = clean.setTargets?.map { target in
                                    var set = target
                                    if let oldSet = oldExercise.setTargets?.first(where: { $0.id == target.id }) {
                                        set.notes = oldSet.notes
                                    }
                                    return set
                                }
                            }
                            return clean
                        }
                    }
                    return merged
                }
                return mergedDay
            }
            return mergedWeek
        }
        return restored
    }

    private func save(_ plan: TrainingPlan, expected: Int64) async throws -> Int64 {
        // All upload paths, including conflict resolution, use the same
        // privacy-preserving account projection.
        guard enabled, accountID == plan.ownerID else {
            throw NSError(domain: "ATHLTH.PlanSync", code: 1)
        }
        let encoded = try JSONEncoder().encode(Self.accountCopy(of: plan))
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
        try Self.accountFingerprint(for: plan)
    }

    // Exposed to the internal XCTest target so private-note changes can be
    // verified not to generate spurious cross-device sync conflicts.
    static func accountFingerprint(for plan: TrainingPlan) throws -> String {
        var comparable = accountCopy(of: plan)
        // Local-only note edits can advance local document metadata. Those
        // fields are not independently meaningful in shared-content comparison.
        comparable.version = 0
        comparable.updatedAt = comparable.createdAt
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let bytes = try encoder.encode(comparable)
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
