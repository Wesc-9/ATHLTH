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
        for _ in 0..<8 {
            guard
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
                errorMessage =
                    error.localizedDescription
                return
            }

            guard let record
            else {
                return
            }

            let command =
                WorkoutDeviceRelayCommand(
                    id: record.id,
                    envelope:
                        record.payload
                )

            do {
                try await process(
                    command
                )
                try await markCompleted(
                    command.id
                )
                lastCompletedCommandID =
                    command.id
                errorMessage = nil
                lastStatusText =
                    ATHLTHLocalization.choose(
                        english:
                            "Remote workout started.",
                        norwegian:
                            "Fjernstart av økt utført."
                    )
            } catch {
                try? await markFailed(
                    command.id,
                    error: error
                )
                errorMessage =
                    error.localizedDescription
                lastStatusText =
                    ATHLTHLocalization.choose(
                        english:
                            "Remote workout could not be started.",
                        norwegian:
                            "Fjernstart av økten kunne ikke gjennomføres."
                    )
            }
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

    private func markCompleted(
        _ commandID: UUID
    ) async throws {
        try await client
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
            .execute()
    }

    private func markFailed(
        _ commandID: UUID,
        error: Error
    ) async throws {
        let cleanMessage =
            String(
                error
                    .localizedDescription
                    .prefix(500)
            )

        try await client
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
            .execute()
    }
}
