import MapKit
import SwiftUI
import Supabase

struct PublicTrailAttemptRecord: Codable, Identifiable, Hashable {
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

    var athleteName: String {
        let display = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let display, !display.isEmpty {
            return display
        }

        let handle = username?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let handle, !handle.isEmpty {
            return "@\(handle)"
        }

        return "ATHLTH athlete"
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
    let averageDeviationMeters: Double?
    let maxDeviationMeters: Double?
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

@MainActor
final class PublicTrailAttemptService {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func load(
        trailID: UUID
    ) async throws -> [PublicTrailAttemptRecord] {
        try await client
            .from("public_trail_attempt_leaderboard")
            .select()
            .eq("trail_id", value: trailID)
            .order("started_at", ascending: false)
            .limit(500)
            .execute()
            .value
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
        case .hiking:
            activityType = "hiking"
        default:
            return
        }

        let payload = PublicTrailAttemptWrite(
            trailID: trailID,
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
            .from("public_trail_attempts")
            .upsert(
                payload,
                onConflict: "trail_id,user_id,workout_id"
            )
            .execute()
    }
}

enum PublicTrailLeaderboardMode: String, CaseIterable, Identifiable {
    case running = "Run"
    case walking = "Walk"
    case hiking = "Hike"

    var id: String { rawValue }

    var databaseValue: String {
        switch self {
        case .running: "running"
        case .walking: "walking"
        case .hiking: "hiking"
        }
    }
}

@MainActor
final class PublicTrailAttemptStore: ObservableObject {
    @Published private(set) var attempts: [PublicTrailAttemptRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSyncingHealth = false
    @Published var errorMessage: String?

    private let service: PublicTrailAttemptService

    init(
        service: PublicTrailAttemptService =
            PublicTrailAttemptService()
    ) {
        self.service = service
    }

    func refresh(trailID: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            attempts = try await service.load(
                trailID: trailID
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncHealthAttempts(
        for trail: PublicTrailRecord,
        userID: UUID,
        health: HealthKitManager
    ) async {
        guard trail.leaderboardEnabled,
              trail.distanceKilometers >= 1,
              !isSyncingHealth
        else {
            return
        }

        isSyncingHealth = true
        errorMessage = nil
        defer { isSyncingHealth = false }

        let route = trail.trainingRoute(
            ownerID: userID
        )
        let routeMeters =
            trail.distanceKilometers * 1_000

        do {
            let existing =
                try await service.load(
                    trailID: trail.id
                )

            attempts = existing

            let existingWorkoutIDs = Set(
                existing
                    .filter { $0.userID == userID }
                    .map(\.workoutID)
            )

            let candidates = health.workouts
                .filter {
                    $0.activity == .running ||
                    $0.activity == .walking ||
                    $0.activity == .hiking
                }
                .filter { workout in
                    guard let distance =
                            workout.distanceMeters,
                          distance > 0
                    else {
                        return true
                    }

                    let ratio =
                        distance / routeMeters
                    return ratio >= 0.72 &&
                        ratio <= 1.35
                }
                .prefix(60)

            for workout in candidates
            where !existingWorkoutIDs.contains(workout.id) {
                guard let analysis =
                        await health.routePerformance(
                            for: workout,
                            against: route
                        )
                else {
                    continue
                }

                let distanceRatio =
                    analysis.distanceMeters /
                    routeMeters

                let deviationOK =
                    analysis.averageDeviationMeters <= 120

                let leaderboardEligible =
                    analysis.routeMatchPercent >= 90 &&
                    analysis.startDistanceMeters <= 200 &&
                    analysis.endDistanceMeters <= 200 &&
                    distanceRatio >= 0.85 &&
                    distanceRatio <= 1.15 &&
                    deviationOK

                guard leaderboardEligible else {
                    continue
                }

                try await service.upsert(
                    trailID: trail.id,
                    userID: userID,
                    analysis: analysis
                )
            }

            attempts = try await service.load(
                trailID: trail.id
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func leaderboard(
        mode: PublicTrailLeaderboardMode
    ) -> [PublicTrailAttemptRecord] {
        let filtered = attempts.filter {
            $0.activityType ==
                mode.databaseValue &&
            $0.routeMatchPercent >= 90
        }

        var bestByUser:
            [UUID: PublicTrailAttemptRecord] = [:]

        for attempt in filtered {
            if let current =
                    bestByUser[attempt.userID] {
                if attempt.durationSeconds <
                    current.durationSeconds {
                    bestByUser[attempt.userID] =
                        attempt
                }
            } else {
                bestByUser[attempt.userID] =
                    attempt
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

            return $0.routeMatchPercent >
                $1.routeMatchPercent
        }
    }
}

struct PublicTrailDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager

    @StateObject private var attempts =
        PublicTrailAttemptStore()
    @State private var mode:
        PublicTrailLeaderboardMode = .running
    @State private var mapPosition:
        MapCameraPosition = .automatic

    let trail: PublicTrailRecord

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    trailMap
                    routeSummary
                    leaderboardCard
                    attribution
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(ATHLTHPremiumCanvas())
            .navigationTitle(trail.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await attempts.refresh(
                    trailID: trail.id
                )

                if !health.shouldDeferAutomaticHealthWork {
                    await attempts.syncHealthAttempts(
                        for: trail,
                        userID: session.profile.userID,
                        health: health
                    )
                }
            }
        }
    }

    private var trailMap: some View {
        Map(position: $mapPosition) {
            MapPolyline(
                coordinates:
                    trail.renderCoordinates
            )
            .stroke(
                ATHLTHTheme.vitality,
                style: StrokeStyle(
                    lineWidth: 6,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
        .mapStyle(
            .standard(elevation: .realistic)
        )
        .frame(height: 250)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.72),
                lineWidth: 0.8
            )
        }
    }

    private var routeSummary: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 14) {
                Image(
                    systemName:
                        trail.routeKind == "hiking"
                            ? "mountain.2.fill"
                            : "figure.walk"
                )
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 48, height: 48)
                .background(
                    ATHLTHTheme.champagneSoft,
                    in: RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
                )

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    Text(trail.kindTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(trail.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                    HStack(spacing: 10) {
                        Label(
                            String(
                                format: "%.1f km",
                                trail.distanceKilometers
                            ),
                            systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                        )

                        if let network = trail.network,
                           !network.isEmpty {
                            Text(network.uppercased())
                        }

                        if trail.athlthVerified {
                            Label(
                                "ATHLTH Verified",
                                systemImage:
                                    "checkmark.seal.fill"
                            )
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()
            }

            if !trail.leaderboardEnabled {
                Label(
                    "Routes under 1 km do not get a leaderboard.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
        }
    }

    private var leaderboardCard: some View {
        ATHLTHCard {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text("Leaderboard")
                        .font(.title3.weight(.bold))

                    Text(
                        "Best GPS-validated attempts"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if attempts.isSyncingHealth {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Picker(
                "Activity",
                selection: $mode
            ) {
                ForEach(
                    PublicTrailLeaderboardMode.allCases
                ) { mode in
                    Text(mode.rawValue)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!trail.leaderboardEnabled)
            .padding(.vertical, 8)

            if !trail.leaderboardEnabled {
                Text(
                    "This route is visible in Trail Mode, but it is too short for competition."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if attempts.isLoading &&
                        attempts.attempts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                let leaderboard =
                    attempts.leaderboard(
                        mode: mode
                    )

                if leaderboard.isEmpty {
                    VStack(spacing: 8) {
                        Image(
                            systemName:
                                "trophy.circle"
                        )
                        .font(.title2)
                        .foregroundStyle(
                            ATHLTHTheme.premiumGold
                        )

                        Text("No verified attempts yet")
                            .font(.subheadline.weight(.semibold))

                        Text(
                            "Complete this route with GPS tracking to become the first."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                } else {
                    VStack(spacing: 0) {
                        ForEach(
                            Array(
                                leaderboard.prefix(10)
                                    .enumerated()
                            ),
                            id: \.element.id
                        ) { index, attempt in
                            leaderboardRow(
                                rank: index + 1,
                                attempt: attempt
                            )

                            if index <
                                min(
                                    leaderboard.count,
                                    10
                                ) - 1 {
                                Divider()
                                    .padding(.leading, 38)
                            }
                        }
                    }
                }
            }
        }
    }

    private func leaderboardRow(
        rank: Int,
        attempt: PublicTrailAttemptRecord
    ) -> some View {
        HStack(spacing: 11) {
            Text("\(rank)")
                .font(.caption.bold())
                .foregroundStyle(
                    rank <= 3
                        ? ATHLTHTheme.premiumGold
                        : ATHLTHTheme.mutedText
                )
                .frame(width: 24)

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(attempt.athleteName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(
                    "\(Int(attempt.routeMatchPercent.rounded()))% route match"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(
                elapsedTime(
                    attempt.durationSeconds
                )
            )
            .font(
                .system(
                    .subheadline,
                    design: .rounded
                )
                .weight(.bold)
            )
        }
        .padding(.vertical, 10)
    }

    private var attribution: some View {
        Link(
            "© OpenStreetMap contributors",
            destination:
                URL(
                    string:
                        "https://www.openstreetmap.org/copyright"
                )!
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    private func elapsedTime(
        _ seconds: TimeInterval
    ) -> String {
        let total =
            max(Int(seconds.rounded()), 0)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remaining = total % 60

        if hours > 0 {
            return String(
                format:
                    "%d:%02d:%02d",
                hours,
                minutes,
                remaining
            )
        }

        return String(
            format: "%d:%02d",
            minutes,
            remaining
        )
    }
}
