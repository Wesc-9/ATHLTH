import CoreLocation
import Foundation
import Supabase

@MainActor
final class ATHLTHRealtimeStore: ObservableObject {
    @Published private(set) var onlineUserIDs: Set<UUID> = []
    @Published private(set) var activeLiveSessions: [LiveWorkoutSessionRecord] = []
    @Published private(set) var currentLiveSession: LiveWorkoutSessionRecord?
    @Published private(set) var watchedSession: LiveWorkoutSessionRecord?
    @Published private(set) var watchedLocation: LiveWorkoutLocationMessage?
    @Published private(set) var watchedTrail: [LiveWorkoutLocationMessage] = []
    @Published private(set) var sharingStateText = "Live location off"
    @Published var errorMessage: String?

    private let client: SupabaseClient
    private var onlineHeartbeatTask: Task<Void, Never>?
    private var ownOnlineUserID: UUID?
    private var senderChannel: RealtimeChannelV2?
    private var viewerChannel: RealtimeChannelV2?
    private var viewerSubscriptions = Set<RealtimeSubscription>()

    private var lastLocationBroadcastAt: Date?
    private var lastMetadataHeartbeatAt: Date?
    private var lastBroadcastLocation: CLLocation?
    private var lastSessionStatus: String?

    private let onlineHeartbeatInterval: TimeInterval = 60
    private let onlineTimeout: TimeInterval = 120
    private let locationBroadcastInterval: TimeInterval = 4
    private let locationMovementThreshold: CLLocationDistance = 8
    private let metadataHeartbeatInterval: TimeInterval = 30
    private let liveSessionTimeout: TimeInterval = 150
    private let maximumTrailPoints = 120

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    deinit {
        onlineHeartbeatTask?.cancel()
    }

    func isOnline(_ userID: UUID) -> Bool {
        onlineUserIDs.contains(userID)
    }

    func configureOnlinePresence(
        userID: UUID,
        enabled: Bool,
        appIsActive: Bool
    ) async {
        onlineHeartbeatTask?.cancel()
        onlineHeartbeatTask = nil
        ownOnlineUserID = userID

        guard appIsActive else {
            await clearOwnOnlinePresence(
                userID: userID
            )
            onlineUserIDs = []
            return
        }

        if enabled {
            await writeOnlineHeartbeat(
                userID: userID
            )
        } else {
            await clearOwnOnlinePresence(
                userID: userID
            )
        }

        await refreshOnlinePresence()

        onlineHeartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(
                    for: .seconds(
                        self?.onlineHeartbeatInterval ?? 60
                    )
                )

                guard !Task.isCancelled,
                      let self
                else {
                    return
                }

                if enabled {
                    await self.writeOnlineHeartbeat(
                        userID: userID
                    )
                }

                await self.refreshOnlinePresence()
            }
        }
    }

    func stopOnlinePresence() async {
        onlineHeartbeatTask?.cancel()
        onlineHeartbeatTask = nil

        if let ownOnlineUserID {
            await clearOwnOnlinePresence(
                userID: ownOnlineUserID
            )
        }

        ownOnlineUserID = nil
    }

    func shutdown() async {
        await stopOnlinePresence()
        await endLiveSharing()
        await stopWatching()
        onlineUserIDs = []
        activeLiveSessions = []
    }

    func refreshOnlinePresence() async {
        do {
            let rows: [OnlinePresenceRecord] =
                try await client
                    .from("social_online_presence")
                    .select()
                    .limit(500)
                    .execute()
                    .value

            let now = Date()
            onlineUserIDs = Set(
                rows
                    .filter {
                        $0.isOnline(
                            now: now,
                            timeout: onlineTimeout
                        )
                    }
                    .map(\.userID)
            )
        } catch {
            // Presence is enhancement-only. Do not turn a temporary realtime
            // or migration issue into an app-level failure.
        }
    }

    func refreshLiveSessions() async {
        do {
            let rows: [LiveWorkoutSessionRecord] =
                try await client
                    .from("live_workout_sessions")
                    .select()
                    .order(
                        "started_at",
                        ascending: false
                    )
                    .limit(80)
                    .execute()
                    .value

            let now = Date()
            activeLiveSessions = rows.filter {
                $0.isLive &&
                now.timeIntervalSince(
                    $0.lastBroadcastAt
                ) <= liveSessionTimeout
            }
        } catch {
            // Live discovery should disappear gracefully when the backend
            // feature is unavailable.
            activeLiveSessions = []
        }
    }

    func handleMirroredWorkout(
        _ snapshot: WatchWorkoutLiveSnapshot,
        userID: UUID,
        shareLocation: Bool,
        audience: LiveWorkoutAudience,
        ghostReferenceID: UUID?
    ) async {
        guard shareLocation,
              snapshot.kind == .running ||
                snapshot.kind == .walking ||
                snapshot.kind == .cycling
        else {
            if currentLiveSession != nil {
                await endLiveSharing()
            }
            return
        }

        if snapshot.state == .completed ||
            snapshot.state == .failed {
            await endLiveSharing()
            return
        }

        let session: LiveWorkoutSessionRecord

        do {
            if let currentLiveSession {
                session = currentLiveSession
            } else {
                session = try await createLiveSession(
                    snapshot: snapshot,
                    userID: userID,
                    audience: audience,
                    ghostReferenceID:
                        ghostReferenceID
                )
                currentLiveSession = session
                sharingStateText =
                    ghostReferenceID == nil
                        ? "Sharing live workout"
                        : "Sharing live Ghost Race"
                try await prepareSenderChannel(
                    for: session
                )
            }

            let desiredStatus =
                snapshot.state == .paused
                    ? "paused"
                    : "active"

            if desiredStatus != lastSessionStatus {
                try await updateSessionMetadata(
                    sessionID: session.id,
                    status: desiredStatus,
                    endedAt: nil
                )
                lastSessionStatus = desiredStatus
            }

            guard let latitude =
                    snapshot.currentLatitude,
                  let longitude =
                    snapshot.currentLongitude
            else {
                return
            }

            let location = CLLocation(
                latitude: latitude,
                longitude: longitude
            )

            guard shouldBroadcast(
                location: location,
                capturedAt: snapshot.capturedAt
            ) else {
                return
            }

            let message =
                LiveWorkoutLocationMessage(
                    sessionID: session.id,
                    ownerID: userID,
                    latitude: latitude,
                    longitude: longitude,
                    capturedAt:
                        snapshot.capturedAt
                            .timeIntervalSince1970,
                    elapsedTime:
                        snapshot.elapsedTime,
                    distanceMeters:
                        snapshot.distanceMeters,
                    routeProgressPercent:
                        snapshot
                            .routeProgressPercent,
                    state:
                        desiredStatus,
                    mode:
                        ghostReferenceID == nil
                            ? "workout"
                            : "ghost",
                    ghostReferenceID:
                        ghostReferenceID
                )

            if senderChannel == nil {
                try await prepareSenderChannel(
                    for: session
                )
            }

            if let senderChannel {
                try await senderChannel.broadcast(
                    event: "location",
                    message: message
                )
            }

            lastLocationBroadcastAt =
                snapshot.capturedAt
            lastBroadcastLocation =
                location

            if shouldRefreshSessionMetadata(
                at: snapshot.capturedAt
            ) {
                try await updateSessionMetadata(
                    sessionID: session.id,
                    status: desiredStatus,
                    endedAt: nil
                )
                lastMetadataHeartbeatAt =
                    snapshot.capturedAt
            }
        } catch {
            errorMessage =
                "Live workout sharing is temporarily unavailable."
            sharingStateText =
                "Live location unavailable"
        }
    }

    func endLiveSharing() async {
        onlineSafeResetSenderState()

        guard let session =
                currentLiveSession
        else {
            sharingStateText =
                "Live location off"
            return
        }

        do {
            try await updateSessionMetadata(
                sessionID: session.id,
                status: "ended",
                endedAt: Date()
            )
        } catch {
            // Ending locally is more important than keeping a stale socket.
        }

        if let senderChannel {
            await client.removeChannel(
                senderChannel
            )
        }

        self.senderChannel = nil
        currentLiveSession = nil
        sharingStateText = "Live location off"
        await refreshLiveSessions()
    }

    func watch(
        _ session: LiveWorkoutSessionRecord
    ) async {
        await stopWatching()

        watchedSession = session
        watchedLocation = nil
        watchedTrail = []
        errorMessage = nil

        let channel =
            client.channel(
                session.channelTopic
            ) {
                $0.isPrivate = true
            }

        let subscription =
            channel.onBroadcast(
                event: "location"
            ) { [weak self] payload in
                guard let message =
                        Self.locationMessage(
                            from: payload
                        )
                else {
                    return
                }

                Task { @MainActor [weak self] in
                    self?.consume(
                        message,
                        expectedSessionID:
                            session.id
                    )
                }
            }

        viewerSubscriptions.insert(
            subscription
        )
        viewerChannel = channel

        await channel.subscribe()
    }

    func stopWatching() async {
        viewerSubscriptions.removeAll()

        if let viewerChannel {
            await client.removeChannel(
                viewerChannel
            )
        }

        viewerChannel = nil
        watchedSession = nil
        watchedLocation = nil
        watchedTrail = []
    }

    func sessions(
        matchingGhostReferenceID referenceID: UUID
    ) -> [LiveWorkoutSessionRecord] {
        activeLiveSessions.filter {
            $0.ghostReferenceID == referenceID
        }
    }

    private func writeOnlineHeartbeat(
        userID: UUID
    ) async {
        let now = Date()
        let payload = OnlinePresenceWrite(
            userID: userID,
            lastSeenAt: now,
            updatedAt: now
        )

        do {
            try await client
                .from("social_online_presence")
                .upsert(payload)
                .execute()
        } catch {
            // Online state is deliberately best-effort.
        }
    }

    private func clearOwnOnlinePresence(
        userID: UUID
    ) async {
        do {
            try await client
                .from("social_online_presence")
                .delete()
                .eq(
                    "user_id",
                    value: userID
                )
                .execute()
        } catch {
            // A stale heartbeat expires client-side after onlineTimeout.
        }

        onlineUserIDs.remove(userID)
    }

    private func createLiveSession(
        snapshot: WatchWorkoutLiveSnapshot,
        userID: UUID,
        audience: LiveWorkoutAudience,
        ghostReferenceID: UUID?
    ) async throws -> LiveWorkoutSessionRecord {
        let id = UUID()
        let now = Date()
        let payload =
            LiveWorkoutSessionInsert(
                id: id,
                ownerID: userID,
                activity:
                    snapshot.kind.rawValue,
                title:
                    snapshot.kind.title,
                mode:
                    ghostReferenceID == nil
                        ? "workout"
                        : "ghost",
                ghostReferenceID:
                    ghostReferenceID,
                visibility:
                    audience.rawValue,
                channelTopic:
                    "live-workout:\(id.uuidString)",
                status:
                    snapshot.state == .paused
                        ? "paused"
                        : "active",
                startedAt:
                    snapshot.startedAt ?? now,
                lastBroadcastAt: now
            )

        let session: LiveWorkoutSessionRecord =
            try await client
                .from("live_workout_sessions")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value

        lastSessionStatus =
            session.status
        lastMetadataHeartbeatAt = now

        return session
    }

    private func prepareSenderChannel(
        for session: LiveWorkoutSessionRecord
    ) async throws {
        if let senderChannel {
            await client.removeChannel(
                senderChannel
            )
        }

        let channel =
            client.channel(
                session.channelTopic
            ) {
                $0.isPrivate = true
                $0.broadcast
                    .acknowledgeBroadcasts =
                    false
            }

        await channel.subscribe()
        senderChannel = channel
    }

    private func updateSessionMetadata(
        sessionID: UUID,
        status: String,
        endedAt: Date?
    ) async throws {
        let now = Date()

        if let endedAt {
            try await client
                .from("live_workout_sessions")
                .update(
                    LiveWorkoutSessionEndWrite(
                        status: status,
                        endedAt: endedAt,
                        lastBroadcastAt: now,
                        updatedAt: now
                    )
                )
                .eq(
                    "id",
                    value: sessionID
                )
                .execute()
        } else {
            try await client
                .from("live_workout_sessions")
                .update(
                    LiveWorkoutSessionHeartbeatWrite(
                        status: status,
                        lastBroadcastAt: now,
                        updatedAt: now
                    )
                )
                .eq(
                    "id",
                    value: sessionID
                )
                .execute()
        }
    }

    private func shouldBroadcast(
        location: CLLocation,
        capturedAt: Date
    ) -> Bool {
        if let lastLocationBroadcastAt,
           capturedAt.timeIntervalSince(
                lastLocationBroadcastAt
           ) < locationBroadcastInterval {
            return false
        }

        guard let lastBroadcastLocation
        else {
            return true
        }

        let moved =
            location.distance(
                from: lastBroadcastLocation
            )

        return moved >= locationMovementThreshold ||
            (
                lastLocationBroadcastAt.map {
                    capturedAt.timeIntervalSince($0)
                } ?? 0
            ) >= 10
    }

    private func shouldRefreshSessionMetadata(
        at date: Date
    ) -> Bool {
        guard let lastMetadataHeartbeatAt
        else {
            return true
        }

        return date.timeIntervalSince(
            lastMetadataHeartbeatAt
        ) >= metadataHeartbeatInterval
    }

    private func onlineSafeResetSenderState() {
        lastLocationBroadcastAt = nil
        lastMetadataHeartbeatAt = nil
        lastBroadcastLocation = nil
        lastSessionStatus = nil
        errorMessage = nil
    }

    private func consume(
        _ message: LiveWorkoutLocationMessage,
        expectedSessionID: UUID
    ) {
        guard message.sessionID ==
                expectedSessionID
        else {
            return
        }

        if let last =
                watchedTrail.last,
           message.capturedAt <=
                last.capturedAt {
            return
        }

        watchedLocation = message
        watchedTrail.append(message)

        if watchedTrail.count >
            maximumTrailPoints {
            watchedTrail.removeFirst(
                watchedTrail.count -
                maximumTrailPoints
            )
        }
    }

    nonisolated private static func locationMessage(
        from payload: JSONObject
    ) -> LiveWorkoutLocationMessage? {
        guard
            let sessionText =
                payload["session_id"]?
                    .stringValue,
            let sessionID =
                UUID(
                    uuidString:
                        sessionText
                ),
            let ownerText =
                payload["owner_id"]?
                    .stringValue,
            let ownerID =
                UUID(
                    uuidString:
                        ownerText
                ),
            let latitude =
                payload["latitude"]?
                    .doubleValue,
            let longitude =
                payload["longitude"]?
                    .doubleValue,
            let capturedAt =
                payload["captured_at"]?
                    .doubleValue,
            let elapsedTime =
                payload["elapsed_time"]?
                    .doubleValue,
            let distanceMeters =
                payload["distance_meters"]?
                    .doubleValue,
            let state =
                payload["state"]?
                    .stringValue,
            let mode =
                payload["mode"]?
                    .stringValue
        else {
            return nil
        }

        let progress =
            payload[
                "route_progress_percent"
            ]?.doubleValue

        let ghostReferenceID =
            payload[
                "ghost_reference_id"
            ]?
            .stringValue
            .flatMap {
                UUID(uuidString: $0)
            }

        return LiveWorkoutLocationMessage(
            sessionID: sessionID,
            ownerID: ownerID,
            latitude: latitude,
            longitude: longitude,
            capturedAt: capturedAt,
            elapsedTime: elapsedTime,
            distanceMeters: distanceMeters,
            routeProgressPercent:
                progress,
            state: state,
            mode: mode,
            ghostReferenceID:
                ghostReferenceID
        )
    }
}

private struct LiveWorkoutSessionHeartbeatWrite: Encodable {
    let status: String
    let lastBroadcastAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case lastBroadcastAt = "last_broadcast_at"
        case updatedAt = "updated_at"
    }
}

private struct LiveWorkoutSessionEndWrite: Encodable {
    let status: String
    let endedAt: Date
    let lastBroadcastAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case endedAt = "ended_at"
        case lastBroadcastAt = "last_broadcast_at"
        case updatedAt = "updated_at"
    }
}
