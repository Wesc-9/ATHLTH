import Combine
import Foundation
import Supabase

struct RouteAttemptRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let routeID: UUID
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
        case routeID = "route_id"
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

    var deviationPercent: Double {
        max(0, 100 - routeMatchPercent)
    }

    var leaderboardEligible: Bool {
        routeMatchPercent >= 85
    }

    var athleteName: String {
        let cleanDisplay = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let cleanDisplay, !cleanDisplay.isEmpty {
            return cleanDisplay
        }

        let cleanUsername = username?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let cleanUsername, !cleanUsername.isEmpty {
            return "@\(cleanUsername)"
        }

        return "ATHLTH athlete"
    }
}

private struct RouteAttemptWrite: Encodable {
    let routeID: UUID
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
        case routeID = "route_id"
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

final class SupabaseRouteAttemptService {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func load(routeID: UUID) async throws -> [RouteAttemptRecord] {
        try await client
            .from("route_attempt_leaderboard")
            .select()
            .eq("route_id", value: routeID)
            .order("started_at", ascending: false)
            .limit(500)
            .execute()
            .value
    }

    func upsert(
        routeID: UUID,
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

        let payload = RouteAttemptWrite(
            routeID: routeID,
            userID: userID,
            workoutID: analysis.workoutID,
            activityType: activityType,
            startedAt: analysis.startedAt,
            durationSeconds: analysis.durationSeconds,
            distanceMeters: analysis.distanceMeters,
            routeMatchPercent: analysis.routeMatchPercent,
            averageDeviationMeters: analysis.averageDeviationMeters,
            maxDeviationMeters: analysis.maxDeviationMeters,
            source: "apple_health"
        )

        try await client
            .from("route_attempts")
            .upsert(
                payload,
                onConflict: "route_id,user_id,workout_id"
            )
            .execute()
    }
}

@MainActor
final class RouteAttemptStore: ObservableObject {
    @Published private(set) var attempts: [RouteAttemptRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSyncingHealth = false
    @Published var errorMessage: String?

    private let service: SupabaseRouteAttemptService

    init(
        service: SupabaseRouteAttemptService =
            SupabaseRouteAttemptService()
    ) {
        self.service = service
    }

    func refresh(routeID: UUID) async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            attempts = try await service.load(routeID: routeID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncHealthAttempts(
        for route: TrainingRoute,
        userID: UUID,
        health: HealthKitManager
    ) async {
        guard !isSyncingHealth,
              route.coordinates.count >= 2,
              route.distanceKilometers > 0
        else {
            return
        }

        isSyncingHealth = true
        errorMessage = nil
        defer { isSyncingHealth = false }

        let routeMeters = route.distanceKilometers * 1_000
        let candidates = health.workouts
            .filter {
                $0.activity == .running ||
                $0.activity == .walking
            }
            .filter { workout in
                guard let distance = workout.distanceMeters,
                      distance > 0
                else {
                    return true
                }

                let ratio = distance / routeMeters
                return ratio >= 0.55 && ratio <= 1.55
            }
            .prefix(80)

        do {
            let existing = try await service.load(
                routeID: route.id
            )
            attempts = existing

            let existingWorkoutIDs = Set(
                existing
                    .filter { $0.userID == userID }
                    .map(\.workoutID)
            )

            for workout in candidates
            where !existingWorkoutIDs.contains(workout.id) {
                guard let analysis = await health.routePerformance(
                    for: workout,
                    against: route
                ) else {
                    continue
                }

                let distanceRatio =
                    analysis.distanceMeters > 0
                        ? analysis.distanceMeters / routeMeters
                        : 1

                let likelyRouteAttempt =
                    analysis.routeMatchPercent >= 60 &&
                    analysis.startDistanceMeters <= 450 &&
                    analysis.endDistanceMeters <= 450 &&
                    distanceRatio >= 0.55 &&
                    distanceRatio <= 1.55

                guard likelyRouteAttempt else {
                    continue
                }

                try await service.upsert(
                    routeID: route.id,
                    userID: userID,
                    analysis: analysis
                )
            }

            attempts = try await service.load(
                routeID: route.id
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func leaderboard(
        currentUserID: UUID? = nil
    ) -> [RouteAttemptRecord] {
        let eligible = attempts.filter(\.leaderboardEligible)
        var bestByUser: [UUID: RouteAttemptRecord] = [:]

        for attempt in eligible {
            if let current = bestByUser[attempt.userID] {
                if attempt.durationSeconds < current.durationSeconds {
                    bestByUser[attempt.userID] = attempt
                }
            } else {
                bestByUser[attempt.userID] = attempt
            }
        }

        return bestByUser.values.sorted {
            if abs($0.durationSeconds - $1.durationSeconds) > 0.1 {
                return $0.durationSeconds < $1.durationSeconds
            }

            if abs($0.routeMatchPercent - $1.routeMatchPercent) > 0.01 {
                return $0.routeMatchPercent > $1.routeMatchPercent
            }

            return $0.startedAt < $1.startedAt
        }
    }

    func attempts(for userID: UUID) -> [RouteAttemptRecord] {
        attempts
            .filter { $0.userID == userID }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func bestAttempt(for userID: UUID) -> RouteAttemptRecord? {
        leaderboard().first { $0.userID == userID }
    }

    func latestAttempt(for userID: UUID) -> RouteAttemptRecord? {
        attempts(for: userID).first
    }
}
