import Combine
import CoreLocation
import Foundation
import Supabase

struct ATHLTHOnlinePresenceRecord: Codable, Hashable {
    let userID: UUID
    let isOnline: Bool
    let deviceSessionID: UUID?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case isOnline = "is_online"
        case deviceSessionID = "device_session_id"
        case updatedAt = "updated_at"
    }
}

enum ATHLTHLiveWorkoutVisibility: String, Codable, CaseIterable, Identifiable {
    case privateOnly = "private"
    case followers
    case mutuals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privateOnly:
            return "Private"
        case .followers:
            return "Followers"
        case .mutuals:
            return "Mutual follows"
        }
    }
}

struct ATHLTHLiveWorkoutSession: Identifiable, Codable, Hashable {
    let id: UUID
    let ownerID: UUID
    let opponentUserID: UUID?
    let ghostChallengeID: UUID?
    let activity: String
    let title: String
    let visibility: String
    let status: String
    let startedAt: Date
    let endedAt: Date?
    let createdAt: Date
    let updatedAt: Date?
    let routeKey: UUID?
    let routeDistanceMeters: Double?
    let routeTitle: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case opponentUserID = "opponent_user_id"
        case ghostChallengeID = "ghost_challenge_id"
        case activity
        case title
        case visibility
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case routeKey = "route_key"
        case routeDistanceMeters = "route_distance_meters"
        case routeTitle = "route_title"
    }

    init(
        id: UUID,
        ownerID: UUID,
        opponentUserID: UUID?,
        ghostChallengeID: UUID?,
        activity: String,
        title: String,
        visibility: String,
        status: String,
        startedAt: Date,
        endedAt: Date?,
        createdAt: Date,
        updatedAt: Date?,
        routeKey: UUID? = nil,
        routeDistanceMeters: Double? = nil,
        routeTitle: String? = nil
    ) {
        self.id = id
        self.ownerID = ownerID
        self.opponentUserID =
            opponentUserID
        self.ghostChallengeID =
            ghostChallengeID
        self.activity = activity
        self.title = title
        self.visibility = visibility
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.routeKey = routeKey
        self.routeDistanceMeters =
            routeDistanceMeters
        self.routeTitle = routeTitle
    }

    var isActive: Bool {
        status == "active" || status == "paused"
    }
}

struct ATHLTHLiveWorkoutLocation: Identifiable, Codable, Hashable {
    var id: String {
        sessionID.uuidString + ":" + userID.uuidString
    }

    let sessionID: UUID
    let userID: UUID
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double?
    let speedMetersPerSecond: Double?
    let courseDegrees: Double?
    let heartRateBPM: Double?
    let distanceMeters: Double
    let elapsedSeconds: Double
    let routeProgressPercent: Double? = nil
    let routeDeviationMeters: Double? = nil
    let updatedAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case userID = "user_id"
        case latitude
        case longitude
        case horizontalAccuracy = "horizontal_accuracy"
        case speedMetersPerSecond = "speed_meters_per_second"
        case courseDegrees = "course_degrees"
        case heartRateBPM = "heart_rate_bpm"
        case distanceMeters = "distance_meters"
        case elapsedSeconds = "elapsed_seconds"
        case routeProgressPercent = "route_progress_percent"
        case routeDeviationMeters = "route_deviation_meters"
        case updatedAt = "updated_at"
        case expiresAt = "expires_at"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }

    var isFresh: Bool {
        expiresAt > Date() &&
        Date().timeIntervalSince(updatedAt) < 95
    }
}

enum ATHLTHLiveGhostComparisonMode: Equatable {
    case routeAware
    case distanceFallback
}

struct ATHLTHLiveGhostComparison: Equatable {
    let sessionID: UUID
    let opponentUserID: UUID
    let opponentDistanceMeters: Double
    let opponentElapsedSeconds: TimeInterval
    let signedDistanceMeters: Double
    let estimatedTimeDeltaSeconds: TimeInterval?
    let mode: ATHLTHLiveGhostComparisonMode
    let routeKey: UUID?
    let ownRouteProgressPercent: Double?
    let opponentRouteProgressPercent: Double?
    let opponentRouteDeviationMeters: Double?
    let updatedAt: Date

    var userIsAhead: Bool {
        signedDistanceMeters >= 0
    }

    var isRouteAware: Bool {
        mode == .routeAware
    }
}

private struct ATHLTHOnlinePresenceWrite: Encodable {
    let userID: UUID
    let isOnline: Bool
    let deviceSessionID: UUID
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case isOnline = "is_online"
        case deviceSessionID = "device_session_id"
        case updatedAt = "updated_at"
    }
}

private struct ATHLTHLiveWorkoutSessionInsert: Encodable {
    let id: UUID
    let ownerID: UUID
    let opponentUserID: UUID?
    let ghostChallengeID: UUID?
    let activity: String
    let title: String
    let visibility: String
    let status: String
    let startedAt: Date
    let routeKey: UUID?
    let routeDistanceMeters: Double?
    let routeTitle: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case opponentUserID = "opponent_user_id"
        case ghostChallengeID = "ghost_challenge_id"
        case activity
        case title
        case visibility
        case status
        case startedAt = "started_at"
        case routeKey = "route_key"
        case routeDistanceMeters = "route_distance_meters"
        case routeTitle = "route_title"
    }
}

private struct ATHLTHLiveWorkoutSessionRouteUpdate: Encodable {
    let routeKey: UUID
    let routeDistanceMeters: Double?
    let routeTitle: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case routeKey = "route_key"
        case routeDistanceMeters = "route_distance_meters"
        case routeTitle = "route_title"
        case updatedAt = "updated_at"
    }
}

private struct ATHLTHLiveWorkoutLocationWrite: Encodable {
    let sessionID: UUID
    let userID: UUID
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double?
    let speedMetersPerSecond: Double?
    let courseDegrees: Double?
    let heartRateBPM: Double?
    let distanceMeters: Double
    let elapsedSeconds: Double
    let routeProgressPercent: Double?
    let routeDeviationMeters: Double?
    let updatedAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case userID = "user_id"
        case latitude
        case longitude
        case horizontalAccuracy = "horizontal_accuracy"
        case speedMetersPerSecond = "speed_meters_per_second"
        case courseDegrees = "course_degrees"
        case heartRateBPM = "heart_rate_bpm"
        case distanceMeters = "distance_meters"
        case elapsedSeconds = "elapsed_seconds"
        case routeProgressPercent = "route_progress_percent"
        case routeDeviationMeters = "route_deviation_meters"
        case updatedAt = "updated_at"
        case expiresAt = "expires_at"
    }
}


private struct BeginGhostLiveSessionParams: Encodable {
    let challengeID: UUID

    enum CodingKeys: String, CodingKey {
        case challengeID = "p_challenge_id"
    }
}

@MainActor
final class ATHLTHRealtimeSocialStore: ObservableObject {
    @Published private(set) var onlineUserIDs: Set<UUID> = []
    @Published private(set) var visibleLiveSessions: [ATHLTHLiveWorkoutSession] = []
    @Published private(set) var currentSession: ATHLTHLiveWorkoutSession?
    @Published private(set) var liveLocations: [ATHLTHLiveWorkoutLocation] = []
    // Viewer-only trail. Nothing here is persisted; it is rebuilt from fresh
    // latest-position samples while the live map is open.
    @Published private(set) var liveTrails:
        [UUID: [CLLocationCoordinate2D]] = [:]
    @Published var selectedLiveGhostSessionID: UUID?
    @Published private(set) var isSharingLiveLocation = false
    @Published var errorMessage: String?

    private let client: SupabaseClient
    private let deviceSessionID = UUID()
    private var heartbeatTask: Task<Void, Never>?
    private var watcherTask: Task<Void, Never>?
    private var appIsActive = false
    private var onlineEnabled = false
    private var lastPublishedLocationAt: Date?

    private let onlineHeartbeatInterval: Duration = .seconds(45)
    private let liveRefreshInterval: Duration = .seconds(3)
    private let minimumLocationPublishInterval: TimeInterval = 3

    init(
        client: SupabaseClient = SupabaseEnvironment.client
    ) {
        self.client = client
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    func isOnline(_ userID: UUID) -> Bool {
        onlineUserIDs.contains(userID)
    }

    func configureOnlinePresence(
        appIsActive: Bool,
        enabled: Bool
    ) async {
        self.appIsActive = appIsActive
        onlineEnabled = enabled

        heartbeatTask?.cancel()
        heartbeatTask = nil

        guard currentUserID != nil else {
            onlineUserIDs.removeAll()
            return
        }

        if appIsActive && enabled {
            await publishOnline(true)
            await refreshOnlineUsers()

            heartbeatTask = Task { @MainActor [weak self] in
                guard let self else { return }

                while !Task.isCancelled {
                    try? await Task.sleep(
                        for: self.onlineHeartbeatInterval
                    )
                    guard !Task.isCancelled,
                          self.appIsActive,
                          self.onlineEnabled
                    else {
                        break
                    }

                    await self.publishOnline(true)
                }
            }
        } else {
            await publishOnline(false)
            onlineUserIDs.removeAll()
        }
    }

    func refreshOnlineUsers() async {
        guard currentUserID != nil else {
            onlineUserIDs.removeAll()
            return
        }

        do {
            let rows: [ATHLTHOnlinePresenceRecord] =
                try await client
                    .from("social_online_presence")
                    .select()
                    .eq("is_online", value: true)
                    .order("updated_at", ascending: false)
                    .limit(500)
                    .execute()
                    .value

            let cutoff = Date().addingTimeInterval(-100)
            onlineUserIDs = Set(
                rows
                    .filter {
                        $0.isOnline &&
                        $0.updatedAt >= cutoff
                    }
                    .map(\.userID)
            )
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshVisibleLiveSessions() async {
        guard currentUserID != nil else {
            visibleLiveSessions = []
            return
        }

        do {
            // Best-effort physical cleanup for crashed/stale live sessions.
            // RLS already hides expired rows; this keeps retained coordinates
            // bounded without adding a background polling loop.
            _ = try? await client
                .rpc(
                    "cleanup_expired_live_workout_state"
                )
                .execute()

            let rows: [ATHLTHLiveWorkoutSession] =
                try await client
                    .from("live_workout_sessions")
                    .select()
                    .order("started_at", ascending: false)
                    .limit(80)
                    .execute()
                    .value

            visibleLiveSessions =
                rows.filter(\.isActive)

            if let selectedLiveGhostSessionID,
               !visibleLiveSessions.contains(
                    where: {
                        $0.id ==
                            selectedLiveGhostSessionID
                    }
               ) {
                self.selectedLiveGhostSessionID =
                    nil
                stopWatching()
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func beginLiveWorkout(
        title: String,
        activity: String,
        visibility: ATHLTHLiveWorkoutVisibility,
        routeKey: UUID? = nil,
        routeDistanceMeters: Double? = nil,
        routeTitle: String? = nil
    ) async -> ATHLTHLiveWorkoutSession? {
        guard let currentUserID else {
            return nil
        }

        if let currentSession,
           currentSession.isActive,
           currentSession.ownerID == currentUserID,
           currentSession.ghostChallengeID == nil {
            return currentSession
        }

        let now = Date()
        let id = UUID()
        let cleanTitle =
            String(
                title
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .prefix(160)
            )

        let payload = ATHLTHLiveWorkoutSessionInsert(
            id: id,
            ownerID: currentUserID,
            opponentUserID: nil,
            ghostChallengeID: nil,
            activity: activity,
            title:
                cleanTitle.isEmpty
                    ? "Live workout"
                    : cleanTitle,
            visibility: visibility.rawValue,
            status: "active",
            startedAt: now,
            routeKey: routeKey,
            routeDistanceMeters:
                routeDistanceMeters.flatMap {
                    $0.isFinite && $0 > 0
                        ? $0
                        : nil
                },
            routeTitle:
                routeTitle?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .prefix(160)
                    .description
        )

        do {
            try await client
                .from("live_workout_sessions")
                .insert(payload)
                .execute()

            let session = ATHLTHLiveWorkoutSession(
                id: id,
                ownerID: currentUserID,
                opponentUserID: nil,
                ghostChallengeID: nil,
                activity: activity,
                title: payload.title,
                visibility: visibility.rawValue,
                status: "active",
                startedAt: now,
                endedAt: nil,
                createdAt: now,
                updatedAt: now,
                routeKey: payload.routeKey,
                routeDistanceMeters:
                    payload.routeDistanceMeters,
                routeTitle:
                    payload.routeTitle
            )

            currentSession = session
            isSharingLiveLocation = true
            return session
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func beginGhostSession(
        challenge: GhostFriendRaceChallengeRecord
    ) async -> ATHLTHLiveWorkoutSession? {
        guard currentUserID != nil else {
            return nil
        }

        do {
            let session: ATHLTHLiveWorkoutSession =
                try await client
                    .rpc(
                        "begin_ghost_live_session",
                        params:
                            BeginGhostLiveSessionParams(
                                challengeID:
                                    challenge.id
                            )
                    )
                    .execute()
                    .value

            currentSession = session
            isSharingLiveLocation = true
            return session
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func publishLocation(
        _ location: CLLocation,
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        heartRateBPM: Double? = nil,
        routeProgressPercent: Double? = nil,
        routeDeviationMeters: Double? = nil,
        routeKey: UUID? = nil,
        routeDistanceMeters: Double? = nil,
        routeTitle: String? = nil
    ) async {
        guard let session = currentSession,
              session.isActive,
              isSharingLiveLocation,
              let currentUserID
        else {
            return
        }

        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 50,
              location.coordinate.latitude.isFinite,
              location.coordinate.longitude.isFinite
        else {
            return
        }

        await bindRouteContextIfNeeded(
            routeKey: routeKey,
            routeDistanceMeters:
                routeDistanceMeters,
            routeTitle: routeTitle
        )

        let now = Date()
        if let lastPublishedLocationAt,
           now.timeIntervalSince(lastPublishedLocationAt) <
                minimumLocationPublishInterval {
            return
        }

        lastPublishedLocationAt = now

        let speed =
            location.speed.isFinite &&
            location.speed >= 0
                ? location.speed
                : nil
        let course =
            location.course.isFinite &&
            location.course >= 0 &&
            location.course <= 360
                ? location.course
                : nil

        let payload = ATHLTHLiveWorkoutLocationWrite(
            sessionID: session.id,
            userID: currentUserID,
            latitude:
                location.coordinate.latitude,
            longitude:
                location.coordinate.longitude,
            horizontalAccuracy:
                location.horizontalAccuracy,
            speedMetersPerSecond: speed,
            courseDegrees: course,
            heartRateBPM:
                heartRateBPM.flatMap {
                    $0.isFinite && $0 > 0
                        ? $0
                        : nil
                },
            distanceMeters:
                max(distanceMeters, 0),
            elapsedSeconds:
                max(elapsedSeconds, 0),
            routeProgressPercent:
                sanitizedRouteProgress(
                    routeProgressPercent
                ),
            routeDeviationMeters:
                sanitizedNonNegative(
                    routeDeviationMeters
                ),
            updatedAt: now,
            expiresAt:
                now.addingTimeInterval(90)
        )

        do {
            try await client
                .from("live_workout_locations")
                .upsert(payload)
                .execute()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func publishMirroredSnapshot(
        _ snapshot: WatchWorkoutLiveSnapshot,
        includeHeartRate: Bool = false
    ) async {
        guard let session = currentSession,
              session.isActive,
              isSharingLiveLocation,
              let currentUserID,
              let latitude = snapshot.currentLatitude,
              let longitude = snapshot.currentLongitude,
              latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude)
        else {
            return
        }

        await bindRouteContextIfNeeded(
            snapshot
        )

        let now = Date()
        if let lastPublishedLocationAt,
           now.timeIntervalSince(lastPublishedLocationAt) <
                minimumLocationPublishInterval {
            return
        }

        lastPublishedLocationAt = now

        let payload = ATHLTHLiveWorkoutLocationWrite(
            sessionID: session.id,
            userID: currentUserID,
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: nil,
            speedMetersPerSecond: nil,
            courseDegrees: nil,
            heartRateBPM:
                includeHeartRate &&
                snapshot.heartRate > 0 &&
                snapshot.heartRate.isFinite
                    ? snapshot.heartRate
                    : nil,
            distanceMeters:
                max(snapshot.distanceMeters, 0),
            elapsedSeconds:
                max(snapshot.elapsedTime, 0),
            routeProgressPercent:
                sanitizedRouteProgress(
                    snapshot
                        .routeProgressPercent
                ),
            routeDeviationMeters:
                sanitizedNonNegative(
                    snapshot
                        .routeDeviationMeters
                ),
            updatedAt: now,
            expiresAt:
                now.addingTimeInterval(90)
        )

        do {
            try await client
                .from("live_workout_locations")
                .upsert(payload)
                .execute()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func bindRouteContextIfNeeded(
        _ snapshot: WatchWorkoutLiveSnapshot
    ) async {
        await bindRouteContextIfNeeded(
            routeKey:
                snapshot.routeComparisonID,
            routeDistanceMeters:
                snapshot.routeDistanceMeters,
            routeTitle:
                snapshot.routeTitle
        )
    }

    private func bindRouteContextIfNeeded(
        routeKey: UUID?,
        routeDistanceMeters: Double?,
        routeTitle: String?
    ) async {
        guard let routeKey,
              let currentUserID,
              let activeSession =
                currentSession,
              activeSession.ownerID ==
                currentUserID,
              activeSession.isActive
        else {
            return
        }

        let distance =
            sanitizedNonNegative(
                routeDistanceMeters
            )
        let cleanTitle =
            routeTitle?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        let title =
            cleanTitle.flatMap {
                $0.isEmpty
                    ? nil
                    : String($0.prefix(160))
            }

        let alreadyBound =
            activeSession.routeKey == routeKey &&
            activeSession.routeDistanceMeters ==
                distance &&
            activeSession.routeTitle ==
                title

        guard !alreadyBound else {
            return
        }

        let now = Date()

        do {
            try await client
                .from("live_workout_sessions")
                .update(
                    ATHLTHLiveWorkoutSessionRouteUpdate(
                        routeKey: routeKey,
                        routeDistanceMeters:
                            distance,
                        routeTitle:
                            title,
                        updatedAt: now
                    )
                )
                .eq(
                    "id",
                    value:
                        activeSession.id
                )
                .eq(
                    "owner_id",
                    value:
                        currentUserID
                )
                .execute()

            let updated =
                ATHLTHLiveWorkoutSession(
                    id: activeSession.id,
                    ownerID:
                        activeSession.ownerID,
                    opponentUserID:
                        activeSession
                            .opponentUserID,
                    ghostChallengeID:
                        activeSession
                            .ghostChallengeID,
                    activity:
                        activeSession.activity,
                    title:
                        activeSession.title,
                    visibility:
                        activeSession.visibility,
                    status:
                        activeSession.status,
                    startedAt:
                        activeSession.startedAt,
                    endedAt:
                        activeSession.endedAt,
                    createdAt:
                        activeSession.createdAt,
                    updatedAt: now,
                    routeKey: routeKey,
                    routeDistanceMeters:
                        distance,
                    routeTitle: title
                )

            currentSession = updated

            if let index =
                    visibleLiveSessions
                        .firstIndex(
                            where: {
                                $0.id ==
                                    updated.id
                            }
                        ) {
                visibleLiveSessions[
                    index
                ] = updated
            }
        } catch is CancellationError {
            return
        } catch {
            // Route context improves comparison accuracy but must never stop
            // live location sharing or the workout itself.
        }
    }

    func selectLiveGhost(
        _ session: ATHLTHLiveWorkoutSession?
    ) {
        guard let session else {
            selectedLiveGhostSessionID = nil
            stopWatching()
            return
        }

        guard session.activity == "running",
              session.ownerID != currentUserID
        else {
            return
        }

        selectedLiveGhostSessionID =
            session.id
        startWatching(session)
    }

    var selectedLiveGhostSession:
        ATHLTHLiveWorkoutSession? {
        guard let selectedLiveGhostSessionID
        else {
            return nil
        }

        return visibleLiveSessions.first {
            $0.id ==
                selectedLiveGhostSessionID
        }
    }

    func liveGhostComparison(
        ownDistanceMeters: Double,
        ownElapsedSeconds: TimeInterval,
        ownRouteKey: UUID? = nil,
        ownRouteProgressPercent: Double? = nil,
        ownRouteDeviationMeters: Double? = nil
    ) -> ATHLTHLiveGhostComparison? {
        guard let selectedSession =
                selectedLiveGhostSession,
              let livePoint =
                liveLocations.first(
                    where: {
                        $0.sessionID ==
                            selectedSession.id &&
                        $0.userID ==
                            selectedSession.ownerID
                    }
                )
        else {
            return nil
        }

        let ownProgress =
            normalizedRouteProgress(
                ownRouteProgressPercent
            )
        let opponentProgress =
            normalizedRouteProgress(
                livePoint
                    .routeProgressPercent
            )
        let routeDistance =
            selectedSession
                .routeDistanceMeters
        let sameRoute =
            ownRouteKey != nil &&
            ownRouteKey ==
                selectedSession.routeKey
        let routeAccuracyOK =
            (ownRouteDeviationMeters ?? 0) <=
                250 &&
            (livePoint.routeDeviationMeters ?? 0) <=
                250

        if sameRoute,
           routeAccuracyOK,
           let ownProgress,
           let opponentProgress,
           let routeDistance,
           routeDistance.isFinite,
           routeDistance >= 250 {
            let progressDelta =
                ownProgress -
                opponentProgress
            let distanceDelta =
                progressDelta *
                routeDistance

            let opponentRouteSpeed:
                Double? = {
                guard livePoint
                        .elapsedSeconds > 10,
                      opponentProgress > 0.002
                else {
                    return nil
                }

                let speed =
                    (
                        opponentProgress *
                        routeDistance
                    ) /
                    livePoint
                        .elapsedSeconds

                return speed.isFinite &&
                    speed > 0.35
                    ? speed
                    : nil
            }()

            return ATHLTHLiveGhostComparison(
                sessionID:
                    selectedSession.id,
                opponentUserID:
                    selectedSession.ownerID,
                opponentDistanceMeters:
                    livePoint.distanceMeters,
                opponentElapsedSeconds:
                    livePoint.elapsedSeconds,
                signedDistanceMeters:
                    distanceDelta,
                estimatedTimeDeltaSeconds:
                    opponentRouteSpeed.map {
                        distanceDelta / $0
                    },
                mode: .routeAware,
                routeKey:
                    selectedSession.routeKey,
                ownRouteProgressPercent:
                    ownProgress * 100,
                opponentRouteProgressPercent:
                    opponentProgress * 100,
                opponentRouteDeviationMeters:
                    livePoint
                        .routeDeviationMeters,
                updatedAt:
                    livePoint.updatedAt
            )
        }

        let distanceDelta =
            max(ownDistanceMeters, 0) -
            max(livePoint.distanceMeters, 0)

        let opponentAverageSpeed:
            Double? = {
            guard livePoint.elapsedSeconds > 10,
                  livePoint.distanceMeters > 25
            else {
                return nil
            }

            let speed =
                livePoint.distanceMeters /
                livePoint.elapsedSeconds

            return speed.isFinite &&
                speed > 0.35
                ? speed
                : nil
        }()

        return ATHLTHLiveGhostComparison(
            sessionID: selectedSession.id,
            opponentUserID:
                selectedSession.ownerID,
            opponentDistanceMeters:
                livePoint.distanceMeters,
            opponentElapsedSeconds:
                livePoint.elapsedSeconds,
            signedDistanceMeters:
                distanceDelta,
            estimatedTimeDeltaSeconds:
                opponentAverageSpeed.map {
                    distanceDelta / $0
                },
            mode: .distanceFallback,
            routeKey:
                selectedSession.routeKey,
            ownRouteProgressPercent:
                ownProgress.map { $0 * 100 },
            opponentRouteProgressPercent:
                opponentProgress.map {
                    $0 * 100
                },
            opponentRouteDeviationMeters:
                livePoint
                    .routeDeviationMeters,
            updatedAt:
                livePoint.updatedAt
        )
    }

    private func sanitizedRouteProgress(
        _ value: Double?
    ) -> Double? {
        guard let value,
              value.isFinite
        else {
            return nil
        }

        return min(
            max(value, 0),
            100
        )
    }

    private func normalizedRouteProgress(
        _ value: Double?
    ) -> Double? {
        guard let value =
                sanitizedRouteProgress(
                    value
                )
        else {
            return nil
        }

        return value / 100
    }

    private func sanitizedNonNegative(
        _ value: Double?
    ) -> Double? {
        guard let value,
              value.isFinite,
              value >= 0
        else {
            return nil
        }

        return value
    }

    func liveGhostDeltaMeters(
        ownDistanceMeters: Double
    ) -> Double? {
        liveGhostComparison(
            ownDistanceMeters:
                ownDistanceMeters,
            ownElapsedSeconds: 0
        )?.signedDistanceMeters
    }

    func startWatching(
        _ session: ATHLTHLiveWorkoutSession
    ) {
        watcherTask?.cancel()
        liveTrails = [:]

        if let currentUserID,
           session.ownerID == currentUserID ||
           session.opponentUserID == currentUserID {
            currentSession = session
        }

        watcherTask = Task { @MainActor [weak self] in
            guard let self else { return }

            await self.refreshLocations(
                sessionID: session.id
            )

            var refreshCycle = 0

            while !Task.isCancelled {
                try? await Task.sleep(
                    for: self.liveRefreshInterval
                )

                guard !Task.isCancelled else {
                    break
                }

                await self.refreshLocations(
                    sessionID: session.id
                )

                refreshCycle += 1

                if refreshCycle % 10 == 0 {
                    let stillActive =
                        await self
                            .watchedSessionIsStillActive(
                                session.id
                            )

                    if !stillActive {
                        if self
                            .selectedLiveGhostSessionID ==
                            session.id {
                            self
                                .selectedLiveGhostSessionID =
                                nil
                        }

                        self.stopWatching()
                        break
                    }
                }
            }
        }
    }

    private func watchedSessionIsStillActive(
        _ sessionID: UUID
    ) async -> Bool {
        do {
            let rows: [ATHLTHLiveWorkoutSession] =
                try await client
                    .from("live_workout_sessions")
                    .select()
                    .eq(
                        "id",
                        value: sessionID
                    )
                    .limit(1)
                    .execute()
                    .value

            guard let session =
                    rows.first
            else {
                return false
            }

            return session.isActive
        } catch is CancellationError {
            return true
        } catch {
            // A transient network error must not end a live race. The normal
            // freshness filter still prevents stale locations being used.
            return true
        }
    }

    func stopWatching(
        keepCurrentSession: Bool = true
    ) {
        watcherTask?.cancel()
        watcherTask = nil
        liveLocations = []
        liveTrails = [:]

        if !keepCurrentSession {
            currentSession = nil
        }
    }

    func setCurrentLiveLocationSharing(
        _ enabled: Bool
    ) async {
        guard let session = currentSession,
              session.isActive,
              let currentUserID,
              session.ownerID == currentUserID ||
              session.opponentUserID == currentUserID
        else {
            isSharingLiveLocation = false
            return
        }

        if enabled {
            isSharingLiveLocation = true
            lastPublishedLocationAt = nil
            return
        }

        isSharingLiveLocation = false
        lastPublishedLocationAt = nil

        do {
            try await client
                .from("live_workout_locations")
                .delete()
                .eq(
                    "session_id",
                    value: session.id
                )
                .eq(
                    "user_id",
                    value: currentUserID
                )
                .execute()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }

        liveLocations.removeAll {
            $0.userID == currentUserID
        }
        liveTrails[currentUserID] = nil
    }

    func leaveCurrentLiveWorkout() async {
        guard let session = currentSession,
              let currentUserID
        else {
            stopWatching(
                keepCurrentSession: false
            )
            return
        }

        do {
            _ = try? await client
                .from("live_workout_locations")
                .delete()
                .eq(
                    "session_id",
                    value: session.id
                )
                .eq(
                    "user_id",
                    value: currentUserID
                )
                .execute()

            if session.ownerID == currentUserID {
                try await client
                    .from("live_workout_sessions")
                    .update([
                        "status": "completed",
                        "ended_at":
                            ISO8601DateFormatter()
                                .string(from: Date())
                    ])
                    .eq("id", value: session.id)
                    .eq(
                        "owner_id",
                        value: currentUserID
                    )
                    .execute()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isSharingLiveLocation = false
        lastPublishedLocationAt = nil

        if selectedLiveGhostSessionID ==
            session.id {
            selectedLiveGhostSessionID =
                nil
        }

        stopWatching(
            keepCurrentSession: false
        )
        await refreshVisibleLiveSessions()
    }

    private func publishOnline(
        _ online: Bool
    ) async {
        guard let currentUserID else {
            return
        }

        do {
            try await client
                .from("social_online_presence")
                .upsert(
                    ATHLTHOnlinePresenceWrite(
                        userID: currentUserID,
                        isOnline: online,
                        deviceSessionID:
                            deviceSessionID,
                        updatedAt: Date()
                    )
                )
                .execute()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshLocations(
        sessionID: UUID
    ) async {
        do {
            let rows: [ATHLTHLiveWorkoutLocation] =
                try await client
                    .from("live_workout_locations")
                    .select()
                    .eq(
                        "session_id",
                        value: sessionID
                    )
                    .order(
                        "updated_at",
                        ascending: false
                    )
                    .limit(8)
                    .execute()
                    .value

            let fresh =
                rows.filter(\.isFresh)
            liveLocations = fresh
            appendFreshTrailSamples(
                fresh
            )
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func appendFreshTrailSamples(
        _ locations: [ATHLTHLiveWorkoutLocation]
    ) {
        let maximumTrailPoints = 120
        let minimumTrailSpacingMeters = 3.0

        for location in locations {
            var trail =
                liveTrails[
                    location.userID,
                    default: []
                ]

            let shouldAppend: Bool
            if let last = trail.last {
                let previous =
                    CLLocation(
                        latitude:
                            last.latitude,
                        longitude:
                            last.longitude
                    )
                let current =
                    CLLocation(
                        latitude:
                            location.latitude,
                        longitude:
                            location.longitude
                    )
                shouldAppend =
                    current.distance(
                        from: previous
                    ) >=
                    minimumTrailSpacingMeters
            } else {
                shouldAppend = true
            }

            guard shouldAppend else {
                continue
            }

            trail.append(
                location.coordinate
            )

            if trail.count >
                maximumTrailPoints {
                trail.removeFirst(
                    trail.count -
                    maximumTrailPoints
                )
            }

            liveTrails[
                location.userID
            ] = trail
        }
    }
}
