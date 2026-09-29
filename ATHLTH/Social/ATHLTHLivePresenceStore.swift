import CoreLocation
import Foundation
import Supabase

struct ATHLTHOnlinePresenceRecord: Codable, Hashable {
    let userID: UUID
    let lastSeenAt: Date
    let onlineUntil: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case lastSeenAt = "last_seen_at"
        case onlineUntil = "online_until"
        case updatedAt = "updated_at"
    }

    var isOnline: Bool {
        onlineUntil > Date()
    }
}

struct ATHLTHLiveWorkoutSession: Identifiable, Codable, Hashable {
    let id: UUID
    let userID: UUID
    let workoutID: UUID?
    let activityKind: String
    let title: String
    let status: String
    let ghostEnabled: Bool
    let startedAt: Date
    let endedAt: Date?
    let updatedAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case workoutID = "workout_id"
        case activityKind = "activity_kind"
        case title
        case status
        case ghostEnabled = "ghost_enabled"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case updatedAt = "updated_at"
        case expiresAt = "expires_at"
    }

    var isActive: Bool {
        status == "active" && expiresAt > Date()
    }
}

struct ATHLTHLiveWorkoutPoint: Identifiable, Codable, Hashable {
    let id: Int64
    let sessionID: UUID
    let userID: UUID
    let capturedAt: Date
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double?
    let horizontalAccuracyMeters: Double?
    let distanceMeters: Double
    let elapsedSeconds: Double
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case userID = "user_id"
        case capturedAt = "captured_at"
        case latitude
        case longitude
        case altitudeMeters = "altitude_meters"
        case horizontalAccuracyMeters = "horizontal_accuracy_meters"
        case distanceMeters = "distance_meters"
        case elapsedSeconds = "elapsed_seconds"
        case expiresAt = "expires_at"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }
}

private struct ATHLTHOnlinePresenceWrite: Encodable {
    let userID: UUID
    let lastSeenAt: Date
    let onlineUntil: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case lastSeenAt = "last_seen_at"
        case onlineUntil = "online_until"
        case updatedAt = "updated_at"
    }
}

private struct ATHLTHLiveWorkoutSessionWrite: Encodable {
    let id: UUID
    let userID: UUID
    let workoutID: UUID?
    let activityKind: String
    let title: String
    let ghostEnabled: Bool
    let startedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case workoutID = "workout_id"
        case activityKind = "activity_kind"
        case title
        case ghostEnabled = "ghost_enabled"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
    }
}

private struct ATHLTHLiveWorkoutSessionFinish: Encodable {
    let status: String
    let endedAt: Date
    let updatedAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case endedAt = "ended_at"
        case updatedAt = "updated_at"
        case expiresAt = "expires_at"
    }
}

private struct ATHLTHLiveWorkoutPointWrite: Encodable {
    let sessionID: UUID
    let userID: UUID
    let capturedAt: Date
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double?
    let horizontalAccuracyMeters: Double?
    let distanceMeters: Double
    let elapsedSeconds: Double

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case userID = "user_id"
        case capturedAt = "captured_at"
        case latitude
        case longitude
        case altitudeMeters = "altitude_meters"
        case horizontalAccuracyMeters = "horizontal_accuracy_meters"
        case distanceMeters = "distance_meters"
        case elapsedSeconds = "elapsed_seconds"
    }
}

@MainActor
final class ATHLTHLivePresenceStore: ObservableObject {
    @Published private(set) var onlineUserIDs: Set<UUID> = []
    @Published private(set) var liveSessions: [ATHLTHLiveWorkoutSession] = []
    @Published private(set) var pointsBySession: [UUID: [ATHLTHLiveWorkoutPoint]] = [:]
    @Published private(set) var ownLiveSessionID: UUID?
    @Published var selectedLiveGhostSessionID: UUID?
    @Published var errorMessage: String?

    private let client: SupabaseClient
    private var channel: RealtimeChannelV2?
    private var realtimeTasks: [Task<Void, Never>] = []
    private var heartbeatTask: Task<Void, Never>?
    private var showOnlineStatus = false
    private var shareLiveLocation = false
    private var lastPointPublishedAt: Date?
    private var lastPointLocation: CLLocation?

    init(
        client: SupabaseClient = SupabaseEnvironment.client
    ) {
        self.client = client
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    func configure(
        showOnlineStatus: Bool,
        shareLiveLocation: Bool
    ) async {
        let onlineChanged =
            self.showOnlineStatus != showOnlineStatus
        let locationChanged =
            self.shareLiveLocation != shareLiveLocation

        self.showOnlineStatus = showOnlineStatus
        self.shareLiveLocation = shareLiveLocation

        if onlineChanged {
            if showOnlineStatus {
                await markOnline()
            } else {
                await markOffline()
            }
        }

        if locationChanged,
           !shareLiveLocation,
           ownLiveSessionID != nil {
            await finishOwnLiveWorkout(cancelled: true)
        }

        await refresh()
    }

    func activate() async {
        await stopRealtime()
        await startRealtime()
        await refresh()

        if showOnlineStatus {
            await markOnline()
            startHeartbeat()
        }
    }

    func deactivate() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil

        if showOnlineStatus {
            await markOffline()
        }
    }

    func reset() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        await stopRealtime()
        onlineUserIDs = []
        liveSessions = []
        pointsBySession = [:]
        ownLiveSessionID = nil
        selectedLiveGhostSessionID = nil
        lastPointPublishedAt = nil
        lastPointLocation = nil
    }

    func isOnline(_ userID: UUID) -> Bool {
        onlineUserIDs.contains(userID)
    }

    func refresh() async {
        guard currentUserID != nil else {
            onlineUserIDs = []
            liveSessions = []
            pointsBySession = [:]
            return
        }

        do {
            async let onlineRows: [ATHLTHOnlinePresenceRecord] =
                client
                    .from("user_online_presence")
                    .select()
                    .gt("online_until", value: Date())
                    .execute()
                    .value

            async let sessions: [ATHLTHLiveWorkoutSession] =
                client
                    .from("live_workout_sessions")
                    .select()
                    .eq("status", value: "active")
                    .order("updated_at", ascending: false)
                    .limit(50)
                    .execute()
                    .value

            let (presence, sessionRows) =
                try await (onlineRows, sessions)

            onlineUserIDs = Set(
                presence
                    .filter(\.isOnline)
                    .map(\.userID)
            )

            liveSessions =
                sessionRows
                    .filter(\.isActive)
                    .filter {
                        $0.userID != currentUserID
                    }

            var refreshedPoints:
                [UUID: [ATHLTHLiveWorkoutPoint]] = [:]

            for session in liveSessions {
                let points:
                    [ATHLTHLiveWorkoutPoint] =
                    try await client
                        .from("live_workout_points")
                        .select()
                        .eq(
                            "session_id",
                            value: session.id
                        )
                        .order(
                            "captured_at",
                            ascending: false
                        )
                        .limit(1)
                        .execute()
                        .value

                refreshedPoints[session.id] =
                    points.sorted {
                        $0.capturedAt < $1.capturedAt
                    }
            }

            pointsBySession = refreshedPoints
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func startOwnLiveWorkout(
        workoutID: UUID,
        walking: Bool,
        title: String,
        ghostEnabled: Bool = true
    ) async -> UUID? {
        guard shareLiveLocation,
              let userID = currentUserID
        else {
            return nil
        }

        if ownLiveSessionID != nil {
            await finishOwnLiveWorkout(cancelled: true)
        }

        let now = Date()
        let sessionID = UUID()

        do {
            try await client
                .from("live_workout_sessions")
                .insert(
                    ATHLTHLiveWorkoutSessionWrite(
                        id: sessionID,
                        userID: userID,
                        workoutID: workoutID,
                        activityKind:
                            walking
                                ? "walking"
                                : "running",
                        title: title,
                        ghostEnabled: ghostEnabled,
                        startedAt: now,
                        updatedAt: now
                    )
                )
                .execute()

            ownLiveSessionID = sessionID
            lastPointPublishedAt = nil
            lastPointLocation = nil

            _ = try? await client
                .rpc("prune_live_workout_data")
                .execute()

            return sessionID
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func publishOwnLivePoint(
        location: CLLocation,
        distanceMeters: Double,
        elapsedSeconds: TimeInterval
    ) async {
        guard shareLiveLocation,
              let sessionID = ownLiveSessionID,
              let userID = currentUserID,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 40
        else {
            return
        }

        let now = Date()

        if let lastPointPublishedAt,
           now.timeIntervalSince(lastPointPublishedAt) < 5,
           let lastPointLocation,
           location.distance(from: lastPointLocation) < 20 {
            return
        }

        do {
            try await client
                .from("live_workout_points")
                .insert(
                    ATHLTHLiveWorkoutPointWrite(
                        sessionID: sessionID,
                        userID: userID,
                        capturedAt: location.timestamp,
                        latitude:
                            location.coordinate.latitude,
                        longitude:
                            location.coordinate.longitude,
                        altitudeMeters:
                            location.altitude.isFinite
                                ? location.altitude
                                : nil,
                        horizontalAccuracyMeters:
                            location.horizontalAccuracy,
                        distanceMeters:
                            max(distanceMeters, 0),
                        elapsedSeconds:
                            max(elapsedSeconds, 0)
                    )
                )
                .execute()

            try await client
                .from("live_workout_sessions")
                .update(
                    ["updated_at":
                        now.ISO8601Format()]
                )
                .eq("id", value: sessionID)
                .execute()

            lastPointPublishedAt = now
            lastPointLocation = location
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finishOwnLiveWorkout(
        cancelled: Bool = false
    ) async {
        guard let sessionID = ownLiveSessionID else {
            return
        }

        let now = Date()

        do {
            try await client
                .from("live_workout_sessions")
                .update(
                    ATHLTHLiveWorkoutSessionFinish(
                        status:
                            cancelled
                                ? "cancelled"
                                : "finished",
                        endedAt: now,
                        updatedAt: now,
                        expiresAt:
                            now.addingTimeInterval(
                                60 * 60
                            )
                    )
                )
                .eq("id", value: sessionID)
                .execute()
        } catch {
            errorMessage = error.localizedDescription
        }

        ownLiveSessionID = nil
        lastPointPublishedAt = nil
        lastPointLocation = nil
    }

    func refreshPoints(
        for sessionID: UUID,
        limit: Int = 240
    ) async {
        guard currentUserID != nil else {
            return
        }

        do {
            let points:
                [ATHLTHLiveWorkoutPoint] =
                try await client
                    .from("live_workout_points")
                    .select()
                    .eq(
                        "session_id",
                        value: sessionID
                    )
                    .order(
                        "captured_at",
                        ascending: false
                    )
                    .limit(
                        min(
                            max(limit, 1),
                            400
                        )
                    )
                    .execute()
                    .value

            pointsBySession[sessionID] =
                points.sorted {
                    $0.capturedAt < $1.capturedAt
                }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func latestPoint(
        for sessionID: UUID
    ) -> ATHLTHLiveWorkoutPoint? {
        pointsBySession[sessionID]?.last
    }

    func liveGhostDeltaMeters(
        ownDistanceMeters: Double
    ) -> Double? {
        guard let selectedLiveGhostSessionID,
              let point =
                latestPoint(
                    for: selectedLiveGhostSessionID
                )
        else {
            return nil
        }

        return ownDistanceMeters -
            point.distanceMeters
    }

    private func markOnline() async {
        guard showOnlineStatus,
              let userID = currentUserID
        else {
            return
        }

        let now = Date()

        do {
            try await client
                .from("user_online_presence")
                .upsert(
                    ATHLTHOnlinePresenceWrite(
                        userID: userID,
                        lastSeenAt: now,
                        onlineUntil:
                            now.addingTimeInterval(
                                90
                            ),
                        updatedAt: now
                    )
                )
                .execute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markOffline() async {
        guard let userID = currentUserID else {
            return
        }

        let now = Date()

        do {
            try await client
                .from("user_online_presence")
                .upsert(
                    ATHLTHOnlinePresenceWrite(
                        userID: userID,
                        lastSeenAt: now,
                        onlineUntil: now,
                        updatedAt: now
                    )
                )
                .execute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()

        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(
                    for: .seconds(45)
                )

                guard !Task.isCancelled,
                      let self
                else {
                    return
                }

                await self.markOnline()
            }
        }
    }

    private func startRealtime() async {
        guard currentUserID != nil else {
            return
        }

        let channel =
            client.channel(
                "athlth-live-(UUID().uuidString)"
            )

        let onlineChanges =
            channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "user_online_presence"
            )
        let sessionChanges =
            channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "live_workout_sessions"
            )
        let pointChanges =
            channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "live_workout_points"
            )

        await channel.subscribe()
        self.channel = channel

        realtimeTasks = [
            Task { [weak self] in
                for await _ in onlineChanges {
                    guard !Task.isCancelled else {
                        return
                    }
                    await self?.refresh()
                }
            },
            Task { [weak self] in
                for await _ in sessionChanges {
                    guard !Task.isCancelled else {
                        return
                    }
                    await self?.refresh()
                }
            },
            Task { [weak self] in
                for await _ in pointChanges {
                    guard !Task.isCancelled else {
                        return
                    }
                    await self?.refresh()
                }
            }
        ]
    }

    private func stopRealtime() async {
        realtimeTasks.forEach { $0.cancel() }
        realtimeTasks = []

        if let channel {
            await client.removeChannel(channel)
            self.channel = nil
        }
    }
}
