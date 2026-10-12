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

/// An invitation's expiry prevents *new* duels, but must not eject
/// athletes from a countdown or a race that was already started.
enum LiveGhostRaceReentry {
    static func allowed(
        expiresAt: Date,
        roomStatus: LiveGhostRaceRoomStatus?,
        now: Date = Date()
    ) -> Bool {
        if expiresAt > now { return true }
        return roomStatus == .countdown || roomStatus == .racing
    }

    /// The backend also rejects reentry to finished/cancelled sessions.
    /// Keep the client UI consistent so athletes are never invited to
    /// reconnect after the competition has ended.
    static func canReconnectSharedSession(
        roomStatus: LiveGhostRaceRoomStatus?
    ) -> Bool {
        roomStatus != .finished && roomStatus != .cancelled
    }

    /// Only a locally recovered recording from this exact challenge may
    /// reconnect its shared session. Never launch a second workout here.
    static func canReconnectPhoneWorkout(
        comparisonRouteID: UUID?,
        challengeID: UUID,
        roomStatus: LiveGhostRaceRoomStatus?
    ) -> Bool {
        comparisonRouteID == challengeID && roomStatus == .racing
    }

    /// A recovered Watch workout may reconnect only when the latest
    /// mirrored session is still recording this exact duel. No HealthKit
    /// session or additional workout is started by this path.
    static func canReconnectWatchWorkout(
        comparisonRouteID: UUID?,
        challengeID: UUID,
        roomStatus: LiveGhostRaceRoomStatus?,
        mirroredWorkoutActive: Bool,
        isRunningOrPaused: Bool
    ) -> Bool {
        mirroredWorkoutActive &&
        isRunningOrPaused &&
        comparisonRouteID == challengeID &&
        roomStatus == .racing
    }
}

/// Countdown validity must come from a fresh server snapshot just before
/// launching HealthKit. Never infer a new workout from a stale race screen.
enum LiveGhostSynchronizedLaunchGate {
    static func mayLaunch(
        status: LiveGhostRaceRoomStatus?,
        startsAt: Date?,
        ownReady: Bool,
        opponentReady: Bool,
        now: Date = Date()
    ) -> Bool {
        guard let startsAt,
              status == .countdown || status == .racing,
              ownReady, opponentReady else { return false }
        let elapsed = now.timeIntervalSince(startsAt)
        // The synchronized window is short; reopening much later should
        // reconnect an existing workout, not start an unrelated new one.
        return elapsed >= 0 && elapsed <= 15
    }
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

/// A second client-side guard complementing the immutable finish time
/// enforced by the Live Ghost database trigger.
enum LiveGhostFinishSubmissionRule {
    static func canSubmit(
        elapsedSeconds: TimeInterval,
        alreadyFinished: Bool
    ) -> Bool {
        !alreadyFinished &&
        elapsedSeconds.isFinite &&
        (5...86_400).contains(elapsedSeconds)
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

    @Published private(set)
    var isCancelling = false

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
    private var isSubmittingFinish = false

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
        guard challenge.status == .accepted,
              let userID = currentUserID,
              userID == challenge.senderID ||
                userID == challenge.recipientID
        else {
            errorMessage = ATHLTHLocalization.choose(
                english: "This Live Ghost room is no longer available.",
                norwegian: "Dette Live Ghost-rommet er ikke lenger tilgjengelig."
            )
            return
        }

        // Invitation expiry is a creation deadline, not a forced stop for
        // a synchronized duel already in countdown or racing. Check the
        // authoritative room on the server before allowing late reentry;
        // absent, finished or cancelled rooms are never reopened by expiry.
        if challenge.expiresAt <= Date() {
            do {
                let currentRooms: [LiveGhostRaceRoomRecord] =
                    try await client
                        .from("live_ghost_race_rooms")
                        .select()
                        .eq("challenge_id", value: challenge.id)
                        .limit(1)
                        .execute().value
                guard LiveGhostRaceReentry.allowed(
                    expiresAt: challenge.expiresAt,
                    roomStatus: currentRooms.first?.status
                ) else {
                    errorMessage = ATHLTHLocalization.choose(
                        english: "This Live Ghost invitation expired before the race started.",
                        norwegian: "Invitasjonen til Live Ghost utløp før løpet startet."
                    )
                    return
                }
            } catch {
                errorMessage = error.localizedDescription
                return
            }
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

    /// Re-fetch both room and athletes before starting a recording.
    /// Realtime is fast but not authoritative when a cancellation or an
    /// opposing READY change races with the local countdown.
    func confirmSynchronizedStart(
        challengeID: UUID,
        senderID: UUID,
        recipientID: UUID
    ) async -> Bool {
        guard activeChallengeID == challengeID,
              let userID = currentUserID,
              userID == senderID || userID == recipientID else {
            return false
        }
        do {
            async let freshRooms: [LiveGhostRaceRoomRecord] = client
                .from("live_ghost_race_rooms")
                .select()
                .eq("challenge_id", value: challengeID)
                .limit(1)
                .execute().value
            async let freshParticipants: [LiveGhostRaceParticipantRecord] = client
                .from("live_ghost_race_participants")
                .select()
                .eq("challenge_id", value: challengeID)
                .execute().value
            let rooms = try await freshRooms
            let athleteRows = try await freshParticipants
            guard !Task.isCancelled,
                  activeChallengeID == challengeID,
                  let latest = rooms.first,
                  latest.challengeID == challengeID,
                  athleteRows.count == 2,
                  let sender = athleteRows.first(where: { $0.userID == senderID }),
                  let recipient = athleteRows.first(where: { $0.userID == recipientID }),
                  sender.userID != recipient.userID,
                  sender.deviceType != nil,
                  recipient.deviceType != nil else { return false }

            room = latest
            participants = athleteRows
            return LiveGhostSynchronizedLaunchGate.mayLaunch(
                status: latest.status,
                startsAt: latest.startsAt,
                ownReady: (userID == senderID ? sender : recipient).ready,
                opponentReady: (userID == senderID ? recipient : sender).ready,
                now: Date()
            )
        } catch {
            // Fail closed. A network outage must not start a new local
            // workout from unverified readiness; retry through the lobby.
            errorMessage = error.localizedDescription
            return false
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

    /// An explicit participant DNF cancels only the synchronized race.
    /// The server verifies membership, preserves terminal state and stops
    /// the shared session. Local HealthKit/Watch recording is left intact.
    @discardableResult
    func cancelDuel() async -> Bool {
        guard let challengeID = activeChallengeID,
              !isCancelling,
              let room,
              room.status != .finished,
              room.status != .cancelled else {
            return false
        }
        isCancelling = true
        errorMessage = nil
        defer { isCancelling = false }

        do {
            let changed: Bool = try await client
                .rpc(
                    "cancel_live_ghost_duel",
                    params: ["p_challenge_id": challengeID.uuidString]
                )
                .execute().value
            await refresh(challengeID: challengeID)
            return changed
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func markFinished(
        elapsedSeconds:
            TimeInterval
    ) async {
        guard let challengeID = activeChallengeID,
              let userID = currentUserID,
              !isSubmittingFinish,
              LiveGhostFinishSubmissionRule.canSubmit(
                  elapsedSeconds: elapsedSeconds,
                  alreadyFinished: currentParticipant?.finishedAt != nil
              ) else {
            return
        }

        isSubmittingFinish = true
        defer { isSubmittingFinish = false }

        do {
            let now = Date()
            try await client
                .from("live_ghost_race_participants")
                .update(
                    LiveGhostParticipantFinishWrite(
                        finishedAt: now,
                        elapsedSeconds: elapsedSeconds,
                        updatedAt: now
                    )
                )
                .eq("challenge_id", value: challengeID)
                .eq("user_id", value: userID)
                .execute()

            // The server preserves the first finish and is authoritative.
            await refresh(challengeID: challengeID)
        } catch {
            // An unsuccessful network call is retryable; never mark the
            // participant finished locally before the server accepts it.
            errorMessage = error.localizedDescription
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
