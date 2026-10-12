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

/// Live race comparisons are provisional: a delayed or implausible sample
/// must never produce a new lead/pass announcement. Keep connection-state
/// reporting separate so temporary packet loss does not end the workout.
enum ATHLTHLiveGhostRacingTelemetry {
    static let maximumActionableAge: TimeInterval = 18

    static func opponentID(
        ownerID: UUID,
        otherID: UUID?,
        viewerID: UUID?
    ) -> UUID? {
        // Without authentication we cannot know which athlete is the
        // opponent. Never accidentally compare the owner to themselves.
        guard let viewerID else { return nil }
        if viewerID == ownerID { return otherID }
        // Spectators may watch a map, but must not compare their own
        // workout against someone else's private synchronized duel.
        guard viewerID == otherID else { return nil }
        return ownerID
    }

    /// A synchronized duel must be backed by its exact Ghost challenge ID.
    /// Route-less legacy live follows keep their original fallback behavior.
    /// Re-uploading an old CLLocation with a new server timestamp can
    /// manufacture a live leader and permanent passing statistics.
    static func freshLocalLocation(
        capturedAt: Date,
        now: Date = Date()
    ) -> Bool {
        let age = now.timeIntervalSince(capturedAt)
        return age.isFinite && (-5...25).contains(age)
    }

    static func matchesWorkout(
        challengeID: UUID?,
        selectedRouteKey: UUID?,
        localComparisonRouteID: UUID?
    ) -> Bool {
        if let challengeID {
            return localComparisonRouteID == challengeID &&
                (selectedRouteKey == nil || selectedRouteKey == challengeID)
        }
        return localComparisonRouteID == nil ||
            selectedRouteKey == nil ||
            localComparisonRouteID == selectedRouteKey
    }

    static func acceptableDeviation(
        _ meters: Double?,
        maximum: Double
    ) -> Bool {
        guard let meters else { return true }
        return meters.isFinite && (0...maximum).contains(meters)
    }

    static func canCompare(
        updatedAt: Date,
        expiresAt: Date,
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        now: Date = Date()
    ) -> Bool {
        let age = now.timeIntervalSince(updatedAt)
        return age.isFinite &&
            (-5...maximumActionableAge).contains(age) &&
            expiresAt > now &&
            distanceMeters.isFinite &&
            distanceMeters >= 0 &&
            elapsedSeconds.isFinite &&
            (0...86_400).contains(elapsedSeconds) &&
            distanceMeters <= max(120, elapsedSeconds * 15)
    }
}

enum ATHLTHLiveGhostComparisonMode: Equatable {
    case routeAware
    case distanceFallback
}

enum ATHLTHLiveGhostConnectionState: Equatable {
    case waiting
    case live
    case delayed(seconds: Int)
    case reconnecting(seconds: Int)

    var isStale: Bool {
        switch self {
        case .delayed, .reconnecting:
            return true
        case .waiting, .live:
            return false
        }
    }
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


/// Only the workout belonging to this Live Ghost challenge may send
/// its GPS updates or trigger shared-session completion. General live
/// workout sharing is unaffected by this restriction.
enum ATHLTHWatchLiveTelemetryFreshness {
    /// Prevent delayed watch messages from being re-timestamped as LIVE GPS.
    /// A stale packet must not update the shared route or imply connectivity.
    static func isFresh(capturedAt: Date, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(capturedAt)
        return age.isFinite && (-10...30).contains(age)
    }
}

enum ATHLTHLiveGhostWorkoutBinding {
    static func accepts(
        ghostChallengeID: UUID?,
        comparisonRouteID: UUID?
    ) -> Bool {
        guard let ghostChallengeID else { return true }
        return comparisonRouteID == ghostChallengeID
    }
}

/// Prevents duplicate iPhone/Apple Watch completion events from racing
/// to submit the same Live Ghost result. The database remains authoritative.
struct ATHLTHLiveGhostFinishGate {
    private var inFlight: Set<UUID> = []
    private var submitted: Set<UUID> = []

    mutating func begin(
        challengeID: UUID,
        completedRouteID: UUID?,
        seconds: TimeInterval
    ) -> Bool {
        // Do not settle a Live Ghost duel using an unrelated run, or a
        // completion from an older Watch transfer without route identity.
        guard completedRouteID == challengeID,
              seconds.isFinite,
              (5...86_400).contains(seconds),
              !inFlight.contains(challengeID),
              !submitted.contains(challengeID)
        else {
            return false
        }
        inFlight.insert(challengeID)
        return true
    }

    mutating func end(challengeID: UUID, succeeded: Bool) {
        inFlight.remove(challengeID)
        if succeeded {
            submitted.insert(challengeID)
        }
    }
}

/// The server preserves the first recorded finish. An HTTP 200 on a
/// repeated UPDATE cannot prove that the requested time was accepted.
enum ATHLTHLiveGhostFinishConfirmation {
    static func matches(
        challengeID: UUID,
        expectedChallengeID: UUID,
        finishedAt: Date?,
        recordedSeconds: TimeInterval?,
        submittedSeconds: TimeInterval
    ) -> Bool {
        guard challengeID == expectedChallengeID,
              finishedAt != nil,
              let recordedSeconds,
              recordedSeconds.isFinite,
              submittedSeconds.isFinite,
              (5...86_400).contains(recordedSeconds),
              (5...86_400).contains(submittedSeconds)
        else { return false }
        return abs(recordedSeconds - submittedSeconds) <= 0.05
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
    private var liveGhostFinishGate = ATHLTHLiveGhostFinishGate()
    @Published private(set) var liveLocations: [ATHLTHLiveWorkoutLocation] = []
    // Viewer-only trail. Nothing here is persisted; it is rebuilt from fresh
    // latest-position samples while the live map is open.
    @Published private(set) var liveTrails:
        [UUID: [CLLocationCoordinate2D]] = [:]
    @Published var selectedLiveGhostSessionID: UUID?
    @Published private(set)
    var liveGhostConnectionState:
        ATHLTHLiveGhostConnectionState = .waiting
    @Published private(set) var isSharingLiveLocation = false
    @Published var errorMessage: String?

    private let client: SupabaseClient
    private let deviceSessionID = UUID()
    private var heartbeatTask: Task<Void, Never>?
    private var watcherTask: Task<Void, Never>?
    private var locationRealtimeTask: Task<Void, Never>?
    private var appIsActive = false
    private var onlineEnabled = false
    private var lastPublishedLocationAt: Date?
    private var lastPublishedDistanceMeters: Double?
    private var lastPublishedElapsedSeconds: TimeInterval?
    private var lastOnlineRefreshAt: Date?
    private var lastVisibleSessionsRefreshAt: Date?

    private let onlineHeartbeatInterval: Duration = .seconds(90)
    private let liveRefreshInterval: Duration = .seconds(3)
    // Match the 18-second actionable GPS policy shared by the Watch and
    // server. Otherwise the UI can say DELAYED while still calculating leads.
    private let liveGhostFreshAge: TimeInterval = 18
    private let liveGhostDelayedAge: TimeInterval = 25
    private let liveGhostMaximumUsableAge: TimeInterval = 90
    private let routeAwareMaximumDeviationMeters = 120.0
    private let selectedLiveGhostDefaultsPrefix =
        "athlth.liveGhost.selectedSession."

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

    func refreshOnlineUsers(
        force: Bool = false
    ) async {
        guard currentUserID != nil else {
            onlineUserIDs.removeAll()
            return
        }

        if !force,
           let lastOnlineRefreshAt,
           Date().timeIntervalSince(lastOnlineRefreshAt) < 60 {
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

            let cutoff = Date().addingTimeInterval(-210)
            onlineUserIDs = Set(
                rows
                    .filter {
                        $0.isOnline &&
                        $0.updatedAt >= cutoff
                    }
                    .map(\.userID)
            )
            lastOnlineRefreshAt = Date()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshVisibleLiveSessions(
        force: Bool = false
    ) async {
        guard currentUserID != nil else {
            visibleLiveSessions = []
            return
        }

        if !force,
           let lastVisibleSessionsRefreshAt,
           Date().timeIntervalSince(
                lastVisibleSessionsRefreshAt
           ) < 20 {
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
            lastVisibleSessionsRefreshAt = Date()

            if selectedLiveGhostSessionID == nil,
               let restoredID =
                    restoredLiveGhostSessionID(),
               let restoredSession =
                    visibleLiveSessions.first(
                        where: {
                            $0.id == restoredID &&
                            $0.activity == "running" &&
                            (
                                $0.ownerID !=
                                    currentUserID ||
                                (
                                    $0.ghostChallengeID != nil &&
                                    $0.opponentUserID ==
                                        currentUserID
                                )
                            )
                        }
                    ) {
                selectedLiveGhostSessionID =
                    restoredID
                startWatching(
                    restoredSession
                )
            }

            if let selectedLiveGhostSessionID {
                guard let selectedSession =
                        visibleLiveSessions.first(
                            where: {
                                $0.id ==
                                    selectedLiveGhostSessionID
                            }
                        )
                else {
                    clearSelectedLiveGhost()
                    stopWatching()
                    return
                }

                // App relaunch, process suspension and transient connectivity
                // can tear down the polling task while the remote session is
                // still active. Resume watching automatically.
                if watcherTask == nil {
                    startWatching(
                        selectedSession
                    )
                }
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
            resetLocationPublishThrottle()
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
            resetLocationPublishThrottle()
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
              let currentUserID,
              ATHLTHLiveGhostWorkoutBinding.accepts(
                  ghostChallengeID: session.ghostChallengeID,
                  comparisonRouteID: routeKey
              ),
              (session.ghostChallengeID == nil ||
                ATHLTHLiveGhostRacingTelemetry.freshLocalLocation(
                    capturedAt: location.timestamp
                ))
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

        let speed =
            location.speed.isFinite &&
            location.speed >= 0
                ? location.speed
                : nil

        guard shouldPublishLiveLocation(
            now: now,
            distanceMeters:
                distanceMeters,
            elapsedSeconds:
                elapsedSeconds,
            speedHint: speed
        ) else {
            return
        }
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

            markLiveLocationPublished(
                at: now,
                distanceMeters:
                    distanceMeters,
                elapsedSeconds:
                    elapsedSeconds
            )
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
              ATHLTHLiveGhostWorkoutBinding.accepts(
                  ghostChallengeID: session.ghostChallengeID,
                  comparisonRouteID: snapshot.routeComparisonID
              ),
              ATHLTHWatchLiveTelemetryFreshness.isFresh(
                  capturedAt: snapshot.capturedAt
              ),
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

        guard shouldPublishLiveLocation(
            now: now,
            distanceMeters:
                snapshot.distanceMeters,
            elapsedSeconds:
                snapshot.elapsedTime,
            speedHint: nil
        ) else {
            return
        }

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

            markLiveLocationPublished(
                at: now,
                distanceMeters:
                    snapshot.distanceMeters,
                elapsedSeconds:
                    snapshot.elapsedTime
            )
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
            clearSelectedLiveGhost()
            stopWatching()
            return
        }

        guard session.activity == "running"
        else {
            return
        }

        if session.ownerID == currentUserID {
            guard
                session.ghostChallengeID != nil,
                session.opponentUserID != nil
            else {
                return
            }
        }

        selectedLiveGhostSessionID =
            session.id
        persistSelectedLiveGhost(
            session.id
        )
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
              let opponentUserID =
                liveGhostOpponentUserID(
                    in: selectedSession
                ),
              let livePoint =
                liveLocations.first(
                    where: {
                        $0.sessionID ==
                            selectedSession.id &&
                        $0.userID ==
                            opponentUserID
                    }
                ),
              ATHLTHLiveGhostRacingTelemetry.canCompare(
                  updatedAt: livePoint.updatedAt,
                  expiresAt: livePoint.expiresAt,
                  distanceMeters: livePoint.distanceMeters,
                  elapsedSeconds: livePoint.elapsedSeconds
              ),
              ownDistanceMeters.isFinite,
              ownDistanceMeters >= 0,
              ownElapsedSeconds.isFinite,
              ownElapsedSeconds >= 0,
              ATHLTHLiveGhostRacingTelemetry.matchesWorkout(
                  challengeID: selectedSession.ghostChallengeID,
                  selectedRouteKey: selectedSession.routeKey,
                  localComparisonRouteID: ownRouteKey
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
            ATHLTHLiveGhostRacingTelemetry.acceptableDeviation(
                ownRouteDeviationMeters,
                maximum: routeAwareMaximumDeviationMeters
            ) &&
            ATHLTHLiveGhostRacingTelemetry.acceptableDeviation(
                livePoint.routeDeviationMeters,
                maximum: routeAwareMaximumDeviationMeters
            ) &&
            (
                livePoint.horizontalAccuracy == nil ||
                (livePoint.horizontalAccuracy ?? 0) <= 50
            )

        // If both athletes report progress on the same route but either
        // GPS projection is unreliable, do NOT silently switch to raw
        // distance and announce a spurious overtake. Wait for valid route
        // samples instead.
        if sameRoute,
           ownProgress != nil,
           opponentProgress != nil,
           !routeAccuracyOK {
            return nil
        }

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
                    opponentUserID,
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
                opponentUserID,
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

    private func liveGhostOpponentUserID(
        in session:
            ATHLTHLiveWorkoutSession
    ) -> UUID? {
        ATHLTHLiveGhostRacingTelemetry.opponentID(
            ownerID: session.ownerID,
            otherID: session.opponentUserID,
            viewerID: currentUserID
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
        locationRealtimeTask?.cancel()
        liveTrails = [:]

        if let currentUserID,
           session.ownerID == currentUserID ||
           session.opponentUserID == currentUserID {
            currentSession = session
        }

        startLocationRealtime(
            sessionID: session.id
        )

        watcherTask = Task { @MainActor [weak self] in
            guard let self else { return }

            await self.refreshLocations(
                sessionID: session.id
            )

            var refreshCycle = 0

            while !Task.isCancelled {
                let interval:
                    Duration

                switch self.liveGhostConnectionState {
                case .reconnecting:
                    interval = .seconds(5)
                case .delayed:
                    interval = .seconds(7)
                case .waiting:
                    interval = .seconds(5)
                case .live:
                    interval = .seconds(12)
                }

                try? await Task.sleep(
                    for: interval
                )

                guard !Task.isCancelled else {
                    break
                }

                await self.refreshLocations(
                    sessionID: session.id
                )
                self.updateLiveGhostConnectionState(
                    session: session
                )

                refreshCycle += 1

                if refreshCycle % 8 == 0 {
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
                                .clearSelectedLiveGhost()
                        }

                        self.stopWatching()
                        break
                    }
                }
            }
        }
    }

    private func startLocationRealtime(
        sessionID: UUID
    ) {
        locationRealtimeTask =
            Task {
                @MainActor [weak self] in
                guard let self else {
                    return
                }

                let channel =
                    await self.client
                        .channel(
                            "live-workout-location-\(sessionID.uuidString.lowercased())"
                        )

                let changes =
                    await channel
                        .postgresChange(
                            AnyAction.self,
                            schema: "public",
                            table:
                                "live_workout_locations"
                        )

                await channel.subscribe()

                for await _ in changes {
                    guard
                        !Task.isCancelled
                    else {
                        break
                    }

                    await self
                        .refreshLocations(
                            sessionID:
                                sessionID
                        )
                }

                await channel
                    .unsubscribe()
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
        locationRealtimeTask?.cancel()
        watcherTask = nil
        locationRealtimeTask = nil
        liveLocations = []
        liveTrails = [:]

        if selectedLiveGhostSessionID == nil {
            liveGhostConnectionState =
                .waiting
        }

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
            resetLocationPublishThrottle()
            return
        }

        isSharingLiveLocation = false
        resetLocationPublishThrottle()

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

    /// A first finish is immutable on the server. Retries repeat the exact
    /// same payload after transient network errors, never another recording.
    /// A bounded schedule avoids indefinitely running network work after
    /// HealthKit/Watch ends or the user closes the app.
    private static let liveGhostFinishRetryDelays: [TimeInterval] = [0, 1, 3]

    func finishCurrentLiveGhostRace(
        elapsedSeconds: TimeInterval,
        completedRouteID: UUID?
    ) async {
        guard
            let session = currentSession,
            session.isActive,
            let challengeID = session.ghostChallengeID,
            let currentUserID,
            liveGhostFinishGate.begin(
                challengeID: challengeID,
                completedRouteID: completedRouteID,
                seconds: elapsedSeconds
            )
        else {
            return
        }

        // The local workout has ended. Stop sharing its live position
        // immediately, even if submitting the finish later fails.
        // This never stops the recorded iPhone/Watch workout itself.
        isSharingLiveLocation = false
        resetLocationPublishThrottle()
        await setCurrentLiveLocationSharing(false)

        var succeeded = false
        defer {
            liveGhostFinishGate.end(
                challengeID: challengeID,
                succeeded: succeeded
            )
        }

        struct FinishWrite: Encodable {
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
                case updatedAt =
                    "updated_at"
            }
        }

        struct FinishReceipt: Decodable {
            let challengeID: UUID
            let finishedAt: Date?
            let elapsedSeconds: TimeInterval?

            enum CodingKeys: String, CodingKey {
                case challengeID = "challenge_id"
                case finishedAt = "finished_at"
                case elapsedSeconds = "elapsed_seconds"
            }

            func confirms(_ submitted: TimeInterval, for challengeID: UUID) -> Bool {
                ATHLTHLiveGhostFinishConfirmation.matches(
                    challengeID: self.challengeID,
                    expectedChallengeID: challengeID,
                    finishedAt: finishedAt,
                    recordedSeconds: elapsedSeconds,
                    submittedSeconds: submitted
                )
            }
        }

        // Capture the original completion instant once. If Supabase
        // committed the first request but its response was lost, the
        // immutable-finish trigger makes the next request idempotent.
        let finishedAt = Date()
        let finishPayload = FinishWrite(
            finishedAt: finishedAt,
            elapsedSeconds: elapsedSeconds,
            updatedAt: finishedAt
        )
        for delay in Self.liveGhostFinishRetryDelays {
            guard !Task.isCancelled else { return }
            if delay > 0 {
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
            }
            do {
                // A successful HTTP response can still update zero rows
                // (for example after RLS revokes access or a duel is
                // cancelled). Verify the exact race row was returned.
                let receipts: [FinishReceipt] = try await client
                    .from("live_ghost_race_participants")
                    .update(finishPayload)
                    .eq("challenge_id", value: challengeID)
                    .eq("user_id", value: currentUserID)
                    .select("challenge_id,finished_at,elapsed_seconds")
                    .execute()
                    .value
                guard receipts.count == 1,
                      receipts[0].confirms(elapsedSeconds, for: challengeID) else {
                    throw NSError(
                        domain: "ATHLTH.LiveGhost",
                        code: 409,
                        userInfo: [
                            NSLocalizedDescriptionKey: ATHLTHLocalization.choose(
                                english: "The shared race did not confirm your finish. Your local workout remains saved.",
                                norwegian: "Den delte duellen bekreftet ikke sluttiden. Din lokale treningsøkt er fortsatt lagret."
                            )
                        ]
                    )
                }
                succeeded = true
                errorMessage = nil
                return
            } catch is CancellationError {
                return
            } catch {
                // If the first write committed but its HTTP response was
                // lost, query the immutable server result before retrying.
                // A different persisted time is NOT accepted as ours.
                let recorded: [FinishReceipt] = (try? await client
                    .from("live_ghost_race_participants")
                    .select("challenge_id,finished_at,elapsed_seconds")
                    .eq("challenge_id", value: challengeID)
                    .eq("user_id", value: currentUserID)
                    .limit(1)
                    .execute().value) ?? []
                if recorded.count == 1,
                   recorded[0].confirms(elapsedSeconds, for: challengeID) {
                    succeeded = true
                    errorMessage = nil
                    return
                }
                // Keep the last server error visible if every attempt fails.
                // Do not report success or award Arena points locally.
                errorMessage = error.localizedDescription
            }
        }
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
        resetLocationPublishThrottle()

        if selectedLiveGhostSessionID ==
            session.id {
            clearSelectedLiveGhost()
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

            let now = Date()
            let usable =
                rows.filter {
                    $0.expiresAt > now &&
                    now.timeIntervalSince(
                        $0.updatedAt
                    ) <=
                        liveGhostMaximumUsableAge
                }

            liveLocations = usable
            appendFreshTrailSamples(
                usable.filter(\.isFresh)
            )
            updateLiveGhostConnectionState()
        } catch is CancellationError {
            return
        } catch {
            // Preserve the last known point while reconnecting. The UI marks
            // it as delayed/stale instead of pretending the opponent is still
            // sending fresh GPS.
            updateLiveGhostConnectionState()
            errorMessage = error.localizedDescription
        }
    }

    private func updateLiveGhostConnectionState(
        session:
            ATHLTHLiveWorkoutSession? = nil
    ) {
        let selected =
            session ??
            selectedLiveGhostSession

        guard let selected,
              let opponentID = liveGhostOpponentUserID(in: selected),
              let point =
                liveLocations.first(
                    where: {
                        $0.sessionID ==
                            selected.id &&
                        $0.userID ==
                            opponentID
                    }
                )
        else {
            liveGhostConnectionState =
                .waiting
            return
        }

        let now = Date()
        guard point.expiresAt > now,
              point.updatedAt <= now.addingTimeInterval(5),
              point.distanceMeters.isFinite,
              point.distanceMeters >= 0,
              point.elapsedSeconds.isFinite,
              (0...86_400).contains(point.elapsedSeconds),
              point.distanceMeters <=
                max(120, point.elapsedSeconds * 15)
        else {
            liveGhostConnectionState = .waiting
            return
        }
        let age = max(now.timeIntervalSince(point.updatedAt), 0)
        let roundedAge =
            max(
                Int(age.rounded()),
                0
            )

        if age <= liveGhostFreshAge {
            liveGhostConnectionState =
                .live
        } else if age <=
                    liveGhostDelayedAge {
            liveGhostConnectionState =
                .delayed(
                    seconds: roundedAge
                )
        } else if age <=
                    liveGhostMaximumUsableAge {
            liveGhostConnectionState =
                .reconnecting(
                    seconds: roundedAge
                )
        } else {
            liveGhostConnectionState =
                .waiting
        }
    }

    private func selectedLiveGhostDefaultsKey(
        userID: UUID
    ) -> String {
        selectedLiveGhostDefaultsPrefix +
            userID.uuidString
    }

    private func persistSelectedLiveGhost(
        _ sessionID: UUID?
    ) {
        guard let currentUserID else {
            return
        }

        let key =
            selectedLiveGhostDefaultsKey(
                userID: currentUserID
            )

        if let sessionID {
            UserDefaults.standard.set(
                sessionID.uuidString,
                forKey: key
            )
        } else {
            UserDefaults.standard
                .removeObject(
                    forKey: key
                )
        }
    }

    private func restoredLiveGhostSessionID()
        -> UUID? {
        guard let currentUserID,
              let raw =
                UserDefaults.standard
                    .string(
                        forKey:
                            selectedLiveGhostDefaultsKey(
                                userID:
                                    currentUserID
                            )
                    )
        else {
            return nil
        }

        return UUID(uuidString: raw)
    }

    private func clearSelectedLiveGhost() {
        selectedLiveGhostSessionID = nil
        persistSelectedLiveGhost(nil)
        liveGhostConnectionState =
            .waiting
    }

    private func resetLocationPublishThrottle() {
        lastPublishedLocationAt = nil
        lastPublishedDistanceMeters = nil
        lastPublishedElapsedSeconds = nil
    }

    private func liveLocationPublishInterval(
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        speedHint: Double?
    ) -> TimeInterval {
        let inferredSpeed:
            Double? = {
                if let speedHint,
                   speedHint.isFinite,
                   speedHint >= 0 {
                    return speedHint
                }

                guard let previousDistance =
                        lastPublishedDistanceMeters,
                      let previousElapsed =
                        lastPublishedElapsedSeconds
                else {
                    return nil
                }

                let elapsedDelta =
                    elapsedSeconds -
                    previousElapsed

                guard elapsedDelta > 0.5
                else {
                    return nil
                }

                return max(
                    distanceMeters -
                        previousDistance,
                    0
                ) /
                elapsedDelta
            }()

        guard let inferredSpeed else {
            return 2
        }

        if inferredSpeed >= 1.0 {
            return 1.5
        }

        if inferredSpeed >= 0.35 {
            return 3
        }

        return 6
    }

    private func shouldPublishLiveLocation(
        now: Date,
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        speedHint: Double?
    ) -> Bool {
        guard let lastPublishedLocationAt else {
            return true
        }

        let interval =
            liveLocationPublishInterval(
                distanceMeters:
                    distanceMeters,
                elapsedSeconds:
                    elapsedSeconds,
                speedHint:
                    speedHint
            )

        return now.timeIntervalSince(
            lastPublishedLocationAt
        ) >= interval
    }

    private func markLiveLocationPublished(
        at date: Date,
        distanceMeters: Double,
        elapsedSeconds: TimeInterval
    ) {
        lastPublishedLocationAt = date
        lastPublishedDistanceMeters =
            max(distanceMeters, 0)
        lastPublishedElapsedSeconds =
            max(elapsedSeconds, 0)
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
