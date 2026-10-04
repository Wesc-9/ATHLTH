import Combine
import Foundation
import Supabase

enum LiveGhostRaceRoomStatus:
    String,
    Codable,
    Hashable
{
    case lobby
    case countdown
    case racing
    case finished
    case cancelled
}

enum LiveGhostRacePhase:
    Equatable
{
    case lobby
    case countdown(seconds: Int)
    case racing
    case finished
    case cancelled
}

struct LiveGhostRaceRoomRecord:
    Identifiable,
    Codable,
    Hashable
{
    var id: UUID { challengeID }

    let challengeID: UUID
    let status: LiveGhostRaceRoomStatus
    let countdownStartedAt: Date?
    let startsAt: Date?
    let finishedAt: Date?
    let winnerID: UUID?
    let senderMaxLeadMeters: Double
    let recipientMaxLeadMeters: Double
    let leadChangeCount: Int
    let lastLeaderID: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys:
        String,
        CodingKey
    {
        case challengeID = "challenge_id"
        case status
        case countdownStartedAt =
            "countdown_started_at"
        case startsAt = "starts_at"
        case finishedAt = "finished_at"
        case winnerID = "winner_id"
        case senderMaxLeadMeters =
            "sender_max_lead_meters"
        case recipientMaxLeadMeters =
            "recipient_max_lead_meters"
        case leadChangeCount =
            "lead_change_count"
        case lastLeaderID =
            "last_leader_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func phase(
        at date: Date = Date()
    ) -> LiveGhostRacePhase {
        switch status {
        case .cancelled:
            return .cancelled

        case .finished:
            return .finished

        case .racing:
            return .racing

        case .countdown:
            guard let startsAt else {
                return .lobby
            }

            let remaining =
                startsAt.timeIntervalSince(
                    date
                )

            guard remaining > 0 else {
                return .racing
            }

            return .countdown(
                seconds:
                    max(
                        Int(ceil(remaining)),
                        1
                    )
            )

        case .lobby:
            return .lobby
        }
    }
}

struct LiveGhostRaceParticipantRecord:
    Identifiable,
    Codable,
    Hashable
{
    var id: String {
        challengeID.uuidString +
        ":" +
        userID.uuidString
    }

    let challengeID: UUID
    let userID: UUID
    let ready: Bool
    let deviceType: String?
    let joinedAt: Date
    let readyAt: Date?
    let finishedAt: Date?
    let elapsedSeconds:
        TimeInterval?
    let updatedAt: Date

    enum CodingKeys:
        String,
        CodingKey
    {
        case challengeID =
            "challenge_id"
        case userID = "user_id"
        case ready
        case deviceType =
            "device_type"
        case joinedAt = "joined_at"
        case readyAt = "ready_at"
        case finishedAt =
            "finished_at"
        case elapsedSeconds =
            "elapsed_seconds"
        case updatedAt = "updated_at"
    }
}

private struct LiveGhostParticipantInsert:
    Encodable
{
    let challengeID: UUID
    let userID: UUID
    let ready: Bool
    let deviceType: String?
    let updatedAt: Date

    enum CodingKeys:
        String,
        CodingKey
    {
        case challengeID =
            "challenge_id"
        case userID = "user_id"
        case ready
        case deviceType =
            "device_type"
        case updatedAt = "updated_at"
    }
}

private struct LiveGhostParticipantReadyWrite:
    Encodable
{
    let ready: Bool
    let deviceType: String?
    let readyAt: Date?
    let updatedAt: Date

    enum CodingKeys:
        String,
        CodingKey
    {
        case ready
        case deviceType =
            "device_type"
        case readyAt = "ready_at"
        case updatedAt = "updated_at"
    }
}

private struct LiveGhostParticipantFinishWrite:
    Encodable
{
    let finishedAt: Date
    let elapsedSeconds:
        TimeInterval
    let updatedAt: Date

    enum CodingKeys:
        String,
        CodingKey
    {
        case finishedAt =
            "finished_at"
        case elapsedSeconds =
            "elapsed_seconds"
        case updatedAt = "updated_at"
    }
}

@MainActor
final class LiveGhostRaceStore:
    ObservableObject
{
    @Published private(set)
    var room:
        LiveGhostRaceRoomRecord?

    @Published private(set)
    var participants:
        [LiveGhostRaceParticipantRecord] = []

    @Published private(set)
    var isLoading = false

    @Published private(set)
    var isChangingReady = false

    @Published var errorMessage: String?

    private let client: SupabaseClient
    private var roomListenerTask:
        Task<Void, Never>?
    private var participantListenerTask:
        Task<Void, Never>?
    private var fallbackRefreshTask:
        Task<Void, Never>?
    private var activeChallengeID:
        UUID?

    init(
        client:
            SupabaseClient =
                SupabaseEnvironment.client
    ) {
        self.client = client
    }

    deinit {
        roomListenerTask?.cancel()
        participantListenerTask?.cancel()
        fallbackRefreshTask?.cancel()
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    var currentParticipant:
        LiveGhostRaceParticipantRecord? {
        guard let currentUserID else {
            return nil
        }

        return participants.first {
            $0.userID == currentUserID
        }
    }

    func participant(
        userID: UUID
    ) -> LiveGhostRaceParticipantRecord? {
        participants.first {
            $0.userID == userID
        }
    }

    func phase(
        at date: Date = Date()
    ) -> LiveGhostRacePhase {
        room?.phase(at: date) ??
            .lobby
    }

    func open(
        challenge:
            GhostFriendRaceChallengeRecord
    ) async {
        guard challenge.status ==
                .accepted,
              challenge.expiresAt >
                Date(),
              let userID =
                currentUserID,
              userID ==
                challenge.senderID ||
              userID ==
                challenge.recipientID
        else {
            errorMessage =
                ATHLTHLocalization.choose(
                    english:
                        "This Live Ghost room is no longer available.",
                    norwegian:
                        "Dette Live Ghost-rommet er ikke lenger tilgjengelig."
                )
            return
        }

        activeChallengeID =
            challenge.id
        errorMessage = nil

        await ensureParticipant(
            challengeID: challenge.id,
            userID: userID
        )
        await refresh(
            challengeID: challenge.id
        )
        startListening(
            challengeID: challenge.id
        )
    }

    func close() {
        activeChallengeID = nil
        stopListening()
    }

    func refresh(
        challengeID: UUID
    ) async {
        guard !isLoading else {
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        do {
            let rooms:
                [LiveGhostRaceRoomRecord] =
                    try await client
                        .from(
                            "live_ghost_race_rooms"
                        )
                        .select()
                        .eq(
                            "challenge_id",
                            value:
                                challengeID
                        )
                        .limit(1)
                        .execute()
                        .value

            let loadedParticipants:
                [LiveGhostRaceParticipantRecord] =
                    try await client
                        .from(
                            "live_ghost_race_participants"
                        )
                        .select()
                        .eq(
                            "challenge_id",
                            value:
                                challengeID
                        )
                        .order(
                            "joined_at",
                            ascending: true
                        )
                        .execute()
                        .value

            guard activeChallengeID ==
                    challengeID
            else {
                return
            }

            room = rooms.first
            participants =
                loadedParticipants
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard activeChallengeID ==
                    challengeID
            else {
                return
            }

            errorMessage =
                error.localizedDescription
        }
    }

    func setReady(
        _ ready: Bool,
        captureDevice:
            WorkoutCaptureDevice
    ) async {
        guard
            let challengeID =
                activeChallengeID,
            let userID =
                currentUserID
        else {
            return
        }

        isChangingReady = true
        errorMessage = nil
        defer {
            isChangingReady = false
        }

        let deviceType: String
        switch captureDevice {
        case .iPhone:
            deviceType = "iphone"
        case .appleWatch:
            deviceType =
                "apple_watch"
        }

        do {
            try await client
                .from(
                    "live_ghost_race_participants"
                )
                .update(
                    LiveGhostParticipantReadyWrite(
                        ready: ready,
                        deviceType:
                            ready
                                ? deviceType
                                : nil,
                        readyAt:
                            ready
                                ? Date()
                                : nil,
                        updatedAt: Date()
                    )
                )
                .eq(
                    "challenge_id",
                    value:
                        challengeID
                )
                .eq(
                    "user_id",
                    value:
                        userID
                )
                .execute()

            await refresh(
                challengeID:
                    challengeID
            )
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }

    func markFinished(
        elapsedSeconds:
            TimeInterval
    ) async {
        guard
            let challengeID =
                activeChallengeID,
            let userID =
                currentUserID
        else {
            return
        }

        do {
            try await client
                .from(
                    "live_ghost_race_participants"
                )
                .update(
                    LiveGhostParticipantFinishWrite(
                        finishedAt: Date(),
                        elapsedSeconds:
                            max(
                                elapsedSeconds,
                                0
                            ),
                        updatedAt: Date()
                    )
                )
                .eq(
                    "challenge_id",
                    value:
                        challengeID
                )
                .eq(
                    "user_id",
                    value:
                        userID
                )
                .execute()

            await refresh(
                challengeID:
                    challengeID
            )
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }

    private func ensureParticipant(
        challengeID: UUID,
        userID: UUID
    ) async {
        do {
            let rows:
                [LiveGhostRaceParticipantRecord] =
                    try await client
                        .from(
                            "live_ghost_race_participants"
                        )
                        .select()
                        .eq(
                            "challenge_id",
                            value:
                                challengeID
                        )
                        .eq(
                            "user_id",
                            value:
                                userID
                        )
                        .limit(1)
                        .execute()
                        .value

            guard rows.isEmpty else {
                return
            }

            try await client
                .from(
                    "live_ghost_race_participants"
                )
                .insert(
                    LiveGhostParticipantInsert(
                        challengeID:
                            challengeID,
                        userID: userID,
                        ready: false,
                        deviceType: nil,
                        updatedAt: Date()
                    )
                )
                .execute()
        } catch {
            // Two app scenes may enter the same lobby together. If another
            // scene inserted the unique participant first, the refresh below
            // remains authoritative.
        }
    }

    private func startListening(
        challengeID: UUID
    ) {
        stopListening()

        roomListenerTask =
            Task {
                @MainActor [weak self] in
                guard let self else {
                    return
                }

                let channel =
                    await self.client
                        .channel(
                            "live-ghost-room-\(challengeID.uuidString.lowercased())"
                        )

                let changes =
                    await channel
                        .postgresChange(
                            AnyAction.self,
                            schema: "public",
                            table:
                                "live_ghost_race_rooms"
                        )

                await channel.subscribe()

                for await _ in changes {
                    guard
                        !Task.isCancelled,
                        self.activeChallengeID ==
                            challengeID
                    else {
                        break
                    }

                    await self.refresh(
                        challengeID:
                            challengeID
                    )
                }

                await channel
                    .unsubscribe()
            }

        participantListenerTask =
            Task {
                @MainActor [weak self] in
                guard let self else {
                    return
                }

                let channel =
                    await self.client
                        .channel(
                            "live-ghost-participants-\(challengeID.uuidString.lowercased())"
                        )

                let changes =
                    await channel
                        .postgresChange(
                            AnyAction.self,
                            schema: "public",
                            table:
                                "live_ghost_race_participants"
                        )

                await channel.subscribe()

                for await _ in changes {
                    guard
                        !Task.isCancelled,
                        self.activeChallengeID ==
                            challengeID
                    else {
                        break
                    }

                    await self.refresh(
                        challengeID:
                            challengeID
                    )
                }

                await channel
                    .unsubscribe()
            }

        // Realtime is the primary path. This low-frequency refresh only covers
        // a suspended socket or a transient subscription failure.
        fallbackRefreshTask =
            Task {
                @MainActor [weak self] in
                guard let self else {
                    return
                }

                while !Task.isCancelled {
                    let interval:
                        Duration

                    switch self.room?.status {
                    case .lobby,
                         .countdown,
                         .none:
                        interval = .seconds(2)

                    case .racing,
                         .finished,
                         .cancelled:
                        interval = .seconds(12)
                    }

                    try? await Task.sleep(
                        for: interval
                    )

                    guard
                        !Task.isCancelled,
                        self.activeChallengeID ==
                            challengeID
                    else {
                        break
                    }

                    await self.refresh(
                        challengeID:
                            challengeID
                    )
                }
            }
    }

    private func stopListening() {
        roomListenerTask?.cancel()
        participantListenerTask?.cancel()
        fallbackRefreshTask?.cancel()

        roomListenerTask = nil
        participantListenerTask =
            nil
        fallbackRefreshTask = nil
    }
}
