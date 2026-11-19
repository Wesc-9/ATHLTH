import Combine
import Foundation
import Supabase
import UIKit

@MainActor
enum ATHLTHDeviceRole {
    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    static var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    static var supportsDirectAppleWatch: Bool {
        isIPhone
    }

    static var workoutDeviceTitle: String {
        isIPad ? "iPad" : "iPhone"
    }

    static var relaySourceValue: String {
        isIPad ? "ipad" : "iphone"
    }

    static var persistentDeviceID: String {
        if let vendorID =
            UIDevice.current.identifierForVendor?
                .uuidString {
            return vendorID.lowercased()
        }

        let key =
            "athlth.deviceRelay.deviceID.v1"
        if let stored =
            UserDefaults.standard.string(
                forKey: key
            ) {
            return stored
        }

        let generated =
            UUID().uuidString.lowercased()
        UserDefaults.standard.set(
            generated,
            forKey: key
        )
        return generated
    }
}

enum WorkoutDeviceRelayTarget:
    String,
    Codable
{
    case iPhone = "iphone"
    case appleWatch = "apple_watch"

    init(
        captureDevice: WorkoutCaptureDevice
    ) {
        switch captureDevice {
        case .iPhone:
            self = .iPhone
        case .appleWatch:
            self = .appleWatch
        }
    }

    var captureDevice:
        WorkoutCaptureDevice {
        switch self {
        case .iPhone:
            return .iPhone
        case .appleWatch:
            return .appleWatch
        }
    }
}

enum WorkoutDeviceRelayKind:
    String,
    Codable
{
    case run
    case walk
    case strength
}

struct WorkoutDeviceRelayEnvelope:
    Codable
{
    var version: Int = 1
    // Created on iPad and stored in both the server row and its payload.
    // Optional to decode commands queued by older releases.
    var clientRequestID: UUID? = nil
    let kind: WorkoutDeviceRelayKind
    let target: WorkoutDeviceRelayTarget
    let workoutPayload:
        SocialWorkoutInvitePayload
    let watchAudioCoach:
        WatchAudioCoachConfiguration?
    let ghostTargetDurationSeconds:
        TimeInterval?
    let ghostUpdates:
        WatchGhostRaceAudioConfiguration?
    var runEnvironment: RunEnvironment? = nil
    var treadmillInclinePercent: Double? = nil
    let spotifyPlaylist:
        SpotifyPlaylistReference?
    let spotifyAutoplay: Bool
    let gearIDs: [UUID]
}

struct WorkoutDeviceRelayCommand:
    Identifiable
{
    let id: UUID
    let envelope:
        WorkoutDeviceRelayEnvelope
}

private struct WorkoutDeviceRelayInsert:
    Encodable
{
    let userID: UUID
    let clientRequestID: UUID
    let sourceDevice: String
    let targetDevice: String
    let commandKind: String
    let payload:
        WorkoutDeviceRelayEnvelope

    enum CodingKeys:
        String,
        CodingKey
    {
        case userID = "user_id"
        case clientRequestID =
            "client_request_id"
        case sourceDevice =
            "source_device"
        case targetDevice =
            "target_device"
        case commandKind =
            "command_kind"
        case payload
    }
}

private struct WorkoutDeviceRelayRecord:
    Decodable
{
    let id: UUID
    let userID: UUID
    let clientRequestID: UUID
    let sourceDevice: String
    let targetDevice: String
    let commandKind: String
    let payload:
        WorkoutDeviceRelayEnvelope
    let createdAt: Date
    let expiresAt: Date
    let claimedAt: Date?
    let claimedByDeviceID: String?
    let completedAt: Date?
    let failedAt: Date?
    let failureMessage: String?

    enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case userID = "user_id"
        case clientRequestID =
            "client_request_id"
        case sourceDevice =
            "source_device"
        case targetDevice =
            "target_device"
        case commandKind =
            "command_kind"
        case payload
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case claimedAt = "claimed_at"
        case claimedByDeviceID =
            "claimed_by_device_id"
        case completedAt =
            "completed_at"
        case failedAt = "failed_at"
        case failureMessage =
            "failure_message"
    }
}

/// Validates the server-claimed envelope before any Watch/HealthKit side
/// effects. Old or mismatched relay rows are never interpreted as starts.
enum WorkoutDeviceRelayClaimPolicy {
    static func accepts(
        source: String,
        target: String,
        kind: String,
        payloadTarget: String,
        payloadKind: String,
        payloadVersion: Int,
        expiresAt: Date,
        claimedDeviceID: String?,
        expectedDeviceID: String,
        completedAt: Date?,
        failedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        source == "ipad" &&
            target == payloadTarget &&
            kind == payloadKind &&
            expiresAt > now &&
            payloadVersion == 1 &&
            claimedDeviceID == expectedDeviceID &&
            !expectedDeviceID.isEmpty &&
            completedAt == nil && failedAt == nil
    }

    static func confirmsReceipt(_ returnedIDs: [UUID], commandID: UUID) -> Bool {
        returnedIDs.count == 1 && returnedIDs[0] == commandID
    }

    /// A timed-out acknowledgement may already have succeeded on the
    /// server. Clear a local success receipt only for one matching,
    /// server-confirmed terminal success, never for a failed or missing row.
    static func confirmsPersistedCompletion(
        _ matches: [(id: UUID, completedAt: Date?, failedAt: Date?)],
        commandID: UUID
    ) -> Bool {
        matches.count == 1 &&
            matches[0].id == commandID &&
            matches[0].completedAt != nil &&
            matches[0].failedAt == nil
    }

    /// A claim RPC must return zero or one row. Multiple rows may already
    /// be claimed on the server; executing only the first would conceal
    /// the remaining commands and make replay/reconciliation unsafe.
    static func hasValidClaimBatchSize(_ count: Int) -> Bool {
        count == 0 || count == 1
    }

    /// Correlate the immutable server row with the original iPad payload.
    /// Legacy requests did not carry the embedded identifier.
    static func hasMatchingRequestID(
        serverID: UUID, payloadID: UUID?
    ) -> Bool {
        payloadID == nil || payloadID == serverID
    }

    /// An active Watch workout can resolve uncertainty only when its
    /// freshly probed identity exactly matches the server's request token.
    /// A same-kind activity, an empty token, or an already failed command
    /// cannot confirm the original remote HealthKit launch.
    static func confirmsUncertainWatchLaunch(
        target: String,
        serverRequestID: UUID,
        watchRequestID: UUID?,
        failedAt: Date?
    ) -> Bool {
        target == WorkoutDeviceRelayTarget.appleWatch.rawValue &&
            watchRequestID == serverRequestID &&
            failedAt == nil
    }

    /// Only a genuinely saved Watch HealthKit workout can prove that a
    /// remote launch completed while the iPhone was disconnected.
    /// Local iPhone recordings are authoritative only when their persisted
    /// owner, exact request token, activity kind and start time agree with
    /// the server claim. A matching plan title or calendar session is not proof.
    static func confirmsIPhoneRecording(
        target: String,
        kind: String,
        serverRequestID: UUID,
        serverCreatedAt: Date,
        recordingRequestID: UUID?,
        recordingKind: String,
        recordingStartedAt: Date,
        ownerMatches: Bool,
        failedAt: Date?
    ) -> Bool {
        target == WorkoutDeviceRelayTarget.iPhone.rawValue &&
            failedAt == nil &&
            ownerMatches &&
            recordingRequestID == serverRequestID &&
            kind == recordingKind &&
            recordingStartedAt >= serverCreatedAt.addingTimeInterval(-120) &&
            recordingStartedAt <= Date().addingTimeInterval(120)
    }

    static func confirmsCompletedWatchLaunch(
        target: String,
        kind: String,
        serverRequestID: UUID,
        serverCreatedAt: Date,
        signedInOwnerID: UUID,
        receipt: WatchRemoteLaunchCompletionReceipt?,
        failedAt: Date?
    ) -> Bool {
        guard target == WorkoutDeviceRelayTarget.appleWatch.rawValue,
              failedAt == nil,
              let receipt,
              receipt.relayRequestID == serverRequestID,
              receipt.ownerID == signedInOwnerID,
              receipt.endedAt >= receipt.startedAt,
              // The Watch must not use a completion of an older workout.
              receipt.startedAt >= serverCreatedAt.addingTimeInterval(-120),
              receipt.startedAt <= Date().addingTimeInterval(120)
        else { return false }

        switch receipt.kind {
        case .running: return kind == WorkoutDeviceRelayKind.run.rawValue
        case .walking: return kind == WorkoutDeviceRelayKind.walk.rawValue
        case .strength: return kind == WorkoutDeviceRelayKind.strength.rawValue
        default: return false
        }
    }

    /// A confirmed receipt written after the launch is stronger evidence
    /// than its older pre-launch uncertainty marker. This resolves crashes
    /// between rememberLaunchedCommand and forgetUncertainLaunch.
    /// Unknown launches must remain uncertain, never guessed successful.
    static func resolvedUncertainIDs(
        uncertainIDs: [UUID],
        confirmedLaunchIDs: [UUID]
    ) -> [UUID] {
        let confirmed = Set(confirmedLaunchIDs)
        return uncertainIDs.filter { !confirmed.contains($0) }
    }

    enum LaunchDecision: Equatable {
        case retryConfirmedReceipt
        case holdForDeviceReconciliation
        case validateNewLaunch
    }

    /// The pre-launch marker is NOT proof of a successful recording.
    /// Only a completed local launch may receive a success receipt.
    static func launchDecision(
        commandID: UUID,
        unacknowledgedLaunchIDs: [UUID],
        uncertainLaunchIDs: [UUID]
    ) -> LaunchDecision {
        if uncertainLaunchIDs.contains(commandID) {
            return .holdForDeviceReconciliation
        }
        if unacknowledgedLaunchIDs.contains(commandID) {
            return .retryConfirmedReceipt
        }
        return .validateNewLaunch
    }
}

private struct ClaimWorkoutDeviceCommandParams:
    Encodable
{
    let deviceID: String

    enum CodingKeys:
        String,
        CodingKey
    {
        case deviceID = "p_device_id"
    }
}

private struct WorkoutDeviceCommandReceipt: Decodable {
    let id: UUID
}

private struct WorkoutDeviceCommandServerStatus: Decodable {
    let id: UUID
    let completedAt: Date?
    let failedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case completedAt = "completed_at"
        case failedAt = "failed_at"
    }
}

private struct WorkoutDeviceCommandReconciliationRow: Decodable {
    let id: UUID
    let clientRequestID: UUID
    let targetDevice: String
    let commandKind: String
    let createdAt: Date
    let failedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case clientRequestID = "client_request_id"
        case targetDevice = "target_device"
        case commandKind = "command_kind"
        case createdAt = "created_at"
        case failedAt = "failed_at"
    }
}

private struct WorkoutDeviceCommandCompletedWrite:
    Encodable
{
    let completedAt: Date

    enum CodingKeys:
        String,
        CodingKey
    {
        case completedAt =
            "completed_at"
    }
}

private struct WorkoutDeviceCommandFailedWrite:
    Encodable
{
    let failedAt: Date
    let failureMessage: String

    enum CodingKeys:
        String,
        CodingKey
    {
        case failedAt = "failed_at"
        case failureMessage =
            "failure_message"
    }
}

@MainActor
final class WorkoutDeviceRelayStore:
    ObservableObject
{
    static let shared =
        WorkoutDeviceRelayStore()

    @Published private(set)
    var lastQueuedCommandID: UUID?
    @Published private(set)
    var lastCompletedCommandID: UUID?
    @Published private(set)
    var lastStatusText: String?
    @Published private(set)
    var errorMessage: String?

    private let client: SupabaseClient
    private var listenerTask:
        Task<Void, Never>?
    private var listeningUserID: UUID?
    private var listenerGeneration: UUID?
    private var isDrainingCommands = false
    private var isReconcilingUncertainStarts = false
    private var reconcileAgainAfterCurrentPass = false
    // A launch may succeed while the Supabase acknowledgement fails.
    // Persist only its command ID, scoped to account and physical device;
    // never persist the workout payload or replay the HealthKit start.
    // Written BEFORE an asynchronous start. A crash between a successful
    // Watch launch and the success receipt must not replay HealthKit.
    private func uncertainJournalKey(userID: UUID) -> String {
        "athlth.relay.uncertain.v1.\(userID.uuidString.lowercased()).\(ATHLTHDeviceRole.persistentDeviceID)"
    }

    private func uncertainLaunchIDs(userID: UUID) -> [UUID] {
        (UserDefaults.standard.stringArray(forKey: uncertainJournalKey(userID: userID)) ?? [])
            .compactMap(UUID.init(uuidString:))
    }

    private func rememberUncertainLaunch(_ id: UUID, userID: UUID) {
        var ids = uncertainLaunchIDs(userID: userID)
        guard !ids.contains(id) else { return }
        ids.append(id)
        UserDefaults.standard.set(ids.map(\.uuidString),
                                  forKey: uncertainJournalKey(userID: userID))
    }

    private func forgetUncertainLaunch(_ id: UUID, userID: UUID) {
        let ids = uncertainLaunchIDs(userID: userID).filter { $0 != id }
        UserDefaults.standard.set(ids.map(\.uuidString),
                                  forKey: uncertainJournalKey(userID: userID))
    }

    private func completedJournalKey(userID: UUID) -> String {
        "athlth.relay.completed.v1.\(userID.uuidString.lowercased()).\(ATHLTHDeviceRole.persistentDeviceID)"
    }

    private func unacknowledgedLaunchIDs(userID: UUID) -> [UUID] {
        let values = UserDefaults.standard.stringArray(
            forKey: completedJournalKey(userID: userID)
        ) ?? []
        return values.compactMap(UUID.init(uuidString:))
    }

    private func rememberLaunchedCommand(_ id: UUID, userID: UUID) {
        var ids = unacknowledgedLaunchIDs(userID: userID)
        guard !ids.contains(id) else { return }
        ids.append(id)
        // Never evict an unacknowledged successful launch: doing so could
        // strand its receipt permanently after a long offline period.
        UserDefaults.standard.set(
            ids.map(\.uuidString),
            forKey: completedJournalKey(userID: userID)
        )
    }

    private func forgetAcknowledgedCommand(_ id: UUID, userID: UUID) {
        let ids = unacknowledgedLaunchIDs(userID: userID).filter { $0 != id }
        UserDefaults.standard.set(
            ids.map(\.uuidString),
            forKey: completedJournalKey(userID: userID)
        )
    }

    /// Complete an interrupted local journal transition without launching
    /// anything. Only an existing confirmed success marker can clear the
    /// matching uncertain marker.
    private func reconcileLocalLaunchMarkers(userID: UUID) {
        let uncertain = uncertainLaunchIDs(userID: userID)
        let remaining = WorkoutDeviceRelayClaimPolicy.resolvedUncertainIDs(
            uncertainIDs: uncertain,
            confirmedLaunchIDs: unacknowledgedLaunchIDs(userID: userID)
        )
        guard remaining != uncertain else { return }
        UserDefaults.standard.set(
            remaining.map(\.uuidString),
            forKey: uncertainJournalKey(userID: userID)
        )
    }

    /// Resolve a crashed/asynchronously failed Watch start only against an
    /// exact live workout identity returned by Watch, never merely against
    /// an inactive Watch state or an elapsed timeout. The server row is
    /// scoped to the signed-in account and this physical iPhone.
    /// Complete a previously uncertain remote start only with either fresh
    /// active Watch proof or a durable saved HealthKit-result receipt. The
    /// latter remains available after the social/history queue was consumed.
    /// Never infer a launch from an idle Watch or matching workout title.
    /// Resolve a stranded iPad relay against the authoritative owner:
    /// a live/saved Watch HealthKit result OR the existing PhoneWorkout /
    /// StrengthWorkoutLog checkpoint. Neither path creates a new recording.
    func reconcileUncertainWorkoutStarts(
        watchConnection: AppleWatchConnectionStore,
        phoneWorkout: IPhoneWorkoutStore,
        strengthWorkout: StrengthWorkoutStore
    ) async {
        // Background, Watch delivery and GPS permission callbacks can race.
        // Only one reconciler may promote/acknowledge local journal entries.
        guard !isReconcilingUncertainStarts else {
            // A later GPS/HealthKit checkpoint may arrive while an earlier
            // probe is waiting. Preserve that event for one final pass.
            reconcileAgainAfterCurrentPass = true
            return
        }
        isReconcilingUncertainStarts = true
        defer {
            isReconcilingUncertainStarts = false
            if reconcileAgainAfterCurrentPass {
                reconcileAgainAfterCurrentPass = false
                Task { @MainActor [weak self] in
                    await self?.reconcileUncertainWorkoutStarts(
                        watchConnection: watchConnection,
                        phoneWorkout: phoneWorkout,
                        strengthWorkout: strengthWorkout
                    )
                }
            }
        }
        guard ATHLTHDeviceRole.isIPhone,
              let userID = currentUserID,
              !uncertainLaunchIDs(userID: userID).isEmpty
        else { return }

        // Phone-owned recordings can reconcile even while Watch sleeps.
        // Probe Watch lazily only for a still-unverified Watch-target claim.
        var liveWatchRequestID: UUID?
        var hasProbedWatch = false

        for commandID in uncertainLaunchIDs(userID: userID) {
            guard currentUserID == userID, !Task.isCancelled else { return }
            do {
                let rows: [WorkoutDeviceCommandReconciliationRow] = try await client
                    .from("workout_device_commands")
                    .select("id,client_request_id,target_device,command_kind,created_at,failed_at")
                    .eq("id", value: commandID)
                    .eq("user_id", value: userID)
                    .eq("claimed_by_device_id",
                        value: ATHLTHDeviceRole.persistentDeviceID)
                    .execute()
                    .value
                guard rows.count == 1, rows[0].id == commandID,
                      currentUserID == userID, !Task.isCancelled
                else { continue }
                let record = rows[0]

                let watchReceipt = watchConnection.completedRelayReceipt(
                    requestID: record.clientRequestID, ownerID: userID
                )
                let isCompletedWatch =
                    WorkoutDeviceRelayClaimPolicy.confirmsCompletedWatchLaunch(
                        target: record.targetDevice,
                        kind: record.commandKind,
                        serverRequestID: record.clientRequestID,
                        serverCreatedAt: record.createdAt,
                        signedInOwnerID: userID,
                        receipt: watchReceipt,
                        failedAt: record.failedAt
                    )
                if record.targetDevice ==
                        WorkoutDeviceRelayTarget.appleWatch.rawValue &&
                   !isCompletedWatch && !hasProbedWatch {
                    hasProbedWatch = true
                    liveWatchRequestID =
                        await watchConnection.confirmedActiveRelayRequestID()
                    guard currentUserID == userID, !Task.isCancelled
                    else { return }
                }
                let isLiveWatch =
                    WorkoutDeviceRelayClaimPolicy.confirmsUncertainWatchLaunch(
                        target: record.targetDevice,
                        serverRequestID: record.clientRequestID,
                        watchRequestID: liveWatchRequestID,
                        failedAt: record.failedAt
                    )

                let phoneCandidates =
                    [phoneWorkout.active, phoneWorkout.lastCompletedWorkout]
                        .compactMap { $0 } + phoneWorkout.history
                let isIPhoneRunOrWalk = phoneCandidates.contains { workout in
                    WorkoutDeviceRelayClaimPolicy.confirmsIPhoneRecording(
                        target: record.targetDevice,
                        kind: record.commandKind,
                        serverRequestID: record.clientRequestID,
                        serverCreatedAt: record.createdAt,
                        recordingRequestID: workout.relayRequestID,
                        recordingKind: workout.walking ? "walk" : "run",
                        recordingStartedAt: workout.start,
                        ownerMatches: phoneWorkout.recordingAccountID == userID,
                        failedAt: record.failedAt
                    )
                }
                let strengthCandidates =
                    [strengthWorkout.activeWorkout].compactMap { $0 }
                        + strengthWorkout.workoutHistory
                let isIPhoneStrength = strengthCandidates.contains { workout in
                    workout.captureDevice == .iPhone &&
                    WorkoutDeviceRelayClaimPolicy.confirmsIPhoneRecording(
                        target: record.targetDevice,
                        kind: record.commandKind,
                        serverRequestID: record.clientRequestID,
                        serverCreatedAt: record.createdAt,
                        recordingRequestID: workout.relayRequestID,
                        recordingKind: "strength",
                        recordingStartedAt: workout.startedAt,
                        ownerMatches: strengthWorkout.isLoaded(for: userID),
                        failedAt: record.failedAt
                    )
                }
                guard isLiveWatch || isCompletedWatch ||
                        isIPhoneRunOrWalk || isIPhoneStrength
                else { continue }

                // The existing source-of-truth workout already exists. Save
                // the success receipt before clearing uncertainty so a
                // second process crash cannot cause duplicate launch.
                rememberLaunchedCommand(commandID, userID: userID)
                forgetUncertainLaunch(commandID, userID: userID)
                lastStatusText = ATHLTHLocalization.choose(
                    english: "Remote workout verified; confirming start.",
                    norwegian: "Fjernstartet økt bekreftet; kvitterer oppstart."
                )
                _ = await reconcileLaunchedCommands(userID: userID)
                // One reconciliation only. Never claim another remote start.
                return
            } catch {
                // Missing network/owner evidence remains uncertain.
                return
            }
        }
    }

    /// Finish prior launch receipts before claiming another start. If the
    /// server is unavailable, retain the receipt and do not advance the queue.
    /// This never re-executes the recorded HealthKit / Watch side effect.
    /// Read only the exact signed-in account/device claim. A network timeout
    /// after UPDATE may mean the server already committed the completion.
    /// This query has no HealthKit or workout-launch side effects.
    private func hasPersistedCompletedReceipt(
        _ commandID: UUID, userID: UUID
    ) async -> Bool {
        guard currentUserID == userID, !Task.isCancelled else { return false }
        do {
            let rows: [WorkoutDeviceCommandServerStatus] = try await client
                .from("workout_device_commands")
                .select("id,completed_at,failed_at")
                .eq("id", value: commandID)
                .eq("user_id", value: userID)
                .eq("claimed_by_device_id",
                    value: ATHLTHDeviceRole.persistentDeviceID)
                .execute()
                .value
            guard currentUserID == userID, !Task.isCancelled else { return false }
            return WorkoutDeviceRelayClaimPolicy.confirmsPersistedCompletion(
                rows.map { (id: $0.id, completedAt: $0.completedAt,
                            failedAt: $0.failedAt) },
                commandID: commandID
            )
        } catch {
            return false
        }
    }

    private func reconcileLaunchedCommands(userID: UUID) async -> Bool {
        for id in unacknowledgedLaunchIDs(userID: userID) {
            guard currentUserID == userID, !Task.isCancelled else { return false }
            do {
                try await markCompleted(id)
                guard currentUserID == userID, !Task.isCancelled else { return false }
                forgetAcknowledgedCommand(id, userID: userID)
            } catch {
                // The server may have committed just before a lost response.
                // Only an exact, verified completed row clears the local
                // receipt; an unknown outcome keeps the queue blocked.
                guard await hasPersistedCompletedReceipt(id, userID: userID),
                      currentUserID == userID, !Task.isCancelled
                else { return false }
                forgetAcknowledgedCommand(id, userID: userID)
            }
        }
        return currentUserID == userID && !Task.isCancelled
    }


    init(
        client:
            SupabaseClient =
                SupabaseEnvironment.client
    ) {
        self.client = client
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    func enqueue(
        _ envelope:
            WorkoutDeviceRelayEnvelope
    ) async throws {
        guard ATHLTHDeviceRole.isIPad else {
            // A no-op falsely tells the launch coordinator that a workout
            // was handed off. Only iPad may create this remote command.
            throw NSError(
                domain: "ATHLTH.DeviceRelay", code: 403,
                userInfo: [NSLocalizedDescriptionKey:
                    ATHLTHLocalization.choose(
                        english: "Only iPad can send workouts to another device.",
                        norwegian: "Kun iPad kan sende treningsøkter til en annen enhet."
                    )]
            )
        }

        guard let userID =
                currentUserID
        else {
            throw NSError(
                domain:
                    "ATHLTH.DeviceRelay",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        ATHLTHLocalization.choose(
                            english:
                                "Sign in before sending a workout to another device.",
                            norwegian:
                                "Logg inn før du sender en økt til en annen enhet."
                        )
                ]
            )
        }

        let requestID = UUID()
        var correlatedEnvelope = envelope
        correlatedEnvelope.clientRequestID = requestID
        let insert =
            WorkoutDeviceRelayInsert(
                userID: userID,
                clientRequestID:
                    requestID,
                sourceDevice:
                    ATHLTHDeviceRole
                        .relaySourceValue,
                targetDevice:
                    envelope
                        .target
                        .rawValue,
                commandKind:
                    envelope
                        .kind
                        .rawValue,
                payload: correlatedEnvelope
            )

        do {
            try await client
                .from(
                    "workout_device_commands"
                )
                .insert(insert)
                .execute()

            lastQueuedCommandID =
                requestID
            errorMessage = nil
            lastStatusText =
                envelope.target ==
                    .appleWatch
                ? ATHLTHLocalization.choose(
                    english:
                        "Sent to iPhone · Apple Watch will start through the paired phone.",
                    norwegian:
                        "Sendt til iPhone · Apple Watch startes via den parede telefonen."
                )
                : ATHLTHLocalization.choose(
                    english:
                        "Sent to iPhone.",
                    norwegian:
                        "Sendt til iPhone."
                )

            Task { @MainActor [weak self] in
                try? await Task.sleep(
                    for: .seconds(4)
                )

                guard let self,
                      self.lastQueuedCommandID ==
                        requestID
                else {
                    return
                }

                self.lastStatusText = nil
            }
        } catch {
            errorMessage =
                error.localizedDescription
            throw error
        }
    }

    func startListening(
        process:
            @escaping @MainActor
            (WorkoutDeviceRelayCommand)
                async throws -> Void
    ) {
        guard ATHLTHDeviceRole.isIPhone,
              let userID = currentUserID
        else {
            stopListening()
            return
        }

        if listenerTask != nil {
            if listeningUserID == userID {
                return
            }
            // A different account has signed in without a full restart.
            // The previous channel must not consume the new account's work.
            stopListening()
        }

        let generation = UUID()
        listeningUserID = userID
        listenerGeneration = generation
        listenerTask = Task { @MainActor [weak self] in
            guard let self else { return }

            defer {
                // A stopped listener must never clear the handle of a newer
                // listener that started during an account transition.
                if self.listenerGeneration == generation {
                    self.listenerTask = nil
                    self.listeningUserID = nil
                    self.listenerGeneration = nil
                }
            }

            await self.drainPending(process: process)
            guard !Task.isCancelled,
                  self.currentUserID == userID
            else { return }

            // When a realtime stream finishes because of a network drop,
            // re-subscribe while the same account remains active. Re-drain
            // after subscribing to recover inserts missed during the gap.
            while !Task.isCancelled && self.currentUserID == userID {
                let channel = await self.client.channel(
                    "workout-device-relay-\(userID.uuidString.lowercased())"
                )

                let changes = await channel.postgresChange(
                    InsertAction.self,
                    schema: "public",
                    table: "workout_device_commands"
                )

                await channel.subscribe()
                await self.drainPending(process: process)

                for await _ in changes {
                    guard !Task.isCancelled,
                          self.currentUserID == userID
                    else { break }

                    await self.drainPending(process: process)
                }

                await channel.unsubscribe()
                guard !Task.isCancelled,
                      self.currentUserID == userID
                else { break }

                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopListening() {
        listenerTask?.cancel()
        listenerTask = nil
        listeningUserID = nil
        listenerGeneration = nil
    }

    func refreshPending(
        process:
            @escaping @MainActor
            (WorkoutDeviceRelayCommand)
                async throws -> Void
    ) async {
        guard ATHLTHDeviceRole.isIPhone
        else {
            return
        }

        await drainPending(
            process: process
        )
    }

    private func drainPending(
        process:
            @escaping @MainActor
            (WorkoutDeviceRelayCommand)
                async throws -> Void
    ) async {
        // Realtime notifications and foreground refresh may overlap. Only
        // one command processor may consume this device's queue at a time.
        guard !isDrainingCommands else { return }
        isDrainingCommands = true
        defer { isDrainingCommands = false }
        guard let processingUserID = currentUserID else { return }
        // The two journal writes are individually durable, not atomic.
        // Recover a confirmed success left with its older uncertain marker
        // after process termination, before blocking the relay queue.
        reconcileLocalLaunchMarkers(userID: processingUserID)
        // An interrupted start has an unknown outcome. Do not claim another
        // start or replay the ambiguous command until device reconciliation.
        guard uncertainLaunchIDs(userID: processingUserID).isEmpty else {
            errorMessage = "A previous remote start needs device reconciliation."
            return
        }
        guard await reconcileLaunchedCommands(userID: processingUserID),
              currentUserID == processingUserID, !Task.isCancelled
        else { return }
        // Drain the complete bounded backlog on reconnect, not only the
        // first eight commands when no further realtime event may arrive.
        for _ in 0..<128 {
            guard currentUserID == processingUserID,
                !Task.isCancelled
            else {
                return
            }

            let record:
                WorkoutDeviceRelayRecord?

            do {
                record =
                    try await claimNext()
            } catch {
                guard currentUserID == processingUserID,
                      !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                return
            }

            guard let record else { return }
            guard currentUserID == processingUserID,
                  record.userID == processingUserID,
                  !Task.isCancelled else {
                // Do not execute a command claimed during an account change.
                return
            }

            // A server claim can reappear when its completion receipt fails.
            // The locally durable launch journal is authoritative for this
            // device: repair the receipt, never replay Watch/HealthKit start.
            let launchDecision = WorkoutDeviceRelayClaimPolicy.launchDecision(
                commandID: record.id,
                unacknowledgedLaunchIDs:
                    unacknowledgedLaunchIDs(userID: processingUserID),
                uncertainLaunchIDs: uncertainLaunchIDs(userID: processingUserID)
            )
            if launchDecision == .retryConfirmedReceipt {
                do {
                    try await markCompleted(record.id)
                    guard currentUserID == processingUserID,
                          !Task.isCancelled else { return }
                    forgetAcknowledgedCommand(record.id, userID: processingUserID)
                } catch {
                    guard await hasPersistedCompletedReceipt(
                        record.id, userID: processingUserID
                    ), currentUserID == processingUserID,
                       !Task.isCancelled
                    else { return }
                    forgetAcknowledgedCommand(record.id, userID: processingUserID)
                }
                continue
            }

            // An uncertain pre-launch marker does not prove that a workout
            // started. It must never be transformed into a success receipt
            // until the original Watch/HealthKit status is reconciled.
            guard launchDecision == .validateNewLaunch else {
                errorMessage = ATHLTHLocalization.choose(
                    english: "Remote start requires device reconciliation.",
                    norwegian: "Fjernstart må avklares mot enhetens opptak."
                )
                return
            }

            guard WorkoutDeviceRelayClaimPolicy.hasMatchingRequestID(
                serverID: record.clientRequestID,
                payloadID: record.payload.clientRequestID
            ) else {
                // The server row and iPad payload disagree. Never launch an
                // activity from a mismatched or tampered correlation token.
                guard currentUserID == processingUserID,
                      !Task.isCancelled else { return }
                try? await markFailed(
                    record.id,
                    error: NSError(
                        domain: "ATHLTH.DeviceRelay", code: 6,
                        userInfo: [NSLocalizedDescriptionKey:
                            "Remote workout request identity does not match."]
                    )
                )
                continue
            }

            guard WorkoutDeviceRelayClaimPolicy.accepts(
                source: record.sourceDevice,
                target: record.targetDevice,
                kind: record.commandKind,
                payloadTarget: record.payload.target.rawValue,
                payloadKind: record.payload.kind.rawValue,
                payloadVersion: record.payload.version,
                expiresAt: record.expiresAt,
                claimedDeviceID: record.claimedByDeviceID,
                expectedDeviceID: ATHLTHDeviceRole.persistentDeviceID,
                completedAt: record.completedAt,
                failedAt: record.failedAt
            ) else {
                // A malformed or expired claim must never launch HealthKit.
                guard currentUserID == processingUserID,
                      !Task.isCancelled else { return }
                try? await markFailed(
                    record.id,
                    error: NSError(
                        domain: "ATHLTH.DeviceRelay", code: 2,
                        userInfo: [NSLocalizedDescriptionKey:
                            "Expired or invalid workout relay command"]
                    )
                )
                continue
            }

            let command =
                WorkoutDeviceRelayCommand(
                    id: record.id,
                    envelope:
                        record.payload
                )

            // Keep the launch result separate from the acknowledgement.
            // A network failure *after* HealthKit started must never mark
            // this command as a failed launch eligible for a second start.
            rememberUncertainLaunch(command.id, userID: processingUserID)
            do {
                try await process(command)
                // Persist the success before any suspension for server I/O.
                // A relaunch or offline reconnect must only retry the receipt.
                rememberLaunchedCommand(command.id, userID: processingUserID)
                forgetUncertainLaunch(command.id, userID: processingUserID)
            } catch {
                // An async start may throw after Watch accepted the request.
                // A thrown error alone cannot prove that HealthKit is idle.
                // Retain the uncertainty and never mark the server claim as
                // definitively failed until device status is reconciled.
                guard currentUserID == processingUserID,
                      !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                lastStatusText = ATHLTHLocalization.choose(
                    english: "Start outcome uncertain; verify on Apple Watch.",
                    norwegian: "Uavklart oppstart – kontroller Apple Watch."
                )
                return
            }
            guard currentUserID == processingUserID,
                  !Task.isCancelled else { return }
            do {
                try await markCompleted(command.id)
                guard currentUserID == processingUserID,
                      !Task.isCancelled else { return }
                forgetAcknowledgedCommand(command.id, userID: processingUserID)
            } catch {
                // The workout already started. The server may even have
                // committed before the response was lost: confirm only the
                // matching persisted receipt without launching anything.
                guard currentUserID == processingUserID,
                      !Task.isCancelled else { return }
                if await hasPersistedCompletedReceipt(
                    command.id, userID: processingUserID
                ) {
                    guard currentUserID == processingUserID,
                          !Task.isCancelled else { return }
                    forgetAcknowledgedCommand(command.id, userID: processingUserID)
                    lastCompletedCommandID = command.id
                    errorMessage = nil
                    lastStatusText = ATHLTHLocalization.choose(
                        english: "Remote workout started.",
                        norwegian: "Fjernstart av økt utført."
                    )
                } else {
                    guard currentUserID == processingUserID,
                          !Task.isCancelled else { return }
                    errorMessage = error.localizedDescription
                    lastStatusText = ATHLTHLocalization.choose(
                        english: "Workout started; confirmation is pending.",
                        norwegian: "Økten er startet, men bekreftelsen venter."
                    )
                }
                // At most one successful launch per drain, regardless of
                // acknowledgement state. Never claim/start the next workout.
                return
            }
            guard currentUserID == processingUserID,
                  !Task.isCancelled else { return }
            lastCompletedCommandID = command.id
            errorMessage = nil
            lastStatusText = ATHLTHLocalization.choose(
                english: "Remote workout started.",
                norwegian: "Fjernstart av økt utført."
            )
            // One successful remote start per drain. A second queued start
            // must not race the newly active Watch/HealthKit recording.
            return
        }
    }

    private func claimNext()
        async throws ->
        WorkoutDeviceRelayRecord?
    {
        let rows:
            [WorkoutDeviceRelayRecord] =
                try await client
                    .rpc(
                        "claim_next_workout_device_command",
                        params:
                            ClaimWorkoutDeviceCommandParams(
                                deviceID:
                                    ATHLTHDeviceRole
                                        .persistentDeviceID
                            )
                    )
                    .execute()
                    .value

        guard WorkoutDeviceRelayClaimPolicy.hasValidClaimBatchSize(
            rows.count
        ) else {
            throw NSError(
                domain: "ATHLTH.DeviceRelay", code: 5,
                userInfo: [NSLocalizedDescriptionKey:
                    "Remote start claim returned multiple commands; no workout was started."]
            )
        }
        return rows.first
    }

    /// Supabase can return HTTP success when a filtered UPDATE changes zero
    /// rows. Never discard the local receipt unless the matching row was
    /// actually acknowledged by this signed-in device.
    private func requireAcknowledgedRow(
        _ rows: [WorkoutDeviceCommandReceipt], commandID: UUID
    ) throws {
        guard WorkoutDeviceRelayClaimPolicy.confirmsReceipt(
            rows.map(\.id), commandID: commandID
        ) else {
            throw NSError(
                domain: "ATHLTH.DeviceRelay", code: 4,
                userInfo: [NSLocalizedDescriptionKey:
                    "Remote command receipt was not acknowledged by the server."]
            )
        }
    }

    private func markCompleted(
        _ commandID: UUID
    ) async throws {
        guard let userID = currentUserID else {
            throw NSError(domain: "ATHLTH.DeviceRelay", code: 3)
        }
        let rows: [WorkoutDeviceCommandReceipt] = try await client
            .from(
                "workout_device_commands"
            )
            .update(
                WorkoutDeviceCommandCompletedWrite(
                    completedAt: Date()
                )
            )
            .eq(
                "id",
                value: commandID
            )
            .eq("user_id", value: userID)
            .eq("claimed_by_device_id", value: ATHLTHDeviceRole.persistentDeviceID)
            .select("id")
            .execute()
            .value
        try requireAcknowledgedRow(rows, commandID: commandID)
    }

    private func markFailed(
        _ commandID: UUID,
        error: Error
    ) async throws {
        guard let userID = currentUserID else {
            throw NSError(domain: "ATHLTH.DeviceRelay", code: 3)
        }
        let cleanMessage =
            String(
                error
                    .localizedDescription
                    .prefix(500)
            )

        let rows: [WorkoutDeviceCommandReceipt] = try await client
            .from(
                "workout_device_commands"
            )
            .update(
                WorkoutDeviceCommandFailedWrite(
                    failedAt: Date(),
                    failureMessage:
                        cleanMessage
                )
            )
            .eq(
                "id",
                value: commandID
            )
            .eq("user_id", value: userID)
            .eq("claimed_by_device_id", value: ATHLTHDeviceRole.persistentDeviceID)
            .select("id")
            .execute()
            .value
        try requireAcknowledgedRow(rows, commandID: commandID)
    }
}
