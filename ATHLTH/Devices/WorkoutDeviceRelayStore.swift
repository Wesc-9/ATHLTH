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

    /// Finish prior launch receipts before claiming another start. If the
    /// server is unavailable, retain the receipt and do not advance the queue.
    /// This never re-executes the recorded HealthKit / Watch side effect.
    private func reconcileLaunchedCommands(userID: UUID) async -> Bool {
        for id in unacknowledgedLaunchIDs(userID: userID) {
            guard currentUserID == userID, !Task.isCancelled else { return false }
            do {
                try await markCompleted(id)
                guard currentUserID == userID, !Task.isCancelled else { return false }
                forgetAcknowledgedCommand(id, userID: userID)
            } catch {
                // An unacknowledged launch may still be recording. Do not
                // consume another remote start while its receipt is pending.
                return false
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
            return
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
                payload: envelope
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
                    // Keep the launch receipt. A later reconnect can retry.
                    return
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
                // The claim remains unresolved, not failed: the Watch or
                // iPhone may already be recording. Never replay this launch
                // just to repair a missing acknowledgement.
                guard currentUserID == processingUserID,
                      !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                lastStatusText = ATHLTHLocalization.choose(
                    english: "Workout started; confirmation is pending.",
                    norwegian: "Økten er startet, men bekreftelsen venter."
                )
                continue
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
