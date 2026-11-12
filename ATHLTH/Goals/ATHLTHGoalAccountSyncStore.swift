import Combine
import Foundation
import Supabase
import UIKit

/// A private copy of one goal plus a compact preview of its custom cover.
/// Images are account data, NOT public/social profile media.
struct ATHLTHCloudGoal: Codable, Equatable, Identifiable {
    var goal: ATHLTHGoal
    var coverBase64: String?

    var id: UUID { goal.id }
}

struct ATHLTHCloudGoalDocument: Codable, Equatable {
    let goals: [ATHLTHCloudGoal]
    let measurements: [ATHLTHBodyMeasurement]
}

/// Three-way reconciliation: independent edits on different devices merge.
/// Concurrent changes to the same goal are held as conflicts rather than
/// silently overwriting either copy. Removal is treated as an actual edit.
enum ATHLTHGoalMergePolicy {
    struct Result {
        let merged: [ATHLTHCloudGoal]
        let conflictingIDs: [UUID]
    }

    static func reconcile(
        base: [ATHLTHCloudGoal],
        local: [ATHLTHCloudGoal],
        remote: [ATHLTHCloudGoal]
    ) -> Result {
        let baseline = Dictionary(base.map { ($0.id, $0) },
                                  uniquingKeysWith: { old, _ in old })
        let localItems = Dictionary(local.map { ($0.id, $0) },
                                    uniquingKeysWith: { old, _ in old })
        let remoteItems = Dictionary(remote.map { ($0.id, $0) },
                                     uniquingKeysWith: { old, _ in old })
        let ids = Set(baseline.keys).union(localItems.keys).union(remoteItems.keys)
        var merged: [ATHLTHCloudGoal] = []
        var conflicts: [UUID] = []

        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            let baseValue = baseline[id]
            let localValue = localItems[id]
            let remoteValue = remoteItems[id]
            let selected: ATHLTHCloudGoal?

            if localValue == remoteValue {
                selected = localValue
            } else if localValue == baseValue {
                selected = remoteValue
            } else if remoteValue == baseValue {
                selected = localValue
            } else {
                conflicts.append(id)
                continue
            }
            if let selected { merged.append(selected) }
        }

        return Result(merged: merged, conflictingIDs: conflicts)
    }

    struct MeasurementResult {
        let merged: [ATHLTHBodyMeasurement]
        let conflictingIDs: [UUID]
    }

    static func reconcileMeasurements(
        base: [ATHLTHBodyMeasurement],
        local: [ATHLTHBodyMeasurement],
        remote: [ATHLTHBodyMeasurement]
    ) -> MeasurementResult {
        let b = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { old, _ in old })
        let l = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { old, _ in old })
        let r = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { old, _ in old })
        var merged: [ATHLTHBodyMeasurement] = []
        var conflicts: [UUID] = []
        for id in Set(b.keys).union(l.keys).union(r.keys)
            .sorted(by: { $0.uuidString < $1.uuidString }) {
            let chosen: ATHLTHBodyMeasurement?
            if l[id] == r[id] { chosen = l[id] }
            else if l[id] == b[id] { chosen = r[id] }
            else if r[id] == b[id] { chosen = l[id] }
            else { conflicts.append(id); continue }
            if let chosen { merged.append(chosen) }
        }
        return MeasurementResult(merged: merged, conflictingIDs: conflicts)
    }

    static func ordered(_ values: [ATHLTHBodyMeasurement]) -> [ATHLTHBodyMeasurement] {
        values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    static func ordered(_ items: [ATHLTHCloudGoal]) -> [ATHLTHCloudGoal] {
        items.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

/// Offline-first synchronization. A failed network request never destroys a
/// locally saved goal. Every write to Supabase uses an atomic server revision.
/// Changes to health measurements themselves remain outside this payload.
@MainActor
final class ATHLTHGoalAccountSyncStore: ObservableObject {
    @Published private(set) var status = ""
    @Published private(set) var isSyncing = false
    @Published private(set) var conflictingGoalIDs: [UUID] = []
    @Published private(set) var conflictingMeasurementIDs: [UUID] = []
    @Published private(set) var lastSuccessfulSync: Date?
    @Published private(set) var lastSyncError: String?

    private struct RemoteDocument: Decodable {
        let revision: Int64
        let body_base64: String
    }

    private struct SaveParams: Encodable {
        let p_expected_revision: Int64
        let p_body_base64: String
    }

    private struct Acknowledgement: Codable {
        let revision: Int64
        let goals: [ATHLTHCloudGoal]
        let measurements: [ATHLTHBodyMeasurement]
    }

    private static var activeAccounts = Set<UUID>()
    private let client = SupabaseEnvironment.client
    private var accountID: UUID?
    private var scheduledTask: Task<Void, Never>?
    private var acknowledgement: Acknowledgement?

    func switchAccount(_ userID: UUID?) {
        guard accountID != userID else { return }
        scheduledTask?.cancel()
        scheduledTask = nil
        accountID = userID
        isSyncing = false
        conflictingGoalIDs = []
        conflictingMeasurementIDs = []
        lastSuccessfulSync = nil
        lastSyncError = nil
        acknowledgement = userID.flatMap {
            AccountLocalStorage.read(
                Acknowledgement.self, name: "goalAccountSyncAcknowledgement", userID: $0
            )
        }
        status = userID == nil ? "" : ATHLTHLocalization.choose(
            english: "Goals are saved offline and synchronize with your account.",
            norwegian: "Mål lagres uten nett og synkroniseres med kontoen."
        )
    }

    func scheduleSync(session: AppSessionStore, goals: GoalStore) {
        guard session.signedIn else { return }
        switchAccount(session.profile.userID)
        // Debounce high-frequency updates, including automatic milestone writes.
        scheduledTask?.cancel()
        scheduledTask = Task { [weak self, weak session, weak goals] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.scheduledTask = nil
            guard let self, let session, let goals else { return }
            await self.sync(session: session, goals: goals)
        }
    }

    func sync(session: AppSessionStore, goals: GoalStore) async {
        guard !isSyncing, session.signedIn,
              let userID = accountID, userID == session.profile.userID,
              goals.ownerAccountID == userID,
              client.auth.currentUser?.id == userID
        else { return }
        guard !Self.activeAccounts.contains(userID) else { return }
        Self.activeAccounts.insert(userID)
        isSyncing = true
        defer {
            Self.activeAccounts.remove(userID)
            isSyncing = false
        }

        let capturedLocalGoals = goals.goals
        let capturedMeasurements = ATHLTHTrainingProfile.load(userID: userID).measurements
        let baseItems = acknowledgement?.goals ?? []
        let baseMeasurements = acknowledgement?.measurements ?? []
        do {
            let localItems = try Self.capture(
                goals: capturedLocalGoals, baseline: baseItems, from: goals
            )
            let rows: [RemoteDocument] = try await client
                .from("athlth_goal_documents")
                .select("revision,body_base64")
                .eq("user_id", value: userID)
                .limit(1)
                .execute().value
            guard accountID == userID, session.profile.userID == userID,
                  goals.ownerAccountID == userID,
                  client.auth.currentUser?.id == userID else { return }

            let remoteRevision = rows.first?.revision ?? 0
            let document = try rows.first.map { try Self.decode($0.body_base64) }
                ?? ATHLTHCloudGoalDocument(goals: [], measurements: [])
            let remoteItems = document.goals
            let remoteMeasurements = document.measurements
            let result = ATHLTHGoalMergePolicy.reconcile(
                base: baseItems, local: localItems, remote: remoteItems
            )
            let measurementResult = ATHLTHGoalMergePolicy.reconcileMeasurements(
                base: baseMeasurements, local: capturedMeasurements, remote: remoteMeasurements
            )

            guard result.conflictingIDs.isEmpty,
                  measurementResult.conflictingIDs.isEmpty else {
                conflictingGoalIDs = result.conflictingIDs
                conflictingMeasurementIDs = measurementResult.conflictingIDs
                status = ATHLTHLocalization.choose(
                    english: "Some goals were edited on both devices. Both copies are preserved; review the conflict before overwriting.",
                    norwegian: "Noen mål er endret på begge enheter. Begge kopier er beholdt; kontroller konflikten før noe overskrives."
                )
                return
            }

            // Local goals could change while the remote request is pending.
            guard goals.goals == capturedLocalGoals,
                  ATHLTHTrainingProfile.load(userID: userID).measurements == capturedMeasurements else {
                scheduleSync(session: session, goals: goals)
                return
            }
            let merged = ATHLTHGoalMergePolicy.ordered(result.merged)
            let mergedMeasurements = ATHLTHGoalMergePolicy.ordered(measurementResult.merged)
            let remote = ATHLTHGoalMergePolicy.ordered(remoteItems)
            let remoteMeasurementsSorted = ATHLTHGoalMergePolicy.ordered(remoteMeasurements)

            var effectiveRevision = remoteRevision
            var didUpload = false
            if merged != remote || mergedMeasurements != remoteMeasurementsSorted {
                let encoded = try Self.encode(ATHLTHCloudGoalDocument(
                    goals: merged, measurements: mergedMeasurements
                ))
                effectiveRevision = try await client
                    .rpc(
                        "athlth_save_goal_document",
                        params: SaveParams(
                            p_expected_revision: remoteRevision,
                            p_body_base64: encoded
                        )
                    )
                    .execute().value
                didUpload = true
            }
            guard accountID == userID, session.profile.userID == userID,
                  goals.ownerAccountID == userID,
                  client.auth.currentUser?.id == userID else { return }

            // Do not replace a more recent edit made during the upload.
            guard goals.goals == capturedLocalGoals,
                  ATHLTHTrainingProfile.load(userID: userID).measurements == capturedMeasurements else {
                // Our uploaded snapshot must be acknowledged before merging
                // a newer edit created while the network call was pending.
                if didUpload {
                    saveAcknowledgement(
                        goals: merged, measurements: mergedMeasurements,
                        revision: effectiveRevision, userID: userID
                    )
                }
                scheduleSync(session: session, goals: goals)
                return
            }
            if merged != ATHLTHGoalMergePolicy.ordered(localItems) {
                try applySnapshot(merged, previous: localItems, to: goals, accountID: userID)
            }
            if mergedMeasurements != ATHLTHGoalMergePolicy.ordered(capturedMeasurements) {
                var profile = ATHLTHTrainingProfile.load(userID: userID)
                profile.measurements = mergedMeasurements
                profile.updatedAt = .now
                profile.save(userID: userID)
                NotificationCenter.default.post(name: .athlthTrainingDataDidChange, object: nil)
            }
            // Commit the acknowledgement only after all imported files/data
            // were persisted. A failed photo write must never clear remote goals.
            saveAcknowledgement(
                goals: merged, measurements: mergedMeasurements,
                revision: effectiveRevision, userID: userID
            )
            conflictingGoalIDs = []
            conflictingMeasurementIDs = []
            lastSyncError = nil
            lastSuccessfulSync = .now
            status = ATHLTHLocalization.choose(
                english: "Your goals are synchronized.",
                norwegian: "Målene dine er synkronisert."
            )
        } catch {
            guard accountID == userID else { return }
            lastSyncError = error.localizedDescription
            status = ATHLTHLocalization.choose(
                english: "Goals are safe offline. Sync failed: ",
                norwegian: "Målene er lagret lokalt. Synkronisering feilet: "
            ) + error.localizedDescription
        }
    }

    private func saveAcknowledgement(
        goals: [ATHLTHCloudGoal], measurements: [ATHLTHBodyMeasurement],
        revision: Int64, userID: UUID
    ) {
        guard accountID == userID else { return }
        let state = Acknowledgement(revision: revision, goals: goals,
                                    measurements: measurements)
        acknowledgement = state
        AccountLocalStorage.write(
            state, name: "goalAccountSyncAcknowledgement", userID: userID
        )
    }

    /// Build the same compact, stable photo preview on all devices.
    private static func capture(
        goals: [ATHLTHGoal],
        baseline: [ATHLTHCloudGoal],
        from store: GoalStore
    ) throws -> [ATHLTHCloudGoal] {
        let prior = Dictionary(baseline.map { ($0.id, $0) },
                               uniquingKeysWith: { old, _ in old })
        return try goals.map { goal in
            var cover: String?
            if let url = store.imageURL(for: goal),
               let data = try? Data(contentsOf: url) {
                cover = Self.compactCover(data).base64EncodedString()
            } else if prior[goal.id]?.goal.imageFilename == goal.imageFilename {
                // A temporarily unavailable local file is not an instruction
                // to delete the image from the cloud.
                cover = prior[goal.id]?.coverBase64
            }
            return ATHLTHCloudGoal(goal: goal, coverBase64: cover)
        }
    }

    private static func compactCover(_ data: Data) -> Data {
        if data.count <= 220_000 { return data }
        guard let image = UIImage(data: data),
              image.size.width > 0, image.size.height > 0
        else { return data }
        let scale = min(1, 640 / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale),
                          height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.jpegData(withCompressionQuality: 0.67) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func encode(_ document: ATHLTHCloudGoalDocument) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(document)
        guard bytes.count <= 6_200_000 else { throw GoalAccountSyncError.tooLarge }
        return bytes.base64EncodedString()
    }

    private static func decode(_ body: String) throws -> ATHLTHCloudGoalDocument {
        guard let bytes = Data(base64Encoded: body) else {
            throw GoalAccountSyncError.invalidRemoteDocument
        }
        let document = try JSONDecoder().decode(ATHLTHCloudGoalDocument.self, from: bytes)
        guard Set(document.goals.map(\.id)).count == document.goals.count,
              Set(document.measurements.map(\.id)).count == document.measurements.count else {
            throw GoalAccountSyncError.invalidRemoteDocument
        }
        return ATHLTHCloudGoalDocument(
            goals: ATHLTHGoalMergePolicy.ordered(document.goals),
            measurements: ATHLTHGoalMergePolicy.ordered(document.measurements)
        )
    }

    private func applySnapshot(
        _ items: [ATHLTHCloudGoal],
        previous: [ATHLTHCloudGoal],
        to store: GoalStore,
        accountID: UUID
    ) throws {
        let localByID = Dictionary(previous.map { ($0.id, $0) },
                                    uniquingKeysWith: { old, _ in old })
        var restored: [ATHLTHGoal] = []
        for entry in items {
            var goal = entry.goal
            if let imageString = entry.coverBase64 {
                guard let image = Data(base64Encoded: imageString) else {
                    throw GoalAccountSyncError.invalidRemoteDocument
                }
                // Keep the higher-quality local original when already present
                // and matching this account's existing goal identity.
                let alreadyExists = store.imageURL(for: goal).map {
                    FileManager.default.fileExists(atPath: $0.path)
                } ?? false
                if !alreadyExists || localByID[goal.id]?.coverBase64 != imageString {
                    goal.imageFilename = try store.saveImageData(image, for: goal.id)
                }
            } else {
                goal.imageFilename = nil
            }
            restored.append(goal)
        }
        store.replaceFromAccountSync(restored, for: accountID)
    }
}

private enum GoalAccountSyncError: LocalizedError {
    case invalidRemoteDocument
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidRemoteDocument:
            return "Goal account data could not be verified."
        case .tooLarge:
            return "The saved goal covers exceed the account sync size limit."
        }
    }
}
