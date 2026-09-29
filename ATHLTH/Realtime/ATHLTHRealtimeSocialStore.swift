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
    let distanceMeters: Double
    let elapsedSeconds: Double
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
        case distanceMeters = "distance_meters"
        case elapsedSeconds = "elapsed_seconds"
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
    let distanceMeters: Double
    let elapsedSeconds: Double
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
        case distanceMeters = "distance_meters"
        case elapsedSeconds = "elapsed_seconds"
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
        visibility: ATHLTHLiveWorkoutVisibility
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
            startedAt: now
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
                updatedAt: now
            )

            currentSession = session
            isSharingLiveLocation = true
            startWatching(session)
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
            startWatching(session)
            return session
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func publishLocation(
        _ location: CLLocation,
        distanceMeters: Double,
        elapsedSeconds: TimeInterval
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
            distanceMeters:
                max(distanceMeters, 0),
            elapsedSeconds:
                max(elapsedSeconds, 0),
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
        _ snapshot: WatchWorkoutLiveSnapshot
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
            distanceMeters:
                max(snapshot.distanceMeters, 0),
            elapsedSeconds:
                max(snapshot.elapsedTime, 0),
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

    func startWatching(
        _ session: ATHLTHLiveWorkoutSession
    ) {
        watcherTask?.cancel()
        currentSession = session

        watcherTask = Task { @MainActor [weak self] in
            guard let self else { return }

            await self.refreshLocations(
                sessionID: session.id
            )

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
            }
        }
    }

    func stopWatching(
        keepCurrentSession: Bool = true
    ) {
        watcherTask?.cancel()
        watcherTask = nil
        liveLocations = []

        if !keepCurrentSession {
            currentSession = nil
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
            try? await client
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

            liveLocations =
                rows.filter(\.isFresh)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
