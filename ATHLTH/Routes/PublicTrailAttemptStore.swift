import Combine
import Foundation
import Supabase

private struct PublicTrailAttemptRow:
    Codable,
    Identifiable,
    Hashable
{
    let id: UUID
    let trailID: UUID
    let userID: UUID
    let workoutID: UUID
    let activityType: String
    let startedAt: Date
    let durationSeconds: TimeInterval
    let distanceMeters: Double
    let routeMatchPercent: Double
    let averageDeviationMeters: Double?
    let maxDeviationMeters: Double?
    let source: String
    let username: String?
    let displayName: String?
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case trailID = "trail_id"
        case userID = "user_id"
        case workoutID = "workout_id"
        case activityType = "activity_type"
        case startedAt = "started_at"
        case durationSeconds = "duration_seconds"
        case distanceMeters = "distance_meters"
        case routeMatchPercent = "route_match_percent"
        case averageDeviationMeters = "average_deviation_meters"
        case maxDeviationMeters = "max_deviation_meters"
        case source
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
    }

    var routeAttempt: RouteAttemptRecord {
        RouteAttemptRecord(
            id: id,
            routeID: trailID,
            userID: userID,
            workoutID: workoutID,
            activityType: activityType,
            startedAt: startedAt,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            routeMatchPercent: routeMatchPercent,
            averageDeviationMeters: averageDeviationMeters,
            maxDeviationMeters: maxDeviationMeters,
            source: source,
            username: username,
            displayName: displayName,
            avatarURL: avatarURL
        )
    }
}

private struct PublicTrailAttemptWrite: Encodable {
    let trailID: UUID
    let userID: UUID
    let workoutID: UUID
    let activityType: String
    let startedAt: Date
    let durationSeconds: TimeInterval
    let distanceMeters: Double
    let routeMatchPercent: Double
    let averageDeviationMeters: Double
    let maxDeviationMeters: Double
    let source: String

    enum CodingKeys: String, CodingKey {
        case trailID = "trail_id"
        case userID = "user_id"
        case workoutID = "workout_id"
        case activityType = "activity_type"
        case startedAt = "started_at"
        case durationSeconds = "duration_seconds"
        case distanceMeters = "distance_meters"
        case routeMatchPercent = "route_match_percent"
        case averageDeviationMeters = "average_deviation_meters"
        case maxDeviationMeters = "max_deviation_meters"
        case source
    }
}

struct PublicTrailLeaderboardConfiguration:
    Decodable
{
    let id: UUID
    let leaderboardEnabled: Bool
    let distanceKilometers: Double

    enum CodingKeys: String, CodingKey {
        case id
        case leaderboardEnabled = "leaderboard_enabled"
        case distanceKilometers = "distance_kilometers"
    }
}

@MainActor
final class SupabasePublicTrailAttemptService {
    private let client: SupabaseClient

    init(
        client: SupabaseClient =
            SupabaseEnvironment.client
    ) {
        self.client = client
    }

    func configuration(
        trailID: UUID
    ) async throws ->
        PublicTrailLeaderboardConfiguration?
    {
        let rows:
            [PublicTrailLeaderboardConfiguration] =
                try await client
                    .from("public_trails")
                    .select(
                        "id,leaderboard_enabled,distance_kilometers"
                    )
                    .eq("id", value: trailID)
                    .limit(1)
                    .execute()
                    .value

        return rows.first
    }

    func load(
        trailID: UUID
    ) async throws -> [RouteAttemptRecord] {
        let rows: [PublicTrailAttemptRow] =
            try await client
                .from(
                    "public_trail_attempt_leaderboard"
                )
                .select()
                .eq("trail_id", value: trailID)
                .order(
                    "started_at",
                    ascending: false
                )
                .limit(500)
                .execute()
                .value

        return rows.map(\.routeAttempt)
    }

    func upsert(
        trailID: UUID,
        userID: UUID,
        analysis: RoutePerformanceAnalysis
    ) async throws {
        let activityType: String

        switch analysis.activity {
        case .running:
            activityType = "running"
        case .walking:
            activityType = "walking"
        default:
            return
        }

        let payload =
            PublicTrailAttemptWrite(
                trailID: trailID,
                userID: userID,
                workoutID: analysis.workoutID,
                activityType: activityType,
                startedAt: analysis.startedAt,
                durationSeconds:
                    analysis.durationSeconds,
                distanceMeters:
                    analysis.distanceMeters,
                routeMatchPercent:
                    analysis.routeMatchPercent,
                averageDeviationMeters:
                    analysis.averageDeviationMeters,
                maxDeviationMeters:
                    analysis.maxDeviationMeters,
                source: "apple_health"
            )

        try await client
            .from("public_trail_attempts")
            .upsert(
                payload,
                onConflict:
                    "trail_id,user_id,workout_id"
            )
            .execute()
    }
}

@MainActor
final class PublicTrailAttemptStore:
    ObservableObject
{
    @Published private(set)
    var attempts: [RouteAttemptRecord] = []

    @Published private(set)
    var loadedTrailID: UUID?

    @Published private(set)
    var leaderboardEnabled = true

    @Published private(set)
    var isLoading = false

    @Published private(set)
    var isSyncingHealth = false

    @Published var errorMessage: String?

    private let service:
        SupabasePublicTrailAttemptService

    private var latestRefreshRequestID = UUID()

    init(
        service:
            SupabasePublicTrailAttemptService =
                SupabasePublicTrailAttemptService()
    ) {
        self.service = service
    }

    func refresh(
        trailID: UUID
    ) async {
        let requestID = UUID()
        latestRefreshRequestID = requestID

        isLoading = true
        errorMessage = nil

        do {
            async let configuration =
                service.configuration(
                    trailID: trailID
                )
            async let loaded =
                service.load(
                    trailID: trailID
                )

            let (
                resolvedConfiguration,
                resolvedAttempts
            ) = try await (
                configuration,
                loaded
            )

            guard latestRefreshRequestID ==
                requestID
            else {
                return
            }

            leaderboardEnabled =
                resolvedConfiguration?
                    .leaderboardEnabled
                ?? false
            attempts = resolvedAttempts
            loadedTrailID = trailID
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            guard latestRefreshRequestID ==
                requestID
            else {
                return
            }

            errorMessage =
                error.localizedDescription
            loadedTrailID = trailID
            isLoading = false
        }
    }

    func syncHealthAttempts(
        for trail: TrainingRoute,
        userID: UUID,
        health: HealthKitManager
    ) async {
        guard !isSyncingHealth,
              trail.coordinates.count >= 2,
              trail.distanceKilometers >= 1
        else {
            return
        }

        isSyncingHealth = true
        errorMessage = nil
        defer {
            isSyncingHealth = false
        }

        do {
            guard let configuration =
                try await service.configuration(
                    trailID: trail.id
                )
            else {
                leaderboardEnabled = false
                attempts = []
                loadedTrailID = trail.id
                return
            }

            leaderboardEnabled =
                configuration.leaderboardEnabled

            guard configuration
                .leaderboardEnabled,
                  configuration
                    .distanceKilometers >= 1
            else {
                attempts =
                    try await service.load(
                        trailID: trail.id
                    )
                loadedTrailID = trail.id
                return
            }

            let trailMeters =
                trail.distanceKilometers *
                1_000

            let candidates =
                health.workouts
                    .filter {
                        $0.activity == .running ||
                        $0.activity == .walking
                    }
                    .filter { workout in
                        guard
                            let distance =
                                workout.distanceMeters,
                            distance > 0
                        else {
                            return true
                        }

                        let ratio =
                            distance / trailMeters
                        return ratio >= 0.55 &&
                            ratio <= 1.55
                    }
                    .prefix(80)

            let existing =
                try await service.load(
                    trailID: trail.id
                )

            attempts = existing

            let existingWorkoutIDs =
                Set(
                    existing
                        .filter {
                            $0.userID == userID
                        }
                        .map(\.workoutID)
                )

            for workout in candidates
            where !existingWorkoutIDs
                .contains(workout.id)
            {
                guard let analysis =
                    await health.routePerformance(
                        for: workout,
                        against: trail
                    )
                else {
                    continue
                }

                let distanceRatio =
                    analysis.distanceMeters > 0
                        ? analysis
                            .distanceMeters /
                            trailMeters
                        : 1

                let likelyTrailAttempt =
                    analysis
                        .routeMatchPercent >= 60 &&
                    analysis
                        .startDistanceMeters <= 450 &&
                    analysis
                        .endDistanceMeters <= 450 &&
                    distanceRatio >= 0.55 &&
                    distanceRatio <= 1.55

                guard likelyTrailAttempt else {
                    continue
                }

                try await service.upsert(
                    trailID: trail.id,
                    userID: userID,
                    analysis: analysis
                )
            }

            attempts =
                try await service.load(
                    trailID: trail.id
                )
            loadedTrailID = trail.id
        } catch is CancellationError {
            return
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }

    func leaderboard() ->
        [RouteAttemptRecord]
    {
        let eligible =
            attempts.filter(
                \.leaderboardEligible
            )

        var bestByUser:
            [UUID: RouteAttemptRecord] = [:]

        for attempt in eligible {
            if let current =
                bestByUser[attempt.userID]
            {
                if attempt.durationSeconds <
                    current.durationSeconds
                {
                    bestByUser[
                        attempt.userID
                    ] = attempt
                }
            } else {
                bestByUser[
                    attempt.userID
                ] = attempt
            }
        }

        return bestByUser.values.sorted {
            if abs(
                $0.durationSeconds -
                $1.durationSeconds
            ) > 0.1 {
                return $0.durationSeconds <
                    $1.durationSeconds
            }

            if abs(
                $0.routeMatchPercent -
                $1.routeMatchPercent
            ) > 0.01 {
                return $0.routeMatchPercent >
                    $1.routeMatchPercent
            }

            return $0.startedAt <
                $1.startedAt
        }
    }

    func attempts(
        for userID: UUID
    ) -> [RouteAttemptRecord] {
        attempts
            .filter {
                $0.userID == userID
            }
            .sorted {
                $0.startedAt > $1.startedAt
            }
    }

    func bestAttempt(
        for userID: UUID
    ) -> RouteAttemptRecord? {
        leaderboard()
            .first {
                $0.userID == userID
            }
    }

    func latestAttempt(
        for userID: UUID
    ) -> RouteAttemptRecord? {
        attempts(
            for: userID
        ).first
    }
}
